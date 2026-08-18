import 'dart:io';

import 'package:ansiwise_checks_tree/ansiwise_checks_tree.dart';
import 'package:test/test.dart';

/// shared-gate — this repository's gate plumbing is the one text every gate shares.
///
/// **Why a copy exists at all.** The gate resolves the tree, so its own program has to start on a
/// fresh clone where no package has been resolved. A gate living in a package would have to be
/// resolved before it could run the resolution. Nothing here removes the copy; what it removes is
/// the copy drifting unwatched.
///
/// **What it caught.** Two copies had already diverged in both directions: one gained the walk that
/// finds a repository rather than a package — added after a gate printed "every check green" with a
/// second package's files never analysed — and the other never got it; one carried an example
/// naming the repository it had been copied out of.
///
/// **What is not compared, and why that is not a loophole.** The files that DECIDE something differ
/// between repositories because their subjects differ. Comparing those would be red for ever, which
/// is a check nobody can satisfy and therefore a check nobody reads.
void main() {
  test('every shared gate file is exactly the one text', () {
    final Directory gate = Directory('tool/gate');
    expect(gate.existsSync(), isTrue, reason: 'this repository has a gate');

    final Map<String, String> held = <String, String>{
      for (final FileSystemEntity each in gate.listSync())
        if (each is File && each.path.endsWith('.dart'))
          each.uri.pathSegments.last: each.readAsStringSync(),
    };

    expect(auditSharedGate(held).map((Finding each) => '${each.subject}: ${each.what}'), isEmpty);
  });

  test('counter-probe: an edited copy is reported, and an untouched one is not', () {
    final Map<String, String> untouched = Map<String, String>.of(canonicalGateFiles);
    expect(
      auditSharedGate(untouched),
      isEmpty,
      reason: 'the innocent case, or nothing means anything',
    );

    // PLANTED: one line changed in one file, which is exactly the shape of a repair that landed in
    // one copy and not the other.
    final Map<String, String> edited = Map<String, String>.of(canonicalGateFiles)
      ..update('paths.dart', (String text) => '$text\n// a repair somebody made here alone\n');
    expect(auditSharedGate(edited).map((Finding each) => each.subject), <String>[
      'tool/gate/paths.dart',
    ]);

    // PLANTED: a file missing altogether. A gate without its plumbing is not a gate that passes.
    final Map<String, String> short = Map<String, String>.of(canonicalGateFiles)
      ..remove('pins.dart');
    expect(auditSharedGate(short).map((Finding each) => each.subject), <String>[
      'tool/gate/pins.dart',
    ]);
  });
}
