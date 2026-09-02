#!/usr/bin/env bash
# =============================================================================
# release/release.sh — the one command that releases ansiwise.
# =============================================================================
#
# WHAT IT DOES. Names the commit of each part this engine is built from, mints
# the tag, and waits at the workflow that tag starts. That workflow is the only
# place anything of ansiwise is built: it loads all four trees, lints and tests
# every one of them, and builds the executable. When it comes back green this
# script writes the two pins downstream that make the new engine the one an
# installation takes.
#
# WHY IT WAITS. A release that ends when the tag is pushed hands back a number
# nobody has verified, and the pins downstream would then name an engine that may
# never exist. So the tag is the middle of this script, not its end.
#
# EVERYTHING IT WILL NEED IS CHECKED BEFORE ANYTHING IS MINTED. A tag is a public
# fact and a push cannot be taken back, so the foreseeable failures are met
# first: a dirty tree, a missing tool, no push rights on a repository this
# release has to write to. Those refusals all end with the same sentence, and
# that sentence is the point of their order.
#
# WHY SHELL. The release is not part of the product. It has to run when the
# product does not build, and it writes into repositories that are not this one.
set -euo pipefail

die() { echo "release: $*" >&2; exit 1; }
say() { echo "release: $*"; }

VERSION="${1:-}"
CHANNEL="${2:-}"
[ -n "$VERSION" ] && [ -n "$CHANNEL" ] \
  || die "usage: release/release.sh <x.y.z> <stable|beta|alpha>"
[[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
  || die "version must be x.y.z with no leading zeros (got '$VERSION')"
case "$CHANNEL" in
  stable|beta|alpha) ;;
  *) die "channel must be stable|beta|alpha (got '$CHANNEL')" ;;
esac

cd "$(git rev-parse --show-toplevel)"

# ── everything this release will need, before it mints anything ──────────────
[ -z "$(git status --porcelain)" ] \
  || die "the worktree is dirty — commit or stash first. Nothing has been minted or pushed"
for tool in git gh awk sed; do
  command -v "$tool" >/dev/null 2>&1 \
    || die "$tool is not on this path and this release needs it. Nothing has been minted or pushed"
done

PLATFORM_REPO="simetrixch/hostyour-cloud"
CATALOG_REPO="simetrixch/hostyour-deploy"
PLATFORM_PIN="clusters/platform/versions.yaml"
CATALOG_PIN="ansiwise/programs/deploy-cluster.yaml"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git clone --quiet "https://github.com/${PLATFORM_REPO}.git" "$WORK/platform" \
  || die "${PLATFORM_REPO} could not be cloned, so this release could not write its pin. Nothing has been minted or pushed"
git clone --quiet "https://github.com/${CATALOG_REPO}.git" "$WORK/catalog" \
  || die "${CATALOG_REPO} could not be cloned, so this release could not write its pin. Nothing has been minted or pushed"
for tree in platform catalog; do
  GIT_TERMINAL_PROMPT=0 git -C "$WORK/$tree" push --dry-run --quiet origin HEAD >/dev/null 2>&1 \
    || die "this machine may not push to the $tree tree, so this release could not write its pin. Nothing has been minted or pushed"
done
say "both trees this release pins are reachable and would accept a push"

# ── the exact commit of each part this engine is built from ──────────────────
# A COMMIT, NOT A TAG. The parts are released by nobody, so there is no tag of
# theirs to name — and a commit is the stronger statement anyway: a tag can be
# moved onto another tree, a commit cannot, because its name IS its content. The
# release notes give back the legibility a tag carries, by naming each one.
#
# ONE PLACE PER REPOSITORY, however many packages it holds: ansiwise-plugins is a
# dozen packages in one tree and every one of them is named out of the same
# checkout. A rewrite that matched a loose version string instead would reach the
# neighbouring repository's ref as well, overwriting the ansiwise-core ref with a
# plugins tag.
name_part() { # <repo> <commit>
  awk -v repo="$1" -v sha="$2" '
    $0 ~ "url: https://github.com/simetrixch/" repo "\\.git" { print; inside = 1; next }
    inside && /^[ \t]*ref:[ \t]*/ { sub(/ref:[ \t]*.*/, "ref: " sha); inside = 0 }
    { print }
  ' pubspec.yaml > pubspec.yaml.next
  mv pubspec.yaml.next pubspec.yaml
}
for repo in ansiwise-core ansiwise-plugins ansiwise-checks; do
  sha="$(git ls-remote "https://github.com/simetrixch/${repo}.git" refs/heads/master | cut -f1)"
  [ -n "$sha" ] || die "${repo} has no master to build from. Nothing has been minted or pushed"
  name_part "$repo" "$sha"
  say "  ${repo} at ${sha:0:12}"
done
grep -q 'ref: master' pubspec.yaml \
  && die "a part is still named by a branch rather than a commit. Nothing has been minted or pushed"

# ── mint, which is what starts the one build ─────────────────────────────────
TAG="${VERSION}-${CHANNEL}-$(date -u +%Y%m%d%H%M%S)"
sed -i -E "0,/^version:[[:space:]]*\S+/s//version: ${VERSION}/" pubspec.yaml
grep -qE "^version: ${VERSION}\$" pubspec.yaml \
  || die "the version could not be written into pubspec.yaml. Nothing has been minted or pushed"
git add -- pubspec.yaml
# A BUMP THAT IS ALREADY THERE IS NOT A FAILURE. A release whose build went red
# leaves this commit behind: the manifest names the version and the three parts,
# and only the tag and the pins are missing. Running the release again then finds
# nothing to commit, and refusing there is refusing the repair — the second run
# would have to undo the first before it could do anything, which is the shape
# that sends a person to fix a manifest by hand.
#
# WHAT IS COMMITTED IS STILL CHECKED: the lines above wrote the version and the
# three refs and read them back, so an empty index here means the file already
# says what this run means it to say.
if ! git diff --cached --quiet -- pubspec.yaml; then
  git commit --quiet -m "release: $TAG" || die "the version bump could not be committed"
else
  say "the manifest already names $VERSION and these three parts, so there is nothing to commit"
fi
git tag "$TAG"
git push --quiet origin HEAD
git push --quiet origin "$TAG"
say "the tag $TAG is on origin — the one build has started"

# ── wait at that build, asked for BY NAME ────────────────────────────────────
# NEVER `gh run list --limit 1`. In the seconds after a push the newest run is
# still the PREVIOUS release's, and reading it reports a verdict that belongs to
# another tag: a script that does exactly that announces a green build for a
# release that has not started.
state=""
for _ in $(seq 1 120); do
  # BY headBranch AND NOT BY THE COMMIT TITLE. A tag push names the tag there, and it is the
  # only field that says which tag a run belongs to. The title is the head commit's message,
  # which names whatever tag was last committed - so a release that had nothing to commit,
  # because its manifest already said what it means to say, looks for a run under the previous
  # tag's name and never finds the one it just started.
  state="$(gh run list --limit 15 --json headBranch,status,conclusion \
           -q ".[] | select(.headBranch == \"${TAG}\") | .status+\" \"+(.conclusion//\"\")" \
           | head -1)"
  case "$state" in completed*) break ;; esac
  sleep 20
done
case "$state" in
  "completed success") say "the build of $TAG is green" ;;
  *) die "the build of $TAG did not finish green (${state:-it never appeared}) — the tag stands, and the pins are NOT written" ;;
esac

assets="$(gh release view "$TAG" --json assets -q '[.assets[].name]|join(", ")' 2>/dev/null || true)"
[ -n "$assets" ] || die "the release $TAG carries no binaries, so nothing may be pinned to it"
say "binaries: $assets"

# ── the two pins downstream ──────────────────────────────────────────────────
# MATCHED ON THE SHAPE OF A TAG rather than on the neighbouring words, so a file
# that renames its keys still pins — and a file carrying no pin at all says so
# instead of being silently left behind.
pin_file() { # <file> <sed expression>
  local file="$1" expression="$2"
  sed -i -E "$expression" "$file"
  grep -qF "$TAG" "$file" || die "$file carries no pin this release could write — the tag stands, and that tree is unchanged"
}
pin_file "$WORK/platform/$PLATFORM_PIN" \
  "s|version: \"[0-9]+\.[0-9]+\.[0-9]+-[a-z]+-[0-9]{14}\"|version: \"$TAG\"|"
git -C "$WORK/platform" commit --quiet -a \
  -m "Pin the engine at $VERSION $CHANNEL" \
  -m "Written by the release of ansiwise-cli, once its binaries were built."
git -C "$WORK/platform" push --quiet origin HEAD
say "pinned ${PLATFORM_REPO} ${PLATFORM_PIN}"

pin_file "$WORK/catalog/$CATALOG_PIN" \
  "s|- ansiwise=[0-9]+\.[0-9]+\.[0-9]+-[a-z]+-[0-9]{14}|- ansiwise=$TAG|"
git -C "$WORK/catalog" commit --quiet -a \
  -m "Stamp the ansiwise $VERSION $CHANNEL pin into the cluster deploy program" \
  -m "Written by the release of ansiwise-cli, once its binaries were built."
git -C "$WORK/catalog" push --quiet origin HEAD
say "stamped ${CATALOG_REPO} ${CATALOG_PIN}"

say "DONE — $TAG is built, and every tree that names an engine names this one"
