import 'dart:io';

import 'package:ansiwise_checks_gate/ansiwise_checks_gate.dart';
import 'package:test/test.dart';

/// resolved-packages — everything THIS binary is composed from answered from one place.
///
/// THE DEFECT IT EXISTS FOR. This repository names the framework and plugin packages of other
/// repositories by a git ref, and a gitignored `pubspec_overrides.yaml` re-points them at working
/// checkouts beside this one. The same commit therefore resolves to two different binaries — one
/// built from the working trees, one from what was pushed — and both are legitimate. What is not
/// legitimate is the third state: some overridden and some not, so the binary is built half from
/// the working tree and half from pushed commits with nothing saying which half is which.
///
/// WHY ONLY THE REAL TREE IS ASKED HERE. The reading itself — what a mix looks like, what a hosted
/// dependency under the cache is, what the gate does with a refusal — is driven with planted
/// resolutions in package:ansiwise_checks_gate, where the code lives. What cannot travel there is
/// this question: whether THIS manifest and THIS resolution agree. This is the only package of the
/// family that names other repositories by a git ref, so it is the only one where the question has
/// a subject at all.
void main() {
  test(
    'the manifest of this repository names packages by git, so the check measures something',
    () {
      // If the manifest stops declaring anything by a git ref, this goes red instead of the test
      // below going quietly green about nothing.
      expect(
        gitNamedDependencies(File('pubspec.yaml').readAsStringSync()),
        isNotEmpty,
        reason: 'with nothing git-named, the composition check would be green about no binary',
      );
    },
  );

  test('every git-named package of this repository has an answer in the real resolution', () {
    final List<String> members = gitNamedDependencies(File('pubspec.yaml').readAsStringSync());
    final List<String> refusals = compositionRefusals(
      composition: compositionOf(
        packageConfigText: File('.dart_tool/package_config.json').readAsStringSync(),
        configDirectory: '${Directory.current.path}/.dart_tool/',
        members: members,
      ),
      members: members,
    );
    expect(
      refusals,
      isEmpty,
      reason:
          'the fix is all or none: name every git-named package in pubspec_overrides.yaml, or '
          'delete that file and resolve again',
    );
  });
}
