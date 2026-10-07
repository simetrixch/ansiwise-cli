import 'dart:io';

/// Why suites that start ansiwise as a process are skipped on machines where it must not run.
const String startsAnsiwiseReason =
    'starts ansiwise as a process; skipped on this machine (ANSIWISE_TESTS_MAY_SKIP=1) and run by the release workflow on GitHub Actions';

/// Answers whether suites that start ansiwise as a process should be skipped under [environment].
///
/// Returns [startsAnsiwiseReason] when `ANSIWISE_TESTS_MAY_SKIP` is `'1'`, and `null` otherwise.
String? startsAnsiwiseSkipFor(Map<String, String> environment) =>
    environment['ANSIWISE_TESTS_MAY_SKIP'] == '1' ? startsAnsiwiseReason : null;

/// Why suites that start ansiwise as a process are skipped on this machine, or `null` if they should run.
///
/// On workstations where ansiwise must never be executed, setting the environment variable
/// `ANSIWISE_TESTS_MAY_SKIP=1` causes tests that start the binary as a process to be skipped with this
/// reason. The suites remain proven on GitHub Actions during the release workflow.
final String? startsAnsiwiseSkip = startsAnsiwiseSkipFor(Platform.environment);
