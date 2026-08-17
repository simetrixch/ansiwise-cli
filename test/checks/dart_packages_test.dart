import 'dart:io';

import 'package:test/test.dart';

import '../../tool/gate/dart_packages.dart';
import '../../tool/gate/paths.dart';

/// dart-packages — which Dart packages of a tree the gate is about to check.
///
/// This walk is the DENOMINATOR of the whole gate. Everything below it — the resolution, the
/// analysis, each suite, and the declaration each package is held to — is done once per entry of
/// the list it answers. A package the walk does not see is not reported as unchecked: it is outside
/// the run, and the verdict still says every check is green.
///
/// Two decisions in it change how many entries there are, and both are planted against below. The
/// root of the tree counts only when it carries code, because a manifest with no `lib/` and no
/// `bin/` declares a workspace and walking it as a package counts every member twice. And a
/// directory that is not source — a resolved dependency, a build output, another ecosystem's
/// dependency directory — is skipped, or the run would judge copies of other people's packages.
///
/// The discovery is a search of the tree and not a read of a workspace list, which is the case that
/// matters: a package on disk but unlisted compiles, imports and breaks a rule like any other, and
/// reading the list would let it do so unwatched.
void main() {
  group('an ordinary tree', () {
    test('answers with every package in it, sorted by directory', () {
      final Directory tree = _scratch();
      _plant(tree, '', name: 'planted_root');
      _plant(tree, 'zeta-tool', name: 'planted_zeta');
      _plant(tree, 'alpha-tool', name: 'planted_alpha');
      _plant(tree, 'alpha-tool/inner-tool', name: 'planted_inner');

      final List<DartPackage> found = dartPackagesIn(tree);

      expect(
        found.map((DartPackage package) => package.name),
        <String>['planted_root', 'planted_alpha', 'planted_inner', 'planted_zeta'],
        reason:
            'a package nested under another one is still a package, and the order is the '
            "directory's: the gate's verdict line names what it covered as a list, and a list that "
            'reshuffles between two runs over the same tree cannot be compared to the last one',
      );
      expect(found.first.directory, tree.path);
    });

    test(
      'names each package the way its manifest declares it, not the way the directory reads',
      () {
        final Directory tree = _scratch();
        _plant(tree, '', name: 'planted_root');
        _plant(tree, 'a-hyphenated-directory', name: 'planted_underscored_name');

        expect(
          dartPackagesIn(tree).map((DartPackage package) => package.name),
          contains('planted_underscored_name'),
          reason:
              'an import says `package:` and then the declared name and nothing else, so a name '
              'derived from the directory would name packages that no import can reach — a Dart '
              'package name may not carry a hyphen and a directory of ours usually does',
        );
      },
    );

    test('answers, in the tree this suite runs in, with the package this suite is in', () {
      expect(
        dartPackagesIn(repositoryOf(Directory.current)).map((DartPackage package) => package.name),
        contains('ansiwise_cli'),
        reason:
            'the planted trees above say what the walk does with a tree somebody made for it; this '
            'says it still finds the real one, and with this package missing from the list the '
            'gate would report every check green having opened nothing',
      );
    });
  });

  group('the root of the tree', () {
    test('is a package when it carries a lib/', () {
      final Directory tree = _scratch();
      _plant(tree, '', name: 'planted_root');

      expect(dartPackagesIn(tree).map((DartPackage package) => package.name), <String>[
        'planted_root',
      ], reason: 'a one-package repository would otherwise be invisible to every check there is');
    });

    test('is a package when it carries a bin/ and no lib/', () {
      final Directory tree = _scratch();
      _plant(tree, '', name: 'planted_tool', holding: 'bin');

      expect(
        dartPackagesIn(tree).map((DartPackage package) => package.name),
        <String>['planted_tool'],
        reason:
            'a package whose whole content is an entry point — a composition root compiled into a '
            'binary is one — has no lib/ at all, and a rule that only looked for lib/ would leave '
            'it out of every run',
      );
    });

    test('is a workspace and not a package when it carries neither', () {
      final Directory tree = _scratch();
      _plant(tree, '', name: 'planted_workspace', holding: null);
      _plant(tree, 'member', name: 'planted_member');

      expect(
        dartPackagesIn(tree).map((DartPackage package) => package.name),
        <String>['planted_member'],
        reason:
            'walking a workspace manifest as a package counts every member twice — once under the '
            'root that lists them and once as itself — so every check below runs twice and the '
            'verdict line states a count nothing in the tree matches',
      );
    });
  });

  group('directories that are not source', () {
    test('hold no package of this tree, for each of the ${prunedDirectories.length} pruned '
        'names', () {
      final Directory tree = _scratch();
      _plant(tree, '', name: 'planted_root');
      for (final String pruned in prunedDirectories) {
        _plant(tree, '$pruned/inner', name: 'planted_inside_something_pruned');
      }

      expect(
        dartPackagesIn(tree).map((DartPackage package) => package.name),
        <String>['planted_root'],
        reason:
            '.dart_tool/ holds a resolved copy of every dependency and build/ holds what a compile '
            "wrote, so walking them puts other people's packages, and copies of our own, into the "
            'run this repository is judged by',
      );
    });

    test(
      'are matched by their whole name, so a directory that merely starts like one is walked',
      () {
        final Directory tree = _scratch();
        _plant(tree, '', name: 'planted_root');
        _plant(tree, 'build_tools', name: 'planted_build_tools');
        _plant(tree, 'buildings/deep', name: 'planted_deep');

        expect(
          dartPackagesIn(tree).map((DartPackage package) => package.name),
          <String>['planted_root', 'planted_build_tools', 'planted_deep'],
          reason:
              'a prune that tested for a prefix would take build_tools out of the run, and every '
              'package under it with it, while the verdict line went on saying every check is green',
        );
      },
    );
  });

  group('the manifest', () {
    test('declares the name on a line of its own, and a nested one is a key of its block', () {
      expect(
        declaredPackageName(
          'dependencies:\n'
          '  some_dependency:\n'
          '    name: planted_nested_key\n'
          'name: planted_package\n',
        ),
        'planted_package',
        reason:
            'the first `name:` anywhere in the file would name this package after a dependency, '
            'and every check below would report under a name no import of this tree uses',
      );
    });

    test('is read past comments, and the name is taken without what trails it', () {
      expect(
        declaredPackageName('# what this package is\nname: planted_package   \n'),
        'planted_package',
      );
    });

    test('with no name declared is not a package at all', () {
      final Directory tree = _scratch();
      _plant(tree, '', name: 'planted_root');
      Directory('${tree.path}/nameless/lib').createSync(recursive: true);
      File('${tree.path}/nameless/pubspec.yaml').writeAsStringSync('version: 0.1.0\n');

      expect(declaredPackageName('version: 0.1.0\n'), isNull);
      expect(
        dartPackagesIn(tree).map((DartPackage package) => package.name),
        <String>['planted_root'],
        reason:
            'there is nothing an import could say after `package:` and nothing a refusal could '
            'name, and the gate reports what it found by name',
      );
    });
  });
}

/// Plants a package at [path] under [tree], declaring [name] and carrying the [holding] directory
/// that makes a root count as code — `null` for the manifest of a workspace, which carries none.
void _plant(Directory tree, String path, {required String name, String? holding = 'lib'}) {
  final String directory = path.isEmpty ? tree.path : '${tree.path}/$path';
  Directory(holding == null ? directory : '$directory/$holding').createSync(recursive: true);
  File('$directory/pubspec.yaml').writeAsStringSync('name: $name\n');
}

Directory _scratch() {
  final Directory directory = Directory.systemTemp.createTempSync('ansiwise-cli-dart-packages-');
  addTearDown(() => directory.deleteSync(recursive: true));
  return directory;
}
