/// Writing `lib/plugins.dart` out of the manifest that says which plugins a binary carries.
///
/// **What this exists to stop.** A hand-kept Dart plugin set makes a tool-named repository into a
/// product one: a second customer with a different set needs a COPY of the composition root —
/// argument parsing, `serve`, the gate and all — and from that moment the two drift, with every
/// repair landing in one of them.
///
/// **Why generated rather than read at run time.** Dart compiles ahead of time, so the imports have
/// to be in the source before anything runs; a list read from a file at start-up cannot bring a
/// package with it. So the manifest is turned into source, and the compiler sees exactly what a
/// hand-written file would have said.
///
/// **Why a generation step is acceptable here and is not for the gate.** The gate has to start on a
/// fresh clone where nothing is resolved, so it can generate nothing. This runs at BUILD time, where
/// everything is resolved and the toolchain is already in hand.
///
/// The manifest is `plugins.yaml`, and it is deliberately the dullest file in the repository: one
/// plugin per line, each naming the package it comes from and the class that is its entry. It reads
/// with no YAML library, because this program is a gate program and imports nothing but `dart:`.
library;

import 'dart:io';

/// One plugin a binary is to carry.
final class DeclaredPlugin {
  /// The [type] exported by [package].
  const DeclaredPlugin({required this.package, required this.type});

  /// The Dart package it comes from, as an import says it after `package:`.
  final String package;

  /// The class that implements the plugin, as the composition root writes it.
  final String type;
}

/// What a manifest that could not be read says about itself.
final class PluginManifestRefused implements Exception {
  /// Refuses [because].
  const PluginManifestRefused(this.because);

  /// What is wrong with the manifest, in the words whoever wrote it reads.
  final String because;

  @override
  String toString() => because;
}

/// The plugins [text] declares, in the order it declares them.
///
/// The format is one plugin per line, `<package> <Type>`, with `#` opening a comment and blank lines
/// ignored. Anything else is refused naming the line: a manifest that is half understood would
/// compile a binary carrying half a plugin set, and nothing afterwards would say so.
List<DeclaredPlugin> pluginsDeclaredIn(String text) {
  final List<DeclaredPlugin> declared = <DeclaredPlugin>[];
  final List<String> lines = text.split('\n');
  for (int i = 0; i < lines.length; i++) {
    final String line = lines[i].trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final List<String> parts = line.split(RegExp(r'\s+'));
    if (parts.length != 2) {
      throw PluginManifestRefused(
        'line ${i + 1} of the plugin manifest is "$line", and a line names a package and the class '
        'that is its entry, separated by a space — nothing else',
      );
    }
    declared.add(DeclaredPlugin(package: parts.first, type: parts.last));
  }
  if (declared.isEmpty) {
    throw const PluginManifestRefused(
      'the plugin manifest declares no plugin, so the binary it composes would know no step at all '
      'and every program would refuse at its first row',
    );
  }
  return declared;
}

/// The source of `lib/plugins.dart` for [declared].
///
/// Written whole rather than patched, so the file on disk is a function of the manifest and of
/// nothing else — which is what lets a check compare the two and report a hand edit.
String pluginSetSource(List<DeclaredPlugin> declared) {
  final List<String> packages = <String>[for (final DeclaredPlugin each in declared) each.package]
    ..sort();
  final StringBuffer out = StringBuffer()
    ..writeln('// GENERATED from plugins.yaml by tool/build.dart. Do not edit.')
    ..writeln('//')
    ..writeln(
      '// Which plugins a binary carries is what tells one product\'s binary from another\'s, and it',
    )
    ..writeln(
      '// is the one thing about this repository that is not generic. Holding it as a hand-written',
    )
    ..writeln(
      '// file made a tool-named repository into a product one: a second customer needed a COPY of',
    )
    ..writeln(
      '// the composition root, and every repair after that would land in one copy and not the other.',
    )
    ..writeln('//')
    ..writeln(
      '// So it is written from a manifest. A different product supplies a different plugins.yaml,',
    )
    ..writeln('// and this file follows.')
    ..writeln('library;')
    ..writeln();
  for (final String package in packages) {
    out.writeln("import 'package:$package/$package.dart';");
  }
  out
    ..writeln("import 'package:ansiwise_core/ansiwise_core.dart';")
    ..writeln()
    ..writeln('/// Every plugin this product\'s binary is compiled with.')
    ..writeln('const PluginSet compiledPlugins = PluginSet(<Plugin>[');
  for (final DeclaredPlugin each in declared) {
    out.writeln('  ${each.type}(),');
  }
  out.writeln(']);');
  return out.toString();
}

/// Writes `lib/plugins.dart` of [package] from its `plugins.yaml`, and says whether it changed.
///
/// Returns true where the file on disk was not already what the manifest says, so a build can report
/// that it wrote one rather than leaving it to be noticed in a diff.
bool writePluginSet(String package) {
  final File manifest = File('$package/plugins.yaml');
  if (!manifest.existsSync()) {
    throw PluginManifestRefused(
      'there is no plugins.yaml in $package, and it is what says which plugins this binary carries',
    );
  }
  final String source = pluginSetSource(pluginsDeclaredIn(manifest.readAsStringSync()));
  final File target = File('$package/lib/plugins.dart');
  if (target.existsSync() && target.readAsStringSync() == source) {
    return false;
  }
  target.writeAsStringSync(source);
  return true;
}
