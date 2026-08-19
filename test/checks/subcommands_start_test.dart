import 'dart:convert';
import 'dart:io';

import 'package:ansiwise_checks_tree/ansiwise_checks_tree.dart';
import 'package:test/test.dart';

/// subcommands-start — every subcommand that executes no step starts under the installation's own
/// configuration.
///
/// **THE DEFECT THIS EXISTS FOR SHIPPED.** Elevation gained a second route — the caller hands the
/// password over with the answers instead of the machine holding it in a file — and the composition
/// root resolved that route for EVERY subcommand at start-up. `serve` comes through the same entry
/// and can never be handed one: its standard input IS the byte stream of the connection, and the
/// option that would carry a password reads that stream to end-of-input. So on any installation that
/// chose the caller's route, the REST surface exited 78 before answering anything, and every test in
/// this repository stayed green because not one of them started the binary the way a machine does.
///
/// **What is asserted is the START, not the work.** `serve` is given a closed standard input, so it
/// has a connection that ends immediately and returns; what matters is that it got that far rather
/// than refusing at start-up. A refusal that belongs to a RUN belongs where a step is about to be
/// taken, and the other half of this check is that a run with no password still refuses.
Future<void> main() async {
  // SKIPPED WHERE THERE IS NO INSTALLATION TO READ, printed rather than passed over: what is judged
  // here is this binary against an installation's configuration, and a clone of this repository
  // standing alone has none.
  if (!installationIsFindable) {
    test('subcommands-start', () {}, skip: installationNotFound);
    return;
  }

  final String installation = installationRoot;
  final String programs = '$installation/$installationPrograms';
  final String configuration = '$installation/ansiwise.yaml';

  Future<ProcessResult> ansiwise(List<String> arguments, {String? stdinText}) async {
    final Process child = await Process.start('dart', <String>[
      'run',
      'bin/ansiwise.dart',
      ...arguments,
      '--programs',
      programs,
      '--config',
      configuration,
    ], workingDirectory: Directory.current.path);
    if (stdinText != null) {
      child.stdin.write(stdinText);
    }
    await child.stdin.close();
    final List<String> out = <String>[
      await utf8.decodeStream(child.stdout),
      await utf8.decodeStream(child.stderr),
    ];
    return ProcessResult(child.pid, await child.exitCode, out.first, out.last);
  }

  group('subcommands-start', () {
    test('serve starts under this installation\'s configuration', () async {
      final ProcessResult answered = await ansiwise(<String>['serve']);

      expect(
        answered.exitCode,
        isNot(78),
        reason:
            'the surface refused to START under the configuration it is meant to serve:\n'
            '${answered.stderr}\n'
            'a subcommand that executes no step holds no password, and refusing one at the entry '
            'takes the whole REST surface away from every installation that chose that route',
      );
      expect(
        answered.stderr,
        isNot(contains('raises a command to root')),
        reason: 'serve was asked for a password it can neither be handed nor use',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('THE INNOCENT NEIGHBOUR: a run with no password still refuses, before any step', () async {
      // The refusal did not disappear, it moved. A run is where a step is about to be taken, and it
      // is where an installation that named the caller's route and was handed nothing must stop.
      final ProcessResult answered = await ansiwise(<String>[
        'deploy-host',
        '--mode',
        'test',
        '--answers',
        '-',
      ], stdinText: '{"answers":{}}');

      expect(answered.exitCode, 78);
      expect(answered.stderr, contains('raises a command to root'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
