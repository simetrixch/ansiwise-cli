import 'dart:convert';
import 'dart:io';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:test/test.dart';

import 'launcher_child.dart' show composedArgvFileName;

/// launcher-options — every option the launcher composes for a run is one this binary declares, and
/// the one that carries a waiver reaches the header.
///
/// **THE DEFECT THIS EXISTS FOR SHIPPED.** `DetachedLauncher` writes `--waived <mode>` into the argv
/// of every child it starts, once per gate an installation waived, and the command line declared no
/// such option. A run started that way reaches a parser that does not know the flag it was handed
/// and exits as usage — on a machine, detached, with nobody holding the session that asked for it,
/// and with the reason two repositories away. Nothing in either repository could notice it: the
/// composing and the parsing meet in no process but a run.
///
/// **So the launcher is really run.** It composes the child's command line inside its own call to
/// `Process.start` and hands back nothing but a run identifier, so what it started is a program that
/// writes down what it was handed — `launcher_child.dart`, named as the program because the first
/// word the launcher composes is the program. Every option it composed is then given to the real
/// binary, word for word. It gets as far as the configuration it names and stops there, which is
/// exactly far enough to say every option was understood.
///
/// **And the waiver is followed to where a reader looks for it.** An absent proof and a waived one
/// look identical from the outside, so a declared option that parsed and went nowhere would leave
/// the same record the missing declaration did. A run of an installation whose gate is waived is
/// started through the real binary and its header is read off the disk.
Future<void> main() async {
  // The child, under the name the launcher is told the program is called. A `.dart` file, because
  // the executable the launcher is given is the Dart toolchain — the options it composes are the
  // same whatever it starts.
  const String childName = 'launcher-child.dart';

  /// The options the real launcher composes for a run it is told everything about.
  ///
  /// Everything, so no option it can compose is left out of what is judged: an identifier for the
  /// run, a run it continues, a waived gate, and inputs that have to travel over standard input.
  ///
  /// The first word the launcher composes is the PROGRAM, and it is not among these: the executable
  /// the launcher is given is the Dart toolchain, which reads that word as the file it runs and
  /// hands the child everything after it. What the child was handed is what this returns, and the
  /// program word is put back below by whoever needs the entry to reach past its own usage line.
  Future<List<String>> composedOptions() async {
    final Directory held = Directory.systemTemp.createTempSync('ansiwise-launcher-options');
    // TAKEN BACK ONLY ONCE THE CHILD HAS GONE. This directory is what the child was started IN, and
    // an operating system that will not delete a directory a running process stands in refuses the
    // first attempt — the child writes its file as the last thing it does and is still on its way
    // out. Waited for rather than passed over, so a directory something really kept is still
    // reported.
    addTearDown(() async {
      for (int attempt = 0; ; attempt++) {
        try {
          held.deleteSync(recursive: true);
          return;
        } on FileSystemException {
          if (attempt == 50) {
            rethrow;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
    File('test/checks/launcher_child.dart').copySync('${held.path}/$childName');

    await DetachedLauncher(
      executable: Platform.resolvedExecutable,
      workingDirectory: held.path,
      newRunId: () => const RunId('the-run-the-launcher-named'),
    ).start(
      program: const ProgramName(childName),
      mode: Mode.run,
      answers: const <String, Object?>{'an_answer': 'a value'},
      elevationPassword: 'not-a-real-password',
      resumes: const RunId('the-run-this-one-continues'),
      waived: const <Mode>[Mode.dry],
    );

    // Waited for rather than awaited: a detached child is nobody's to wait on, which is the whole
    // point of starting it that way, so the only thing that says it ran is what it left behind.
    final File composed = File('${held.path}/$composedArgvFileName');
    for (int waited = 0; waited < 600 && !composed.existsSync(); waited++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!composed.existsSync()) {
      fail('the launcher started a child that never wrote what it was handed');
    }
    return <String>[
      for (final Object? word in jsonDecode(composed.readAsStringSync()) as List<Object?>)
        word! as String,
    ];
  }

  /// The real binary, run with [arguments] and told nothing over standard input.
  Future<ProcessResult> ansiwise(List<String> arguments) async {
    final Process child = await Process.start('dart', <String>[
      'run',
      'bin/ansiwise.dart',
      ...arguments,
    ], workingDirectory: Directory.current.path);
    await child.stdin.close();
    // BOTH STREAMS ARE DRAINED AT ONCE. A process whose output fills a pipe buffer blocks on its
    // next write until somebody reads, and the refusal probed here is the one that prints the whole
    // usage — which is what fills it.
    final Future<String> said = utf8.decodeStream(child.stdout);
    final Future<String> complained = utf8.decodeStream(child.stderr);
    return ProcessResult(child.pid, await child.exitCode, await said, await complained);
  }

  /// The command the launcher composes, as the entry of this binary receives one: the program it
  /// names and then every option it composed for it.
  Future<List<String>> composedCommand() async => <String>[childName, ...await composedOptions()];

  group('the argv the launcher composes', () {
    test('names the gate the run is going without', () async {
      expect(
        await composedOptions(),
        containsAllInOrder(<String>['--waived', Mode.dry.flag]),
        reason:
            'a launcher that stopped composing this would leave the case below that judges every '
            'composed option judging an argv the option is not in, and it would stay green over a '
            'command line nobody waived anything on; the two header cases pass --waived literally '
            'and would not notice either',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('every option in it is one this binary declares', () async {
      final ProcessResult answered = await ansiwise(await composedCommand());

      expect(
        answered.exitCode,
        isNot(64),
        reason:
            'the binary refused the command the launcher composed for it, as usage:\n'
            '${answered.stderr}',
      );
      expect(
        answered.stderr,
        contains('nothing says which plugins are active'),
        reason:
            'the command was understood and the process stopped at the configuration it names, '
            'which is what says the options were read rather than that it died earlier',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('THE PLANTED DEFECT: one option the binary does not declare turns it red', () async {
      // The shape of the defect itself, planted: a launcher composing an option no parser declares.
      // It is invisible until it runs, and the only place the two meet is a process.
      final ProcessResult answered = await ansiwise(<String>[
        for (final String word in await composedCommand())
          if (word == '--waived') '--waivered' else word,
      ]);

      expect(answered.exitCode, 64);
      expect(answered.stderr, contains('waivered'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('what the run does with the waiver it is handed', () {
    // An installation of its own, written here rather than found: what is judged is a run whose gate
    // was waived, and the installation this platform was built for runs with the gate on.
    late Directory held;
    late List<String> installation;

    setUp(() {
      held = Directory.systemTemp.createTempSync('ansiwise-launcher-waiver');
      Directory('${held.path}/programs').createSync();
      File('${held.path}/ansiwise.yaml').writeAsStringSync(
        'plugins:\n  - ansiwise-host\n'
        'gate:\n  dry: false\n',
      );
      File('${held.path}/programs/waiver-probe.yaml').writeAsStringSync(
        'name: waiver-probe\n'
        'roles: [master]\n'
        'steps:\n'
        '  - step: require_commands\n'
        '    on_failure: exit\n'
        '    commands: [dart]\n',
      );
      installation = <String>[
        '--programs',
        '${held.path}/programs',
        '--config',
        '${held.path}/ansiwise.yaml',
        '--runs',
        '${held.path}/runs',
      ];
    });

    tearDown(() => held.deleteSync(recursive: true));

    /// What the header of run [id] says it went without, read off the disk.
    List<Object?> waivedIn(String id) {
      final File header = File('${held.path}/runs/$id/run.json');
      if (!header.existsSync()) {
        fail('the run left no header at ${header.path}');
      }
      return (jsonDecode(header.readAsStringSync()) as Map<String, Object?>)['waived']!
          as List<Object?>;
    }

    test('the header states it, where a reader looks for it', () async {
      final ProcessResult answered = await ansiwise(<String>[
        'waiver-probe',
        '--mode',
        Mode.run.flag,
        '--run',
        'the-waived-run',
        '--waived',
        Mode.dry.flag,
        ...installation,
      ]);

      expect(answered.exitCode, 0, reason: 'stderr:\n${answered.stderr}');
      expect(
        waivedIn('the-waived-run'),
        <String>[Mode.dry.name],
        reason:
            'the run was told which proof it is going without and its record does not say so — a '
            'reader cannot tell it from a run that was gated normally',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('THE INNOCENT NEIGHBOUR: a run told nothing states nothing', () async {
      // Every case above proves nothing if the list were filled by something other than the option:
      // this run stands on the same installation and is told no waiver.
      final ProcessResult answered = await ansiwise(<String>[
        'waiver-probe',
        '--mode',
        Mode.test.flag,
        '--run',
        'the-gated-run',
        ...installation,
      ]);

      expect(answered.exitCode, 0, reason: 'stderr:\n${answered.stderr}');
      expect(waivedIn('the-gated-run'), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
