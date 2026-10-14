/// The Dart pin, applied to the SDK release/build.sh builds a release with.
///
/// release/build.sh passes the one argument: what the `dart` on its PATH answered to `--version`.
/// That `dart` is the one it then runs tool/build.dart with, and tool/build.dart compiles with the
/// SDK it runs on. The refusal is package:ansiwise_checks_gate's own, the one tool/ci.dart makes,
/// against the pin that package names, so a release is never built under a Dart the gate would
/// refuse to judge.
///
/// THE SDK'S OWN ANSWER AND NOT `Platform.version`: both name the same SDK when build.sh launches
/// this, and the answer is what build.sh can be shown to ask — a stand-in `dart` on the PATH
/// answering another version is refused through this file in test/checks/release_build_test.dart.
library;

import 'dart:io';

import 'package:ansiwise_checks_gate/ansiwise_checks_gate.dart';

/// Answers zero where [arguments] name the pinned Dart, and refuses with a sentence otherwise.
void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'build: FAIL — usage: dart run tool/dart_version.dart "<what dart --version answered>"',
    );
    exit(2);
  }
  final String answered = arguments.single.trim();
  if (!answered.startsWith(_answerOpening)) {
    stderr.writeln(
      'build: FAIL — dart --version answered "$answered", which names no SDK version, so the '
      'Dart pin $dartVersion could not be held to it',
    );
    exit(1);
  }
  final String? refusal = dartVersionRefusal(
    running: answered.substring(_answerOpening.length),
    pinned: dartVersion,
  );
  if (refusal != null) {
    stderr.writeln('build: FAIL — $refusal');
    exit(1);
  }
}

/// What `dart --version` writes before the version, which `Platform.version` does not carry.
const String _answerOpening = 'Dart SDK version: ';
