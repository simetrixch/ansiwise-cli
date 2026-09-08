import 'dart:convert';
import 'dart:io';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:test/test.dart';

/// record-not-removed — what this binary answers when the bound on run records cannot be held.
///
/// **THE DEFECT IT EXISTS FOR.** Writing a run's opening header is where the number of records the
/// machine keeps is applied, and that happens before the first step. A record this account owns and
/// cannot remove made the file system refuse, the refusal was a `FileSystemException` nothing
/// caught, and the process died with a Dart stack and exit 255 — measured on a master on
/// 2026-09-06, where 499 of the 501 records under `/var/lib/ansiwise/runs` had been written by root
/// on a timer. The operator was told the engine had crashed, and what was true was that the machine
/// was in a state the engine will not work in.
///
/// **WHY THE EXIT LIVES HERE AND THE RULE LIVES IN THE FRAMEWORK.** `RunRemoval` decides which
/// records are this account's and raises `RecordNotRemoved` for one of its own that will not go.
/// Which exit code a refusal before the first step answers with, and where its sentence is
/// recorded, is this binary's: `StartupReason.refuse` writes to standard error, writes
/// `<id>.startup.log` where the run was given an identifier, and ends the process with 65 — the
/// same code every other refusal over what a run was given answers with.
///
/// **PLANTED, NOT BORROWED.** The store this drives is two records this test writes with the
/// framework's own recorder, so the shape is fixed here rather than being whatever a machine
/// happens to hold.
void main() {
  group(
    'record-not-removed',
    () {
      test(
        'THE PLANTED DEFECT: a record this account cannot remove ends the run with 65',
        () async {
          final Directory records = await _plantRecords('refused');
          final String held = RunDirectory(records.path).of(_older);
          await setPermissions(held, 320);
          addTearDown(() => setPermissions(held, 448));

          final ProcessResult refused = await _ansiwise(records);

          expect(
            refused.exitCode,
            65,
            reason:
                'the bound could not be held and the run answered something other than a refusal:\n'
                '${refused.stdout}${refused.stderr}',
          );
          expect(
            refused.stderr,
            allOf(contains(held), contains('cannot remove it')),
            reason: 'the operator is left with a stack unless the refusal names the record',
          );
          expect(
            refused.stderr,
            isNot(contains('#0      ')),
            reason: 'a Dart stack frame reached the operator, which is the defect this replaces',
          );
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      test('THE INNOCENT NEIGHBOUR: the same store with nothing held back runs through', () async {
        // Without this the case above would pass on a binary that refuses every run, and on one that
        // never applies the bound at all.
        final Directory records = await _plantRecords('allowed');

        final ProcessResult ran = await _ansiwise(records);

        expect(ran.exitCode, 0, reason: 'the run did not finish:\n${ran.stdout}${ran.stderr}');
        expect(
          Directory(RunDirectory(records.path).of(_older)).existsSync(),
          isFalse,
          reason: 'the record past the bound stayed, so the bound was never applied here',
        );
      }, timeout: const Timeout(Duration(minutes: 3)));
    },
    // The rule degrades on Windows: there is no POSIX owner and no permission bit to plant, so
    // every record under the root counts as this account's own and a directory cannot be made
    // unremovable this way.
    skip: Platform.isWindows ? 'Windows has no POSIX permission bits' : null,
  );
}

/// The older of the two planted records, and the one the bound reaches first.
const RunId _older = RunId('20260101T000000Z-1-aaaaaaaa');

/// The newer one, which the bound of two keeps.
const RunId _newer = RunId('20260101T000100Z-1-bbbbbbbb');

/// A run root under [what] holding both planted records, each written and closed.
///
/// Written with the framework's own recorder rather than as hand-built JSON, so what is planted is
/// what a run really leaves behind and cannot drift from it.
Future<Directory> _plantRecords(String what) async {
  final Directory records = Directory('${_probe.path}/records-$what')..createSync(recursive: true);
  final RunDirectory directory = RunDirectory(records.path);
  final DateTime begun = DateTime.utc(2026);
  int minute = 0;
  for (final RunId id in <RunId>[_older, _newer]) {
    final DateTime start = begun.add(Duration(minutes: minute++));
    final RunRecord header = RunRecord(
      id: id,
      program: const ProgramName('probe-no-root'),
      mode: Mode.test,
      argv: const <String>['ansiwise', 'probe-no-root'],
      start: start,
      stage: const Stage('dev'),
      role: const Role('master'),
      fqdn: const Fqdn(''),
      commit: '',
      fingerprint: 'planted',
    );
    // The bound of the planting recorder stands far above what it plants, so writing the second
    // record does not remove the first.
    final FileRecorder recorder = await FileRecorder.open(
      id: id,
      directory: directory,
      clock: const RealClock(),
      redactor: Redactor.none,
      retention: const RunRetention(1000),
    );
    await recorder.save(header);
    await recorder.close();
    await recorder.save(
      header.closed(
        end: start.add(const Duration(seconds: 1)),
        exitCode: 0,
        steps: const <StepRecord>[],
        issues: const <String>[],
      ),
    );
  }
  return records;
}

/// Starts the deployment binary against the probe installation, with [records] as its run root.
Future<ProcessResult> _ansiwise(Directory records) async {
  final Process child = await Process.start('dart', <String>[
    'run',
    'bin/ansiwise.dart',
    'probe-no-root',
    '--mode',
    'test',
    '--config',
    '${_probe.path}/ansiwise.yaml',
    '--programs',
    '${_probe.path}/programs',
    '--runs',
    records.path,
    '--answers',
    '-',
  ], workingDirectory: Directory.current.path);
  child.stdin.write(jsonEncode(<String, Object?>{'answers': <String, Object?>{}}));
  await child.stdin.close();
  // Both streams are drained at once. Waiting for one to end before reading the other leaves the
  // second pipe unread, and a child that fills its buffer blocks on its next write for ever.
  final Future<String> out = utf8.decodeStream(child.stdout);
  final Future<String> err = utf8.decodeStream(child.stderr);
  return ProcessResult(child.pid, await child.exitCode, await out, await err);
}

/// The installation this check plants, built once and used by both cases.
final Directory _probe = _plant();

Directory _plant() {
  final Directory root = Directory.systemTemp.createTempSync('ansiwise-record-removal-probe');
  Directory('${root.path}/programs').createSync();
  Directory('${root.path}/under-root').createSync();

  // Two records of this account's own, and a bound of two, so a third — this run's own header —
  // puts the oldest of them past it.
  File('${root.path}/ansiwise.yaml').writeAsStringSync(
    'log_level: info\n'
    'plugins:\n'
    '  - ansiwise-host\n'
    'runs:\n'
    '  keep: 2\n',
  );

  // set_process_flag reading a file that already carries the flag it would write, so the row has
  // nothing to do and the run finishes on every machine without a tool having to exist there. Its
  // check is two file reads and nothing else, at the elevation the row states, which is what this
  // probe needs and what create_storage_directory stopped being when it started measuring the
  // machine's data disk.
  File('${root.path}/under-root/args').writeAsStringSync('--probe=stands\n');
  File('${root.path}/programs/probe-no-root.yaml').writeAsStringSync(
    'name: probe-no-root\n'
    'roles: [master]\n'
    'steps:\n'
    '  - step: set_process_flag\n'
    '    args_path: ${root.path}/under-root/args\n'
    "    flag: '--probe'\n"
    '    value: stands\n'
    '    file_mode: 420\n'
    "    restart_command: ['true']\n"
    '    elevated: false\n'
    '    on_failure: exit\n',
  );
  return root;
}
