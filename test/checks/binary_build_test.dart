import 'dart:io';

import 'package:test/test.dart';

import '../../tool/gate/binary_build.dart';
import '../../tool/gate/dart_toolchain.dart';
import '../../tool/gate/fake_dart_toolchain.dart';
import '../../tool/gate/real_dart_toolchain.dart';

/// binary-build — the one executable that travels to a machine, compiled from the composition root.
///
/// A client reaches a fresh Ubuntu with a username and a password and nothing else on it: no Dart
/// and no checkout, so what is copied there is this artifact alone. Two answers decide everything
/// the build reports — the compiler's exit code and the version banner — and the probes below hand
/// both over to a scripted toolchain, because handing an answer over is the only way to show the
/// build reads it correctly. No `dart compile` is started here and no executable is produced.
///
/// WHAT THIS SUITE DOES NOT PROVE, said rather than left to be assumed: a compiler that exits zero
/// and writes no file is reported as a build that landed. `BinaryBuild.to` decides on the exit code
/// alone and never looks for the artifact it names, so there is no refusal for a probe to plant.
/// The module has to gain that look before this suite can carry the shape.
void main() {
  group('a build that works', () {
    test('reports where the artifact landed and which tool version compiled it', () async {
      final Directory package = _scratch();
      final BuildOutcome outcome = await BinaryBuild(
        toolchain: _toolchain(),
        package: package.path,
      ).to('build/ansiwise');

      expect(
        outcome,
        isA<Built>(),
        reason: 'a build that answered failed for everything would pass every probe below',
      );
      final Built built = outcome as Built;
      expect(built.target, 'build/ansiwise');
      expect(
        built.toolVersion,
        '3.13.0',
        reason:
            'the version alone and not the whole banner: this string is what traces a binary '
            'sitting on a machine back to the SDK that compiled it',
      );
      expect(built.toString(), 'built build/ansiwise (3.13.0)');
    });

    test('hands the compiler the composition root and the target it was given', () async {
      final Directory package = _scratch();
      final FakeDartToolchain toolchain = _toolchain();
      await BinaryBuild(toolchain: toolchain, package: package.path).to('build/ansiwise');

      expect(
        toolchain.calls.map((ToolCall call) => call.what),
        contains('compile bin/ansiwise.dart -> build/ansiwise'),
        reason:
            'the entry point decides which plugins exist in the binary — Dart ahead of time loads '
            'no code that was not compiled in — so compiling a different file ships a different '
            'product under the same name',
      );
      expect(
        toolchain.calls.map((ToolCall call) => call.directory),
        everyElement(package.path),
        reason:
            'the compiler runs inside the package, so the pubspec and the analysis options that '
            'apply are the ones that package ships',
      );
    });

    test('compiles an entry point named by the caller instead of the default one', () async {
      final Directory package = _scratch();
      final FakeDartToolchain toolchain = _toolchain();
      await BinaryBuild(
        toolchain: toolchain,
        package: package.path,
        entryPoint: 'bin/planted_root.dart',
      ).to('build/planted');

      expect(
        toolchain.calls.map((ToolCall call) => call.what),
        contains('compile bin/planted_root.dart -> build/planted'),
        reason: 'a build that compiled a fixed path would ignore both arguments and say nothing',
      );
    });

    test('reads the version out of the banner this very SDK writes', () async {
      final Directory package = _scratch();
      final ToolRun banner = await const RealDartToolchain().version(directory: package.path);
      final BuildOutcome outcome = await BinaryBuild(
        toolchain: _toolchain(version: banner.output),
        package: package.path,
      ).to('build/ansiwise');

      expect(
        (outcome as Built).toolVersion,
        matches(RegExp(r'^\d+\.\d+\.\d+')),
        reason:
            'the parse takes what follows `Dart SDK version:`; the day that banner changes shape '
            'the build line would carry the whole banner in place of a version, and the scripted '
            'probes above would go on passing over the shape it used to have',
      );
    });

    test('passes a banner it cannot parse through whole rather than dropping it', () async {
      final Directory package = _scratch();
      final BuildOutcome outcome = await BinaryBuild(
        toolchain: _toolchain(version: 'some tool nobody expected here\n'),
        package: package.path,
      ).to('build/ansiwise');

      expect(
        (outcome as Built).toolVersion,
        'some tool nobody expected here',
        reason:
            '`built build/ansiwise ()` reads as a binary nobody can trace to anything; the whole '
            'line at least names what answered',
      );
    });
  });

  group('a build that did not work', () {
    test('is a failure carrying what the compiler said, not a binary nobody has', () async {
      final Directory package = _scratch();
      final BuildOutcome outcome = await BinaryBuild(
        toolchain: _toolchain(
          answers: <String, ToolRun>{
            'compile bin/ansiwise.dart -> build/ansiwise': const ToolRun(
              exitCode: 254,
              output: 'Error: something in the composition root does not compile\n',
            ),
          },
        ),
        package: package.path,
      ).to('build/ansiwise');

      expect(outcome, isA<BuildFailed>());
      expect(
        (outcome as BuildFailed).why,
        'Error: something in the composition root does not compile',
        reason:
            'an exit code on its own sends the reader back to a compile that has already scrolled '
            'away, and the plugin that would not compile is named in the words the compiler used',
      );
      expect(outcome.toString(), startsWith('the build failed'));
    });

    test('asks for no tool version, because there is no artifact to trace to one', () async {
      final Directory package = _scratch();
      final FakeDartToolchain toolchain = _toolchain(
        answers: <String, ToolRun>{
          'compile bin/ansiwise.dart -> build/ansiwise': const ToolRun(
            exitCode: 254,
            output: 'Error: something in the composition root does not compile\n',
          ),
        },
      );
      await BinaryBuild(toolchain: toolchain, package: package.path).to('build/ansiwise');

      expect(
        toolchain.calls.map((ToolCall call) => call.what),
        isNot(contains('--version')),
        reason: 'a version beside a failure names the SDK of a binary that was never written',
      );
    });
  });

  group('the directory the artifact is written into', () {
    test('is made before the compile when it is not there', () async {
      final Directory package = _scratch();
      expect(
        Directory('${package.path}/build').existsSync(),
        isFalse,
        reason: 'the planted state: a target under a directory this package does not have',
      );

      final BuildOutcome outcome = await BinaryBuild(
        toolchain: _toolchain(),
        package: package.path,
      ).to('build/dist/nested/ansiwise');

      expect(outcome, isA<Built>());
      expect(
        Directory('${package.path}/build/dist/nested').existsSync(),
        isTrue,
        reason:
            'the compiler writes no directory of its own: `dart compile exe -o` into a directory '
            'that is not there fails on the output path, and the message is about a path rather '
            'than about the code, which is the failure hardest to read of the two',
      );
    });

    test('is left as it is when it already stands, with what is in it', () async {
      final Directory package = _scratch();
      final File earlier = File('${package.path}/build/ansiwise.earlier');
      earlier.parent.createSync(recursive: true);
      earlier.writeAsStringSync('the artifact of an earlier build\n');

      final BuildOutcome outcome = await BinaryBuild(
        toolchain: _toolchain(),
        package: package.path,
      ).to('build/ansiwise');

      expect(outcome, isA<Built>());
      expect(
        earlier.readAsStringSync(),
        'the artifact of an earlier build\n',
        reason:
            'a build that emptied its output directory first would take whatever a release put '
            'beside the executable with it, and nothing here writes the directory back',
      );
    });
  });
}

/// A toolchain that compiles cleanly, calls itself [version], and answers [answers] where they name
/// a call.
FakeDartToolchain _toolchain({
  String version =
      'Dart SDK version: 3.13.0 (stable) (Wed Aug 5 00:28:05 2026 -0700) '
      'on "windows_x64"\n',
  Map<String, ToolRun> answers = const <String, ToolRun>{},
}) => FakeDartToolchain(
  answers: <String, ToolRun>{
    '--version': ToolRun(exitCode: 0, output: version),
    ...answers,
  },
);

Directory _scratch() {
  final Directory directory = Directory.systemTemp.createTempSync('ansiwise-cli-binary-build-');
  addTearDown(() => directory.deleteSync(recursive: true));
  return directory;
}
