import 'dart:io';

import 'package:test/test.dart';

import '../../tool/gate/plugin_set.dart';

/// plugin-set — `lib/plugins.dart` is what `plugins.yaml` says, and nothing else.
///
/// **Why the set is a manifest at all.** Which plugins a binary carries is the one thing about this
/// repository that is not generic. Held as hand-written Dart it made a tool-named repository into a
/// product one: a second customer with a different set needed a COPY of the composition root —
/// argument parsing, `serve`, the gate and all — and from that moment every repair would land in one
/// copy and not the other.
///
/// **Why generated rather than read at run time.** Dart compiles ahead of time, so the imports must
/// be in the source before anything runs. A list read at start-up cannot bring a package with it.
///
/// **Why this check, and not just the build.** A build writes the file; nothing stops somebody
/// editing it afterwards and compiling once by hand. Then the manifest says one thing, the binary
/// carries another, and the file that looks authoritative is the wrong one. So the two are held
/// against each other here.
void main() {
  group('the file on disk', () {
    test('is exactly what the manifest composes', () {
      // From the working directory, which `dart test` sets to the package. Platform.script points at
      // the test runner's own entry point under Windows and answers a path nowhere near the tree.
      final Directory package = Directory.current;
      final String manifest = File('${package.path}/plugins.yaml').readAsStringSync();
      final String generated = pluginSetSource(pluginsDeclaredIn(manifest));

      expect(
        File('${package.path}/lib/plugins.dart').readAsStringSync().replaceAll('\r\n', '\n'),
        generated.replaceAll('\r\n', '\n'),
        reason:
            'lib/plugins.dart is written by tool/build.dart from plugins.yaml — edit the manifest '
            'and build, rather than the file',
      );
    });
  });

  group('what the manifest may say', () {
    test('a plugin per line, package then type', () {
      final List<DeclaredPlugin> declared = pluginsDeclaredIn(
        '# a comment\n\nfirst_package  FirstPlugin\nsecond_package SecondPlugin\n',
      );

      expect(declared.map((DeclaredPlugin each) => each.package), <String>[
        'first_package',
        'second_package',
      ]);
      expect(declared.map((DeclaredPlugin each) => each.type), <String>[
        'FirstPlugin',
        'SecondPlugin',
      ]);
    });

    test('THE PLANTED DEFECT: a line that is not two words is refused, naming the line', () {
      // Half-understood is the dangerous state: a manifest read past a broken line composes a binary
      // carrying half a plugin set, and nothing afterwards says so.
      expect(
        () => pluginsDeclaredIn('first_package FirstPlugin\nsecond_package\n'),
        throwsA(
          isA<PluginManifestRefused>().having(
            (PluginManifestRefused each) => each.because,
            'because',
            allOf(contains('line 2'), contains('second_package')),
          ),
        ),
      );
    });

    test('a manifest declaring nothing is refused', () {
      // A binary carrying no plugin knows no step, and every program refuses at its first row — a
      // failure that reads like a broken program file rather than an empty manifest.
      expect(
        () => pluginsDeclaredIn('# nothing but comments\n\n'),
        throwsA(isA<PluginManifestRefused>()),
      );
    });
  });

  group('what it composes', () {
    test('one import per package, sorted, and one entry per plugin in the order declared', () {
      final String source = pluginSetSource(
        pluginsDeclaredIn('zebra_package ZebraPlugin\nalpha_package AlphaPlugin\n'),
      );

      expect(
        source.indexOf("import 'package:alpha_package/"),
        lessThan(source.indexOf("import 'package:zebra_package/")),
        reason: 'sorted, so the file does not churn when the manifest is reordered',
      );
      expect(
        source.indexOf('ZebraPlugin()'),
        lessThan(source.indexOf('AlphaPlugin()')),
        reason: 'the ORDER of the set is the manifest\'s, because that is how they read',
      );
    });

    test('it says it is generated, so nobody edits it by accident', () {
      expect(pluginSetSource(pluginsDeclaredIn('a_package APlugin\n')), startsWith('// GENERATED'));
    });
  });
}
