/// What a person reads when they run tool/release.dart, what the release page says, and the one line
/// that says what the run did.
///
/// The text is here rather than written where the work happens, so a check can assert what a person
/// sees without a git, a remote or a terminal — the screen IS the feature of cli#3, and a screen
/// nothing can read is a screen nobody can hold to anything.
library;

import 'release_assets.dart';
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
        'release: OK — nothing was pushed; a release starts when a version and a channel are typed',
    isGreen: true,
  );

  /// The tag [tag] was pushed to [remote], which is the whole of what starts a release.
  ///
  /// [bumped] says what happened to the version the manifest declares, because a person who typed a
  /// version has to know whether a commit was made in their name before the tag was put on it.
  factory ReleaseOutcome.pushed({
    required String tag,
    required String remote,
    required ReleaseChannel channel,
    required String bumped,
  }) => ReleaseOutcome(
    text:
        'release: OK — the tag $tag is on $remote, and pushing it is the whole of what starts a '
        'release\n'
        '  $bumped\n'
        '  $releaseWorkflowPath runs the gate, compiles the binaries for linux-x64 and attaches\n'
        '  them to a GitHub Release named $tag:\n'
        '${assetsFor(tag).map((String each) => '    $each\n').join()}'
        '  ${channel.isPreRelease ? 'marked as a pre-release because ${channel.name} is not the ripest channel' : 'published plainly, because ${channel.name} is the ripest channel'}\n'
        '  gh run watch --repo simetrixch/ansiwise-cli   follows it\n'
        '  THE CHANNEL IS A CEILING, NOT A DEPLOYMENT: ${channel.name} reaches ${channel.reaches}.\n'
        '  Nothing in this repository enforces that ceiling — it is enforced where deployments\n'
        '  are written (hostyour-manager/shared/release.ts:8)\n'
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

/// What one run of the notes program produced: the page, or the reason there is none.
final class NotesOutcome {
  /// [page] is what the release page carries, and [isPreRelease] how the release is to be marked.
  const NotesOutcome.written({required this.page, required this.isPreRelease}) : refusal = null;

  /// Nothing was written, and [refusal] says what could not be read.
  const NotesOutcome.refused(this.refusal) : page = '', isPreRelease = false;

  /// What the release page carries.
  final String page;

  /// Whether the release is to be marked as a pre-release.
  final bool isPreRelease;

  /// Why there is no page, or null when there is one.
  final String? refusal;

  /// Whether the run did what it was asked.
  bool get isGreen => refusal == null;
}

/// The page a GitHub Release named by [release]'s tag carries.
///
/// [previous] is the release this one follows, or null when it is the first, and [subjects] are the
/// commit subjects between the two. AN EMPTY RANGE IS SAID OUT LOUD rather than left as a heading
/// with nothing under it: a release whose tag names the same commit as the last one is a real thing
/// — the same code cut on a riper channel — and a page that simply showed no changes would read as a
/// page nobody generated.
String notesFor({
  required ReleasedTag release,
  required ReleaseChannel channel,
  required String? previous,
  required List<String> subjects,
}) {
  final StringBuffer page = StringBuffer()
    ..writeln('Channel **${channel.name}** — this release may run in ${channel.reaches}.')
    ..writeln('')
    ..writeln(
      'The ceiling is enforced where deployments are written, not by this release '
      '(hostyour-manager/shared/release.ts:8).',
    )
    ..writeln('')
    ..writeln('Binaries, linux-x64, attached below — a machine is given every one of them:')
    ..writeln('')
    ..writeAll(assetsFor(release.tag).map((String each) => '- `$each`\n'))
    ..writeln('')
    ..writeln(
      previous == null
          ? '## Changes — every commit up to this tag, because nothing was released before it'
          : '## Changes since $previous',
    )
    ..writeln('');
  if (subjects.isEmpty) {
    page.writeln(
      previous == null
          ? 'No commit was found behind this tag, which is a history nobody could read.'
          : 'Nothing changed since $previous: this tag names the same code, cut again.',
    );
  }
  for (final String subject in subjects) {
    page.writeln('- $subject');
  }
  if (previous != null) {
    page
      ..writeln('')
      ..writeln('`git log --format=%s $previous..${release.tag}` is the range this was read from.');
  }
  return page.toString();
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
      ..writeln('tags on $remote this screen could not place as a release:');
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
    ..writeln('and the channel, which is a ceiling on where the tag may run:');
  for (final ReleaseChannel channel in ReleaseChannel.values) {
    screen.writeln('  ${channel.name.padRight(16)}reaches ${channel.reaches}');
  }
  screen
    ..writeln('')
    ..writeln('type the version and the channel you decided on:')
    ..writeln('  dart run tool/release.dart <version> <channel>')
    ..writeln('  dart run tool/release.dart help     what a release is, and what it is not');
  return screen.toString();
}

/// What `help` writes.
///
/// IT DOES NOT SPELL OUT WHICH TAGS ARE ADMITTED, and that is the point of cli#3 rather than a gap in
/// this text. The one place that decides is `on.push.tags` in the workflow; the program reads it
/// every run and the screen prints what it says today, so a help text carrying its own copy would be
/// the second spelling this repository was careful not to grow.
const String helpText =
    '''
release — show what has been released, and start a release of a version and a channel you type.

  dart run tool/release.dart                        what has been released, and what could come next
  dart run tool/release.dart <version> <channel>    push the tag, which starts the release
  dart run tool/release.dart help                   this

WITH NO ARGUMENTS IT CHANGES NOTHING. It reads the tags on origin, prints what has been released,
names the commit a release would carry and proposes what could come next. It never picks a version:
which release a change deserves is a decision, and a program that took it would hide it.

WHAT THE TWO ARGUMENTS COMPOSE. The tag is <major>.<minor>.<patch>-<channel>-<ts14>, where the ts14
is the UTC yyyyMMddHHmmss this program stamps at the moment you run it — never typed, which is what
makes one version cut twice on one channel two tags instead of one name pushed twice. The grammar is
hostyour-manager/shared/release.ts:22, one grammar for every release of everything.

THE CHANNEL IS A CEILING ON WHERE THE TAG MAY RUN — alpha reaches dev, beta reaches test, stable
reaches everywhere — and NOTHING HERE ENFORCES IT. It is enforced where deployments are written
(hostyour-manager/shared/release.ts:8). What the channel decides here is only whether the release
page marks the release as a pre-release.

WHICH TAGS ARE ADMITTED IS NOT WRITTEN IN THIS PROGRAM. $releaseWorkflowPath triggers on
`on.push.tags` and on nothing else, so a tag that filter does not match starts nothing — no gate, no
build, no release. The filter is read out of that file on every run and the composed tag is held
against it; run with no arguments to see what it states today. The one thing this program refuses
that the filter cannot is a leading zero in a number, because a filter pattern has no alternation and
`01.2.3` is no version.

WHAT HAPPENS WHEN YOU TYPE THEM. The working tree has to be clean. The version pubspec.yaml declares
is set to the one you typed and that bump is committed — and when the manifest already declares it,
nothing is committed and the tag names HEAD as it stands. An ANNOTATED tag is then created, HEAD is
pushed and the tag is pushed, and that is all that happens here. The workflow runs the gate, compiles
the binaries for linux-x64 and attaches each of them to a GitHub Release named by the tag — one file
per executable, named <binary>-<tag>-linux-x64, because a machine runs a program with `ansiwise` and
serves the REST surface with `ansiwise-rest` and needs both.

WHAT DOES NOT HAPPEN. No release is created here — the workflow creates it, writes its notes and
marks a pre-release. And no machine gets the new binary: hostyour-manager's place-ansiwise installs
the version `cliTools.ansiwise.version` pins in hostyour-cloud's platform/versions.yaml, and moving
that pin is a separate act in a separate repository.
''';
