import 'dart:convert';
import 'dart:io';

import 'package:ansiwise_checks_tree/ansiwise_checks_tree.dart';
import 'package:test/test.dart';

/// How a line of a hand-built request ends on the wire.
const String crlf = '\r\n';

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
///
/// **THE THREE RUNS BELOW ARE THE WHOLE OF WHAT THAT REFUSAL IS ASKED ABOUT.** It answers whether
/// root is reachable and never whether this run needs it — nothing on this side of the engine knows
/// that, because elevation is chosen per call inside a step while it runs. So silence about a
/// password is read as need, which is right for a run a person starts and impossible for one the
/// machine starts after a reboot: told nothing, refused before its first step, and no caller there
/// to be told. The three cases are a run that says nothing, one that says the silence is meant, and
/// one that says both — and the second of them is the one this exists for.
///
/// What a run holding no password may then be, and what it is refused for, is a different question
/// and is measured elsewhere: test/checks/elevation_without_password_test.dart.
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

  // THE TWO BINARIES ARE BOTH STARTED HERE, and which one a case uses is the point of the case.
  // `serve` is a program of the serving binary; a deployment program is a program of the other. What
  // this suite holds is that the composition IN FRONT of both — the configuration, the plugins, the
  // elevation route — behaves the same way for each, because they share it: a refusal that moved to
  // one of them and not the other is exactly the defect this exists for.
  Future<ProcessResult> started(
    String entryPoint,
    List<String> arguments, {
    String? stdinText,
  }) async {
    final Process child = await Process.start('dart', <String>[
      'run',
      entryPoint,
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
    // BOTH STREAMS ARE DRAINED AT ONCE, and this is the same deadlock the recording shell writes
    // about. Waiting for one to end before reading the other leaves the second pipe unread: a child
    // that fills its buffer blocks on its next write, never exits, and the wait never returns. It
    // held while every case here answered in one or two lines, and stopped holding at the first one
    // that names four missing answers on standard error.
    final Future<String> out = utf8.decodeStream(child.stdout);
    final Future<String> err = utf8.decodeStream(child.stderr);
    return ProcessResult(child.pid, await child.exitCode, await out, await err);
  }

  /// The serving binary, whose one program is `serve`.
  Future<ProcessResult> ansiwiseRest(List<String> arguments, {String? stdinText}) =>
      started('bin/ansiwise_rest.dart', arguments, stdinText: stdinText);

  /// The deployment tool, which carries every program of the installation.
  Future<ProcessResult> ansiwise(List<String> arguments, {String? stdinText}) =>
      started('bin/ansiwise.dart', arguments, stdinText: stdinText);

  group('subcommands-start', () {
    test('serve starts under this installation\'s configuration', () async {
      final ProcessResult answered = await ansiwiseRest(<String>['serve']);

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

    test('a run that says it hands over no password is not asked for one', () async {
      // THE CASE THE SECOND CONFIGURATION FILE WAS WRITTEN FOR. Same installation, same absence of
      // a password — and the run walks past the elevation refusal to the next thing that can refuse
      // it, which is the answers it was not given.
      //
      // A PROGRAM WHOSE EVERY ROW SAYS `on_failure: exit`, because that is what the option admits:
      // a row saying `continue` would carry the run past the refusal a command that has to run as
      // root meets, and such a program is refused before its first step instead. Which programs of
      // an installation are of which shape is measured in
      // test/checks/elevation_without_password_test.dart, against rows that check plants rather
      // than against whichever rows a catalogue happens to carry today.
      final ProcessResult answered = await ansiwise(<String>[
        'disable-password-login',
        '--mode',
        'test',
        '--without-elevation-password',
        '--answers',
        '-',
      ], stdinText: '{"answers":{}}');

      expect(
        answered.exitCode,
        65,
        reason:
            'the run was to reach the answers it is missing and did not:\n${answered.stderr}\n'
            '78 is the elevation refusal, still asked of a caller that said it hands none over',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('THE INNOCENT NEIGHBOUR: a run that says both is refused, and starts nothing', () async {
      // A caller saying it hands none over WHILE handing one over says two opposite things about
      // one run. Choosing either would act on a decision nobody made, so neither is taken.
      final ProcessResult answered = await ansiwise(<String>[
        'disable-password-login',
        '--mode',
        'test',
        '--without-elevation-password',
        '--answers',
        '-',
      ], stdinText: '{"answers":{},"elevation_password":"what raises a command"}');

      expect(
        answered.exitCode,
        78,
        reason:
            'the two together were resolved instead of refused:\n${answered.stderr}\n'
            'nothing else answers 78 here — a password arrived, so the refusal for a missing one '
            'cannot be what spoke',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
    test('serve ANSWERS over its own stdio, which is the door every first installation uses', () async {
      // Starting is not answering, and for a while it was only starting. The server socket handed
      // out its one connection from a stream that ended in the same turn, so the request arrived at
      // a server that had already shut: serve wrote nothing, exited zero, and said nothing. Only a
      // request written into a real process catches that — a test that feeds the connection from a
      // queued controller wins the race the real thing always loses.
      final Process session = await Process.start('dart', <String>[
        'run',
        'bin/ansiwise_rest.dart',
        'serve',
        '--programs',
        programs,
        '--config',
        configuration,
      ], workingDirectory: Directory.current.path);

      session.stdin.write('GET /programs HTTP/1.1');
      session.stdin.write(crlf);
      session.stdin.write('Host: m');
      session.stdin.write(crlf);
      session.stdin.write(crlf);
      await session.stdin.flush();

      final Future<String> answered = utf8.decodeStream(session.stdout);
      // The channel closes the way a session closes, which is also what must end the process.
      await Future<void>.delayed(const Duration(seconds: 3));
      await session.stdin.close();

      final String said = await answered;
      expect(said, startsWith('HTTP/1.1 200'), reason: 'the door was mute');
      expect(said, contains('deploy-host'), reason: 'it answered, but not with this installation');
      expect(
        await session.exitCode.timeout(const Duration(seconds: 20)),
        0,
        reason: 'the channel closed and the process stayed — one left behind per session',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
