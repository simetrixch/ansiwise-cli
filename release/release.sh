#!/usr/bin/env bash
# =============================================================================
# release/release.sh — the ONE release of ansiwise, end to end.
# =============================================================================
#
# WHAT THIS IS. ansiwise-cli is the product; ansiwise-core, ansiwise-plugins and
# ansiwise-checks are its parts and are released by nobody. This script is what
# turns a working tree into the engine a machine downloads: it names the exact
# sibling commits it builds from, proves the tree on THIS machine, mints the tag,
# waits for the binaries, and writes the two pins downstream that make the new
# engine the one an installation actually takes.
#
# EVERYTHING IT WILL NEED IS CHECKED BEFORE ANYTHING IS MINTED. A tag is a public
# fact and a push cannot be taken back, so every foreseeable failure is met
# first: a dirty tree, a missing tool, no push rights on a repository this
# release has to write to. Those refusals all end with the same sentence —
# nothing has been minted or pushed — and that is the whole point of their order.
#
# WHY SHELL AND NOT DART. The release is not part of the product. It has to run
# when the product does not build, and it writes into repositories that are not
# this one. Tying it to the toolchain the product pins is what stopped the gate
# on 2026-09-01: the workstation had moved one patch version, tool/ci.dart
# refused every run, and two releases were cut without any gate at all.
#
# GITHUB BUILDS. IT DOES NOT JUDGE. The gate is `dart run tool/ci.dart` and it
# runs HERE, before the tag exists. `dart test` is a subset of it — it misses the
# toolchain pin, the formatting, the analysis, and whether each package still
# declares the checks it claims. This script does not offer that road.
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

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# ── everything this release will need, before it mints anything ──────────────
[ -z "$(git status --porcelain)" ] \
  || die "the worktree is dirty — commit or stash first. Nothing has been minted or pushed"
for tool in git gh python3 dart; do
  command -v "$tool" >/dev/null 2>&1 \
    || die "$tool is not on this path and this release needs it. Nothing has been minted or pushed"
done

# The two trees this release writes its pins into. A release that cannot write
# them leaves an engine nobody takes, which looks exactly like one that worked.
PLATFORM_REPO="simetrixch/hostyour-cloud"
CATALOG_REPO="digitaplatform/digita-deploy"
PLATFORM_PIN="clusters/platform/versions.yaml"
CATALOG_PIN="ansiwise/programs/deploy-cluster.yaml"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git clone --quiet "https://github.com/${PLATFORM_REPO}.git" "$WORK/platform" \
  || die "${PLATFORM_REPO} could not be cloned, so this release could not write its pin. Nothing has been minted or pushed"
git clone --quiet "https://github.com/${CATALOG_REPO}.git" "$WORK/catalog" \
  || die "${CATALOG_REPO} could not be cloned, so this release could not write its pin. Nothing has been minted or pushed"
for d in platform catalog; do
  GIT_TERMINAL_PROMPT=0 git -C "$WORK/$d" push --dry-run --quiet origin HEAD >/dev/null 2>&1 \
    || die "this machine may not push to the $d tree, so this release could not write its pin. Nothing has been minted or pushed"
done
say "both trees this release pins are reachable and would accept a push"

# ── the exact sibling commits this engine is built from ──────────────────────
# A COMMIT, NOT A TAG. The parts are released by nobody, so there is no tag to
# name — and a commit is the stronger statement anyway: a tag can be moved onto
# another tree, a commit cannot. What a reader loses is legibility, and the
# release notes give that back by naming what each commit says.
for repo in ansiwise-core ansiwise-plugins ansiwise-checks; do
  sha="$(git ls-remote "https://github.com/simetrixch/${repo}.git" refs/heads/master | cut -f1)"
  [ -n "$sha" ] || die "${repo} has no master to build from. Nothing has been minted or pushed"
  python3 "$ROOT/release/name_sibling.py" pubspec.yaml "$repo" "$sha"
done

# ── the gate, HERE, before the tag exists ────────────────────────────────────
dart pub get >/dev/null 2>&1 \
  || die "the tree does not resolve at those commits. Nothing has been minted or pushed"
say "running the gate"
if ! dart run tool/ci.dart; then
  git checkout -- pubspec.yaml pubspec.lock 2>/dev/null || true
  die "the gate is not green, so nothing here is worth releasing. Nothing has been minted or pushed"
fi

# ── mint ─────────────────────────────────────────────────────────────────────
TAG="${VERSION}-${CHANNEL}-$(date -u +%Y%m%d%H%M%S)"
python3 "$ROOT/release/name_version.py" pubspec.yaml "$VERSION"
git add -- pubspec.yaml pubspec.lock 2>/dev/null || true
git commit --quiet -m "release: $TAG" || die "the version bump could not be committed"
git tag "$TAG"
git push --quiet origin HEAD
git push --quiet origin "$TAG"
say "OK — the tag $TAG is on origin, and the build has started"

# ── wait for THIS build, asked for by name ───────────────────────────────────
# NEVER `gh run list --limit 1`. In the seconds after a push the newest run is
# still the PREVIOUS release's, and reading it reports a verdict belonging to
# another tag. Measured on 2026-09-01: a chain script did exactly that and
# announced a green build for a release that had not started.
state=""
for _ in $(seq 1 90); do
  state="$(gh run list --limit 15 --json displayTitle,status,conclusion \
           -q ".[] | select(.displayTitle | contains(\"${TAG}\")) | .status+\" \"+(.conclusion//\"\")" | head -1)"
  case "$state" in completed*) break ;; esac
  sleep 20
done
case "$state" in
  "completed success") say "the build of $TAG is green" ;;
  *) die "the build of $TAG did not finish green (${state:-never appeared}) — the tag stands, the pins are NOT written" ;;
esac

assets="$(gh release view "$TAG" --json assets -q '[.assets[].name]|join(", ")' 2>/dev/null || true)"
[ -n "$assets" ] \
  || die "the release $TAG carries no binaries, so nothing may be pinned to it"
say "binaries: $assets"

# ── the two pins downstream ──────────────────────────────────────────────────
python3 "$ROOT/release/write_pin.py" "$WORK/platform/$PLATFORM_PIN" version "$TAG"
git -C "$WORK/platform" add -- "$PLATFORM_PIN"
git -C "$WORK/platform" commit --quiet \
  -m "Pin the engine at $VERSION $CHANNEL" \
  -m "Written by the release of ansiwise-cli, once its binaries were built."
git -C "$WORK/platform" push --quiet origin HEAD
say "pinned ${PLATFORM_REPO} ${PLATFORM_PIN}"

python3 "$ROOT/release/write_pin.py" "$WORK/catalog/$CATALOG_PIN" tool "$TAG"
git -C "$WORK/catalog" add -- "$CATALOG_PIN"
git -C "$WORK/catalog" commit --quiet \
  -m "Stamp the ansiwise $VERSION $CHANNEL pin into the cluster deploy program" \
  -m "Written by the release of ansiwise-cli, once its binaries were built."
git -C "$WORK/catalog" push --quiet origin HEAD
say "stamped ${CATALOG_REPO} ${CATALOG_PIN}"

say "DONE — $TAG is built, and every tree that names an engine names this one"
