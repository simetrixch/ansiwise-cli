import 'dart:io';

import 'package:test/test.dart';

import '../../tool/build.dart' show binaries;
import '../../tool/release_assets.dart';
import '../../tool/release_command.dart';
import '../../tool/release_git.dart';
import '../../tool/release_manifest.dart';
import '../../tool/release_notes_command.dart';
import '../../tool/release_report.dart';
import '../../tool/release_tag_filter.dart';
import '../../tool/release_versions.dart';

/// release — a version and a channel compose the one tag that starts a release, the tag is held
/// against the filter that decides, and it is pushed only when a person typed both.
///
/// **What cannot be shown by running it.** A real accepted run pushes a commit and a tag to GitHub,
/// which no check may do, and a release is not something to be started by a suite. So the deciding
/// half is driven over a scripted git and a manifest that is a value: what it was asked to run is a
/// list of argument lists in order, and both claims of cli#3 are readable in it — the screen RUNS
/// ONLY READS, and a version and a channel that are typed reach `git push` as the last of exactly
/// eight commands. The refusing half needs none of that and is driven as the real program, on this
/// repository's own files. NO INVOCATION HERE IS AN ACCEPTING ONE at the process level, on purpose.
///
/// **Where the grammar comes from is itself checked.** The program carries no admission grammar; it
/// reads `on.push.tags` out of .github/workflows/release.yml. The counter-probe for that is a planted
/// workflow whose filter says something else — the same tag is then accepted or refused according to
/// the file, which a program with its own copy of the grammar could not do. The two things the
/// program DOES state — that a number carries no leading zero, and that alpha is less ripe than
/// stable — are the two a glob cannot say, and each has a counter-probe of its own.
///
/// **What a release CARRIES is read the same way.** The workflow states its binaries once, in
/// `env.BINARIES`, and both of its jobs compose `<binary>-<tag>-linux-x64` from that list. What is
/// held here is that the list is tool/build.dart's `binaries` and that the shell composes the name
/// tool/release_assets.dart states — a workflow naming one binary of two, or a name nothing builds,
/// is answered by a planted file below. WHAT NO CHECK HERE CAN SHOW is the run itself: whether the
/// upload/download pair really carries both files is decided by GitHub, and this workflow has never
/// run.
void main() {
  group('which tags start a release', () {
    test('is read from the workflow this repository really has', () {
      final TagFilter filter = TagFilter.ofWorkflow(File(releaseWorkflowPath).readAsStringSync());

      expect(
        filter.unreadable,
        isNull,
        reason: 'the file that decides whether a tag starts anything has to be readable here',
      );
      expect(filter.stated, hasLength(ReleaseChannel.values.length));

      final String? declared = declaredVersionIn(File('pubspec.yaml').readAsStringSync());
      expect(
        declared,
        isNotNull,
        reason: 'the first release is proposed from what pubspec declares',
      );
      for (final ReleaseChannel channel in ReleaseChannel.values) {
        expect(
          filter.accepts(tagFor(version: declared!, channel: channel, at: _atThatMoment)),
          isTrue,
          reason:
              'the version pubspec.yaml declares is proposed as the first release, and it has to be '
              'releasable on every channel this program offers — a proposal the workflow would '
              'ignore is a proposal that starts nothing',
        );
      }
      expect(
        filter.accepts(declared!),
        isFalse,
        reason:
            'the channel is ALWAYS present: a bare 0.1.0 is not a tag under this grammar, however '
            'much it looks like the version a person typed',
      );
    });

    test('is three numbers, a channel, and fourteen digits — and nothing else', () {
      final TagFilter filter = TagFilter.ofWorkflow(File(releaseWorkflowPath).readAsStringSync());

      for (final String tag in <String>[
        '0.1.0-alpha-20260821194500',
        '0.1.0-beta-20260821194500',
        '0.1.0-stable-20260901120000',
        '1.4.2-beta-20260901120000',
        '10.0.0-stable-20991231235959',
      ]) {
        expect(
          filter.accepts(tag),
          isTrue,
          reason:
              '"$tag" is a tag by the grammar hostyour-manager/shared/release.ts:22 owns, and a '
              'filter that refused one would leave a person unable to release it',
        );
      }

      for (final String notATag in <String>[
        '0.1.0',
        '0.1.0-alpha',
        '0.1.0-beta.2',
        '0.1.0-stable-',
        '0.1.0-stable-2026082119450',
        '0.1.0-stable-202608211945000',
        '0.1.0-gamma-20260821194500',
        '0.1.0-stable-2026082119450x',
        'v0.1.0-stable-20260821194500',
        '0.1.0+7',
        'nightly',
      ]) {
        expect(
          filter.accepts(notATag),
          isFalse,
          reason:
              '"$notATag" is no tag under this grammar, and a tag that starts a release is what '
              'every machine is then given by name',
        );
      }
    });

    test('and the one thing no filter pattern can say is said by the program instead', () {
      final String workflow = File(releaseWorkflowPath).readAsStringSync();
      final TagFilter filter = TagFilter.ofWorkflow(workflow);

      // GitHub's filter patterns have no alternation, so `0|[1-9][0-9]*` cannot be written and a
      // leading zero passes `on.push.tags`. It is the ONLY thing left over now that each channel has
      // a pattern of its own and the stamp is fourteen spelled-out digits.
      expect(
        filter.accepts('01.2.3-stable-20260821194500'),
        isTrue,
        reason: 'this is the gap the workflow states, and a check that hid it would state none',
      );
      expect(
        workflow,
        contains('01.2.3-stable-20260901120000 is\n      # admitted here'),
        reason:
            'the gap is named in the file where the filter is written, so a narrowing that leaves '
            'this behind is read there rather than found on a release day',
      );
      expect(
        numbersRefusalFor('01.2.3'),
        allOf(contains('leading zero'), contains('release.ts:22')),
        reason: 'what the filter cannot refuse is refused where the tag is composed',
      );
      expect(
        numbersRefusalFor('1.2.3'),
        isNull,
        reason: 'the innocent case, or nothing means anything',
      );
      expect(
        numbersRefusalFor('0.1.0'),
        isNull,
        reason: 'a lone 0 is a number, and refusing it would refuse every version this repo has',
      );
    });

    test('COUNTER-PROBE: the patterns that stood here before admit what this grammar refuses', () {
      // PLANTED: the two patterns this workflow triggered on before the platform grammar — three
      // numbers, and anything at all after a hyphen. They admit a tag with no channel and a tag with
      // no stamp, which is what the release page and the deployment ceiling now read.
      final TagFilter asItWas = TagFilter.ofWorkflow(
        _workflowTriggeringOn(<String>["'[0-9]+.[0-9]+.[0-9]+'", "'[0-9]+.[0-9]+.[0-9]+-*'"]),
      );
      expect(asItWas.accepts('0.1.0'), isTrue);
      expect(asItWas.accepts('0.1.0-beta.2'), isTrue);
      expect(asItWas.accepts('0.1.0-'), isTrue);
      expect(
        asItWas.accepts('0.1.0-stable-20260821194500'),
        isTrue,
        reason: 'the innocent case, or nothing means anything',
      );

      final TagFilter now = TagFilter.ofWorkflow(File(releaseWorkflowPath).readAsStringSync());
      expect(now.accepts('0.1.0'), isFalse);
      expect(now.accepts('0.1.0-beta.2'), isFalse);
      expect(now.accepts('0.1.0-'), isFalse);
      expect(now.accepts('0.1.0-stable-20260821194500'), isTrue);
    });

    test('COUNTER-PROBE: a workflow saying something else is answered by what it says', () {
      final TagFilter asItIs = TagFilter.ofWorkflow(
        _workflowTriggeringOn(<String>["'[0-9]+.[0-9]+.[0-9]+-stable-$_fourteenDigits'"]),
      );
      expect(asItIs.accepts('0.1.0-stable-20260821194500'), isTrue);
      expect(
        asItIs.accepts('v0.1.0-stable-20260821194500'),
        isFalse,
        reason: 'the innocent case, or nothing means anything',
      );

      // PLANTED: the same filter with a v in front of it, which is a filter this repository does not
      // have. A program carrying its own copy of the grammar would answer both of these the same way
      // as above and neither of the two expectations below would hold.
      final TagFilter withAV = TagFilter.ofWorkflow(
        _workflowTriggeringOn(<String>["'v[0-9]+.[0-9]+.[0-9]+-stable-$_fourteenDigits'"]),
      );
      expect(withAV.accepts('v0.1.0-stable-20260821194500'), isTrue);
      expect(withAV.accepts('0.1.0-stable-20260821194500'), isFalse);
    });

    test('a workflow that states no tag is a refusal, not a filter accepting everything', () {
      for (final String workflow in <String>[
        'name: release\non:\n  workflow_dispatch:\njobs:\n  gate:\n',
        'name: release\njobs:\n  gate:\n',
        'name: release\non:\n  push:\n    branches:\n      - master\n',
      ]) {
        final TagFilter filter = TagFilter.ofWorkflow(workflow);
        expect(filter.unreadable, contains(releaseWorkflowPath));
        expect(
          filter.accepts('0.1.0-stable-20260821194500'),
          isFalse,
          reason: 'a filter nobody could read must accept nothing, or it accepts everything',
        );
      }
    });

    test('a pattern this program cannot read is refused by name', () {
      for (final (String pattern, String said) in <(String, String)>[
        ("'!0.1.0'", 'negates'),
        ("'[0-9.0'", 'never closes'),
        ("'+0.1.0'", 'nothing in front of it'),
        (r"'0.1.0\'", 'ends on a backslash'),
        ("''", 'it is empty'),
      ]) {
        final TagFilter filter = TagFilter.ofWorkflow(_workflowTriggeringOn(<String>[pattern]));
        expect(
          filter.unreadable,
          contains(said),
          reason: 'a filter guessed at is worse than one refused',
        );
      }
    });

    test('the refusal names where in what was typed the filter stopped reading', () {
      final TagFilter filter = TagFilter.ofWorkflow(
        _workflowTriggeringOn(<String>["'[0-9]+.[0-9]+.[0-9]+-stable-$_fourteenDigits'"]),
      );

      expect(
        filter.refusalFor('v0.1.0-stable-20260821194500'),
        allOf(contains('[0-9]+'), contains('"v0.1.0-stable-20260821194500" stands there')),
      );
      expect(filter.refusalFor('0.1.0-stable-2026'), contains('ends there'));
      expect(filter.refusalFor('0.1.0-beta-20260821194500'), contains('after "0.1.0-"'));
      expect(
        filter.refusalFor('0.1.0-stable-20260821194500'),
        isNull,
        reason: 'a refusal that had something to say about every tag would say nothing',
      );
      expect(filter.refusalFor('v0.1.0-stable-20260821194500'), contains(releaseWorkflowPath));
    });
  });

  group('the tag a version and a channel compose', () {
    test('is the three numbers, the channel, and the moment it was stamped at', () {
      expect(
        tagFor(version: '1.4.2', channel: ReleaseChannel.beta, at: _atThatMoment),
        '1.4.2-beta-20260821194500',
      );
      expect(
        _theFilter.accepts(
          tagFor(version: '1.4.2', channel: ReleaseChannel.beta, at: _atThatMoment),
        ),
        isTrue,
        reason: 'what this composes has to be what the workflow triggers on, or it builds nothing',
      );
    });

    test('is stamped in UTC, and is fourteen digits at every moment', () {
      expect(stampOf(DateTime.utc(2026, 8, 21, 19, 45)), '20260821194500');
      expect(
        stampOf(DateTime.utc(2026, 1, 2, 3, 4, 5)),
        '20260102030405',
        reason: 'a single-digit month, day, hour, minute or second is padded, or it is thirteen',
      );
      expect(
        stampOf(DateTime.utc(2026, 8, 21, 19, 45).toLocal()),
        '20260821194500',
        reason:
            'the same moment written in this machine\'s time zone is the same tag, or two machines '
            'releasing at once would compose two different names for one instant',
      );
      for (final DateTime moment in <DateTime>[
        DateTime.utc(2026),
        DateTime.utc(2026, 12, 31, 23, 59, 59),
        DateTime.utc(2099, 6, 15, 12),
      ]) {
        expect(stampOf(moment), hasLength(14));
        expect(
          _theFilter.accepts(tagFor(version: '0.1.0', channel: ReleaseChannel.alpha, at: moment)),
          isTrue,
        );
      }
    });
  });

  group('the order the screen lists releases in', () {
    test('is the numbers first, and then the moment each was minted at', () {
      final Releases releases = Releases.ofTags(<String>[
        '0.1.0-alpha-20260801100000',
        '0.1.0-stable-20260810100000',
        '0.1.0-alpha-20260812100000',
        '0.2.0-alpha-20260805100000',
        '0.10.0-beta-20260806100000',
      ], filter: _theFilter);

      expect(
        releases.releases.map((ReleasedTag each) => each.tag),
        <String>[
          '0.1.0-alpha-20260801100000',
          '0.1.0-stable-20260810100000',
          '0.1.0-alpha-20260812100000',
          '0.2.0-alpha-20260805100000',
          '0.10.0-beta-20260806100000',
        ],
        reason:
            '0.10.0 is later than 0.2.0 for the numbers, and within 0.1.0 the alpha cut two days '
            'after the stable is the later release — a fix cut on alpha after a stable release is '
            'exactly what a screen must not show as the older one',
      );
      expect(releases.latest?.tag, '0.10.0-beta-20260806100000');
    });

    test('a tag that would have started no release is kept, and named as such', () {
      final Releases releases = Releases.ofTags(<String>[
        '0.1.0-stable-20260810100000',
        'nightly',
        '0.1.0',
        'v0.9.9-stable-20260810100000',
      ], filter: _theFilter);

      expect(releases.releases.map((ReleasedTag each) => each.tag), <String>[
        '0.1.0-stable-20260810100000',
      ]);
      expect(
        releases.otherTags,
        <String>['0.1.0', 'nightly', 'v0.9.9-stable-20260810100000'],
        reason:
            'a person deciding a version has to see everything standing on the remote, including '
            'the tags that started nothing',
      );
      expect(releases.holds('nightly'), isTrue, reason: 'the name is taken whatever it started');
    });

    test(
      'proposes the three directions after stable, and the same version after a pre-release',
      () {
        expect(
          Releases.ofTags(<String>[
            '1.4.2-stable-20260810100000',
          ], filter: _theFilter).proposals(declaredVersion: '0.1.0').map(_version),
          <String>['1.4.3', '1.5.0', '2.0.0'],
        );
        final List<Proposal> afterAlpha = Releases.ofTags(<String>[
          '1.4.2-alpha-20260810100000',
        ], filter: _theFilter).proposals(declaredVersion: '0.1.0');
        expect(afterAlpha.map(_version), <String>['1.4.2']);
        expect(
          afterAlpha.single.because,
          allOf(contains('released on alpha'), contains('beta or stable')),
          reason:
              'under this grammar the same version on a riper channel is a release of its own, and '
              'the reason has to say which channels it has not been cut on yet',
        );
        expect(
          Releases.ofTags(<String>[
            '1.4.2-beta-20260810100000',
          ], filter: _theFilter).proposals(declaredVersion: '0.1.0').single.because,
          allOf(contains('released on beta'), contains('stable')),
        );
        expect(
          Releases.ofTags(
            <String>[],
            filter: _theFilter,
          ).proposals(declaredVersion: '0.1.0').map(_version),
          <String>['0.1.0'],
          reason:
              'the only version this repository states about itself is the one pubspec declares',
        );
        expect(
          Releases.ofTags(<String>[], filter: _theFilter).proposals(declaredVersion: null),
          isEmpty,
          reason: 'a first release invented here would be a version no file states',
        );
      },
    );

    test('COUNTER-PROBE: a channel nothing ranks is placed, and said to be unrankable', () {
      // PLANTED: a filter admitting a fourth channel. The program's ranking is the maturity order of
      // hostyour-manager/shared/release.ts:12 and cannot be read out of a glob, so a widened filter
      // has to show up as a release whose ripeness nobody here can state — never as a release
      // quietly treated as finished, and never as a tag dropped off the screen.
      final TagFilter withAFourth = TagFilter.ofWorkflow(
        _workflowTriggeringOn(<String>["'[0-9]+.[0-9]+.[0-9]+-gamma-$_fourteenDigits'"]),
      );
      final Releases releases = Releases.ofTags(<String>[
        '1.4.2-gamma-20260810100000',
      ], filter: withAFourth);

      expect(releases.releases.single.channel, isNull);
      expect(releases.releases.single.channelName, 'gamma');
      expect(
        releases.proposals(declaredVersion: '0.1.0').single.because,
        contains('nothing ranks its channel "gamma"'),
      );
      expect(
        Releases.ofTags(<String>[
          '1.4.2-beta-20260810100000',
        ], filter: _theFilter).releases.single.channel,
        ReleaseChannel.beta,
        reason: 'the innocent case, or nothing means anything',
      );
    });

    test('the version pubspec declares is read from the manifest, and written back into it', () {
      expect(declaredVersionIn('name: ansiwise_cli\nversion: 1.4.2\n\ndependencies:\n'), '1.4.2');
      expect(declaredVersionIn('name: ansiwise_cli\ndependencies:\n  args: ^2.7.0\n'), isNull);
      expect(
        pubspecWithVersion('name: ansiwise_cli\nversion: 1.4.2\n\ndependencies:\n', '1.5.0'),
        'name: ansiwise_cli\nversion: 1.5.0\n\ndependencies:\n',
      );
      expect(
        pubspecWithVersion('name: ansiwise_cli\ndependencies:\n', '1.5.0'),
        isNull,
        reason: 'a manifest declaring no version is a refusal, not a line invented at the bottom',
      );
    });
  });

  group('the screen', () {
    test('shows what has been released, latest first, and what could come next', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{_readTags.join(' '): _twoReleases});

      final ReleaseOutcome outcome = await _command(git).show();

      expect(outcome.isGreen, isTrue);
      expect(outcome.text, contains('0.1.0-alpha-20260801100000'));
      expect(outcome.text, contains('master at 58adecd'));
      expect(
        outcome.text,
        contains('0.1.0'),
        reason: 'the latest release is 0.1.0 on alpha, so 0.1.0 on a riper channel is proposed',
      );
      for (final String pattern in _theFilter.stated) {
        expect(
          outcome.text,
          contains(pattern),
          reason:
              'every pattern the workflow triggers on is on the screen, because this program states '
              'no admission grammar a person could read anywhere else',
        );
      }
      for (final String said in <String>[
        'alpha           reaches dev',
        'beta            reaches dev and test',
        'stable          reaches everywhere',
      ]) {
        expect(
          outcome.text,
          contains(said),
          reason:
              'the channel is the second of the two decisions, and a screen that offered no reading '
              'of what it costs would leave half the decision unexplained',
        );
      }
      expect(
        outcome.text,
        contains('nightly'),
        reason: 'a tag that started no release still stands on the remote',
      );
      expect(
        outcome.text
            .split('\n')
            .where((String line) => line.trim() == '0.1.0-alpha-20260801100000')
            .length,
        1,
        reason:
            'the annotated tag is listed twice by git, once peeled with ^{}, and two lines for one '
            'release would read as two releases',
      );
    });

    test('changes nothing at all', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{_readTags.join(' '): _twoReleases});
      final FakeManifest manifest = _aManifestAt('0.1.0');

      await _command(git, manifest: manifest).show();

      expect(
        git.ran,
        <List<String>>[_readTags, _readBranch, _readCommit],
        reason:
            'running with no arguments proposes, and a proposal that tagged, committed or pushed '
            'anything would have taken the decision this program exists to leave to a person',
      );
      expect(manifest.writes, isEmpty, reason: 'and it bumps nothing either');
    });

    test('a remote it could not read is not a remote with nothing on it', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{
        _readTags.join(' '): const GitAnswer(
          status: 128,
          output:
              "fatal: could not read Username for 'https://github.com': terminal prompts disabled",
        ),
      });

      final ReleaseOutcome outcome = await _command(git).show();

      expect(outcome.isGreen, isFalse);
      expect(outcome.text, contains('could not be read'));
      expect(
        outcome.text,
        contains('could not read Username'),
        reason: 'what git said is what tells the person whether this is a credential or a network',
      );
      expect(
        outcome.text,
        isNot(contains('the first release')),
        reason:
            'an unreadable remote proposing a first release would offer one to somebody who has '
            'already released 1.4.2',
      );
    });
  });

  group('a version and a channel that are typed', () {
    test('bump, commit, annotated tag, HEAD, tag — in that order and no other', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{_readTags.join(' '): _twoReleases});
      final FakeManifest manifest = _aManifestAt('0.1.0');

      final ReleaseOutcome outcome = await _command(
        git,
        manifest: manifest,
      ).release('0.2.0', 'stable');

      const String tag = '0.2.0-stable-20260821194500';
      expect(git.ran, <List<String>>[
        <String>['status', '--porcelain'],
        <String>['rev-parse', '-q', '--verify', 'refs/tags/$tag'],
        _readTags,
        <String>['add', '--update'],
        <String>['commit', '-m', 'release: $tag'],
        <String>['tag', '-a', tag, '-m', tag],
        <String>['push', 'origin', 'HEAD'],
        <String>['push', 'origin', 'refs/tags/$tag'],
      ]);
      expect(
        manifest.text,
        contains('version: 0.2.0'),
        reason: 'the tag and the version the package declares have to be one answer, not two',
      );
      expect(outcome.isGreen, isTrue);
      expect(outcome.text, contains('the tag $tag is on origin'));
      expect(
        outcome.text,
        allOf(contains('ansiwise-$tag-linux-x64'), contains('ansiwise-rest-$tag-linux-x64')),
        reason:
            'the person has to read the name of EVERY file the release will carry — a screen '
            'naming one of two reads as a release that carries one',
      );
      expect(
        outcome.text,
        contains('published plainly, because stable is the ripest channel'),
        reason: 'how the workflow will mark it is decided by the channel that was typed',
      );
      expect(
        outcome.text,
        allOf(
          contains('stable reaches everywhere'),
          contains('Nothing in this repository enforces'),
        ),
        reason:
            'the ceiling is what the channel costs, and this program cannot enforce it — saying the '
            'first without the second would be a guarantee nothing here makes',
      );
      expect(
        outcome.text,
        contains('cliTools.ansiwise.version'),
        reason:
            'a release is not an installation: what a machine is given is what that pin names, and '
            'this run did not move it',
      );
    });

    test('an alpha is said to be marked a pre-release, and the tag carries the channel', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{_readTags.join(' '): _twoReleases});

      final ReleaseOutcome outcome = await _command(git).release('0.2.0', 'alpha');

      expect(outcome.isGreen, isTrue);
      expect(outcome.text, contains('0.2.0-alpha-20260821194500'));
      expect(outcome.text, contains('marked as a pre-release because alpha is not the ripest'));
      expect(outcome.text, contains('alpha reaches dev'));
    });

    test('a manifest already declaring the version is not a commit saying nothing', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{_readTags.join(' '): _twoReleases});
      final FakeManifest manifest = _aManifestAt('0.2.0');

      final ReleaseOutcome outcome = await _command(
        git,
        manifest: manifest,
      ).release('0.2.0', 'beta');

      expect(manifest.writes, isEmpty);
      expect(
        git.ran.map((List<String> each) => each.first),
        isNot(contains('add')),
        reason: '`git commit` on an empty index refuses, and a commit forced through says nothing',
      );
      expect(git.ran.map((List<String> each) => each.first), isNot(contains('commit')));
      expect(outcome.isGreen, isTrue);
      expect(outcome.text, contains('already declared 0.2.0'));
      expect(outcome.text, contains('names HEAD as it stood'));
    });

    test('COUNTER-PROBE: a channel nothing ranks is refused before a remote is reached', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{});
      final FakeManifest manifest = _aManifestAt('0.1.0');

      final ReleaseOutcome outcome = await _command(
        git,
        manifest: manifest,
      ).release('0.2.0', 'gamma');

      expect(outcome.isGreen, isFalse);
      expect(outcome.text, contains('"gamma" is no channel'));
      expect(outcome.text, contains('alpha, beta, stable'));
      expect(outcome.text, contains('release.ts:12'));
      expect(
        git.ran,
        isEmpty,
        reason: 'a channel nothing ranks is answered by this program, not by asking GitHub',
      );
      expect(manifest.writes, isEmpty);
      expect(
        (await _command(
          _gitAnswering(<String, GitAnswer>{_readTags.join(' '): _twoReleases}),
        ).release('0.2.0', 'beta')).isGreen,
        isTrue,
        reason: 'the innocent case, or nothing means anything',
      );
    });

    test(
      'COUNTER-PROBE: a leading zero the filter admits is refused before anything is written',
      () async {
        final ScriptedGit git = _gitAnswering(<String, GitAnswer>{});
        final FakeManifest manifest = _aManifestAt('0.1.0');

        expect(
          _theFilter.accepts('01.2.3-stable-20260821194500'),
          isTrue,
          reason: 'the filter admits it — that is the whole reason this refusal has to exist',
        );

        final ReleaseOutcome outcome = await _command(
          git,
          manifest: manifest,
        ).release('01.2.3', 'stable');

        expect(outcome.isGreen, isFalse);
        expect(outcome.text, contains('leading zero'));
        expect(git.ran, isEmpty);
        expect(manifest.writes, isEmpty);
      },
    );

    test('a version the filter refuses says the version is what stopped it', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{});

      final ReleaseOutcome outcome = await _command(git).release('0.2', 'stable');

      expect(outcome.isGreen, isFalse);
      expect(outcome.text, contains('"0.2" is no version'));
      expect(
        outcome.text,
        contains('the channel "stable" is one it does'),
        reason:
            'two arguments were typed and one of them is wrong: a refusal that named neither would '
            'leave the person reading a whole tag they never typed',
      );
      expect(outcome.text, contains(releaseWorkflowPath));
      expect(git.ran, isEmpty);
    });

    test(
      'COUNTER-PROBE: a filter that drops a channel refuses it, though the program ranks it',
      () async {
        // PLANTED: a workflow triggering on stable alone. `beta` is a channel this program ranks and
        // this filter does not, which is the opposite direction to the gamma probe above — and the two
        // refusals have to be told apart, or a person is sent to the wrong file.
        final ScriptedGit git = _gitAnswering(<String, GitAnswer>{});
        final ReleaseCommand command = ReleaseCommand(
          git: git,
          manifest: _aManifestAt('0.1.0'),
          filter: TagFilter.ofWorkflow(
            _workflowTriggeringOn(<String>["'[0-9]+.[0-9]+.[0-9]+-stable-$_fourteenDigits'"]),
          ),
          now: _theClock,
        );

        final ReleaseOutcome outcome = await command.release('0.2.0', 'beta');

        expect(outcome.isGreen, isFalse);
        expect(outcome.text, contains('does not trigger on the channel "beta"'));
        expect(outcome.text, isNot(contains('is no channel')));
        expect(git.ran, isEmpty);
        expect(
          (await command.release('0.2.0', 'stable')).isGreen,
          isTrue,
          reason: 'the innocent case, or nothing means anything',
        );
      },
    );

    test('COUNTER-PROBE: a dirty working tree is refused before the manifest is touched', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{
        'status --porcelain': const GitAnswer(
          status: 0,
          output: ' M lib/ansiwise.dart\n?? scratch\n',
        ),
      });
      final FakeManifest manifest = _aManifestAt('0.1.0');

      final ReleaseOutcome outcome = await _command(
        git,
        manifest: manifest,
      ).release('0.2.0', 'stable');

      expect(outcome.isGreen, isFalse);
      expect(outcome.text, contains('the working tree is not clean — commit or stash first'));
      expect(
        outcome.text,
        contains('M lib/ansiwise.dart'),
        reason: 'what git listed is what tells the person which change the tag would have missed',
      );
      expect(git.ran, <List<String>>[
        <String>['status', '--porcelain'],
      ], reason: 'the tag would name a commit carrying none of it, so nothing after this may run');
      expect(manifest.writes, isEmpty);
    });

    test('is refused when the tag already stands in this checkout', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{
        'rev-parse -q --verify refs/tags/0.2.0-stable-20260821194500': const GitAnswer(
          status: 0,
          output: '9f2b7d1c4e8a6b3f5d0c9e7a2b4f6d8c1a3e5b7d\n',
        ),
      });

      final ReleaseOutcome outcome = await _command(git).release('0.2.0', 'stable');

      expect(outcome.isGreen, isFalse);
      expect(outcome.text, contains('already exists in this checkout'));
      expect(
        outcome.text,
        contains('same second'),
        reason:
            'the stamp comes from the clock, so this is a run inside one second or a clock that '
            'went backwards, and a person told only "it exists" would not know to try again',
      );
      expect(git.ran, hasLength(2));
    });

    test('is refused when the tag already stands on the remote, and nothing is written', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{
        _readTags.join(' '): const GitAnswer(
          status: 0,
          output:
              '9f2b7d1c4e8a6b3f5d0c9e7a2b4f6d8c1a3e5b7d\trefs/tags/0.2.0-stable-20260821194500\n',
        ),
      });
      final FakeManifest manifest = _aManifestAt('0.1.0');

      final ReleaseOutcome outcome = await _command(
        git,
        manifest: manifest,
      ).release('0.2.0', 'stable');

      expect(outcome.isGreen, isFalse);
      expect(outcome.text, contains('already stands on origin'));
      expect(git.ran, hasLength(3));
      expect(manifest.writes, isEmpty);
    });

    test('is refused when the tags could not be read, and nothing is written', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{
        _readTags.join(' '): const GitAnswer(status: 128, output: 'fatal: no such remote'),
      });
      final FakeManifest manifest = _aManifestAt('0.1.0');

      final ReleaseOutcome outcome = await _command(
        git,
        manifest: manifest,
      ).release('0.2.0', 'stable');

      expect(outcome.isGreen, isFalse);
      expect(
        git.ran,
        hasLength(3),
        reason:
            'a release pushed against an unknown history could be a '
            'version that already exists',
      );
      expect(manifest.writes, isEmpty);
    });

    test('says the tag is still here when the remote refused the commit', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{
        _readTags.join(' '): _twoReleases,
        'push origin HEAD': const GitAnswer(status: 1, output: 'error: failed to push some refs'),
      });

      final ReleaseOutcome outcome = await _command(git).release('0.2.0', 'stable');

      expect(outcome.isGreen, isFalse);
      expect(outcome.text, contains('failed to push some refs'));
      expect(
        outcome.text,
        contains('git tag -d 0.2.0-stable-20260821194500'),
        reason:
            'the tag was created here before anything was pushed, and a person left with it and no '
            'way named to remove it cannot try again',
      );
      expect(
        git.ran.map((List<String> each) => each.join(' ')),
        isNot(contains('push origin refs/tags/0.2.0-stable-20260821194500')),
        reason: 'a tag naming a commit origin does not have is a release nothing can build',
      );
    });

    test('says the commit is already on the remote when the tag was refused', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{
        _readTags.join(' '): _twoReleases,
        'push origin refs/tags/0.2.0-stable-20260821194500': const GitAnswer(
          status: 1,
          output: 'error: failed to push some refs',
        ),
      });

      final ReleaseOutcome outcome = await _command(git).release('0.2.0', 'stable');

      expect(outcome.isGreen, isFalse);
      expect(
        outcome.text,
        contains('THE COMMIT IS ALREADY ON origin and this program does not take it back'),
        reason:
            'the bump was pushed before the tag was, and a refusal that did not say so would leave '
            'a person believing the run changed nothing',
      );
      expect(outcome.text, contains('git tag -d 0.2.0-stable-20260821194500'));
    });

    test('does not push when the annotated tag could not be created here', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{
        _readTags.join(' '): _twoReleases,
        'tag -a 0.2.0-stable-20260821194500 -m 0.2.0-stable-20260821194500': const GitAnswer(
          status: 128,
          output: "fatal: tag '0.2.0-stable-20260821194500' already exists",
        ),
      });

      final ReleaseOutcome outcome = await _command(git).release('0.2.0', 'stable');

      expect(outcome.text, contains('already exists'));
      expect(
        git.ran.map((List<String> each) => each.first),
        isNot(contains('push')),
        reason: 'nothing reaches the remote once the tag it would name could not be made',
      );
    });
  });

  group('the notes the workflow publishes', () {
    test('name the channel, the binary, and every commit since the release before', () async {
      final ScriptedGit git = ScriptedGit(
        answers: <String, GitAnswer>{
          'tag --list': const GitAnswer(
            status: 0,
            output: '0.1.0-alpha-20260801100000\n0.2.0-beta-20260821194500\nnightly\n',
          ),
          'log --format=%s 0.1.0-alpha-20260801100000..0.2.0-beta-20260821194500': const GitAnswer(
            status: 0,
            output: 'Narrow the tag filter\nCarry the Elastic License 2.0\n',
          ),
        },
      );

      final NotesOutcome outcome = await ReleaseNotesCommand(
        git: git,
        filter: _theFilter,
      ).of('0.2.0-beta-20260821194500');

      expect(outcome.isGreen, isTrue);
      expect(outcome.isPreRelease, isTrue, reason: 'beta is not the ripest channel');
      expect(outcome.page, contains('Channel **beta** — this release may run in dev and test.'));
      expect(
        outcome.page,
        allOf(
          contains('- `ansiwise-0.2.0-beta-20260821194500-linux-x64`'),
          contains('- `ansiwise-rest-0.2.0-beta-20260821194500-linux-x64`'),
        ),
        reason:
            'the page is where somebody looks for what a release carries, and it carries two files '
            'because a machine runs nothing with only one of them',
      );
      expect(outcome.page, contains('## Changes since 0.1.0-alpha-20260801100000'));
      expect(outcome.page, contains('- Narrow the tag filter'));
      expect(outcome.page, contains('- Carry the Elastic License 2.0'));
      expect(
        outcome.page,
        contains('git log --format=%s 0.1.0-alpha-20260801100000..0.2.0-beta-20260821194500'),
        reason: 'the range the sentences came from is what makes the page checkable by a reader',
      );
    });

    test('a stable release is not a pre-release, and its page says where it may run', () async {
      final ScriptedGit git = ScriptedGit(
        answers: <String, GitAnswer>{
          'tag --list': const GitAnswer(status: 0, output: '0.2.0-stable-20260821194500\n'),
          'log --format=%s 0.2.0-stable-20260821194500': const GitAnswer(
            status: 0,
            output: 'Carry the Elastic License 2.0\n',
          ),
        },
      );

      final NotesOutcome outcome = await ReleaseNotesCommand(
        git: git,
        filter: _theFilter,
      ).of('0.2.0-stable-20260821194500');

      expect(outcome.isGreen, isTrue);
      expect(outcome.isPreRelease, isFalse);
      expect(outcome.page, contains('Channel **stable** — this release may run in everywhere.'));
      expect(
        outcome.page,
        contains(
          '## Changes — every commit up to this tag, because nothing was released before it',
        ),
        reason:
            'the first release follows nothing, and a range against nothing would read as empty',
      );
    });

    test('COUNTER-PROBE: a channel nothing ranks is refused, never marked by a guess', () async {
      // PLANTED: a workflow triggering on a fourth channel. Marking that release would be a guess
      // about how finished it is, printed on a page everybody reads.
      final NotesOutcome outcome = await ReleaseNotesCommand(
        git: ScriptedGit(),
        filter: TagFilter.ofWorkflow(
          _workflowTriggeringOn(<String>["'[0-9]+.[0-9]+.[0-9]+-gamma-$_fourteenDigits'"]),
        ),
      ).of('1.4.2-gamma-20260810100000');

      expect(outcome.isGreen, isFalse);
      expect(outcome.refusal, contains('not one of alpha, beta, stable'));
      expect(outcome.refusal, contains(releaseWorkflowPath));
      expect(
        (await ReleaseNotesCommand(
          git: ScriptedGit(),
          filter: _theFilter,
        ).of('1.4.2-beta-20260810100000')).isGreen,
        isTrue,
        reason: 'the innocent case, or nothing means anything',
      );
    });

    test(
      'a history it could not read refuses, rather than a page saying nothing changed',
      () async {
        final NotesOutcome outcome = await ReleaseNotesCommand(
          git: ScriptedGit(
            answers: <String, GitAnswer>{
              'tag --list': const GitAnswer(status: 0, output: '0.2.0-stable-20260821194500\n'),
              'log --format=%s 0.2.0-stable-20260821194500': const GitAnswer(
                status: 128,
                output: "fatal: bad revision '0.2.0-stable-20260821194500'",
              ),
            },
          ),
          filter: _theFilter,
        ).of('0.2.0-stable-20260821194500');

        expect(outcome.isGreen, isFalse);
        expect(outcome.refusal, contains('fetch-depth: 0'));
      },
    );

    test('a tag the workflow would not have started is refused', () async {
      final NotesOutcome outcome = await ReleaseNotesCommand(
        git: ScriptedGit(),
        filter: _theFilter,
      ).of('v0.1.0');

      expect(outcome.isGreen, isFalse);
      expect(outcome.refusal, contains('would start no release'));
    });
  });

  group('the names the release carries', () {
    test('are one file per binary, spelled so one address composes both', () {
      expect(assetsFor(_aTag), <String>[
        'ansiwise-$_aTag-linux-x64',
        'ansiwise-rest-$_aTag-linux-x64',
      ], reason: 'these two strings are what hostyour-manager and digita-deploy fetch by name');
      expect(
        assetsFor(_aTag).map((String each) => each.split('-$_aTag-').first),
        binaries.keys,
        reason:
            'the leading part of an asset name is the name the binary carries on the machine — the '
            'name tool/build.dart writes and the name each binary looks for the other under. That '
            'is what lets ONE address fill in <name> and <version> and reach either file, instead '
            'of a second setting able to name a second release',
      );
    });

    test('are the set the workflow really builds and attaches', () {
      final String workflow = File(releaseWorkflowPath).readAsStringSync();

      expect(
        binariesIn(workflow),
        binaries.keys.toList(),
        reason:
            'the workflow states the list once in `env.BINARIES` and both jobs compose from it; a '
            'list that is not tool/build.dart\'s is a release attaching a file nothing built or '
            'leaving behind a binary the build wrote',
      );
      expect(
        assetFor(binary: r'$binary', tag: r'$TAG').allMatches(workflow),
        hasLength(2),
        reason:
            'the build job moves each built binary to this name and the publish job requires a '
            'file behind the same name before it creates the release. Both are the shell spelling '
            'of assetFor, so a third spelling anywhere is a third answer to what a release carries',
      );
    });

    test('COUNTER-PROBE: a workflow naming one binary of the two is reported', () {
      // PLANTED: the list as it stood while this repository produced one executable. Every other
      // line of the file is the real one, so what is being answered here is the list alone.
      expect(
        binariesIn(_workflowBuilding('ansiwise')),
        isNot(binaries.keys.toList()),
        reason: 'a release cut from this workflow carries no ansiwise-rest, and nothing said so',
      );
      expect(
        binariesIn(_workflowBuilding('ansiwise ansiwise-rest')),
        binaries.keys.toList(),
        reason: 'the innocent case, or nothing means anything',
      );
    });

    test('COUNTER-PROBE: a workflow naming a binary nothing builds is reported', () {
      // PLANTED: a name tool/build.dart does not write. The build job would find no such file and
      // stop; this is what says so before a tag is ever pushed.
      expect(binariesIn(_workflowBuilding('ansiwise ansiwise-serve')), <String>[
        'ansiwise',
        'ansiwise-serve',
      ]);
      expect(
        binariesIn(_workflowBuilding('ansiwise ansiwise-serve')),
        isNot(binaries.keys.toList()),
      );
    });

    test('COUNTER-PROBE: a list nowhere in the file is no list, not every binary', () {
      expect(
        binariesIn('name: release\n\njobs:\n  build:\n    env:\n      BINARIES: ansiwise\n'),
        isEmpty,
        reason:
            'a job may carry an env of its own, and reading one as the release list would let a '
            'file that states nothing pass for the file that states everything',
      );
    });
  });

  group('the program as a person starts it', () {
    test('refuses a version no release may carry, having read the real files', () async {
      final ProcessResult run = await _release(_thePairNoEditCanRelease);
      final String said = run.stderr as String;

      expect(run.exitCode, 1);
      expect(said, contains('leading zero'));
      expect(
        said,
        contains('release.ts:22'),
        reason:
            'the refusal names the file it was decided by, so nobody has to take this program at '
            'its word about what the grammar is',
      );
    });

    test('help says what both invocations do and where the grammar is', () async {
      final ProcessResult run = await _release(<String>['help']);
      final String help = run.stdout as String;

      expect(run.exitCode, 0);
      for (final String said in <String>[
        'dart run tool/release.dart                        what has been released',
        'dart run tool/release.dart <version> <channel>    push the tag',
        'CHANGES NOTHING',
        'NOT WRITTEN IN THIS PROGRAM',
        'ANNOTATED tag',
        'release.ts:22',
        'NOTHING HERE ENFORCES IT',
        releaseWorkflowPath,
        'cliTools.ansiwise.version',
      ]) {
        expect(help, contains(said));
      }
    });

    test('takes either none of the two arguments or both', () async {
      for (final List<String> arguments in <List<String>>[
        <String>['0.1.0'],
        <String>['0.1.0', 'stable', 'now'],
      ]) {
        final ProcessResult run = await _release(arguments);

        expect(run.exitCode, 2);
        expect(run.stderr as String, contains('a version and a channel'));
      }
    });
  });
}

/// The filter this repository's workflow states, as the checks that are not about reading it use it.
///
/// Read from the real file rather than written out here a second time, so the screen and the
/// refusals below are driven by the patterns a pushed tag is really held against.
final TagFilter _theFilter = TagFilter.ofWorkflow(File(releaseWorkflowPath).readAsStringSync());

/// The moment the composed tags below are stamped at, handed to the command instead of a clock.
final DateTime _atThatMoment = DateTime.utc(2026, 8, 21, 19, 45);

DateTime _theClock() => _atThatMoment;

/// Fourteen `[0-9]`, as the workflow spells the stamp, for the planted filters below.
const String _fourteenDigits =
    '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]';

String _version(Proposal proposal) => proposal.version;

/// The tag the asset names below are composed for, as a person would have released it.
const String _aTag = '0.1.0-alpha-20260821194500';

/// A workflow whose top-level `env.BINARIES` states [names], and the keys around it a real one has.
///
/// It carries a `BINARIES` inside a job as well, which is not the list a release is cut from: a
/// reader that took the first one it saw would report this planted file as the real set.
String _workflowBuilding(String names) =>
    'name: release\n'
    '\n'
    'permissions:\n'
    '  contents: read\n'
    '\n'
    'env:\n'
    '  BINARIES: $names\n'
    '\n'
    'jobs:\n'
    '  build:\n'
    '    env:\n'
    '      BINARIES: ansiwise-a-job-said-this\n';

/// A workflow file stating [patterns] under `on.push.tags`, and the keys around it a real one has.
String _workflowTriggeringOn(List<String> patterns) =>
    'name: release\n'
    '\n'
    'on:\n'
    '  push:\n'
    '    tags:\n'
    '      # the grammar, in the one place that decides it\n'
    '${patterns.map((String each) => '      - $each\n').join()}'
    '\n'
    'permissions:\n'
    '  contents: read\n';

/// The three reads the screen is built from.
const List<String> _readTags = <String>['ls-remote', '--tags', 'origin'];
const List<String> _readBranch = <String>['rev-parse', '--abbrev-ref', 'HEAD'];
const List<String> _readCommit = <String>['rev-parse', '--short', 'HEAD'];

const GitAnswer _onMaster = GitAnswer(status: 0, output: 'master\n');
const GitAnswer _atACommit = GitAnswer(status: 0, output: '58adecd\n');

/// What `git ls-remote --tags origin` writes: an object name, a tab and a ref — and an ANNOTATED tag
/// listed a second time with `^{}` for the commit it points at.
const GitAnswer _twoReleases = GitAnswer(
  status: 0,
  output:
      '3a1f6c2e9b7d4f8a0c5e2b9d7f1a3c6e8b4d2f0a\trefs/tags/0.1.0-alpha-20260801100000\n'
      '9f2b7d1c4e8a6b3f5d0c9e7a2b4f6d8c1a3e5b7d\trefs/tags/0.1.0-alpha-20260801100000^{}\n'
      '1c3e5a7b9d2f4c6e8a0b1d3f5c7e9a2b4d6f8c0e\trefs/tags/nightly\n',
);

ReleaseCommand _command(Git git, {Manifest? manifest}) => ReleaseCommand(
  git: git,
  manifest: manifest ?? _aManifestAt('0.1.0'),
  filter: _theFilter,
  now: _theClock,
);

FakeManifest _aManifestAt(String version) =>
    FakeManifest('pubspec.yaml', 'name: ansiwise_cli\nversion: $version\n\ndependencies:\n');

ScriptedGit _gitAnswering(Map<String, GitAnswer> answers) => ScriptedGit(
  answers: <String, GitAnswer>{
    _readBranch.join(' '): _onMaster,
    _readCommit.join(' '): _atACommit,
    'status --porcelain': const GitAnswer(status: 0, output: ''),
    ...answers,
  },
);

/// The one pair of arguments a check may hand the REAL program, and why it is this pair.
///
/// A process started here runs against the real git and the real origin, so an invocation that ever
/// stopped refusing would push a tag and start a release — which is the one thing a check must never
/// do. `01.2.3` carries a leading zero and `gamma` is no channel, so THREE independent refusals
/// stand between this pair and `git push`: tool/release_versions.dart's numbersRefusalFor, the
/// [ReleaseChannel] ranking, and .github/workflows/release.yml's filter, which triggers on no
/// `gamma` pattern. Deleting any one of them leaves the other two, and the check goes red rather
/// than releasing. NOTHING ELSE MAY BE PASSED TO [_release] but this pair and arguments refused for
/// their number: a pair that composes an admissible tag is one edit away from a real release.
const List<String> _thePairNoEditCanRelease = <String>['01.2.3', 'gamma'];

/// The real program, started the way a person starts it, with [arguments].
///
/// EVERY INVOCATION USED HERE REFUSES OR PRINTS, and none of them reaches git at all — the accepting
/// path is driven over [ScriptedGit] above, because a check that started a release would be a check
/// that released. See [_thePairNoEditCanRelease] for what may be handed to it.
Future<ProcessResult> _release(List<String> arguments) =>
    Process.run(Platform.resolvedExecutable, <String>['run', 'tool/release.dart', ...arguments]);

/// A manifest that is a value: what it holds is readable, and what was written to it is recorded.
final class FakeManifest implements Manifest {
  /// Declares [text] at [path], until something writes over it.
  FakeManifest(this.path, this.text);

  @override
  final String path;

  @override
  String? text;

  /// Everything that was written to it, in order.
  final List<String> writes = <String>[];

  @override
  void write(String written) {
    text = written;
    writes.add(written);
  }
}

/// A git that answers what a check wrote for it, and records what it was asked to run.
final class ScriptedGit implements Git {
  /// Answers each command line in [answers] with what it names, and everything else with an empty
  /// success.
  ScriptedGit({this.answers = const <String, GitAnswer>{}});

  /// What each command answers, keyed by its arguments joined with spaces.
  final Map<String, GitAnswer> answers;

  /// Every command that was run, in order.
  final List<List<String>> ran = <List<String>>[];

  @override
  Future<GitAnswer> run(List<String> arguments) async {
    ran.add(arguments);
    final String line = arguments.join(' ');
    if (answers[line] case final GitAnswer answered) {
      return answered;
    }
    // A tag nobody scripted is a tag this checkout does not hold, which is what `git rev-parse -q
    // --verify` answers with 1. An empty success there would read as "the tag is already here" and
    // every release below would refuse for a reason no check wrote.
    if (line.startsWith('rev-parse -q --verify')) {
      return const GitAnswer(status: 1, output: '');
    }
    return const GitAnswer(status: 0, output: '');
  }
}
