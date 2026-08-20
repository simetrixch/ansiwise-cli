/// Compiles the binary that gets copied to a machine.
///
/// ```
/// dart run tool/build.dart              to build/ansiwise
/// dart run tool/build.dart <target>     to a path of your own, relative to this package
/// ```
library;

import 'dart:io';

import 'gate/binary_build.dart';
import 'gate/plugin_set.dart';
import 'gate/paths.dart';
import 'gate/real_dart_toolchain.dart';
import 'gate/service_unit.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length > 1) {
    stderr.writeln('build: FAIL — expected at most one argument, the target path');
    exit(2);
  }

  // WRITTEN BEFORE ANYTHING IS COMPILED, because the compiler needs the imports in the source. The
  // manifest is what says which plugins this product's binary carries; this file is what the
  // compiler reads, and it is a function of that manifest and of nothing else.
  final String package = packageOfToolScript(Platform.script).path;
  if (writePluginSet(package)) {
    stdout.writeln('wrote lib/plugins.dart from plugins.yaml');
  }

  // The unit the binary places on a machine, for the same reason and at the same moment: it is
  // carried inside the executable, so the compiler has to see it before it compiles anything.
  if (writeServiceUnitSource(package)) {
    stdout.writeln('wrote lib/service_unit.dart from $serviceUnitFileName');
  }

  final BinaryBuild build = BinaryBuild(toolchain: const RealDartToolchain(), package: package);

  switch (await build.to(arguments.isEmpty ? defaultTarget : arguments.single)) {
    case Built(:final String target, :final String toolVersion):
      stdout.writeln('built $target ($toolVersion)');
    case BuildFailed(:final String why):
      stderr.writeln('build: FAIL — $why');
      exitCode = 1;
  }
}

/// Where the executable lands when nobody says otherwise.
const String defaultTarget = 'build/ansiwise';
