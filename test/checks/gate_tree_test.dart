import 'dart:io';

import 'package:test/test.dart';

import '../../tool/gate/paths.dart';

/// gate-tree — WHICH tree the gate walks, decided by path arithmetic it does for itself.
///
/// Nothing under tool/ may import package:path — the gate is what resolves the tree, so its own
/// program has to start on a clone where no package has been resolved — and a wrong answer here
/// points every tool the gate starts at the wrong directory. What is found IN the tree once it is
/// named, and what is compiled out of it, are two other subjects with two suites of their own.
void main() {
  group('the path arithmetic tool/ does without package:path', () {
    test('a program under tool/ finds the package it is part of', () {
      expect(
        packageOfToolScript(Uri.file('/repos/hostyour-cloud/tool/ci.dart')).path,
        endsWith('hostyour-cloud'),
        reason:
            'taken from where the program sits and not from the working directory, so a run from a '
            'subdirectory answers the same instead of quietly gating less',
      );
    });

    test('the last segment is found whichever separator wrote the path', () {
      expect(baseName(r'D:\repos\hostyour-cloud\tool'), 'tool');
      expect(baseName('/work/hostyour-cloud/tool'), 'tool');
    });

    test('the repository is the directory holding .git, not the package below it', () {
      // The distinction the gate could not make. While this repository held ONE package the two were
      // the same directory; a second arrived, the walk was still rooted at the first, and the run
      // printed `every check green` over sixty-four files it had never opened.
      final Directory scratch = _scratch();
      Directory('${scratch.path}/.git').createSync(recursive: true);
      final Directory package = Directory('${scratch.path}/a-package/tool')
        ..createSync(recursive: true);
      expect(repositoryOf(package).path, scratch.absolute.path);
    });

    test('a directory under no repository is refused rather than guessed at', () {
      // Answering with SOMETHING — the filesystem root, or the directory it started from — would
      // send the gate over a tree nobody named, and let it report about that one in exactly the
      // words it reports about ours.
      expect(
        () => repositoryOf(_scratch()),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('no .git at or above'),
          ),
        ),
      );
    });
  });
}

Directory _scratch() {
  final Directory directory = Directory.systemTemp.createTempSync('hostyour-cloud-tool-tree-');
  addTearDown(() => directory.deleteSync(recursive: true));
  return directory;
}
