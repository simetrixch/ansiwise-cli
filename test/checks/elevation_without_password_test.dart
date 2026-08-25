import 'dart:convert';
import 'dart:io';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

/// elevation-without-password — what `--without-elevation-password` may promise, held against what
/// the engine underneath it actually does with a command that has to run as root.
///
/// **THE PROMISE AND THE MECHANISM THAT BREAKS IT.** A run started with that option holds no
/// password at all, so the shell refuses every command marked elevated before it starts one. That
/// refusal is an exception; a step turns every exception it catches into the verdict of the row it
/// was running, under that row's own `on_failure`; and `continue` is the program saying in advance
/// that a failure of this row is walked past. So the run-wide condition — this run holds NO password
/// — is converted into a per-row note, and the run carries on to the rows after it.
///
/// **WHAT THIS CHECK COVERS, one by one rather than counted.** `on_failure` has exactly two values,
/// and both are measured here: `continue`, which is the shape the run is refused for, and `exit`,
/// which is the shape it is admitted for. The premise underneath — that a row's policy really is
/// what decides whether an elevation refusal ends the run — is measured in this process against the
/// real shell and the real runner, so it cannot rot into an assumption about code in another
/// repository. What it does NOT cover is a step that raises a command to root from somewhere the
/// engine does not route through a row's policy; nothing in the framework offers such a place today,
/// and the premise probe is what would notice if one appeared.
Future<void> main() async {
  group('elevation-without-password', () {
    test(
      'THE PREMISE: a row that says continue carries the run past an elevation refusal',
      () async {
        // MEASURED, NOT ASSUMED, and measured against the real shell. This is the whole reason the
        // command line refuses such a program before its first step: the engine has no way to end a
        // run on a condition that belongs to the run rather than to a row. If this ever goes red, an
        // elevation refusal has become something a row's policy cannot swallow, and the refusal in
        // bin/ansiwise.dart is doing work somebody else has taken over.
        final RunRecord walked = await _premiseRun(OnFailure.continueRun);

        expect(
          walked.steps.length,
          2,
          reason:
              'the run stopped at the first row that needed root, so the refusal no longer depends '
              'on the row policy and the command line need not ask about it',
        );
        expect(
          walked.exitCode,
          2,
          reason: 'a run that walked past both refusals closes on issues, and this one did not',
        );
      },
    );

    test(
      'THE PREMISE, INNOCENT NEIGHBOUR: a row that says exit ends the run at that command',
      () async {
        final RunRecord stopped = await _premiseRun(OnFailure.exit);

        expect(stopped.steps.length, 1, reason: 'the run went past the row that needed root');
        expect(stopped.exitCode, 1, reason: 'the run did not end on the row that needed root');
      },
    );

    test('BOTH POLICIES ARE MEASURED, so a third would not slip past unasked', () {
      expect(
        OnFailure.values.length,
        2,
        reason:
            'a policy was added, and what a run holding no password does under it is not measured '
            'anywhere here',
      );
    });

    test(
      'THE PLANTED DEFECT: a program with a continue row is refused before its first step',
      () async {
        // The shape the verification found in the shipped catalogue: rows that need root, standing
        // under `on_failure: continue`. Both modes an operator reaches this through are asked,
        // because the dry run is where they decide and a refusal they only meet at the real run is a
        // refusal that came too late.
        for (final String mode in <String>['dry', 'run']) {
          final Directory records = Directory('${_probe.path}/records-$mode');
          final ProcessResult refused = await _ansiwise(
            <String>['probe-continue', '--mode', mode, '--without-elevation-password'],
            configuration: _callerConfiguration,
            records: records,
          );

          expect(
            refused.exitCode,
            78,
            reason:
                'the run started in --mode $mode holding no password, over a program whose rows are '
                'pre-authorised to be walked past:\n${refused.stdout}${refused.stderr}',
          );
          expect(
            records.existsSync(),
            isFalse,
            reason: 'the run was refused and still wrote a record, so it had begun',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('THE INNOCENT NEIGHBOUR: every row saying exit, and the run goes ahead', () async {
      // The shape the option exists for. It is admitted, and it stops at the first command that has
      // to run as root — which is the whole of what the option's help text promises.
      final ProcessResult ran = await _ansiwise(
        <String>['probe-exit', '--mode', 'run', '--without-elevation-password'],
        configuration: _callerConfiguration,
        records: Directory('${_probe.path}/records-exit'),
      );

      expect(
        ran.exitCode,
        1,
        reason:
            'the run was to start and end on the row that needs root:\n${ran.stdout}${ran.stderr}\n'
            '78 is a refusal before the first step, which this program gives no reason for',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('THE INNOCENT NEIGHBOUR: a run that needs no root starts and finishes', () async {
      // The run a machine starts after a reboot: nothing it does is raised to root, and the option
      // is what stops the installation's own elevation route from refusing it before its first step.
      final ProcessResult ran = await _ansiwise(
        <String>['probe-no-root', '--mode', 'run', '--without-elevation-password'],
        configuration: _callerConfiguration,
        records: Directory('${_probe.path}/records-no-root'),
      );

      expect(ran.exitCode, 0, reason: 'the run did not finish:\n${ran.stdout}${ran.stderr}');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('THE INNOCENT NEIGHBOUR: an installation holding a password is not refused', () async {
      // The option says only that the CALLER hands none over. Where the machine keeps one in a file
      // the run holds a password, every command can still be raised to root, and there is nothing
      // for a row's policy to walk past — so the same program is admitted, and the run says which
      // of the two states it is in rather than leaving the option looking like it did something.
      final ProcessResult ran = await _ansiwise(
        <String>['probe-continue', '--mode', 'run', '--without-elevation-password'],
        configuration: _fileConfiguration,
        records: Directory('${_probe.path}/records-from-file'),
      );

      expect(
        ran.exitCode,
        isNot(78),
        reason:
            'a run that can reach root was refused for a promise it does not have to keep:\n'
            '${ran.stdout}${ran.stderr}',
      );
      expect(
        ran.stdout,
        contains('can still be raised to root'),
        reason: 'the option changed nothing here and the run did not say so',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('THE INNOCENT NEIGHBOUR: without the option the refusal stands where it was', () async {
      final ProcessResult refused = await _ansiwise(
        <String>['probe-continue', '--mode', 'run'],
        configuration: _callerConfiguration,
        records: Directory('${_probe.path}/records-unsaid'),
      );

      expect(refused.exitCode, 78);
      expect(
        refused.stderr,
        contains('raises a command to root'),
        reason: 'something other than the elevation refusal answered 78',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

/// A step whose work is one command that has to run as root, and nothing else.
///
/// The command is never started: the shell reads the elevation password before it starts a process,
/// and a run holding none is refused there. That is what makes this probe the same on every machine
/// and what keeps it from touching anything.
final class _NeedsRoot extends IrreversibleStep {
  const _NeedsRoot();

  static const List<String> argv = <String>['id', '-u'];

  @override
  String get irreversibleReason => 'this probe never runs its command, so nothing takes one back';

  @override
  Future<CheckResult> check(StepContext context) async => const CheckResult.ready();

  @override
  Future<StepPlan> plan(StepContext context) async => const StepPlan.argv(argv);

  @override
  Future<void> apply(StepContext context) async {
    await context.shell.run(
      Command.detailed(argv.first, arguments: argv.sublist(1), elevated: true),
    );
  }
}

/// A run of two rows that both need root, under [policy], against a machine no password reaches.
///
/// The real shell and the real runner, so what this measures is what a machine does rather than what
/// a fake was told to answer.
Future<RunRecord> _premiseRun(OnFailure policy) async {
  final Registry registry = registryOf(
    steps: <String, (String, Step Function(Arguments))>{
      'needs_root': ('test/checks/elevation_without_password_test.dart', (_) => const _NeedsRoot()),
    },
  );
  final ResolvedProgram resolved = ProgramResolver(registry).resolve(
    programOf('premise', <(String, OnFailure, List<String>)>[
      ('needs_root', policy, const <String>[]),
      ('needs_root', policy, const <String>[]),
    ]),
  );
  final MemoryRecorder recorder = MemoryRecorder(const RealClock());
  final Machine machine = Machine(
    shell: const RealShell(elevation: Elevation.unconfigured()),
    files: const RealFiles(),
    http: const RealHttp(),
    clock: const RealClock(),
    entropy: RealEntropy(),
  );
  return Runner(machine: machine, recorder: recorder, redactor: Redactor(const <String>[])).run(
    program: resolved,
    mode: Mode.run,
    header: RunRecord(
      id: const RunId('premise'),
      program: const ProgramName('premise'),
      mode: Mode.run,
      argv: const <String>[],
      start: const RealClock().now(),
      stage: const Stage('dev'),
      role: const Role('master'),
      fqdn: const Fqdn(''),
      commit: '',
      fingerprint: 'premise',
    ),
  );
}

/// Starts the deployment binary against the probe installation and collects what it said.
Future<ProcessResult> _ansiwise(
  List<String> arguments, {
  required String configuration,
  required Directory records,
}) async {
  final Process child = await Process.start('dart', <String>[
    'run',
    'bin/ansiwise.dart',
    ...arguments,
    '--config',
    configuration,
    '--programs',
    '${_probe.path}/programs',
    '--runs',
    records.path,
    '--answers',
    '-',
  ], workingDirectory: Directory.current.path);
  child.stdin.write(
    jsonEncode(<String, Object?>{
      'answers': <String, Object?>{'storage_subdirectory': '${_probe.path}/under-root'},
    }),
  );
  await child.stdin.close();
  // Both streams are drained at once. Waiting for one to end before reading the other leaves the
  // second pipe unread, and a child that fills its buffer blocks on its next write for ever.
  final Future<String> out = utf8.decodeStream(child.stdout);
  final Future<String> err = utf8.decodeStream(child.stderr);
  return ProcessResult(child.pid, await child.exitCode, await out, await err);
}

/// The installation this check plants, built once and used by every case that starts the binary.
///
/// **PLANTED RATHER THAN BORROWED FROM THE CUSTOMER'S CATALOGUE.** What is measured here is a pair
/// of shapes — a program whose rows carry the run past their own failure, and one whose rows do not
/// — and a check reading a real catalogue measures whichever shapes that catalogue happens to hold
/// today. It would go quiet the day somebody changed one row, without anything saying so.
final Directory _probe = _plant();

/// The configuration that takes the elevation password from whoever starts the run.
String get _callerConfiguration => '${_probe.path}/from-caller.yaml';

/// The configuration that reads it from a file on the machine.
String get _fileConfiguration => '${_probe.path}/from-file.yaml';

Directory _plant() {
  final Directory root = Directory.systemTemp.createTempSync('ansiwise-elevation-probe');
  Directory('${root.path}/programs').createSync();
  Directory('${root.path}/under-root').createSync();

  File('${root.path}/from-caller.yaml').writeAsStringSync(
    'log_level: info\n'
    'plugins:\n'
    '  - ansiwise-host\n'
    // The gate is what makes a real run wait for a clean dry run of the same input. Off here
    // because what this check measures stands before the gate, and a run stopped by it would prove
    // nothing about the refusal in front of it.
    'gate:\n'
    '  dry: false\n'
    'elevation:\n'
    '  password_from_caller: true\n',
  );
  File('${root.path}/password.txt').writeAsStringSync('this probe never starts a process\n');
  File('${root.path}/from-file.yaml').writeAsStringSync(
    'log_level: info\n'
    'plugins:\n'
    '  - ansiwise-host\n'
    'gate:\n'
    '  dry: false\n'
    'elevation:\n'
    '  password_file: ${root.path}/password.txt\n',
  );

  // create_storage_directory is what a row that needs root is planted with: told `elevated: true`
  // it reads the path as root, so the run meets the elevation refusal in the step's own check on
  // every machine, without a tool having to exist there.
  File('${root.path}/programs/probe-continue.yaml').writeAsStringSync(
    _programSaying(name: 'probe-continue', elevated: true, onFailure: 'continue'),
  );
  File(
    '${root.path}/programs/probe-exit.yaml',
  ).writeAsStringSync(_programSaying(name: 'probe-exit', elevated: true, onFailure: 'exit'));
  File(
    '${root.path}/programs/probe-no-root.yaml',
  ).writeAsStringSync(_programSaying(name: 'probe-no-root', elevated: false, onFailure: 'exit'));
  return root;
}

/// A program of two rows reading one path, [elevated] or not, each under [onFailure].
String _programSaying({required String name, required bool elevated, required String onFailure}) =>
    'name: $name\n'
    'roles: [master]\n'
    'steps:\n'
    '  - step: create_storage_directory\n'
    '    elevated: $elevated\n'
    '    on_failure: $onFailure\n'
    '  - step: create_storage_directory\n'
    '    elevated: $elevated\n'
    '    on_failure: $onFailure\n'
    'answers:\n'
    '  - name: storage_subdirectory\n'
    '    kind: text\n'
    '    describes: >-\n'
    '      Where this probe reads. It is a directory that is already there, so a row that reads it '
    'without root finds it and has nothing to do.\n';
