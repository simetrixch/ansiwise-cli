import 'dart:io';

import 'package:ansiwise_checks_gate/ansiwise_checks_gate.dart';
import 'package:test/test.dart';

import '../support/starts_ansiwise.dart';

/// release-build — release/build.sh refuses what would publish a binary nobody may pin.
///
/// The publish pipeline on the owner's master runs release/build.sh on the release tag and pushes
/// every file it leaves in its output directory to Zot. So the script refuses a tag outside the
/// release grammar, a Dart other than the gate's pin, and a binary that does not answer the tag,
/// and it leaves one file per binary and nothing else.
///
/// THE SDK IS A FAKE `dart` FIRST ON PATH. It answers `--version` with the version a case plants,
/// does nothing for `pub get`, and for `run tool/build.dart <dir>` writes one script per binary
/// that answers `--version` with the ANSIWISE_RELEASE_TAG it was built under. Every other `run` is
/// handed to the real SDK, so the pin is held by the real tool/dart_version.dart and the real
/// package:ansiwise_checks_gate. The binaries are the ones build.sh names on its BINARIES line, read
/// here rather than restated.
///
/// THE PLANTED INNOCENT is case (a): the pinned Dart and a release tag, which must leave exactly
/// `<binary>-<tag>-linux-x64` per binary. THE PLANTED DEFECTS are (b) another Dart, refused before
/// anything is built; (c) tags outside the grammar, refused before any Dart is asked; (d) a binary
/// answering another tag; and (e) an output directory already holding a file.
void main() {
  // SKIPPED WHERE THE REPOSITORY'S RULE SAYS SO, printed rather than passed over: every suite that
  // starts a process skips where ANSIWISE_TESTS_MAY_SKIP=1 (test/support_starts_ansiwise_test.dart).
  if (startsAnsiwiseSkip != null) {
    test('release-build', () {}, skip: startsAnsiwiseSkip);
    return;
  }
  const String tag = '0.8.312-alpha-20261014120000';
  const Timeout realDart = Timeout(Duration(minutes: 2));
  final List<String> binaries = _binariesOfBuildScript();

  test('build.sh names its binaries on one BINARIES line', () {
    expect(binaries, <String>['ansiwise', 'ansiwise-rest']);
  });

  test('(a) innocent: the pinned Dart and a release tag leave one file per binary', () async {
    final _Build build = await _Build.prepare(dart: dartVersion, binaries: binaries);

    final ProcessResult ran = await build.run(tag);

    expect(ran.exitCode, 0, reason: '${ran.stdout}${ran.stderr}');
    expect(build.produced(), <String>[
      for (final String binary in binaries) '$binary-$tag-linux-x64',
    ]);
    expect(build.calls(), <Object>[
      'pub get',
      '--version',
      startsWith('run tool/dart_version.dart '),
      startsWith('run tool/build.dart '),
    ]);
  }, timeout: realDart);

  test('(b) defect: another Dart is refused before anything is built', () async {
    const String other = '2.19.6';
    final _Build build = await _Build.prepare(dart: other, binaries: binaries);

    final ProcessResult ran = await build.run(tag);

    expect(ran.exitCode, isNot(0));
    expect('${ran.stderr}', allOf(contains('Dart $other'), contains('Dart $dartVersion')));
    expect(build.calls(), isNot(contains(startsWith('run tool/build.dart'))));
    expect(build.produced(), isEmpty);
  }, timeout: realDart);

  for (final String outside in <String>[
    '',
    '0.8.312',
    'v0.8.312-alpha-20261014120000',
    '08.8.312-alpha-20261014120000',
    '0.8.312-gamma-20261014120000',
    '0.8.312-alpha-2026101412000',
    '0.8.312-alpha-20261014120000x',
  ]) {
    test('(c) defect: the tag "$outside" is refused before any Dart is asked', () async {
      final _Build build = await _Build.prepare(dart: dartVersion, binaries: binaries);

      final ProcessResult ran = await build.run(outside);

      expect(ran.exitCode, isNot(0));
      expect('${ran.stderr}', contains('build: '));
      expect(build.calls(), isEmpty);
      expect(build.produced(), isEmpty);
    });
  }

  test('(d) defect: a binary answering another tag is refused, and nothing is left', () async {
    final _Build build = await _Build.prepare(
      dart: dartVersion,
      binaries: binaries,
      answer: '0.8.311-stable-20261012090928',
    );

    final ProcessResult ran = await build.run(tag);

    expect(ran.exitCode, isNot(0));
    expect('${ran.stderr}', contains('0.8.311-stable-20261012090928'));
    expect(build.produced(), isEmpty);
  }, timeout: realDart);

  test('(e) defect: an output directory already holding a file is refused', () async {
    final _Build build = await _Build.prepare(dart: dartVersion, binaries: binaries);
    File('${build.output}/stray')
      ..createSync(recursive: true)
      ..writeAsStringSync('left by somebody else');

    final ProcessResult ran = await build.run(tag);

    expect(ran.exitCode, isNot(0));
    expect('${ran.stderr}', contains(build.output));
    expect(build.calls(), isEmpty);
    expect(build.produced(), <String>['stray']);
  });
}

/// The binaries release/build.sh names on its one `BINARIES="..."` line.
List<String> _binariesOfBuildScript() {
  final RegExpMatch? line = RegExp(
    r'^BINARIES="([^"]*)"$',
    multiLine: true,
  ).firstMatch(File('release/build.sh').readAsStringSync());
  if (line == null) {
    fail('release/build.sh carries no BINARIES="..." line');
  }
  return line.group(1)!.split(' ').where((String each) => each.isNotEmpty).toList();
}

/// A temporary directory holding a fake `dart`, its log, and the output directory build.sh fills.
final class _Build {
  _Build._(this.root, this.environment);

  /// A fake SDK answering [dart] to `--version`, whose build writes [binaries] answering [answer],
  /// or the tag they were built under where [answer] is null.
  static Future<_Build> prepare({
    required String dart,
    required List<String> binaries,
    String? answer,
  }) async {
    final Directory root = await Directory.systemTemp.createTemp('release-build-');
    addTearDown(() => root.delete(recursive: true));
    Directory('${root.path}/sdk').createSync();
    final File fake = File('${root.path}/sdk/dart')..writeAsStringSync(_fakeDart);
    Process.runSync('chmod', <String>['+x', fake.path]);
    return _Build._(root.path, <String, String>{
      'PATH': '${root.path}/sdk:${Platform.environment['PATH']}',
      'FAKE_DART_LOG': '${root.path}/calls',
      'FAKE_DART_VERSION': dart,
      'FAKE_DART_BINARIES': binaries.join(' '),
      'FAKE_DART_ANSWER': answer ?? '',
      'REAL_DART': Platform.resolvedExecutable,
    });
  }

  /// The temporary directory.
  final String root;

  /// What build.sh runs under.
  final Map<String, String> environment;

  /// The directory build.sh is asked to fill.
  String get output => '$root/out';

  /// Runs release/build.sh for [tag] into [output].
  Future<ProcessResult> run(String tag) =>
      Process.run('bash', <String>['release/build.sh', tag, output], environment: environment);

  /// Every call build.sh made of the fake `dart`, in order.
  List<String> calls() {
    final File log = File('$root/calls');
    return log.existsSync() ? log.readAsLinesSync() : <String>[];
  }

  /// The names of the files left in [output], sorted.
  List<String> produced() {
    final Directory directory = Directory(output);
    if (!directory.existsSync()) {
      return <String>[];
    }
    return directory.listSync().map((FileSystemEntity each) => each.uri.pathSegments.last).toList()
      ..sort();
  }
}

/// The fake SDK, as a bash script reading its answers from the environment [_Build] sets.
const String _fakeDart = r'''#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_DART_LOG"
case "$1" in
  --version)
    echo "Dart SDK version: $FAKE_DART_VERSION (stable) (Thu Jan 1 00:00:00 2026 +0000) on \"linux_x64\""
    ;;
  pub)
    ;;
  run)
    if [ "$2" = tool/build.dart ]; then
      mkdir -p "$3"
      for binary in $FAKE_DART_BINARIES; do
        printf '#!/usr/bin/env bash\necho "%s"\n' "${FAKE_DART_ANSWER:-$ANSIWISE_RELEASE_TAG}" > "$3/$binary"
        chmod +x "$3/$binary"
      done
    else
      exec "$REAL_DART" "$@"
    fi
    ;;
  *)
    echo "fake dart: no answer for: $*" >&2
    exit 99
    ;;
esac
''';
