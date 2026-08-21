/// What a person reads when they run tool/release.dart: the screen they decide on, the help, and the
/// one line that says what the run did.
///
/// The text is here rather than written where the work happens, so a check can assert what a person
/// sees without a git, a remote or a terminal — the screen IS the feature of cli#3, and a screen
/// nothing can read is a screen nobody can hold to anything.
library;

import 'release_tag_filter.dart';
import 'release_versions.dart';

/// What one invocation of the release program did.
final class ReleaseOutcome {
  /// [text] is everything the person reads, and [isGreen] whether the run did what it was asked.
  const ReleaseOutcome({required this.text, required this.isGreen});

  /// Nothing was done, and [why] says what was wrong.
  factory ReleaseOutcome.refused(String why) =>
      ReleaseOutcome(text: 'release: FAIL — $why', isGreen: false);

  /// [listing] was shown and nothing was touched.
  factory ReleaseOutcome.shown(String listing) => ReleaseOutcome(
    text:
        '$listing\n'
        'release: OK — nothing was pushed; a release starts when a version is typed',
    isGreen: true,
  );

  /// The tag [tag] was pushed to [remote], which is the whole of what starts a release.
  factory ReleaseOutcome.pushed({required String tag, required String remote}) => ReleaseOutcome(
    text:
        'release: OK — the tag $tag is on $remote, and pushing it is the whole of what starts a '
        'release\n'
        '  $releaseWorkflowPath runs the gate, compiles the binary for linux-x64 and attaches\n'
        '  ansiwise-$tag-linux-x64 to a GitHub Release named $tag\n'
        '  gh run watch --repo simetrixch/ansiwise-cli   follows it\n'
        '  NO MACHINE HAS IT YET: what place-ansiwise puts on a machine is the version\n'
        "  cliTools.ansiwise.version pins in hostyour-cloud's platform/versions.yaml, and this\n"
        '  release did not move that pin',
    isGreen: true,
  );

  /// Everything the person reads.
  final String text;

  /// Whether the run did what it was asked.
  final bool isGreen;
}

/// The screen shown when the program is run with no arguments: what the workflow releases on, what
/// has been released, what a tag would name, and what could come next.
///
/// [branch] and [commit] describe what HEAD is, because the tag a release pushes names THIS commit —
/// a person deciding a version is deciding which commit becomes a release, and a screen that hid it
/// would hide half the decision.
String listingOf(
  Releases releases, {
  required TagFilter filter,
  required String? declaredVersion,
  required String remote,
  required String branch,
  required String commit,
}) {
  final StringBuffer screen = StringBuffer()
    ..writeln('a tag starts a release when $releaseWorkflowPath triggers on it, which is:');
  for (final String pattern in filter.stated) {
    screen.writeln('  $pattern');
  }
  screen
    ..writeln('')
    ..writeln('released so far, read from the tags on $remote:');
  if (releases.releases.isEmpty) {
    screen.writeln('  nothing — no version of this binary has been released');
  } else {
    for (final ReleasedTag released in releases.releases.reversed) {
      screen.writeln('  ${released.tag}');
    }
  }
  if (releases.otherTags.isNotEmpty) {
    screen
      ..writeln('')
      ..writeln('tags on $remote that started no release:');
    for (final String tag in releases.otherTags) {
      screen.writeln('  $tag');
    }
  }
  screen
    ..writeln('')
    ..writeln('a release would name this commit:')
    ..writeln('  $branch at $commit')
    ..writeln('')
    ..writeln('possible next versions, none of them chosen:');
  final List<Proposal> proposals = releases.proposals(declaredVersion: declaredVersion);
  if (proposals.isEmpty) {
    screen.writeln('  none — pubspec.yaml declares no version to offer as the first release');
  }
  for (final Proposal proposal in proposals) {
    screen.writeln('  ${proposal.version.padRight(16)}${proposal.because}');
  }
  screen
    ..writeln('')
    ..writeln('type the one you decided on:')
    ..writeln('  dart run tool/release.dart <version>')
    ..writeln('  dart run tool/release.dart help     what a release is, and what it is not');
  return screen.toString();
}

/// What `help` writes.
///
/// IT DOES NOT SPELL OUT WHAT A VERSION MAY LOOK LIKE, and that is the point of cli#3 rather than a
/// gap in this text. The one place that decides is `on.push.tags` in the workflow; the program reads
/// it every run and the screen prints what it says today, so a help text carrying its own copy would
/// be the second spelling this repository was careful not to grow.
const String helpText =
    '''
release — show what has been released, and start a release of a version you type.

  dart run tool/release.dart              what has been released, and what could come next
  dart run tool/release.dart <version>    push the tag <version>, which starts the release
  dart run tool/release.dart help         this

WITH NO ARGUMENTS IT CHANGES NOTHING. It reads the tags on origin, prints what has been released,
names the commit a release would carry and proposes what could come next. It never picks a version:
which release a change deserves is a decision, and a program that took it would hide it.

WHICH VERSIONS ARE ALLOWED IS NOT WRITTEN IN THIS PROGRAM. $releaseWorkflowPath triggers on
`on.push.tags` and on nothing else, so a tag that filter does not match starts nothing — no gate, no
build, no release. The filter is read out of that file on every run and what you type is held
against it; run with no arguments to see what it states today. Nothing here carries a second copy of
it, because two copies of one grammar are two answers to "may this be released".

WHAT HAPPENS WHEN YOU TYPE ONE. The tag is created in this checkout and pushed to origin, and that
is all that happens here. The workflow then runs the gate, compiles the binary for linux-x64 and
attaches it to a GitHub Release named by the tag. The tag names the commit HEAD is at, which the
screen shows before you decide.

WHAT DOES NOT HAPPEN. No machine gets the new binary. hostyour-manager's place-ansiwise installs the
version `cliTools.ansiwise.version` pins in hostyour-cloud's platform/versions.yaml, and moving that
pin is a separate act in a separate repository.
''';
