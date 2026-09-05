import 'dart:io';

import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_checks_gate/ansiwise_checks_gate.dart';
import 'package:test/test.dart';

/// declared-checks — this package is told what it checks, and holds the disk against it.
///
/// The reading and its counter-probe are [auditDeclaredChecks], shared with every other package of
/// this family. What is here besides it is the one thing the reading cannot do: notice its own
/// absence. A check and its counter-probe live in one file, so deleting the reader takes the
/// reading with it and leaves `checks.yaml` describing a suite nobody compares anything to. The
/// gate asks that question before anything runs, and [undeclaredSuites] is asked here as well so
/// the tree says whether it would.
///
/// The refusal itself is driven over planted packages in package:ansiwise_checks_gate, where it
/// lives. What is asked here is only whether this repository satisfies it today.
void main() {
  auditDeclaredChecks();

  test('every package of this repository that has a suite carries both files', () {
    expect(
      undeclaredSuites(dartPackagesIn(repositoryOf(Directory.current))),
      isEmpty,
      reason:
          'this is the gate refusing to start, run here so the tree says whether it would — a '
          'package whose declaration or whose reader is gone is a package nothing holds to what it '
          'says it checks',
    );
  });
}
