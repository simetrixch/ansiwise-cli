/// Compiles the binaries that get copied to a machine.
///
/// ```
/// dart run tool/build.dart              into build/
/// dart run tool/build.dart <directory>  into a directory of your own, relative to this package
/// ```
///
/// TWO OF THEM, and a machine carries both. `ansiwise` executes a config flow; `ansiwise-rest`
/// serves the REST surface over a session's own pipes. The second starts a run by invoking the
/// first, which it finds standing beside it — so a placement that carried one and not the other
/// would answer for programs and run none of them.
///
/// THE ARGUMENT IS A DIRECTORY AND NOT A TARGET, because there are two targets and their names are
/// not this caller's to choose: each binary is found by the other under the name stated here.
library;

import 'dart:io';

import 'package:ansiwise_checks_gate/ansiwise_checks_gate.dart';

import 'gate/binary_build.dart';
import 'gate/plugin_set.dart';
import 'gate/release_stamp.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length > 1) {
    stderr.writeln('build: FAIL — expected at most one argument, the directory to build into');
    exit(2);
  }

  // WRITTEN BEFORE ANYTHING IS COMPILED, because the compiler needs the imports in the source. The
  // manifest is what says which plugins this product's binary carries; this file is what the
  // compiler reads, and it is a function of that manifest and of nothing else.
  final String package = packageOfToolScript(Platform.script).path;
  if (writePluginSet(package)) {
    stdout.writeln('wrote lib/plugins.dart from plugins.yaml');
  }

  // The second generated source, and the last thing written before the compiler runs. A binary that
  // cannot say which version it is leaves every reader parsing a filename for one — see
  // tool/gate/release_stamp.dart.
  final String stamp;
  try {
    stamp = stampFor(Platform.environment);
  } on ReleaseStampRefused catch (refused) {
    // Read as a failure of this build and not as a crash of it. The value came from an environment
    // a person or a workflow set, and what they need is the sentence saying which value and why.
    stderr.writeln('build: FAIL — $refused');
    exit(2);
  }
  if (writeReleaseStamp(package, stamp)) {
    stdout.writeln('wrote $releaseStampFileName stamping $stamp');
  }

  final String directory = arguments.isEmpty ? defaultDirectory : arguments.single;

  for (final MapEntry<String, String> each in binaries.entries) {
    final BinaryBuild build = BinaryBuild(
      toolchain: const RealDartToolchain(),
      package: package,
      entryPoint: each.value,
    );
    switch (await build.to('$directory/${each.key}')) {
      case Built(:final String target, :final String toolVersion):
        stdout.writeln('built $target ($toolVersion)');
      case BuildFailed(:final String why):
        stderr.writeln('build: FAIL — $why');
        exitCode = 1;
        // The second is not attempted after the first failed: a directory holding one of the two is
        // worse than one holding neither, because a placement would copy it and the machine would
        // come up able to answer and unable to run.
        return;
    }
  }
}

/// Where the executables land when nobody says otherwise.
const String defaultDirectory = 'build';

/// What is compiled, by the name a machine carries it under and the entry point it comes from.
///
/// The NAME on the left is what the other binary looks for beside itself and what a unit file
/// starts; the entry point on the right is a Dart file name and follows Dart's own spelling. They
/// differ for that reason alone.
const Map<String, String> binaries = <String, String>{
  'ansiwise': 'bin/ansiwise.dart',
  'ansiwise-rest': 'bin/ansiwise_rest.dart',
};
