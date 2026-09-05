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
# -E so the trap below is reached from inside a function as well; without it a failure in
# `name_part` would end this script with no sentence at all.
set -Eeuo pipefail

# WHAT STANDS IS ONE SENTENCE, RE-SET WHERE THE WORLD CHANGES AND NEVER WRITTEN OUT PER REFUSAL.
# Every refusal ends with it, so a refusal cannot carry a clause that is no longer true: a tag push
# failing after the commit push succeeded, or a catalog pin failing after the platform pin is
# already on its remote. It is re-set at the three points below where a push has been shown to have
# landed, and nowhere else.
STANDING=". Nothing has been minted or pushed"

die() { echo "release: $*$STANDING" >&2; exit 1; }
say() { echo "release: $*"; }

# WHAT WAS NEVER FORESEEN STILL ENDS IN A SENTENCE. Every refusal in this script is one it went
# looking for; this is the rest. Without it an unforeseen failure ends with whatever the failing
# command said and nothing about where the release stopped — which is the promise at the top of this
# file failing rather than being kept. The Windows twin's `catch` is this, and says the same words.
#
# It fires where `set -e` fires and nowhere else, so a `grep -q ... && die` whose grep finds nothing
# is left alone, as are every `|| die` and every `if !` below.
stopped() {
  die "${1%%$'\n'*}"   # the first line of it: name_part's whole awk program is not a sentence
}
trap 'stopped "$BASH_COMMAND"' ERR

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

TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$TOP" ] \
  || die "this is not a git working copy, and a release is cut from the root of one"
cd "$TOP"

# ── everything this release will need, before it mints anything ──────────────
[ -z "$(git status --porcelain)" ] \
  || die "the worktree is dirty — commit or stash first"
for tool in git gh awk sed; do
  command -v "$tool" >/dev/null 2>&1 \
    || die "$tool is not on this path and this release needs it"
done

PLATFORM_REPO="simetrixch/hostyour-cloud"
CATALOG_REPO="simetrixch/hostyour-deploy"
PLATFORM_PIN="clusters/platform/versions.yaml"
CATALOG_PIN="ansiwise/programs/deploy-cluster.yaml"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git clone --quiet "https://github.com/${PLATFORM_REPO}.git" "$WORK/platform" \
  || die "${PLATFORM_REPO} could not be cloned, so this release could not write its pin"
git clone --quiet "https://github.com/${CATALOG_REPO}.git" "$WORK/catalog" \
  || die "${CATALOG_REPO} could not be cloned, so this release could not write its pin"
GIT_TERMINAL_PROMPT=0 git -C "$WORK/platform" push --dry-run --quiet origin HEAD >/dev/null 2>&1 \
  || die "this machine may not push to ${PLATFORM_REPO}, so this release could not write its pin"
GIT_TERMINAL_PROMPT=0 git -C "$WORK/catalog" push --dry-run --quiet origin HEAD >/dev/null 2>&1 \
  || die "this machine may not push to ${CATALOG_REPO}, so this release could not write its pin"
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
  [ -n "$sha" ] || die "${repo} has no master to build from"
  name_part "$repo" "$sha"
  # READ BACK, because the line below reports this part as named at this commit and nothing else
  # looks. The rewrite matches on the url of the dependency: a manifest that spells that url any
  # other way is written out unchanged, and the grep under this loop stays quiet, because the ref
  # a previous release left there is a commit and not `master`.
  grep -qF "ref: $sha" pubspec.yaml \
    || die "pubspec.yaml does not name ${repo} at ${sha} after the rewrite"
  say "  ${repo} at ${sha:0:12}"
done
grep -q 'ref: master' pubspec.yaml \
  && die "a part is still named by a branch rather than a commit"

# ── the manifest is resolved before anything is minted ──────────────────────
# THE LAST FORESEEABLE FAILURE, and the one this script used to leave to the build.
# Each part names its siblings as well, and nothing here moves those: a part that
# names another at an older commit asks the resolver for one repository at two
# commits through two paths, which it refuses. The refusal is reported against
# whichever package it reached first, so it names one nobody edited, and it
# arrives minutes after a tag is already public. Measured twice in one release on
# 2026-09-03, each time costing a tag that named nothing and a build that read it.
#
# The cost is small where the failure is not: resolving fetches the four trees,
# and this script has already asked every one of them for its master.
say 'resolving the parts named above, together, before anything is minted'
if ! RESOLVED="$(dart pub get 2>&1)"; then
  echo "$RESOLVED" >&2
  die 'the parts this release names cannot be resolved together. The lines above are the resolver, and they name the two packages that disagree'
fi

# ── mint, which is what starts the one build ─────────────────────────────────
TAG="${VERSION}-${CHANNEL}-$(date -u +%Y%m%d%H%M%S)"
sed -i -E "0,/^version:[[:space:]]*\S+/s//version: ${VERSION}/" pubspec.yaml
grep -qE "^version: ${VERSION}\$" pubspec.yaml \
  || die "the version could not be written into pubspec.yaml"
git add -- pubspec.yaml || die "pubspec.yaml could not be staged"
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
git tag "$TAG" || die "the tag $TAG could not be created"
git push --quiet origin HEAD || die "the release commit could not be pushed to origin"
STANDING=". The release commit is on origin, and no tag is minted"
git push --quiet origin "$TAG" \
  || die "the tag $TAG could not be pushed to origin, so it exists on this machine only"
# NOTHING IS PINNED BEFORE IT EXISTS. The push is what makes the tag fetchable; the read-back is
# what proves it, and it is asked of the REMOTE rather than of this checkout, which already has
# the tag whatever the remote thinks. A zero exit from the push above is the weaker fact, and the
# forty minutes of waiting that follow this line rest on the stronger one.
[ -n "$(git ls-remote --tags origin "refs/tags/$TAG")" ] \
  || die "origin does not carry $TAG after the push, so a machine could not fetch it"
STANDING=" — the tag $TAG stands, and no pin is written"
say "the tag $TAG is on origin — the one build has started"

# ── wait at that build, asked for BY NAME ────────────────────────────────────
# NEVER `gh run list --limit 1`. In the seconds after a push the newest run is
# still the PREVIOUS release's, and reading it reports a verdict that belongs to
# another tag: a script that does exactly that announces a green build for a
# release that has not started.
state=""
run_id=""
for _ in $(seq 1 120); do
  # BY headBranch AND NOT BY THE COMMIT TITLE. A tag push names the tag there, and it is the
  # only field that says which tag a run belongs to. The title is the head commit's message,
  # which names whatever tag was last committed - so a release that had nothing to commit,
  # because its manifest already said what it means to say, looks for a run under the previous
  # tag's name and never finds the one it just started.
  #
  # THE RUN'S NUMBER IS TAKEN WITH ITS STATE, in one reading rather than a second one afterwards.
  # A later listing can answer about a different run, and the number is what the log below is
  # asked for by.
  found="$(gh run list --limit 15 --json headBranch,status,conclusion,databaseId \
           -q ".[] | select(.headBranch == \"${TAG}\") | .status+\" \"+(.conclusion//\"\")+\" \"+(.databaseId|tostring)" \
           | head -1)"
  state="${found% *}"
  run_id="${found##* }"
  case "$state" in completed*) break ;; esac
  sleep 20
done
case "$state" in
  "completed success") say "the build of $TAG is green" ;;
  *)
    # THE REASON IS PRINTED HERE, not left to a command somebody is told to run next. Whoever reads
    # this failure is standing at a terminal with the credential already in hand, and a release that
    # sends them one round trip away for the cause has answered nothing. The FAILED STEPS are what
    # the build refused on; the whole log is thousands of lines of green and buries them.
    if [ -n "$run_id" ]; then
      printf '%s\n' "----- the failed steps of run $run_id -----" >&2
      gh run view "$run_id" --log-failed 2>&1 | tail -120 >&2 \
        || printf '%s\n' "the log of run $run_id could not be read" >&2
      printf '%s\n' "----- end of run $run_id -----" >&2
    fi
    die "the build of $TAG did not finish green (${state:-it never appeared})"
    ;;
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
  grep -qF "$TAG" "$file" || die "$file carries no pin this release could write"
}
pin_file "$WORK/platform/$PLATFORM_PIN" \
  "s|version: \"[0-9]+\.[0-9]+\.[0-9]+-[a-z]+-[0-9]{14}\"|version: \"$TAG\"|"
git -C "$WORK/platform" commit --quiet -a \
  -m "Pin the engine at $VERSION $CHANNEL" \
  -m "Written by the release of ansiwise-cli, once its binaries were built." \
  || die "the pin of ${PLATFORM_REPO} could not be committed"
git -C "$WORK/platform" push --quiet origin HEAD \
  || die "the pin of ${PLATFORM_REPO} could not be pushed, so it is a pin only this machine believes"
STANDING=" — the tag $TAG stands, ${PLATFORM_REPO} is pinned, and ${CATALOG_REPO} is NOT"
say "pinned ${PLATFORM_REPO} ${PLATFORM_PIN}"

pin_file "$WORK/catalog/$CATALOG_PIN" \
  "s|- ansiwise=[0-9]+\.[0-9]+\.[0-9]+-[a-z]+-[0-9]{14}|- ansiwise=$TAG|"
git -C "$WORK/catalog" commit --quiet -a \
  -m "Stamp the ansiwise $VERSION $CHANNEL pin into the cluster deploy program" \
  -m "Written by the release of ansiwise-cli, once its binaries were built." \
  || die "the pin of ${CATALOG_REPO} could not be committed"
git -C "$WORK/catalog" push --quiet origin HEAD \
  || die "the pin of ${CATALOG_REPO} could not be pushed, so it is a pin only this machine believes"
say "stamped ${CATALOG_REPO} ${CATALOG_PIN}"

say "DONE — $TAG is built, and every tree that names an engine names this one"
