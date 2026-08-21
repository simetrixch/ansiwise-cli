import 'dart:io';

import 'package:test/test.dart';

import '../../tool/gate/dart_packages.dart';
import '../../tool/gate/dart_toolchain.dart';
import '../../tool/gate/fake_dart_toolchain.dart';
import '../../tool/gate/gate_log.dart';
import '../../tool/gate/package_gate.dart';

/// The check sequence of the gate, driven against a scripted toolchain.
///
/// The verdict line is the one thing a person reads off a gate run, and everything below decides it.
/// A resolution that failed must END the run: everything after it reads the resolution, so the
/// analyzer, the formatter and the suites would report the missing dependencies as findings about
/// the code — which is what a release run did with thirty-four format findings after a private
/// dependency could not be cloned. Every package is still taken through `dart pub get` before the
/// run ends, so one missing credential names every package it stops rather than only the first, and
/// after that step every package and every step runs even when an earlier one went red.
void main() {
  test('a green run says exactly what the gate is read by', () async {
    final GateVerdict verdict = await _gate(FakeDartToolchain(), <String>['one']).run();
    expect(verdict.green, isTrue);
    expect(verdict.line, 'ci: OK — every check green for 1 package(s): one');
  });

  test('the green line names every package it covered', () async {
    // The count and the names are in the line the reader takes the verdict from, not only in the
    // log above it. This gate has already printed `every check green` over a package it never
    // opened: a second one arrived in the repository and the walk was still rooted at the first.
    // A number a reader knows is what turns that from invisible into obvious.
    final GateVerdict verdict = await _gate(FakeDartToolchain(), <String>['one', 'two']).run();
    expect(verdict.line, 'ci: OK — every check green for 2 package(s): one, two');
  });

  test('a run that found no package is not green', () async {
    final GateVerdict verdict = await _gate(FakeDartToolchain(), <String>[]).run();
    expect(
      verdict.line,
      'ci: FAIL — no Dart package was found to check, so nothing was measured',
      reason:
          'there is no such thing as every check passing when no check ran, and a gate pointed at '
          'the wrong directory is exactly how that happens',
    );
  });

  test('every package is resolved, analysed once, and tested', () async {
    final FakeDartToolchain toolchain = FakeDartToolchain();
    await _gate(toolchain, <String>['one', 'two']).run();
    expect(
      toolchain.calls.map((ToolCall call) => call.what),
      <String>['pub get', 'pub get', 'run tool/analysis.dart', 'test', 'test'],
      reason:
          'one analysis run covers every package, so it is started once and only after every '
          'resolution',
    );
  });

  test('a resolution that failed ends the run, and nothing after it is asked anything', () async {
    final List<DartPackage> packages = _packages(<String>['one', 'two']);
    final FakeDartToolchain toolchain = FakeDartToolchain(
      answers: <String, ToolRun>{
        'pub get in ${packages.first.directory}': const ToolRun(
          exitCode: 69,
          output: 'could not resolve',
        ),
      },
    );
    final CollectedGateLog log = CollectedGateLog();
    final GateVerdict verdict = await PackageGate(
      toolchain: toolchain,
      packages: packages,
      log: log,
      analysisRoot: '/work',
    ).run();

    expect(verdict.failures, <String>['one/pub-get']);
    expect(verdict.line, 'ci: FAIL — one/pub-get');
    expect(
      toolchain.calls.map((ToolCall call) => call.what),
      <String>['pub get', 'pub get'],
      reason:
          'the analyzer, the formatter and the suites all read the resolution, so what they would '
          'report about a tree that is not there is the missing dependencies wearing the shape of '
          'findings about the code',
    );
    expect(
      log.said,
      contains('the tree is not resolved'),
      reason: 'a run that stops without saying it stopped is a run somebody reads as complete',
    );
    expect(
      log.said.join('\n'),
      contains('1 of 2 package(s) did not resolve'),
      reason: 'how much of the tree was lost is what says whether this is one package or all of it',
    );
  });

  test('every package is taken through pub get before the run ends, not only the first', () async {
    final List<DartPackage> packages = _packages(<String>['one', 'two']);
    final FakeDartToolchain toolchain = FakeDartToolchain(
      answers: <String, ToolRun>{
        'pub get': const ToolRun(exitCode: 69, output: 'could not resolve'),
      },
    );
    final GateVerdict verdict = await PackageGate(
      toolchain: toolchain,
      packages: packages,
      log: CollectedGateLog(),
      analysisRoot: '/work',
    ).run();

    expect(
      verdict.failures,
      <String>['one/pub-get', 'two/pub-get'],
      reason:
          'one missing credential stops every package it hits, and a run naming the first alone '
          'sends the next run to find the second',
    );
  });

  test('a red analysis is named on its own, because it is one run over every package', () async {
    final FakeDartToolchain toolchain = FakeDartToolchain()..streamedExitCode = 1;
    final GateVerdict verdict = await _gate(toolchain, <String>['one']).run();
    expect(verdict.failures, contains('analysis'));
  });

  test('a red suite names the package it was in', () async {
    final FakeDartToolchain toolchain = FakeDartToolchain()..streamedExitCode = 1;
    final GateVerdict verdict = await _gate(toolchain, <String>['one']).run();
    expect(verdict.failures, contains('one/test'));
  });

  test(
    'a package with no test directory is said to have none rather than passing quietly',
    () async {
      final Directory scratch = _scratch();
      final DartPackage package = DartPackage(
        directory: '${scratch.path}/untested',
        name: 'untested',
      );
      Directory(package.directory).createSync(recursive: true);
      final CollectedGateLog log = CollectedGateLog();
      final GateVerdict verdict = await PackageGate(
        toolchain: FakeDartToolchain(),
        packages: <DartPackage>[package],
        log: log,
        analysisRoot: scratch.path,
      ).run();

      expect(verdict.green, isTrue);
      expect(log.said, contains('no test/ directory in untested'));
    },
  );
}

PackageGate _gate(FakeDartToolchain toolchain, List<String> names) => PackageGate(
  toolchain: toolchain,
  packages: _packages(names),
  log: CollectedGateLog(),
  analysisRoot: '/work',
);

/// One scratch package per name, in that order, each carrying the test/ directory that makes a suite
/// run.
List<DartPackage> _packages(List<String> names) {
  final Directory scratch = _scratch();
  final List<DartPackage> packages = <DartPackage>[];
  for (final String name in names) {
    Directory('${scratch.path}/$name/test').createSync(recursive: true);
    packages.add(DartPackage(directory: '${scratch.path}/$name', name: name));
  }
  return packages;
}

Directory _scratch() {
  final Directory directory = Directory.systemTemp.createTempSync('hostyour-cloud-package-gate-');
  addTearDown(() => directory.deleteSync(recursive: true));
  return directory;
}
