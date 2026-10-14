import 'dart:io';

import 'package:test/test.dart';

import '../support/starts_ansiwise.dart';

/// release-pin — the release stamps the programs pin and moves the CI's ansiwise-cli commit in ONE
/// commit.
///
/// The programs repository's CI binds every program to the ansiwise-cli commit its ci-sources.json
/// names. A release that stamped the pin and left that commit behind sent the next push there to
/// an older registry than the machines run, and a program using a new step went red.
///
/// Each case runs against a bare origin in a temporary directory, and a missing bash or git fails
/// it.
void main() {
  // SKIPPED WHERE THE REPOSITORY'S RULE SAYS SO, printed rather than passed over: every suite that
  // starts a process skips where ANSIWISE_TESTS_MAY_SKIP=1 (test/support_starts_ansiwise_test.dart).
  if (startsAnsiwiseSkip != null) {
    test('release-pin', () {}, skip: startsAnsiwiseSkip);
    return;
  }
  const String tag = '0.8.200-stable-20261011000000';
  const String commit = 'c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00';
  const String pin = 'ansiwise/programs/deploy-cluster.yaml';
  const String sources = 'ci-sources.json';

  String pinFile(String version) => 'steps:\n  - packages:\n      - ansiwise=$version\n';
  String sourcesFile({String? commit}) =>
      '{\n'
      '  "git": {\n'
      '    "hostyour-cloud": "1111111111111111111111111111111111111111"'
      '${commit == null ? '' : ',\n    "ansiwise-cli": "$commit"'}\n'
      '  }\n'
      '}\n';

  test(
    '(a) one commit names both files, the tag in the pin and the commit in ci-sources.json',
    () async {
      final _Origin origin = await _Origin.holding(<String, String>{
        pin: pinFile('0.8.100-stable-20261001000000'),
        sources: sourcesFile(commit: 'a' * 40),
      });
      final String before = await origin.head();

      final ProcessResult ran = await _writePin(origin, tag: tag, commit: commit);

      expect(ran.exitCode, 0, reason: '${ran.stderr}');
      expect(await origin.count('$before..HEAD'), 1);
      expect(await origin.changedIn('HEAD'), <String>[pin, sources]);
      expect(await origin.show('HEAD', pin), contains('- ansiwise=$tag\n'));
      final String moved = await origin.show('HEAD', sources);
      expect(moved, contains('"ansiwise-cli": "$commit"'));
      expect(
        moved,
        contains('"hostyour-cloud": "${'1' * 40}"'),
        reason: 'another source keeps its commit',
      );
    },
  );

  test(
    '(b) a ci-sources.json that pins no ansiwise-cli is refused by name, origin unchanged',
    () async {
      final _Origin origin = await _Origin.holding(<String, String>{
        pin: pinFile('0.8.100-stable-20261001000000'),
        sources: sourcesFile(),
      });
      final String before = await origin.head();

      final ProcessResult ran = await _writePin(origin, tag: tag, commit: commit);

      expect(ran.exitCode, 1);
      expect('${ran.stderr}', contains(sources));
      expect(await origin.head(), before);
    },
  );

  test('(c) a pin and a commit already standing write no commit', () async {
    final _Origin origin = await _Origin.holding(<String, String>{
      pin: pinFile(tag),
      sources: sourcesFile(commit: commit),
    });
    final String before = await origin.head();

    final ProcessResult ran = await _writePin(origin, tag: tag, commit: commit);

    expect(ran.exitCode, 0, reason: '${ran.stderr}');
    expect(await origin.head(), before);
  });

  test('a pin standing without the commit still moves the commit', () async {
    final _Origin origin = await _Origin.holding(<String, String>{
      pin: pinFile(tag),
      sources: sourcesFile(commit: 'a' * 40),
    });
    final String before = await origin.head();

    final ProcessResult ran = await _writePin(origin, tag: tag, commit: commit);

    expect(ran.exitCode, 0, reason: '${ran.stderr}');
    expect(await origin.count('$before..HEAD'), 1);
    expect(await origin.changedIn('HEAD'), <String>[sources]);
  });
}

/// Runs the release's write_pin on [origin]'s clone, as the release's programs call does.
Future<ProcessResult> _writePin(_Origin origin, {required String tag, required String commit}) {
  const String pinShape = r'[0-9]+\.[0-9]+\.[0-9]+-[a-z]+-[0-9]{14}';
  final String release = Directory('release').absolute.path;
  return Process.run('bash', <String>[
    '-c',
    r'die() { echo "release: $*" >&2; exit 1; }; say() { echo "release: $*"; }; '
        r'TAG="$1"; source "$2"; '
        r'write_pin simetrixch/hostyour-deploy "$3" ansiwise/programs/deploy-cluster.yaml '
        '"s|- ansiwise=$pinShape|- ansiwise=\$TAG|" "release: stamp" "" "" '
        r'ci-sources.json "$4"',
    'write_pin',
    tag,
    '$release/write_pin.sh',
    origin.clone,
    commit,
  ], environment: origin.environment);
}

/// A bare origin holding one commit, and the clone a release writes its pin in.
final class _Origin {
  _Origin._(this.bare, this.clone, this.environment);

  /// A new origin whose master holds [files], with a clone of it standing on master.
  static Future<_Origin> holding(Map<String, String> files) async {
    final Directory root = await Directory.systemTemp.createTemp('release-pin-');
    addTearDown(() => root.delete(recursive: true));
    final File config = File('${root.path}/gitconfig')
      ..writeAsStringSync('[user]\n\tname = release\n\temail = release@example.org\n');
    final Map<String, String> environment = <String, String>{
      // The machine's own git configuration stays out: a global hooks path would run a push gate on
      // a push into a temporary directory.
      'GIT_CONFIG_GLOBAL': config.path,
      'GIT_CONFIG_NOSYSTEM': '1',
    };
    final String bare = '${root.path}/origin.git';
    final String seed = '${root.path}/seed';
    final String clone = '${root.path}/clone';
    await _git(<String>['init', '--quiet', '--bare', '--initial-branch=master', bare], environment);
    await _git(<String>['clone', '--quiet', bare, seed], environment);
    for (final MapEntry<String, String> each in files.entries) {
      File('$seed/${each.key}')
        ..createSync(recursive: true)
        ..writeAsStringSync(each.value);
    }
    await _git(<String>['-C', seed, 'add', '--all'], environment);
    await _git(<String>['-C', seed, 'commit', '--quiet', '-m', 'seed'], environment);
    await _git(<String>['-C', seed, 'push', '--quiet', 'origin', 'HEAD:master'], environment);
    await _git(<String>['clone', '--quiet', bare, clone], environment);
    return _Origin._(bare, clone, environment);
  }

  /// The bare repository the clone pushes to.
  final String bare;

  /// The clone write_pin writes in.
  final String clone;

  /// The environment every git and the release's write_pin run under.
  final Map<String, String> environment;

  /// The commit origin's master stands on.
  Future<String> head() => _git(<String>['-C', bare, 'rev-parse', 'master'], environment);

  /// How many commits [range] holds on origin.
  Future<int> count(String range) async =>
      int.parse(await _git(<String>['-C', bare, 'rev-list', '--count', range], environment));

  /// The files [commit] on origin changed, sorted.
  Future<List<String>> changedIn(String commit) async => (await _git(<String>[
    '-C',
    bare,
    'diff-tree',
    '--no-commit-id',
    '--name-only',
    '-r',
    commit,
  ], environment)).split('\n')..sort();

  /// [path] as [commit] on origin holds it.
  Future<String> show(String commit, String path) =>
      _git(<String>['-C', bare, 'show', '$commit:$path'], environment, trim: false);
}

/// Runs git, failing the test on a non-zero exit.
Future<String> _git(
  List<String> arguments,
  Map<String, String> environment, {
  bool trim = true,
}) async {
  final ProcessResult ran = await Process.run('git', arguments, environment: environment);
  if (ran.exitCode != 0) {
    fail('git ${arguments.join(' ')} exited ${ran.exitCode}: ${ran.stderr}');
  }
  return trim ? '${ran.stdout}'.trim() : '${ran.stdout}';
}
