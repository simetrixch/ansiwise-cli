/// The version the compiled binaries answer with, written into `lib/` before anything is compiled.
///
/// **A BINARY THAT CANNOT SAY WHAT IT IS FORCES EVERYBODY ELSE TO GUESS.** Before this, the only
/// statement about which version stood on a machine was the NAME of the file a symlink pointed at,
/// and every reader downstream was built on that: a `readlink -f` probe parsing a version back out
/// of a filename, a sentinel for a file whose version nothing could read, and a hand-composed shell
/// script to install under the versioned name and link the plain one. `install_pinned_tool` — the
/// step that already manages argocd, vault and yq — decides its skip on the version and refuses a
/// tool nothing can ask, so none of them could be managed by it at all.
///
/// **THE STAMP IS A RELEASE TAG OR IT IS [unreleased], and never something in between.** A build is
/// told its tag through [releaseTagVariable] and the value is held against the grammar before it is
/// written: a tag that cannot be read is a refusal here, not a string that reaches a machine and
/// compares unequal to every pin for a reason nobody can see. A build nobody told answers
/// [unreleased], which is deliberately not shaped like a version — a developer's binary must not be
/// mistakable for a released one by anything reading its answer.
///
/// **IT IS A GENERATED SOURCE FILE and not a `--define`, for the reason `lib/plugins.dart` is: the
/// compiler reads source, `tool/build.dart` already writes that one before it compiles anything, and
/// a third mechanism beside them would be a second answer to "what does the compiler see". Nothing
/// in `lib/` may import `tool/`, so the value crosses that line as the one thing it can: a constant.
library;

import 'dart:io';

import 'release_versions.dart';

/// The environment variable a release run states the tag in.
///
/// Named for this repository rather than taken from the runner's own `GITHUB_REF_NAME`, because a
/// build is a build wherever it happens: a person compiling at a tag on their own machine states
/// the same variable, and nothing here has to know which continuous-integration product is running.
const String releaseTagVariable = 'ANSIWISE_RELEASE_TAG';

/// What a build that was told no tag answers instead.
///
/// It is a word and not a number on purpose. Anything shaped like a version would be compared
/// against a pin somewhere and found unequal, and the reader would be left deciding whether a
/// machine drifted or was never released — which is the question this whole file exists to answer.
const String unreleased = 'unreleased';

/// The file this writes, relative to the package root.
const String releaseStampFileName = 'lib/release_stamp.dart';

/// The stamp a build in [environment] carries.
///
/// Throws [ReleaseStampRefused] where the variable is set to something that is not a release tag.
/// An empty value counts as unset — a runner that templates a variable it has no value for writes
/// the empty string, and refusing that would fail every build outside a release.
String stampFor(Map<String, String> environment) {
  final String stated = environment[releaseTagVariable]?.trim() ?? '';
  if (stated.isEmpty) {
    return unreleased;
  }
  // BOTH READERS, because neither is the whole grammar on its own. ReleasedTag.read answers the
  // SHAPE — three numbers, a channel, fourteen digits — and its own numbers are `[0-9]+`, which
  // accepts a leading zero the platform's grammar forbids. numbersRefusalFor is what refuses that,
  // and it is the same reader tool/release.dart holds a typed version against, so a tag this
  // refuses here is a tag that could never have been released either.
  if (ReleasedTag.read(stated) == null) {
    throw ReleaseStampRefused(
      '$releaseTagVariable is "$stated", which is no release tag: a tag is '
      '<major>.<minor>.<patch>-<channel>-<ts14>. A binary stamped with it would answer that string '
      'to everything asking what version it is, and every pin it was held against would disagree '
      'for a reason nobody could read. State the tag being released, or nothing at all for a build '
      'that answers "$unreleased"',
    );
  }
  if (numbersRefusalFor(stated) case final String refusal) {
    throw ReleaseStampRefused('$releaseTagVariable holds a tag that is no release: $refusal');
  }
  // AND THE STAMP IS FOURTEEN DIGITS, which neither reader above says. ReleasedTag reads it as
  // `[0-9]+` because it is ordering tags that a filter already admitted, and the filter cannot
  // count either — `[0-9]+` is what a glob can write. The authority is
  // hostyour-manager/shared/release.ts:22, `-([0-9]{14})$`, and a tag one digit short is a tag that
  // repository refuses: a binary stamped with it would answer a version the platform cannot read.
  if (ReleasedTag.read(stated)?.stamp.length != _stampDigits) {
    throw ReleaseStampRefused(
      '$releaseTagVariable is "$stated", whose stamp is not $_stampDigits digits. A release is '
      'stamped yyyyMMddHHmmss in UTC, and hostyour-manager/shared/release.ts:22 reads exactly that '
      'many — a tag a digit short is one the platform refuses, so a binary answering it would name '
      'a release nothing downstream can read',
    );
  }
  return stated;
}

/// The source of [releaseStampFileName] stamping [stamp].
String releaseStampSource(String stamp) =>
    '''
// GENERATED by tool/build.dart. Do not edit.
//
// What the binaries answer when they are asked which version they are. A build is told its tag in
// the $releaseTagVariable environment variable and this file is how that value reaches the
// compiler; a build nobody told stamps "$unreleased".
//
// It is here rather than in the version a manifest declares because a manifest states three numbers
// and a release is <major>.<minor>.<patch>-<channel>-<ts14>: the channel and the stamp are what a
// pin is written with, and a comparison against three numbers alone would never match one.
library;

/// The release this binary was built at, or `$unreleased` for a build that was told no tag.
///
/// EVERY READER OF A PLACED BINARY ASKS THIS. It is what `--version` answers, what a pinned-tool
/// step compares against the pin it carries, and therefore what decides whether a machine is left
/// alone or fetched again.
const String releaseStamp = '$stamp';
''';

/// Writes [releaseStampFileName] of [package] stamping [stamp], and says whether it changed.
///
/// Returns true where the file on disk was not already what the stamp says, so a build can report
/// that it wrote one rather than leaving it to be noticed in a diff.
bool writeReleaseStamp(String package, String stamp) {
  final String source = releaseStampSource(stamp);
  final File target = File('$package/$releaseStampFileName');
  if (target.existsSync() && target.readAsStringSync().replaceAll('\r\n', '\n') == source) {
    return false;
  }
  target.writeAsStringSync(source);
  return true;
}

/// How many digits a release stamp carries: `yyyyMMddHHmmss`.
const int _stampDigits = 14;

/// A stamp that was stated and cannot be used.
final class ReleaseStampRefused implements Exception {
  /// Refuses with [message], which says what was stated and what a tag looks like.
  const ReleaseStampRefused(this.message);

  /// What a person reads.
  final String message;

  @override
  String toString() => message;
}
