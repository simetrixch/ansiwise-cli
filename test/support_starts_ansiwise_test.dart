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
}
