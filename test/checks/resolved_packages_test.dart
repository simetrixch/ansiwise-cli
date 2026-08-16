import 'dart:io';

import 'package:test/test.dart';

import '../../tool/gate/dart_packages.dart';
import '../../tool/gate/fake_dart_toolchain.dart';
import '../../tool/gate/gate_log.dart';
import '../../tool/gate/package_gate.dart';
import '../../tool/gate/resolved_packages.dart';

/// resolved-packages — everything the binary is composed from answered from one place.
///
/// This repository names the framework and plugin packages of other repositories by a git ref, and
/// a gitignored pubspec_overrides.yaml re-points them at working checkouts beside this one. The
/// same commit therefore resolves to two legitimate binaries — all from the working trees, or all
/// from pushed commits — and one illegitimate third: SOME overridden and some not, so the binary is
/// built half from the working tree and half from what was pushed, with nothing saying which half
/// is which. The check refuses the mix and the gate logs which of the two uniform compositions this
/// resolution is.
///
/// What decides is `.dart_tool/package_config.json`, which `dart pub get` writes: each entry's
/// `rootUri` against the config's own `pubCache` says whether a package answered from a pushed
/// commit in the cache or from a working checkout outside it.
///
/// The functions take text, so every probe below plants fabricated inputs and touches no checkout.
void main() {
  // A planted config in the shape pub writes: the package itself, one member from a working
  // checkout, one member from a git checkout inside the cache, and one hosted dependency.
  const String configDirectory = '/repo/product/.dart_tool/';
  const List<String> members = <String>['tool_a', 'tool_b'];
  String config({required String toolA, required String toolB}) =>
      '{"configVersion":2,"packages":['
      '{"name":"product","rootUri":"../","packageUri":"lib/"},'
      '{"name":"tool_a","rootUri":"$toolA","packageUri":"lib/"},'
      '{"name":"tool_b","rootUri":"$toolB","packageUri":"lib/"},'
      '{"name":"third_party","rootUri":"file:///cache/hosted/pub.dev/third_party-1.0.0",'
      '"packageUri":"lib/"}'
      '],"pubCache":"file:///cache"}';

  group('the composition question', () {
    test('a mixed composition is refused, naming both halves', () {
      final List<String> refusals = compositionRefusals(
        composition: compositionOf(
          packageConfigText: config(
            toolA: '../../work/tool-a',
            toolB: 'file:///cache/git/plugins-abc123/tool-b',
          ),
          configDirectory: configDirectory,
          members: members,
        ),
        members: members,
      );
      expect(refusals, hasLength(1), reason: 'this refusal cannot go red on the mix it exists for');
      expect(
        refusals.single,
        allOf(
          contains('mixed composition'),
          contains('/repo/work/tool-a'),
          contains('/cache/git/plugins-abc123/tool-b'),
        ),
        reason: 'a refusal naming one of the two halves leaves the reader to guess at the other',
      );
    });

    test('a composition answered entirely from working checkouts passes, and the line says so', () {
      final List<ComposedPackage> composition = compositionOf(
        packageConfigText: config(toolA: '../../work/tool-a', toolB: '../../work/tool-b'),
        configDirectory: configDirectory,
        members: members,
      );
      expect(
        compositionRefusals(composition: composition, members: members),
        isEmpty,
        reason: 'a refusal that reported everything would pass the mixed probe above',
      );
      expect(compositionLine(composition), contains('working checkout'));
    });

    test('a composition answered entirely from pushed commits passes, and the line says so', () {
      final List<ComposedPackage> composition = compositionOf(
        packageConfigText: config(
          toolA: 'file:///cache/git/plugins-abc123/tool-a',
          toolB: 'file:///cache/git/plugins-abc123/tool-b',
        ),
        configDirectory: configDirectory,
        members: members,
      );
      expect(compositionRefusals(composition: composition, members: members), isEmpty);
      expect(compositionLine(composition), contains('pushed commit'));
    });

    test('a hosted dependency under the cache is not judged, and the package is not its own '
        'composition', () {
      final List<ComposedPackage> composition = compositionOf(
        packageConfigText: config(toolA: '../../work/tool-a', toolB: '../../work/tool-b'),
        configDirectory: configDirectory,
        members: members,
      );
      expect(
        composition.map((ComposedPackage composed) => composed.name),
        <String>['tool_a', 'tool_b'],
        reason:
            'a hosted dependency resolves through the pub cache by design, and the package itself '
            'answers from nowhere else',
      );
    });

    test('a package git-named by a member rather than by this manifest is judged too', () {
      // The shape a member list read from one manifest alone cannot see: a git-named dependency
      // itself names a package by git, so that package is composed into the binary without any
      // manifest of this repository declaring it. Overridden while the members are not, it is the
      // same mix.
      final List<String> refusals = compositionRefusals(
        composition: compositionOf(
          packageConfigText:
              '{"configVersion":2,"packages":['
              '{"name":"product","rootUri":"../","packageUri":"lib/"},'
              '{"name":"tool_a","rootUri":"file:///cache/git/plugins-abc123/tool-a",'
              '"packageUri":"lib/"},'
              '{"name":"tool_inner","rootUri":"../../work/tool-inner","packageUri":"lib/"}'
              '],"pubCache":"file:///cache"}',
          configDirectory: configDirectory,
          members: const <String>['tool_a'],
        ),
        members: const <String>['tool_a'],
      );
      expect(refusals, hasLength(1));
      expect(refusals.single, allOf(contains('mixed composition'), contains('tool_inner')));
    });

    test('a member the resolution has no answer for is refused by name', () {
      final List<String> refusals = compositionRefusals(
        composition: compositionOf(
          packageConfigText: config(toolA: '../../work/tool-a', toolB: '../../work/tool-b'),
          configDirectory: configDirectory,
          members: const <String>['tool_a', 'tool_b', 'tool_x'],
        ),
        members: const <String>['tool_a', 'tool_b', 'tool_x'],
      );
      expect(refusals, hasLength(1));
      expect(
        refusals.single,
        contains('tool_x'),
        reason:
            'the manifest and the package config disagree, and nothing true can be said about '
            'what a build would compile',
      );
    });
  });

  group('reading the git-named dependencies out of a manifest', () {
    test('git sources are found in both blocks, hosted ones are not', () {
      const String pubspec =
          'name: product\n'
          'dependencies:\n'
          '  tool_a:\n'
          '    git:\n'
          '      url: https://example.invalid/tools.git\n'
          '      path: tool-a\n'
          '  third_party: ^1.0.0\n'
          'dev_dependencies:\n'
          '  audit_suite:\n'
          '    git:\n'
          '      url: https://example.invalid/audits.git\n'
          '  lints: ^6.0.0\n';
      expect(
        gitNamedDependencies(pubspec),
        <String>['audit_suite', 'tool_a'],
        reason:
            'a dev dependency is in — the audits judging working-tree code while resolved from a '
            'commit is the same split one level down — and a hosted dependency is not',
      );
    });

    test(
      'the manifest of this repository names packages by git, so the check measures something',
      () {
        // The successor of the deleted test refusing to pass over an empty measurement: if the
        // manifest stops declaring anything by a git ref, this goes red instead of everything above
        // going quietly green about nothing.
        expect(
          gitNamedDependencies(File('pubspec.yaml').readAsStringSync()),
          isNotEmpty,
          reason: 'with nothing git-named, the composition check would be green about no binary',
        );
      },
    );

    test('every git-named package of this repository has an answer in the real resolution', () {
      final List<String> realMembers = gitNamedDependencies(
        File('pubspec.yaml').readAsStringSync(),
      );
      final List<String> refusals = compositionRefusals(
        composition: compositionOf(
          packageConfigText: File('.dart_tool/package_config.json').readAsStringSync(),
          configDirectory: '${Directory.current.path}/.dart_tool/',
          members: realMembers,
        ),
        members: realMembers,
      );
      expect(
        refusals,
        isEmpty,
        reason:
            'the fix is all or none: name every git-named package in pubspec_overrides.yaml, or '
            'delete that file and resolve again',
      );
    });
  });

  group('the gate carries the answer', () {
    test('a mixed composition turns the gate red and the log names it', () async {
      final _PlantedPackage planted = _plant(
        toolARoot: '../../work/tool-a',
        toolBRoot: 'file:///cache/git/plugins-abc123/tool-b',
      );
      final CollectedGateLog log = CollectedGateLog();
      final GateVerdict verdict = await _gateOver(planted, log).run();
      expect(verdict.failures, contains('composition'));
      expect(log.said.join('\n'), contains('mixed composition'));
    });

    test(
      'a uniform composition leaves the gate green and the log says which build this is',
      () async {
        final _PlantedPackage planted = _plant(
          toolARoot: '../../work/tool-a',
          toolBRoot: '../../work/tool-b',
        );
        final CollectedGateLog log = CollectedGateLog();
        final GateVerdict verdict = await _gateOver(planted, log).run();
        expect(verdict.failures, isNot(contains('composition')));
        expect(
          log.said.join('\n'),
          contains('working checkout'),
          reason:
              'built from the working tree and built from what was pushed are two different '
              'binaries, and this line is where an operator learns which one they have',
        );
      },
    );
  });

  group('the intra-repository question, kept for the day a second package arrives', () {
    const DartPackage product = DartPackage(directory: '/work/product', name: 'product');
    const DartPackage tool = DartPackage(directory: '/work/tool-plugin', name: 'tool_plugin');
    const List<DartPackage> repository = <DartPackage>[product, tool];

    test('a package composed from somewhere else is reported, naming both copies', () {
      final List<String> refusals = splitResolutions(
        resolutions: const <ResolvedDependency>[
          ResolvedDependency(
            inPackage: 'product',
            name: 'tool_plugin',
            root: '/cache/git/plugins-abc123/tool-plugin',
          ),
        ],
        repositoryPackages: repository,
      );
      expect(
        refusals,
        hasLength(1),
        reason: 'this refusal cannot go red on the split it exists for',
      );
      expect(
        refusals.single,
        allOf(contains('/cache/git/plugins-abc123/tool-plugin'), contains(tool.directory)),
      );
    });

    test('a package composed from its checkout in this repository is not reported', () {
      expect(
        splitResolutions(
          resolutions: const <ResolvedDependency>[
            ResolvedDependency(
              inPackage: 'product',
              name: 'tool_plugin',
              root: '/work/tool-plugin',
            ),
          ],
          repositoryPackages: repository,
        ),
        isEmpty,
        reason: 'a refusal that reported everything would pass the probe above',
      );
    });

    test('the same directory written two ways is the same directory', () {
      expect(sameDirectory(r'D:\work\tool-plugin', 'D:/work/tool-plugin/'), isTrue);
      expect(
        sameDirectory('/work/tool-plugin', '/work/Tool-Plugin'),
        isFalse,
        reason:
            'a path that differs only in case is a different path on the machine the product runs '
            'on, and the gate is not the place to start treating the two as one',
      );
    });

    test('a package nothing has resolved answers with nothing rather than with an assumption', () {
      final Directory scratch = Directory.systemTemp.createTempSync('ansiwise-cli-unresolved-');
      addTearDown(() => scratch.deleteSync(recursive: true));
      expect(
        inRepositoryResolutionOf(
          DartPackage(directory: scratch.path, name: 'planted'),
          const <DartPackage>[],
        ),
        isEmpty,
        reason: 'its pub get failing is the gate\'s own finding, and it is already reported there',
      );
    });
  });
}

/// A scratch package whose manifest names two packages by git and whose planted resolution answers
/// them from the two roots handed to `_plant`.
final class _PlantedPackage {
  const _PlantedPackage(this.package, this.scratch);

  final DartPackage package;
  final Directory scratch;
}

_PlantedPackage _plant({required String toolARoot, required String toolBRoot}) {
  final Directory scratch = Directory.systemTemp.createTempSync('ansiwise-cli-composition-');
  addTearDown(() => scratch.deleteSync(recursive: true));
  final Directory root = Directory('${scratch.path}/product')..createSync();
  File('${root.path}/pubspec.yaml').writeAsStringSync(
    'name: product\n'
    'dependencies:\n'
    '  tool_a:\n'
    '    git:\n'
    '      url: https://example.invalid/tools.git\n'
    '      path: tool-a\n'
    '  tool_b:\n'
    '    git:\n'
    '      url: https://example.invalid/tools.git\n'
    '      path: tool-b\n',
  );
  Directory('${root.path}/.dart_tool').createSync();
  File('${root.path}/.dart_tool/package_config.json').writeAsStringSync(
    '{"configVersion":2,"packages":['
    '{"name":"product","rootUri":"../","packageUri":"lib/"},'
    '{"name":"tool_a","rootUri":"$toolARoot","packageUri":"lib/"},'
    '{"name":"tool_b","rootUri":"$toolBRoot","packageUri":"lib/"}'
    '],"pubCache":"file:///cache"}',
  );
  return _PlantedPackage(DartPackage(directory: root.path, name: 'product'), scratch);
}

PackageGate _gateOver(_PlantedPackage planted, CollectedGateLog log) => PackageGate(
  toolchain: FakeDartToolchain(),
  packages: <DartPackage>[planted.package],
  log: log,
  analysisRoot: planted.scratch.path,
);
