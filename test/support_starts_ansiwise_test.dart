import 'dart:io';

import 'package:test/test.dart';

import 'support/starts_ansiwise.dart';

void main() {
  group('startsAnsiwiseSkipFor', () {
    test('answers null when ANSIWISE_TESTS_MAY_SKIP is unset', () {
      expect(startsAnsiwiseSkipFor(const <String, String>{}), isNull);
    });

    test('answers the skip reason when ANSIWISE_TESTS_MAY_SKIP is 1', () {
      expect(
        startsAnsiwiseSkipFor(const <String, String>{'ANSIWISE_TESTS_MAY_SKIP': '1'}),
        'starts ansiwise as a process; skipped on this machine (ANSIWISE_TESTS_MAY_SKIP=1) and run by the release workflow on GitHub Actions',
      );
    });

    test('the planted innocent: answers null when ANSIWISE_TESTS_MAY_SKIP is 0', () {
      expect(startsAnsiwiseSkipFor(const <String, String>{'ANSIWISE_TESTS_MAY_SKIP': '0'}), isNull);
    });

    test('startsAnsiwiseSkip agrees with the current environment', () {
      expect(startsAnsiwiseSkip, startsAnsiwiseSkipFor(Platform.environment));
    });
  });

  // The next suite that starts a process will not know the rule, so the rule checks itself: every
  // suite that starts one must be able to skip where ansiwise must not run.
  test('every suite that starts a process skips through startsAnsiwiseSkip', () {
    final RegExp startsProcess = RegExp(r'Process\.(start|run)\(');
    final List<String> starting = <String>[];
    final List<String> missing = <String>[];
    for (final FileSystemEntity entity in Directory('test').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('_test.dart')) {
        continue;
      }
      final String text = entity.readAsStringSync();
      if (!startsProcess.hasMatch(text)) {
        continue;
      }
      starting.add(entity.path);
      if (!text.contains('startsAnsiwiseSkip')) {
        missing.add(entity.path);
      }
    }
    expect(
      starting,
      isNotEmpty,
      reason: 'no suite under test/ starts a process, so this scan proves nothing',
    );
    expect(
      missing,
      isEmpty,
      reason: 'these suites start a process but cannot skip where ansiwise must not run: $missing',
    );
  });
}
