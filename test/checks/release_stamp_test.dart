import 'dart:io';

import 'package:test/test.dart';

import '../../tool/gate/release_stamp.dart';

/// release-stamp — what the binaries answer when asked which version they are.
///
/// **A BINARY THAT CANNOT SAY WHAT IT IS FORCES EVERYBODY ELSE TO GUESS**, and this repository spent
/// a long time paying for that: the only statement about which version stood on a machine was the
/// NAME of the file a symlink pointed at, so a `readlink -f` probe parsed a version back out of a
/// filename, a sentinel stood for a file whose version nothing could read, and a hand-composed
/// shell script installed under the versioned name and linked the plain one. `install_pinned_tool`,
/// the step that keeps argocd, vault and yq at the version a program pins, decides its skip on the
/// version and refuses a tool it cannot ask — so it could manage neither of these two at all.
///
/// **THE FILE IN THIS TREE MUST SAY `unreleased`, and that is the check that matters most here.**
/// `lib/release_stamp.dart` is generated and TRACKED, like `lib/plugins.dart` beside it — but
/// unlike that one its content depends on the environment a build ran in. A stamped copy committed by accident is not a stale file: it is every later
/// build on every machine answering a release it is not, and a pinned-tool step then leaving a
/// machine alone that carries something else entirely.
///
/// **NO COMPILER RUNS HERE.** What is measured is the value the stamp is composed from and the file
/// composed out of it. That the compiler puts the constant into the executable is Dart's, and that
/// the binary prints it is `answeredVersion` in `lib/installation.dart`.
void main() {
  group('the stamp a build carries', () {
    test('is the tag the environment states', () {
      expect(
        stampFor(<String, String>{releaseTagVariable: '0.1.0-alpha-20260821194500'}),
        '0.1.0-alpha-20260821194500',
      );
    });

    test('is $unreleased where nothing states one', () {
      expect(stampFor(const <String, String>{}), unreleased);
    });

    test('is $unreleased where the variable is empty, and that is not a refusal', () {
      // A runner that templates a variable it has no value for writes the empty string. Refusing
      // that would fail every build that is not a release, which is most of them.
      expect(stampFor(<String, String>{releaseTagVariable: ''}), unreleased);
      expect(stampFor(<String, String>{releaseTagVariable: '   '}), unreleased);
    });

    test('is trimmed, because a variable carries what a shell put in it', () {
      expect(
        stampFor(<String, String>{releaseTagVariable: ' 0.1.0-beta-20260821194500 '}),
        '0.1.0-beta-20260821194500',
      );
    });

    test('$unreleased is not shaped like a version, so nothing can compare it to a pin', () {
      // The reader every pinned-tool step uses takes `\d+\.\d+(\.\d+)?` out of the answer. A
      // sentinel that matched would be read as a version and held against a pin, and whoever read
      // the result would be deciding whether a machine drifted or was never released.
      expect(RegExp(r'\d+\.\d+(\.\d+)?').hasMatch(unreleased), isFalse);
    });
  });

  group('COUNTER-PROBE: a value that is no release tag is refused, not stamped', () {
    // Each of these was planted against the real tool/build.dart and seen red before it went in.
    // The first four are refused by the shape; the last three are the ones a shape reader lets
    // through, and each needed a reader of its own.
    for (final (String stated, String because) in const <(String, String)>[
      ('v1.2.3', 'a v prefix, which this grammar has no room for'),
      ('main', 'a branch name'),
      ('latest', 'a word that is not a version at all'),
      ('1.2.3', 'three numbers with no channel and no stamp'),
      ('0.1.0-alpha', 'a channel and no stamp'),
      ('01.2.3-alpha-20260821194500', 'a leading zero, which the platform grammar forbids'),
      ('0.1.0-alpha-2026082119450', 'thirteen stamp digits, one short of fourteen'),
      ('0.1.0-alpha-202608211945000', 'fifteen stamp digits, one too many'),
    ]) {
      test('"$stated" — $because', () {
        expect(
          () => stampFor(<String, String>{releaseTagVariable: stated}),
          throwsA(isA<ReleaseStampRefused>()),
          reason:
              'a binary stamped with this would answer it to everything asking what version it is, '
              'and every pin it was held against would disagree for a reason nobody could read',
        );
      });
    }

    test('and the refusal names the value, or nobody can put it right', () {
      expect(
        () => stampFor(<String, String>{releaseTagVariable: 'v1.2.3'}),
        throwsA(
          isA<ReleaseStampRefused>().having(
            (ReleaseStampRefused refused) => refused.message,
            'message',
            allOf(contains('v1.2.3'), contains(releaseTagVariable)),
          ),
        ),
      );
    });

    test('INNOCENT CASE: every channel of the grammar is stamped, not refused', () {
      for (final String channel in const <String>['alpha', 'beta', 'stable']) {
        final String tag = '10.20.30-$channel-20270214235959';
        expect(stampFor(<String, String>{releaseTagVariable: tag}), tag);
      }
    });
  });

  group('the file this repository carries', () {
    // From the working directory, which `dart test` sets to the package — Platform.script points
    // at the compiled test and not at this tree, the same reason plugin_set_test.dart reads it this
    // way.
    final File tracked = File('${Directory.current.path}/$releaseStampFileName');

    test('is there, because the compiler reads it and not the environment', () {
      expect(
        tracked.existsSync(),
        isTrue,
        reason:
            '$releaseStampFileName is generated by tool/build.dart and tracked, like lib/plugins.dart '
            'beside it. Absent, nothing in lib/ compiles',
      );
    });

    test('says $unreleased — a stamped copy in this tree is a defect and not a stale file', () {
      expect(
        tracked.readAsStringSync().replaceAll('\r\n', '\n'),
        releaseStampSource(unreleased),
        reason:
            'a stamped copy committed here makes EVERY later build on EVERY machine answer a '
            'release it is not, and a pinned-tool step then leaves a machine alone that carries '
            'something else. Run dart run tool/build.dart with no $releaseTagVariable set',
      );
    });
  });
}
