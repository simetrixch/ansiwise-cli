import 'dart:io';

import 'package:test/test.dart';

import '../../tool/release_command.dart';
import '../../tool/release_git.dart';
import '../../tool/release_report.dart';
import '../../tool/release_tag_filter.dart';
import '../../tool/release_versions.dart';

/// release — the tag that starts a release is proposed, held against the filter that decides, and
/// pushed only when a person typed it.
///
/// **What cannot be shown by running it.** A real accepted run pushes a tag to GitHub, which no check
/// may do, and a release is not something to be started by a suite. So the deciding half is driven
/// over a scripted git: what it was asked to run is a list of argument lists in order, and both
/// claims of cli#3 are readable in it — the screen RUNS ONLY READS, and a version that is typed
/// reaches `git push` as the last of exactly three commands. The refusing half needs none of that
/// and is driven as the real program, on this repository's own files.
///
/// **Where the grammar comes from is itself checked.** The program carries no version grammar; it
/// reads `on.push.tags` out of .github/workflows/release.yml. The counter-probe for that is a
/// planted workflow whose filter says something else — the same version is then accepted or refused
/// according to the file, which a program with its own copy of the grammar could not do.
void main() {
  group('which tags start a release', () {
    test('is read from the workflow this repository really has', () {
      final TagFilter filter = TagFilter.ofWorkflow(File(releaseWorkflowPath).readAsStringSync());

      expect(
        filter.unreadable,
        isNull,
        reason: 'the file that decides whether a tag starts anything has to be readable here',
      );
      expect(filter.stated, isNotEmpty);

      final String? declared = declaredVersionIn(File('pubspec.yaml').readAsStringSync());
      expect(
        declared,
        isNotNull,
        reason: 'the first release is proposed from what pubspec declares',
      );
      expect(
        filter.accepts(declared!),
        isTrue,
        reason:
            'the version pubspec.yaml declares this package at is proposed as the first release, '
            'and a proposal the workflow would ignore is a proposal that starts nothing',
      );
      expect(
        filter.accepts('v$declared'),
        isFalse,
        reason:
            'the filter reads numbers first, and a v in front of them is the tag digita-deploy '
            'asks for and this workflow never sees',
      );
    });

    test('is three numbers, and a pre-release after a hyphen, and nothing else', () {
      final TagFilter filter = TagFilter.ofWorkflow(File(releaseWorkflowPath).readAsStringSync());

      for (final String version in <String>[
        '0.1.0',
        '1.4.2',
        '10.0.0',
        '0.1.0-alpha',
        '0.1.0-beta.2',
      ]) {
        expect(
          filter.accepts(version),
          isTrue,
          reason:
              '"$version" is a version by the grammar ansiwise-client/tool/release_version.dart:18 '
              'spells out, and a filter that refused one would leave a person unable to release it',
        );
      }

      for (final String notAVersion in <String>[
        '0.1.0+7',
        '0.1.0+8',
        'v0.1.0',
        '0.1',
        '0.1.0.1',
        'nightly',
      ]) {
        expect(
          filter.accepts(notAVersion),
          isFalse,
          reason:
              '"$notAVersion" is no version, and a tag that starts a release is what every machine '
              'is then given by name',
        );
      }
    });

    test('and where the pattern language cannot say it, the workflow says so instead', () {
      final String workflow = File(releaseWorkflowPath).readAsStringSync();
      final TagFilter filter = TagFilter.ofWorkflow(workflow);

      // GitHub's filter patterns have no alternation, so `0|[1-9][0-9]*` cannot be written, and
      // `[...]` matches one alphanumeric character, so the pre-release identifier set with its `.`
      // and `-` cannot be written either. What is left over is admitted here and is no version.
      for (final (String admitted, String said) in <(String, String)>[
        ('01.2.3', '01.2.3 is admitted here'),
        ('0.1.0-beta+7', '0.1.0-beta+7 and a bare 0.1.0- are admitted too'),
        ('0.1.0-', 'a bare 0.1.0- are admitted too'),
      ]) {
        expect(
          filter.accepts(admitted),
          isTrue,
          reason: 'this is the gap the workflow states, and a check that hid it would state none',
        );
        expect(
          workflow,
          contains(said),
          reason:
              'the gap is named in the file where the filter and the grammar are both written, so '
              'a narrowing that leaves this behind is read there rather than found on a release day',
        );
      }
    });

    test('COUNTER-PROBE: the pattern that stood here before admits what started run 32493864140', () {
      // PLANTED: the single pattern this workflow triggered on until the tag 0.1.0+7 was pushed. Its
      // trailing `*` is any run of characters, so it reads the build metadata the grammar refuses as
      // part of the version.
      final TagFilter asItWas = TagFilter.ofWorkflow(
        _workflowTriggeringOn("'[0-9]+.[0-9]+.[0-9]+*'"),
      );
      expect(asItWas.accepts('0.1.0+7'), isTrue);
      expect(
        asItWas.accepts('0.1.0'),
        isTrue,
        reason: 'the innocent case, or nothing means anything',
      );

      final TagFilter now = TagFilter.ofWorkflow(File(releaseWorkflowPath).readAsStringSync());
      expect(now.accepts('0.1.0+7'), isFalse);
      expect(now.accepts('0.1.0'), isTrue);
    });

    test('COUNTER-PROBE: a workflow saying something else is answered by what it says', () {
      final TagFilter asItIs = TagFilter.ofWorkflow(
        _workflowTriggeringOn("'[0-9]+.[0-9]+.[0-9]+*'"),
      );
      expect(asItIs.accepts('0.1.0'), isTrue);
      expect(
        asItIs.accepts('v0.1.0'),
        isFalse,
        reason: 'the innocent case, or nothing means anything',
      );

      // PLANTED: the same filter with a v in front of it, which is a filter this repository does not
      // have. A program carrying its own copy of the grammar would answer both of these the same way
      // as above and neither of the two expectations below would hold.
      final TagFilter withAV = TagFilter.ofWorkflow(
        _workflowTriggeringOn("'v[0-9]+.[0-9]+.[0-9]+*'"),
      );
      expect(withAV.accepts('v0.1.0'), isTrue);
      expect(withAV.accepts('0.1.0'), isFalse);
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
          filter.accepts('0.1.0'),
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
        final TagFilter filter = TagFilter.ofWorkflow(_workflowTriggeringOn(pattern));
        expect(
          filter.unreadable,
          contains(said),
          reason: 'a filter guessed at is worse than one refused',
        );
      }
    });

    test('the refusal names where in what was typed the filter stopped reading', () {
      final TagFilter filter = TagFilter.ofWorkflow(
        _workflowTriggeringOn("'[0-9]+.[0-9]+.[0-9]+*'"),
      );

      expect(
        filter.refusalFor('v0.1.0'),
        allOf(contains('[0-9]+'), contains('"v0.1.0" stands there')),
      );
      expect(filter.refusalFor('0.1'), contains('ends there'));
      expect(filter.refusalFor('0.1.x'), contains('after "0.1."'));
      expect(
        filter.refusalFor('0.1.0'),
        isNull,
        reason: 'a refusal that had something to say about every version would say nothing',
      );
      expect(filter.refusalFor('v0.1.0'), contains(releaseWorkflowPath));
    });
  });

  group('the order the screen lists releases in', () {
    test('is the numbers first, and a release stands later than a pre-release of it', () {
      final Releases releases = Releases.ofTags(<String>[
        '0.1.0',
        '0.2.0',
        '0.1.0-beta.2',
        '0.1.0-beta.10',
        '0.10.0',
      ], filter: _theFilter);

      expect(
        releases.releases.map((ReleasedTag each) => each.tag),
        <String>['0.1.0-beta.2', '0.1.0-beta.10', '0.1.0', '0.2.0', '0.10.0'],
        reason:
            'beta.10 is the tenth beta and stands after the second, which comparing text alone gets '
            'backwards, and 0.10.0 is later than 0.2.0 for the same reason',
      );
      expect(releases.latest?.tag, '0.10.0');
    });

    test('a tag that would have started no release is kept, and named as such', () {
      final Releases releases = Releases.ofTags(<String>[
        '0.1.0',
        'nightly',
        'v0.9.9',
      ], filter: _theFilter);

      expect(releases.releases.map((ReleasedTag each) => each.tag), <String>['0.1.0']);
      expect(
        releases.otherTags,
        <String>['nightly', 'v0.9.9'],
        reason:
            'a person deciding a version has to see everything standing on the remote, including '
            'the tags that started nothing',
      );
      expect(releases.holds('nightly'), isTrue, reason: 'the name is taken whatever it started');
    });

    test('proposes the three directions after a release and the release after a pre-release', () {
      expect(
        Releases.ofTags(
          <String>['1.4.2'],
          filter: _theFilter,
        ).proposals(declaredVersion: '0.1.0').map((Proposal each) => each.version),
        <String>['1.4.3', '1.5.0', '2.0.0'],
      );
      expect(
        Releases.ofTags(
          <String>['1.4.2-beta.2'],
          filter: _theFilter,
        ).proposals(declaredVersion: '0.1.0').map((Proposal each) => each.version),
        <String>['1.4.2'],
      );
      expect(
        Releases.ofTags(
          <String>[],
          filter: _theFilter,
        ).proposals(declaredVersion: '0.1.0').map((Proposal each) => each.version),
        <String>['0.1.0'],
        reason: 'the only version this repository states about itself is the one pubspec declares',
      );
      expect(
        Releases.ofTags(<String>[], filter: _theFilter).proposals(declaredVersion: null),
        isEmpty,
        reason: 'a first release invented here would be a version no file states',
      );
    });

    test(
      'the version pubspec declares is read from the manifest, not from a number typed here',
      () {
        expect(declaredVersionIn('name: ansiwise_cli\nversion: 1.4.2\n\ndependencies:\n'), '1.4.2');
        expect(declaredVersionIn('name: ansiwise_cli\ndependencies:\n  args: ^2.7.0\n'), isNull);
      },
    );
  });

  group('the screen', () {
    test('shows what has been released, latest first, and what could come next', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{_readTags.join(' '): _twoReleases});

      final ReleaseOutcome outcome = await _command(git).show();

      expect(outcome.isGreen, isTrue);
      expect(outcome.text, contains('0.1.0-beta.2'));
      expect(outcome.text, contains('master at 58adecd'));
      expect(
        outcome.text,
        contains('0.1.1'),
        reason: 'the latest release is 0.1.0, so the next patch is what is proposed',
      );
      for (final String pattern in <String>['[0-9]+.[0-9]+.[0-9]+', '[0-9]+.[0-9]+.[0-9]+-*']) {
        expect(
          outcome.text,
          contains(pattern),
          reason:
              'every pattern the workflow triggers on is on the screen, because this program states '
              'no grammar a person could read anywhere else',
        );
      }
      expect(
        outcome.text,
        contains('nightly'),
        reason: 'a tag that started no release still stands on the remote',
      );
      expect(
        outcome.text.split('\n').where((String line) => line.trim() == '0.1.0').length,
        1,
        reason:
            'the annotated tag is listed twice by git, once peeled with ^{}, and two lines for one '
            'release would read as two releases',
      );
    });

    test('changes nothing at all', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{_readTags.join(' '): _twoReleases});

      await _command(git).show();

      expect(
        git.ran,
        <List<String>>[_readTags, _readBranch, _readCommit],
        reason:
            'running with no arguments proposes, and a proposal that tagged or pushed anything '
            'would have taken the decision this program exists to leave to a person',
      );
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

  group('a version that is typed', () {
    test('is pushed as one tag, and that is the whole of what starts a release', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{_readTags.join(' '): _twoReleases});

      final ReleaseOutcome outcome = await _command(git).release('0.2.0');

      expect(git.ran, <List<String>>[
        _readTags,
        <String>['tag', '0.2.0'],
        <String>['push', 'origin', 'refs/tags/0.2.0'],
      ]);
      expect(outcome.isGreen, isTrue);
      expect(outcome.text, contains('the tag 0.2.0 is on origin'));
      expect(
        outcome.text,
        contains(releaseWorkflowPath),
        reason: 'the person has to know where the building then happens and what to watch',
      );
      expect(
        outcome.text,
        contains('cliTools.ansiwise.version'),
        reason:
            'a release is not an installation: what a machine is given is what that pin names, and '
            'this run did not move it',
      );
    });

    test('COUNTER-PROBE: one the filter forbids is refused before a remote is reached', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{});

      final ReleaseOutcome outcome = await _command(git).release('v0.2.0');

      expect(outcome.isGreen, isFalse);
      expect(outcome.text, contains('would start no release'));
      expect(
        git.ran,
        isEmpty,
        reason:
            'a tag that starts nothing is answered by reading the workflow, not by asking GitHub',
      );
    });

    test('is refused when it has already been released, and nothing is written', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{_readTags.join(' '): _twoReleases});

      final ReleaseOutcome outcome = await _command(git).release('0.1.0');

      expect(outcome.isGreen, isFalse);
      expect(outcome.text, contains('has already been released'));
      expect(git.ran, <List<String>>[
        _readTags,
      ], reason: 'a second tag of one name would be a release nobody could tell from the first');
    });

    test('is refused when the tags could not be read, and nothing is written', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{
        _readTags.join(' '): const GitAnswer(status: 128, output: 'fatal: no such remote'),
      });

      final ReleaseOutcome outcome = await _command(git).release('0.2.0');

      expect(outcome.isGreen, isFalse);
      expect(
        git.ran,
        <List<String>>[_readTags],
        reason:
            'a release pushed against an unknown history could be a version that already exists',
      );
    });

    test('says the tag is still here when the remote refused it', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{
        _readTags.join(' '): _twoReleases,
        'push origin refs/tags/0.2.0': const GitAnswer(
          status: 1,
          output: 'error: failed to push some refs',
        ),
      });

      final ReleaseOutcome outcome = await _command(git).release('0.2.0');

      expect(outcome.isGreen, isFalse);
      expect(outcome.text, contains('failed to push some refs'));
      expect(
        outcome.text,
        contains('git tag -d 0.2.0'),
        reason:
            'the tag was created here before it was pushed, and a person left with it and no way '
            'named to remove it cannot try again',
      );
    });

    test('does not push when the tag could not be created here', () async {
      final ScriptedGit git = _gitAnswering(<String, GitAnswer>{
        _readTags.join(' '): _twoReleases,
        'tag 0.2.0': const GitAnswer(status: 128, output: "fatal: tag '0.2.0' already exists"),
      });

      final ReleaseOutcome outcome = await _command(git).release('0.2.0');

      expect(outcome.text, contains('already exists'));
      expect(git.ran, <List<String>>[
        _readTags,
        <String>['tag', '0.2.0'],
      ]);
    });
  });

  group('the program as a person starts it', () {
    test('refuses a version the workflow would ignore, having read the real file', () async {
      final ProcessResult run = await _release(<String>['v0.1.0']);
      final String said = run.stderr as String;

      expect(run.exitCode, 1);
      expect(said, contains('would start no release'));
      expect(
        said,
        contains(releaseWorkflowPath),
        reason:
            'the refusal names the file it was decided by, so nobody has to take this program '
            "at its word about what the grammar is",
      );
    });

    test('help says what both invocations do and where the grammar is', () async {
      final ProcessResult run = await _release(<String>['help']);
      final String help = run.stdout as String;

      expect(run.exitCode, 0);
      for (final String said in <String>[
        'dart run tool/release.dart              what has been released',
        'dart run tool/release.dart <version>    push the tag',
        'CHANGES NOTHING',
        'NOT WRITTEN IN THIS PROGRAM',
        releaseWorkflowPath,
        'cliTools.ansiwise.version',
      ]) {
        expect(help, contains(said));
      }
    });

    test('takes one argument at most', () async {
      final ProcessResult run = await _release(<String>['0.1.0', '0.2.0']);

      expect(run.exitCode, 2);
      expect(run.stderr as String, contains('one at most'));
    });
  });
}

/// The filter this repository's workflow states, as the checks that are not about reading it use it.
///
/// Read from the real file rather than written out here a second time, so the screen and the
/// refusals below are driven by the patterns a pushed tag is really held against.
final TagFilter _theFilter = TagFilter.ofWorkflow(File(releaseWorkflowPath).readAsStringSync());

/// A workflow file stating [pattern] under `on.push.tags`, and the keys around it a real one has.
String _workflowTriggeringOn(String pattern) =>
    'name: release\n'
    '\n'
    'on:\n'
    '  push:\n'
    '    tags:\n'
    '      # the grammar, in the one place that decides it\n'
    '      - $pattern\n'
    '\n'
    'permissions:\n'
    '  contents: read\n';

/// The three reads the screen is built from, and the two writes a release is.
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
      '3a1f6c2e9b7d4f8a0c5e2b9d7f1a3c6e8b4d2f0a\trefs/tags/0.1.0-beta.2\n'
      '9f2b7d1c4e8a6b3f5d0c9e7a2b4f6d8c1a3e5b7d\trefs/tags/0.1.0\n'
      '58adecd0a1b2c3d4e5f60718293a4b5c6d7e8f90\trefs/tags/0.1.0^{}\n'
      '1c3e5a7b9d2f4c6e8a0b1d3f5c7e9a2b4d6f8c0e\trefs/tags/nightly\n',
);

ReleaseCommand _command(Git git) =>
    ReleaseCommand(git: git, filter: _theFilter, declaredVersion: '0.1.0');

ScriptedGit _gitAnswering(Map<String, GitAnswer> answers) => ScriptedGit(
  answers: <String, GitAnswer>{
    _readBranch.join(' '): _onMaster,
    _readCommit.join(' '): _atACommit,
    ...answers,
  },
);

/// The real program, started the way a person starts it, with [arguments].
///
/// Every invocation used here refuses or prints, and none of them reaches git at all — the accepting
/// path is driven over [ScriptedGit] above, because a check that started a release would be a check
/// that released.
Future<ProcessResult> _release(List<String> arguments) =>
    Process.run(Platform.resolvedExecutable, <String>['run', 'tool/release.dart', ...arguments]);

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
    return answers[arguments.join(' ')] ?? const GitAnswer(status: 0, output: '');
  }
}
