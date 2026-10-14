#!/usr/bin/env bash
# =============================================================================
# release/release.sh — the one command that releases ansiwise.
# =============================================================================
#
# WHAT IT DOES. Names the commit of each part this engine is built from, mints
# the tag, and waits for the binaries that tag starts. On the tag the publish
# pipeline on the owner's master clones this repository, builds both binaries
# with release/build.sh, and pushes them as ONE manifest to Zot under the tag.
# When that manifest is there this script reads the digests out of it and
# writes the two pins downstream that make the new engine the one an
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
# failing after the commit push succeeded, or a programs pin failing after the platform pin is
# already on its remote. It is re-set at the three points below where a push has been shown to have
# landed, and nowhere else.
STANDING=". Nothing has been minted or pushed"

die() { echo "release: $*$STANDING" >&2; exit 1; }
say() { echo "release: $*"; }
# shellcheck source=release/write_pin.sh
source "$(dirname "${BASH_SOURCE[0]}")/write_pin.sh"
# shellcheck source=release/manifest_digests.sh
source "$(dirname "${BASH_SOURCE[0]}")/manifest_digests.sh"

# WHAT WAS NEVER FORESEEN STILL ENDS IN A SENTENCE. Every refusal in this script is one it went
# looking for; this is the rest. Without it an unforeseen failure ends with whatever the failing
# command said and nothing about where the release stopped — which is the promise at the top of this
# file failing rather than being kept.
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
for tool in git curl jq awk sed; do
  command -v "$tool" >/dev/null 2>&1 \
    || die "$tool is not on this path and this release needs it"
done
# THE BINARIES ARE release/build.sh's OWN, read rather than restated: the manifest this release waits
# for is held to one digest for each of them, and a build.sh naming none is met here, before a tag.
binaries="$(awk -F'"' '/^BINARIES="/ { print $2; exit }' release/build.sh)"
[ -n "$binaries" ] \
  || die "release/build.sh names no BINARIES, so the digests of this release could not be held to them"

PLATFORM_REPO="simetrixch/hostyour-cloud"
PROGRAMS_REPO="simetrixch/hostyour-deploy"
PLATFORM_PIN="clusters/platform/versions.yaml"
PROGRAMS_PIN="ansiwise/programs/deploy-cluster.yaml"
PROGRAMS_SOURCES="ci-sources.json"
PLATFORM_DIGESTS="clusters/platform/ansiwise.sha256"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git clone --quiet "https://github.com/${PLATFORM_REPO}.git" "$WORK/platform" \
  || die "${PLATFORM_REPO} could not be cloned, so this release could not write its pin"
git clone --quiet "https://github.com/${PROGRAMS_REPO}.git" "$WORK/programs" \
  || die "${PROGRAMS_REPO} could not be cloned, so this release could not write its pin"
GIT_TERMINAL_PROMPT=0 git -C "$WORK/platform" push --dry-run --quiet origin HEAD >/dev/null 2>&1 \
  || die "this machine may not push to ${PLATFORM_REPO}, so this release could not write its pin"
GIT_TERMINAL_PROMPT=0 git -C "$WORK/programs" push --dry-run --quiet origin HEAD >/dev/null 2>&1 \
  || die "this machine may not push to ${PROGRAMS_REPO}, so this release could not write its pin"
say "both trees this release pins are reachable and would accept a push"

# ── the parts, brought onto the same commits before they are named ──────────
# EVERY REFERENCE MOVES WITH A RELEASE, AND NOBODY MOVES ONE BY HAND. Each part names its
# siblings in its own manifest — ansiwise-checks names ansiwise-core, every package of
# ansiwise-plugins names both — and the build resolves all of them together: a part still
# naming a sibling at an older commit asks the resolver for one repository at two commits,
# which it refuses. So the two trees that name siblings are brought onto the masters this
# release names, here, before anything is minted: checks onto core, then plugins onto core and
# onto the checks commit that write produced. A tree already there is left alone, so a release
# after which nothing moved writes and pushes nothing. As with the pins downstream, the clone
# runs no hook and the subject opens with `release:`.
name_ref_in() { # <manifest> <repo> <commit>
  awk -v repo="$2" -v sha="$3" '
    $0 ~ "url: https://github.com/simetrixch/" repo "\\.git" { print; inside = 1; next }
    inside && /^[ \t]*ref:[ \t]*/ { sub(/ref:[ \t]*.*/, "ref: " sha); inside = 0 }
    { print }
  ' "$1" > "$1.next"
  mv "$1.next" "$1"
}
bring_onto() { # <repo> <subject> [<sibling> <commit>]...
  local repo="$1" subject="$2" clone="$WORK/$1" manifest
  shift 2
  git clone --quiet "https://github.com/simetrixch/${repo}.git" "$clone" \
    || die "${repo} could not be cloned, so its references could not be brought onto this release"
  GIT_TERMINAL_PROMPT=0 git -C "$clone" push --dry-run --quiet origin HEAD >/dev/null 2>&1 \
    || die "this machine may not push to ${repo}, so its references could not be brought onto this release"
  while [ $# -ge 2 ]; do
    while IFS= read -r manifest; do
      name_ref_in "$manifest" "$1" "$2"
    done < <(find "$clone" -name pubspec.yaml -not -path '*/.dart_tool/*')
    shift 2
  done
  if git -C "$clone" diff --quiet; then
    say "  ${repo} already names its siblings at these commits"
    return 0
  fi
  git -C "$clone" commit --quiet -a -m "$subject" \
    -m "Written by the release of ansiwise-cli, so every part names its siblings at the commits this release builds from." \
    || die "the references of ${repo} could not be committed"
  git -C "$clone" push --quiet origin HEAD \
    || die "the references of ${repo} could not be pushed, so they stand on this machine only"
  say "  ${repo} now names its siblings at these commits, as $(git -C "$clone" rev-parse --short=12 HEAD)"
}
CORE_SHA="$(git ls-remote "https://github.com/simetrixch/ansiwise-core.git" refs/heads/master | cut -f1)"
[ -n "$CORE_SHA" ] || die "ansiwise-core has no master to build from"
say "bringing every part onto ansiwise-core at ${CORE_SHA:0:12} before it is named"
bring_onto ansiwise-checks "release: name ansiwise-core at ${CORE_SHA:0:12}" ansiwise-core "$CORE_SHA"
CHECKS_SHA="$(git -C "$WORK/ansiwise-checks" rev-parse HEAD)"
bring_onto ansiwise-plugins "release: name ansiwise-core at ${CORE_SHA:0:12} and ansiwise-checks at ${CHECKS_SHA:0:12}" \
  ansiwise-core "$CORE_SHA" ansiwise-checks "$CHECKS_SHA"
STANDING=". The parts name their siblings at this release's commits, and nothing has been minted"

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
# THE LAST FORESEEABLE FAILURE, and left to the build it costs a tag that names
# nothing and a build that reads it. Each part names its siblings as well, and
# nothing here moves those: a part that names another at an older commit asks the
# resolver for one repository at two commits through two paths, which it refuses.
# The refusal is reported against whichever package it reached first, so it names
# one nobody edited, and it arrives minutes after a tag is already public.
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

# ── wait for the binaries, asked for BY TAG ──────────────────────────────────
# THE MANIFEST IS ADDRESSED BY THE TAG, so no answer can belong to another release: Zot answers 404
# until the publish pipeline has pushed this tag's manifest, and 200 once it stands. It is read
# anonymously, as every machine reads the binaries, so a release cannot pass on a credential the
# machines do not hold. Every other answer, and a curl that could not ask at all, is waited past as
# well, because the registry may be restarting; the last one is named if the wait runs out.
MANIFEST_URL="https://zot.master.digitacloud.app/v2/simetrixch/ansiwise-cli/manifests/$TAG"
answer=""
published=""
for _ in $(seq 1 120); do
  if status="$(curl -sS --max-time 60 -o "$WORK/manifest.json" -w '%{http_code}' \
                 -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
                 "$MANIFEST_URL" 2>"$WORK/curl.err")"; then
    answer="HTTP $status"
    if [ "$status" = 200 ]; then
      published=yes
      break
    fi
  else
    answer="curl: $(head -1 "$WORK/curl.err" 2>/dev/null || true)"
  fi
  sleep 20
done
# THE BUILD'S OWN LOG IS NOT READ HERE. It stands on the master's Tekton, behind a login this script
# does not hold, so the refusal names where it is.
[ -n "$published" ] \
  || die "$MANIFEST_URL did not answer the manifest of $TAG within 40 minutes (the last answer: ${answer:-none}). The build runs on the master's Tekton: its PipelineRun ansiwise-cli-publish-* on the Tekton Dashboard, https://tekton.master.digitacloud.app, says why"
say "Zot holds the manifest of $TAG"

# THE DIGESTS OF WHAT THIS RELEASE BUILT, as Zot holds them in the manifest the publish pipeline
# pushed. They are written beside the platform pin, in the same commit as the pin, or in a commit of
# their own where the head already names the tag without them. A machine then fetches each binary
# by its digest and holds it against the bytes built here.
#
# manifest_digests stands in release/manifest_digests.sh, sourced at the head of this script. It
# refuses a manifest that does not carry exactly one SHA-256 for every binary build.sh names, or
# that carries anything else, and sorts the lines by title, so a second run composes the same file
# the first one wrote. Written to a file rather than captured, so its refusal ends this script.
# shellcheck disable=SC2086 # the binaries are words, split on purpose
manifest_digests "$WORK/manifest.json" "$TAG" $binaries > "$WORK/digests"
digests="$(cat "$WORK/digests")"
say "digests: $(printf '%s\n' "$digests" | awk '{ printf "%s%s %s", (NR > 1 ? ", " : ""), $2, substr($1, 1, 12) }')"

# ── the two pins downstream ──────────────────────────────────────────────────
# write_pin stands in release/write_pin.sh, sourced at the head of this script.
write_pin "$PLATFORM_REPO" "$WORK/platform" "$PLATFORM_PIN" \
  "s|version: \"[0-9]+\.[0-9]+\.[0-9]+-[a-z]+-[0-9]{14}\"|version: \"$TAG\"|" \
  "release: pin the engine at $VERSION $CHANNEL" "$PLATFORM_DIGESTS" "$digests"
STANDING=" — the tag $TAG stands, ${PLATFORM_REPO} is pinned, and ${PROGRAMS_REPO} is NOT"
say "pinned ${PLATFORM_REPO} ${PLATFORM_PIN}"

RELEASE_COMMIT="$(git rev-parse "$TAG^{commit}")"
write_pin "$PROGRAMS_REPO" "$WORK/programs" "$PROGRAMS_PIN" \
  "s|- ansiwise=[0-9]+\.[0-9]+\.[0-9]+-[a-z]+-[0-9]{14}|- ansiwise=$TAG|" \
  "release: stamp the ansiwise $VERSION $CHANNEL pin into deploy-cluster" "" "" \
  "$PROGRAMS_SOURCES" "$RELEASE_COMMIT"
say "stamped ${PROGRAMS_REPO} ${PROGRAMS_PIN} and moved ${PROGRAMS_SOURCES} to $RELEASE_COMMIT"

say "DONE — $TAG is built, and every tree that names an engine names this one"
