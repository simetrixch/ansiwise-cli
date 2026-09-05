/// startup-reason — a run that never started says why, where a caller can read it.
///
///   dart test test/checks/startup_reason_test.dart
///
/// **THE DEFECT THIS EXISTS FOR.** A run started over `ansiwise-rest serve` is a DETACHED CHILD
/// whose standard error is a pipe nobody reads — the launcher writes its standard input and forgets
/// the run exists, in its own words. A refusal this binary makes BEFORE it writes a header therefore
/// reaches nobody, and the caller is left with an absence:
///
///     machine run 20260827T125317Z-… was accepted but never wrote its record — it started
///     and died before its first step; read the machine's serve log
///
/// There is no serve log. Such a defect is diagnosable only by running the child BY HAND with the
/// same envelope, because the machine keeps its own words to itself.
///
/// THREE THINGS ARE HELD, and they are different in kind. The first is behaviour: a run given an
/// identifier writes its reason beside the records, and a run given none does not. The second is
/// STRUCTURAL: no other place in this binary may write to standard error and then end the run,
/// because a refusal that skips StartupReason.refuse is a refusal nobody can read. The third is the
/// READING, which is the half the sentence above is written for: the serving binary answers
/// `GET /runs/{id}` for a run that left a reason with that reason, and a reason nobody reads back is
/// the same absence it replaced.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ansiwise_checks_tree/ansiwise_checks_tree.dart';
import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:test/test.dart';

/// How a line of a hand-built request ends on the wire.
const String crlf = '\r\n';

void main() {
  late Directory runs;

  setUp(() => runs = Directory.systemTemp.createTempSync('ansiwise-startup'));
  tearDown(() {
    if (runs.existsSync()) runs.deleteSync(recursive: true);
  });

  /// This binary, started the way the launcher starts it: told which run it is and where records go.
  ///
  /// It is started somewhere that is NOT an installation, which is the first thing the composition
  /// refuses and the cheapest of these to arrange — and it is one an operator meets for real, by
  /// running the binary from anywhere but the tree it belongs to.
  Future<ProcessResult> started({String? runId}) async {
    final Process child = await Process.start('dart', <String>[
      'run',
      'bin/ansiwise.dart',
      'any-program',
      '--programs',
      '${runs.path}/there-is-nothing-here',
      '--runs',
      runs.path,
      '--mode',
      'test',
      if (runId != null) ...<String>['--run', runId],
    ], workingDirectory: Directory.current.path);
    await child.stdin.close();
    // BOTH STREAMS AT ONCE: waiting for one to end before reading the other leaves the second pipe
    // unread, and a child that fills its buffer never exits.
    final Future<String> out = utf8.decodeStream(child.stdout);
    final Future<String> err = utf8.decodeStream(child.stderr);
    return ProcessResult(child.pid, await child.exitCode, await out, await err);
  }

  test('a run that cannot compose leaves its reason beside the records', () async {
    final ProcessResult answer = await started(runId: 'probe-run');

    expect(answer.exitCode, 78);
    final File said = File(RunDirectory(runs.path).startupLog(const RunId('probe-run')));
    expect(said.existsSync(), isTrue, reason: 'the run ended and said why to nobody');
    expect(
      said.readAsStringSync(),
      allOf(contains('ansiwise.yaml'), contains('which plugins are active')),
      reason: 'the file has to carry the sentence, not the fact that there was one',
    );
  });

  // STANDARD ERROR IS NOT REPLACED, and that matters: the file is for the reader who has no
  // terminal, not instead of the one who has.
  test('the same sentence still reaches standard error', () async {
    final ProcessResult answer = await started(runId: 'probe-both');
    expect(answer.stderr.toString(), contains('ansiwise.yaml'));
  });

  // THE INNOCENT CASE. A run nobody named is a person at a terminal, who is already looking at the
  // sentence — and a file per such run would be litter nothing ever removes.
  test('a run nobody named writes no file at all', () async {
    final ProcessResult answer = await started();

    expect(answer.exitCode, 78);
    expect(answer.stderr.toString(), contains('ansiwise.yaml'));
    expect(
      runs.listSync().map((FileSystemEntity e) => e.path.split(Platform.pathSeparator).last),
      isEmpty,
      reason: 'nothing was recorded for a run that has no identifier to come back for',
    );
  });

  // THE STRUCTURAL HALF. A refusal written as its own `stderr.writeln` followed by its own exit is
  // unreadable to the caller that matters. What keeps a new one from being written that way is this
  // test, and not anybody's memory.
  test('nothing else in this binary says something and then ends the run', () {
    final List<String> offenders = <String>[];
    for (final File source in <File>[File('bin/ansiwise.dart'), File('lib/installation.dart')]) {
      final List<String> lines = source.readAsLinesSync();
      for (int at = 0; at < lines.length; at++) {
        if (!lines[at].contains('stderr.writeln')) continue;
        // What follows a refusal, ignoring the lines that are only the rest of its own sentence.
        final String after = lines
            .skip(at + 1)
            .take(6)
            .firstWhere(
              (String line) => line.trim().startsWith('exit(') || line.trim().startsWith('return '),
              orElse: () => '',
            );
        if (after.isEmpty) continue;
        // The two places that may, and both are named rather than pattern-matched.
        //
        // StartupReason.refuse itself IS the recording, and the argument list's own parse failure
        // comes BEFORE anything can be recorded: which run this is and where records go are two
        // options, and the parse that would have read them is the one that just failed. Everything
        // between those two ends is what this holds.
        if (source.path.endsWith('installation.dart') &&
            lines[at].contains('stderr.writeln(message);')) {
          continue;
        }
        if (lines[at].contains('stderr.writeln(bad.message);') ||
            lines[at].contains('stderr.writeln(parser.usage);')) {
          continue;
        }
        offenders.add('${source.path}:${at + 1} — ${lines[at].trim()} … ${after.trim()}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'each of these says something and ends the run without recording it, so a caller who '
          'cannot see standard error is told only that nothing was written. Use StartupReason.refuse',
    );
  });

  // THE READING HALF, over the door the reason exists for. A run that died before its first step
  // and an identifier nobody ever issued were one 404 with one sentence, so a caller holding an id
  // it had just been handed at `202` could do nothing but wait out its own clock: measured on apps6
  // on 2026-09-04, three declared answers missing, all three on disk beside the runs, 180 seconds
  // spent before the caller reported it could not tell a slow run from a dead one.
  //
  // SKIPPED WHERE THERE IS NO INSTALLATION TO READ, printed rather than passed over: the serving
  // binary composes itself from an installation's configuration, and a clone of this repository
  // standing alone has none.
  if (!installationIsFindable) {
    test('the door reads the reason back', () {}, skip: installationNotFound);
    return;
  }

  test('the door hands back what a run that never started said, and only for that run', () async {
    const RunId refused = RunId('20260903T234009Z-547069-7b5dc756');
    const RunId neverIssued = RunId('20260903T234009Z-000000-deadbeef');
    const String said = 'deploy-branch: needs the answer "build_platform_repo_write_pat"';
    File(RunDirectory(runs.path).startupLog(refused)).writeAsStringSync('$said\n');

    final Process session = await Process.start('dart', <String>[
      'run',
      'bin/ansiwise_rest.dart',
      'serve',
      '--programs',
      '$installationRoot/$installationPrograms',
      '--config',
      '$installationRoot/ansiwise.yaml',
      // THE RUN ROOT THE PLANTED REASON STANDS IN. The door has to read refusals out of the same
      // root it answers records from, and this is where that is decided for the whole process.
      '--runs',
      runs.path,
    ], workingDirectory: Directory.current.path);

    final StringBuffer complained = StringBuffer();
    session.stderr.transform(utf8.decoder).listen(complained.write);
    final Future<String> answered = utf8.decodeStream(session.stdout);
    try {
      // BOTH ASKS DOWN ONE CHANNEL, which is what a session is: `serve` speaks over the pipes of
      // the session it was started in, and there is no second connection to be had.
      for (final RunId asked in <RunId>[refused, neverIssued]) {
        session.stdin.write('GET /runs/${asked.value} HTTP/1.1$crlf');
        session.stdin.write('Host: m$crlf');
        session.stdin.write(crlf);
      }
      await session.stdin.flush();
      // The channel closes the way a session closes, and that is also what ends the process.
      await Future<void>.delayed(const Duration(seconds: 3));
      await session.stdin.close();

      final String door = await answered.timeout(
        const Duration(seconds: 110),
        onTimeout: () => fail('the door never answered\nstderr so far:\n$complained'),
      );
      expect(
        'HTTP/1.1 404'.allMatches(door),
        hasLength(2),
        reason: 'both asks are about a run with no record, and both are answered:\n$door',
      );
      expect(
        door,
        contains(onTheWire(said)),
        reason:
            'the words the child wrote did not reach the caller, so the answer is the absence this '
            'exists to replace:\n$door',
      );
      expect(
        door,
        contains(onTheWire('no run is called "${neverIssued.value}"')),
        reason:
            'an identifier nobody issued must keep the answer it has always had — a door that said '
            'the same thing about both has removed nothing:\n$door',
      );
    } finally {
      session.kill();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// [text] as it stands inside the JSON the door answers with.
///
/// A refusal crosses the wire as `{"refused": "..."}`, so the quotes a child wrote arrive as `\"`
/// and a line break as `\n`. A test looking for the raw sentence would be looking for something no
/// correct answer can contain.
String onTheWire(String text) {
  final String encoded = jsonEncode(text);
  return encoded.substring(1, encoded.length - 1);
}
