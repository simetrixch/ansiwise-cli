#!/usr/bin/env bash
# =============================================================================
# release/build.sh — the binaries of one release, built and named as Zot holds them.
# =============================================================================
#
# WHO RUNS IT. The publish pipeline on the owner's master, on the tag release/release.sh mints:
# it clones this repository at that tag, runs `bash release/build.sh <tag> <out-dir>`, and pushes
# every file left in <out-dir> as one raw blob layer of ONE OCI manifest to Zot, at
# `zot.master.digitacloud.app/simetrixch/ansiwise-cli:<tag>`. release/release.sh then reads the
# digests a release pins out of that manifest. A person can run it the same way.
#
# WHAT IT REFUSES, each before the next step: a tag outside the release grammar, a host that is not
# linux-x64, an <out-dir> already holding a file, a Dart other than the gate's pin, and a binary
# that does not answer the tag it was built at. A refusal leaves <out-dir> without a binary, so
# nothing is published.
#
# WHAT IT LEAVES. In <out-dir> exactly one file per binary, named `<binary>-<tag>-linux-x64`, and
# nothing else, because every file there becomes a layer of the release and a machine fetches each
# binary by that name.
#
# WHAT IT CHANGES IN THE CHECKOUT. tool/build.dart writes the tag into lib/release_stamp.dart, which
# is how the binaries answer it. The pipeline's clone is thrown away; a person's checkout shows the
# change afterwards.
#
# NO GITHUB SERVICE. Nothing here asks GitHub for anything but git: `dart pub get` clones the parts
# pubspec.yaml names, at the commits it names.
set -Eeuo pipefail

# THE BINARIES OF A RELEASE, on one line that release/release.sh reads rather than restates: it
# holds the manifest to one digest for each of them.
BINARIES="ansiwise ansiwise-rest"

die() { echo "build: FAIL — $*" >&2; exit 1; }
say() { echo "build: $*"; }

TAG="${1:-}"
OUT="${2:-}"
{ [ $# -eq 2 ] && [ -n "$TAG" ] && [ -n "$OUT" ]; } \
  || die "usage: bash release/build.sh <tag> <out-dir>"
# THE GRAMMAR release/release.sh mints and hostyour-manager reads: no leading zero in a number, a
# channel of the three, and the fourteen digits of the UTC moment the tag was minted at.
[[ "$TAG" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-(alpha|beta|stable)-[0-9]{14}$ ]] \
  || die "'$TAG' is no release tag: a release tag is <x.y.z>-<alpha|beta|stable>-<14 digits>, with no leading zero"

# THE HOST BUILDS WHAT IT IS: `dart compile exe` compiles for the machine it runs on, and every
# binary is named and fetched as linux-x64. Built anywhere else, a machine would be placed files it
# cannot run, under a name that says it can.
host="$(uname -sm)" || die "uname -sm did not answer"
[ "$host" = "Linux x86_64" ] \
  || die "this host is $host, and the binaries are linux-x64: dart compile exe builds for the host it runs on, so build on Linux x86_64"

if [ -e "$OUT" ]; then
  [ -d "$OUT" ] || die "$OUT is not a directory"
  [ -z "$(ls -A "$OUT")" ] \
    || die "$OUT already holds files, and every file there would be published as a binary of $TAG"
fi
mkdir -p "$OUT" || die "$OUT could not be made"
OUT="$(cd "$OUT" && pwd)"

# The root is this file's own folder, one level up, so the script runs from wherever it is called.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say "dart pub get"
dart pub get || die "dart pub get could not resolve the parts pubspec.yaml names"

# THE PIN IS THE GATE'S, read through the gate. tool/dart_version.dart holds what this `dart` answers
# against the version package:ansiwise_checks_gate pins, with the refusal tool/ci.dart makes, so the
# version is written in one place and a release is never built under a Dart the gate would refuse.
answered="$(dart --version 2>&1)" || die "dart --version did not answer"
dart run tool/dart_version.dart "$answered" || exit 1
say "${answered%% (*}, the gate's pin"

ANSIWISE_RELEASE_TAG="$TAG" dart run tool/build.dart "$WORK/linux-x64" \
  || die "tool/build.dart did not build the binaries of $TAG"

# ASKED OF THE BINARY ITSELF, because the stamp is compiled in and nothing after this can correct it.
# Every binary is asked before any is moved, so a refusal leaves <out-dir> empty.
for binary in $BINARIES; do
  built="$WORK/linux-x64/$binary"
  [ -f "$built" ] || die "tool/build.dart wrote no $binary"
  said="$("$built" --version)" || die "$binary did not answer --version"
  [ "$said" = "$TAG" ] || die "$binary answers \"$said\" and this release is $TAG"
  say "$binary answers $said"
done
for binary in $BINARIES; do
  mv "$WORK/linux-x64/$binary" "$OUT/$binary-$TAG-linux-x64"
  say "left $OUT/$binary-$TAG-linux-x64"
done
