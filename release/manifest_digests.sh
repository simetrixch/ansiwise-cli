# shellcheck shell=bash
# release/manifest_digests.sh — the digests of a release, read out of its manifest in Zot, sourced by
# release/release.sh.
#
# A file of its own so a test can call it alone (test/checks/release_digests_test.dart); it reads die
# from whoever sourced it, and needs jq.
#
# WHAT IT PRINTS is one line `<hex>  <title>` per layer, sorted by title: the lines release.sh writes
# into `clusters/platform/ansiwise.sha256` beside the platform pin. The publish pipeline pushes every
# file release/build.sh wrote as one raw blob layer, titled by the annotation
# `org.opencontainers.image.title`, so a title is a binary's file name and the digest is the address
# a machine fetches it at.
#
# EVERY BINARY OF THE TAG STANDS THERE ONCE, AND NOTHING ELSE DOES, because every machine asks for
# each binary by name and refuses a pin that lacks one, and a line naming another tag or another file
# would be a pin for bytes this release did not build. A layer whose digest is not `sha256:<64 hex>`
# is refused as well: the pin file holds SHA-256 and nothing else.
manifest_digests() { # <manifest.json> <tag> <binary>...
  local manifest="$1" tag="$2" layers said digest title binary known count lines=""
  shift 2
  if ! layers="$(jq -r '
      .layers
      | if type == "array" then . else error("it names no layers") end
      | sort_by(.annotations["org.opencontainers.image.title"] // "")
      | .[]
      | (.digest // "") + "\t" + (.annotations["org.opencontainers.image.title"] // "")
    ' "$manifest" 2>&1)"; then
    said="$(head -1 <<< "$layers")"
    die "the manifest of $tag could not be read (${said:-jq said nothing}), so nothing may be pinned to it"
  fi
  [ -n "$layers" ] || die "the manifest of $tag names no binaries, so nothing may be pinned to it"
  while IFS=$'\t' read -r digest title; do
    [[ "$digest" =~ ^sha256:[0123456789abcdef]{64}$ ]] \
      || die "the manifest of $tag answers no SHA-256 for ${title:-a layer with no title} (${digest:-no digest}), so nothing may be pinned to it"
    known=""
    for binary in "$@"; do
      if [ "$title" = "$binary-$tag-linux-x64" ]; then
        known=yes
      fi
    done
    [ -n "$known" ] \
      || die "the manifest of $tag carries ${title:-a layer with no title}, which is no binary of $tag, so nothing may be pinned to it"
    lines+="${digest#sha256:}  $title"$'\n'
  done <<< "$layers"
  for binary in "$@"; do
    count="$(printf '%s' "$lines" | awk -v file="$binary-$tag-linux-x64" '$2 == file' | grep -c . || true)"
    [ "$count" = 1 ] \
      || die "the manifest of $tag does not answer exactly one digest for $binary-$tag-linux-x64, so nothing may be pinned to it"
  done
  printf '%s' "$lines"
}
