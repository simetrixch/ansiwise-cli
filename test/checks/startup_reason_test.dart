/// startup-reason — a run that never started says why, where a caller can read it.
///
///   dart test test/checks/startup_reason_test.dart
///
/// **THE DEFECT THIS EXISTS FOR COST MOST OF A NIGHT.** A run started over `ansiwise-rest serve` is a
/// DETACHED CHILD whose standard error is a pipe nobody reads — the launcher writes its standard
/// input and forgets the run exists, in its own words. So every refusal this binary makes BEFORE it
/// writes a header reached nobody, and the caller was left with an absence:
///
///     machine run 20260827T125317Z-… was accepted but never wrote its record — it started
///     and died before its first step; read the machine's serve log
///
/// There was no serve log. Three separate defects on one installation were diagnosed only by running
/// the child BY HAND with the same envelope, because the machine kept its own words to itself.
///
/// TWO THINGS ARE HELD, and they are different in kind. The first is behaviour: a run given an
/// identifier writes its reason beside the records, and a run given none does not. The second is
/// STRUCTURAL: no other place in this binary may write to standard error and then end the run,
/// because a refusal that skips StartupReason.refuse is a refusal nobody can read — and that is exactly
/// how sixteen of them came to exist.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:test/test.dart';

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

  // THE STRUCTURAL HALF. Every one of these used to be its own `stderr.writeln` followed by its own
  // exit, and every one of them was unreadable to the caller that matters. What keeps a new one from
  // being written the same way is this, and not anybody's memory.
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
}
