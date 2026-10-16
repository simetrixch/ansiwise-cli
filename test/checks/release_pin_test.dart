import 'dart:io';

import 'package:test/test.dart';

import '../support/bare_origin.dart';
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
      final BareOrigin origin = await BareOrigin.holding(<String, String>{
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
      final BareOrigin origin = await BareOrigin.holding(<String, String>{
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
    final BareOrigin origin = await BareOrigin.holding(<String, String>{
      pin: pinFile(tag),
      sources: sourcesFile(commit: commit),
    });
    final String before = await origin.head();

    final ProcessResult ran = await _writePin(origin, tag: tag, commit: commit);

    expect(ran.exitCode, 0, reason: '${ran.stderr}');
    expect(await origin.head(), before);
  });

  test('a pin standing without the commit still moves the commit', () async {
    final BareOrigin origin = await BareOrigin.holding(<String, String>{
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
Future<ProcessResult> _writePin(BareOrigin origin, {required String tag, required String commit}) {
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
