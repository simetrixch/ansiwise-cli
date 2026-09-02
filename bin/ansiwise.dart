// The composition root, and the only place that decides what the real implementations are.
//
// `dart:io` is used here for the process's own arguments, its exit code and its standard streams,
// and for nothing else. Everything this does to a machine goes through the same four ports every
// step uses, built once here and handed down.
import 'dart:io';

import 'package:args/args.dart';
import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_cli/installation.dart';
import 'package:ansiwise_cli/plugins.dart';

Future<void> main(List<String> argv) async {
  final ArgParser parser = ArgParser();
  addSharedOptions(parser);
  parser
    ..addOption(
      'mode',
      allowed: <String>['test', 'dry', 'run'],
      help: 'test measures the machine, dry says what would change, run does it',
    )
    ..addOption('run', help: 'the identifier of this run, when something else chose it')
    ..addOption('resume', help: 'the identifier of a run this one continues')
    ..addMultiOption(
      'waived',
      allowed: <String>[for (final Mode mode in Mode.values) mode.flag],
      help:
          'a proof this run is going without, named by the mode that would have produced it, once '
          'per waiver. Typed here it is the operator\'s own declaration: this command line writes '
          'what it is given into the run\'s header and does not ask the gate whether that is what '
          'it waived. Composed rather than typed when the run was started over the API, where the '
          'launcher writes one per gate that installation waived. An absent proof and a waived one '
          'look identical from the outside, and only one of them was somebody\'s choice',
    )
    ..addFlag(
      'no-unwind',
      help: 'disable unwinding steps on failure so evidence is preserved for debugging',
    )
    ..addFlag(
      'without-elevation-password',
      negatable: false,
      help:
          'this run hands over no password that raises a command to root, and that is meant. An '
          'installation whose configuration takes the password from the caller otherwise refuses '
          'every run that arrives without one, which is right for a run a person or the manager '
          'starts and impossible for one the machine starts after a reboot, where there is no '
          'caller to hand one over. It turns nothing off: the run holds no password, so a step '
          'that has to run as root is refused at its own command and the run stops there — and a '
          'program with a row that says "on_failure: continue" is refused before its first step, '
          'naming those rows, because such a row would carry the run past that refusal. On an '
          'installation whose password comes from a file it changes nothing at all, and the run '
          'says so',
    )
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults options;
  try {
    options = parser.parse(argv);
  } on FormatException catch (bad) {
    stderr.writeln(bad.message);
    stderr.writeln(parser.usage);
    exit(64);
  }

  // ANSWERED BEFORE A PROGRAM IS LOOKED FOR. Asking a binary what it is is not a run: it has to
  // work on a machine that carries the executables and nothing else, which is every machine before
  // its catalogue is placed.
  if (answeredVersion(options, stdout)) {
    return;
  }

  final List<String> rest = options.rest;
  if (options.flag('help') || rest.isEmpty) {
    stdout
      ..writeln('ansiwise <program> --mode test|dry|run [--$answersOption <file>]')
      ..writeln()
      // The other binary is named here because somebody looking for it types this one first. It is
      // a POINTER and not a second interface: what its programs are called and what they take is
      // stated where they live, and repeating any of it here would be a second help text to keep in
      // step with a binary this one does not carry.
      ..writeln('the REST service is its own binary: ansiwise-rest --help')
      ..writeln()
      ..writeln(parser.usage);
    exit(rest.isEmpty && !options.flag('help') ? 64 : 0);
  }

  // Every plugin this binary was compiled with. Dart ahead of time loads no code that was not
  // built in, so this list is a fact of the build — and the configuration decides which of them
  // are on, which is a fact of the installation. The serving binary carries the SAME list out of
  // the same generated file, so one machine's two programs cannot know different steps.
  const PluginSet plugins = compiledPlugins;

  final Installation installation = await openInstallation(
    options: options,
    plugins: plugins,
    // The option wins where both say it, because whoever typed it meant this run.
    unwindDisabledBy: options.flag('no-unwind') ? 'the --no-unwind option' : null,
  );

  exit(
    await _runProgram(
      machine: installation.machine,
      catalogue: installation.catalogue,
      store: installation.store,
      directory: installation.directory,
      options: options,
      argv: argv,
      program: ProgramName(rest.first),
      logLevel: installation.logLevel,
      inputs: installation.inputs,
      // Handed on so the password that raises a command to root is redacted like any other secret,
      // whichever route it came by, and so a run can refuse when the route named one and none came.
      elevation: installation.elevation,
      elevationSource: installation.elevationSource,
      // Whether the caller says the absence of a password is what it meant, rather than something
      // it forgot. Read here and not in the composition root because the serving binary shares that
      // root and carries no such option: `install-service` writes files that belong to root on
      // every installation there is, so nothing may excuse it a password.
      withoutElevationPassword: options.flag('without-elevation-password'),
      // Handed on so the answer conditions can be measured before the answers are checked.
      registry: installation.registry,
      requireDryRun: installation.requireDryRun,
      unwindDisabledBy: installation.unwindDisabledBy,
    ),
  );
}

Future<int> _runProgram({
  required bool requireDryRun,
  required Machine machine,
  required Catalogue catalogue,
  required FileRunStore store,
  required RunDirectory directory,
  required ArgResults options,
  required List<String> argv,
  required ProgramName program,
  required LogLevel logLevel,
  required CallerInputs inputs,
  required Elevation elevation,
  required ElevationSource? elevationSource,
  required bool withoutElevationPassword,
  required Registry registry,
  required String? unwindDisabledBy,
}) async {
  // The same refusal the composition used, rebuilt from the same two options: everything that can
  // still end this run BEFORE its first step goes through it, so a caller who cannot see standard
  // error is told why anyway.
  final StartupReason reason = startupReasonFrom(options);
  final ResolvedProgram? resolved = catalogue.byName(program);
  if (resolved == null) {
    reason.refuse(
      'no program is called "$program"\n'
      'there is: ${catalogue.programs.map((ResolvedProgram p) => p.declared.name).join(', ')}',
      65,
    );
  }

  // Where the caller's route is refused, and it is refused HERE because here is where a step is
  // about to be taken. The process entry cannot refuse it: `serve` comes through the same entry and
  // holds no password by design, since it executes nothing itself.
  //
  // A CALLER THAT SAYS SO IS NOT ASKED, and what that costs is asked of the program instead, three
  // refusals down.
  //
  // The question this refusal would like to ask is whether any step of THIS run raises a command to
  // root, and nothing here can answer it. Elevation is a property of the single call — the
  // `elevated` flag on a command and on every file operation — chosen inside a step while it runs.
  // What a resolved program carries is each step's registry entry and each row's arguments, and
  // neither states it: most steps fix it in their own code, so an answer read off the rows would
  // say "nothing here needs root" for a program full of steps that do. So the refusal asks the one
  // question it can answer — whether a password is here at all — and reads silence as need.
  //
  // Reading silence as need is right for a run a person or the manager starts, and impossible for
  // one the machine starts: a unit that runs a program after a reboot has no caller, and the other
  // route the configuration offers is a password in a file, which is the one credential this
  // platform stopped keeping at rest. So the caller says the silence is meant, and the run then
  // holds no password at all — what a step that has to run as root meets is the shell's own
  // refusal, raised before that command starts and naming it and both routes.
  if (withoutElevationPassword &&
      elevationSource is ElevationFromCaller &&
      elevation.password != null) {
    // Refused rather than resolved either way. The two say opposite things about the same run, and
    // a code that picked one would act on a decision nobody made.
    stderr.writeln(
      'this run was started with --without-elevation-password, and an '
      '"${CallerInputs.elevationPasswordField}" arrived beside the answers',
    );
    reason.refuse('drop the option, or stop sending the password', 78);
  }
  if (!withoutElevationPassword) {
    if (elevationRefusal(elevationSource, elevation) case final String refused) {
      reason.refuse(refused, 78);
    }
  }

  // WHAT DECLINING THE REFUSAL ABOVE COSTS, ASKED OF THE PROGRAM AND NOT ASSUMED. A run holding no
  // password meets the shell's own refusal at the first command that has to be raised to root, and
  // what happens to the run then is that row's `on_failure` and nothing else: the refusal is an
  // exception, a step turns every exception it catches into that row's verdict, and `continue` is
  // the program saying in advance that a failure of this row is to be walked past. So on a program
  // holding such a row the run-wide condition — this run holds NO password at all — is converted
  // into a per-row note, and the run carries on to the rows after it.
  //
  // Measured before this was written, on a program of two rows that both read a path belonging to
  // root, both saying `on_failure: continue`: started with the option, the run walked both, changed
  // nothing only because those two rows were the whole program, and closed `exit 2  2 proven`.
  //
  // A ROW'S POLICY IS ABOUT THAT ROW'S OWN FAILURE and was never meant to answer a question about
  // the whole run, so it is not made to. The run is refused here instead, where every row is known
  // and nothing has been touched — which is also where the operator can act on it.
  if (withoutElevationPassword && elevation.password == null) {
    final List<String> carryOn = _rowsCarryingTheRunPastTheirOwnFailure(resolved);
    if (carryOn.isNotEmpty) {
      stderr.writeln(
        'this run was started with --without-elevation-password, so it holds no password at all — '
        'and "$program" says the run carries on when these rows fail:',
      );
      reason.refuse(
        <String>[
          for (final String row in carryOn) '  $row',
          'a step that has to run as root is refused for want of that password, and '
              '"on_failure: continue" turns the refusal into an issue the run walks past, so this '
              'run would go on to the rows after it and change this machine',
          'send the password beside the answers, or run a program whose every row says '
              '"on_failure: exit"',
        ].join('\n'),
        78,
      );
    }
  }

  final Mode mode = _modeNamed(options.option('mode'));

  // Checked before the gate and before the first step: an installation stopped halfway for a value
  // somebody could have supplied at the start is the worst of both. The same call the API makes, so
  // the two doors cannot come to disagree about what a program needs.
  final Arguments answers;
  try {
    final Map<String, Object?> given = _withElevationPassword(inputs, resolved, elevationSource);

    // WHICH CONDITIONS HOLD, ASKED BEFORE THE ANSWERS ARE CHECKED. An answer stated only under a
    // condition is required exactly where that condition holds, so the question comes first — and it
    // is asked against the answers AS SUPPLIED, because the validation that would tidy them is the
    // thing waiting on this. Nothing is recorded: a program whose answers do not add up never
    // becomes a run.
    final Set<String> holding = await PredicateEvaluation.unrecorded(
      machine: machine,
      answers: Arguments(<String, Object>{
        for (final MapEntry<String, Object?> each in given.entries)
          if (each.value case final Object value) each.key: value,
      }),
    ).answerConditionsThatHold(resolved, registry);

    answers = resolved.declared.answers.validate(
      given,
      program: program.value,
      conditionsThatHold: holding,
    );
  } on ElevationUnavailable catch (refused) {
    // Its own exit, because it is a configuration problem and not an answer somebody mistyped: a
    // caller sending the password under the name the run fills itself, or a program declaring that
    // name on an installation whose password comes from a file.
    reason.refuse(refused.message, 78);
  } on ConditionUnanswerable catch (refused) {
    // Its own exit and its own sentence: the operator has to be sent to the condition that could not
    // be answered, not to the answer it was deciding about.
    reason.refuse(refused.because, 65);
  } on AnswersRejected catch (refused) {
    reason.refuse(refused.message, 65);
  } on FormatException catch (unreadable) {
    reason.refuse('--answers: ${unreadable.message}', 65);
  }

  final String commit = await commitOf(machine);
  final String fingerprint = fingerprintOf(program: resolved, commit: commit, answers: answers);

  // WHICH OF THE TWO STATES THE OPTION LEFT THIS RUN IN, said before its first step. The option
  // says only that no password is being handed over; whether root is reachable at all is the
  // installation's own answer, and on one that keeps a password in a file the option changes
  // nothing whatever. Both readings are written out, because an operator reading a failed boot has
  // to see which of them they are in, in front of the failure rather than after it — and the second
  // was silence until it was measured.
  if (withoutElevationPassword) {
    stdout.writeln(
      elevation.password == null
          ? 'this run holds no password that raises a command to root, and every row of $program '
                'ends the run when it fails: a step that has to run as root stops it at that command'
          : 'this run was started with --without-elevation-password, and this installation reads '
                'that password from a file: a command of this run can still be raised to root',
    );
  }

  // Said BEFORE the run, and by the one implementation. Every step declares whether it can be taken
  // back, so where a run stops being reversible is a fact this program can state rather than a
  // surprise the operator meets at the failure. Printed for a dry run as much as for a real one:
  // the dry run is where somebody decides, and a boundary they read afterwards is a boundary they
  // could not act on.
  if (pointOfNoReturnSaid(resolved) case final String boundary) {
    stdout.writeln(boundary);
  }

  try {
    await Gate(
      store,
      requireDryRun: requireDryRun,
    ).admit(mode: mode, program: program, fingerprint: fingerprint);
  } on GateNotMet catch (refusal) {
    reason.refuse(refusal.message, 69);
  }

  final String? chosen = options.option('run');
  final RunId id = chosen == null || chosen.isEmpty ? newRunId(machine) : RunId(chosen);

  // Resuming runs the same program again rather than skipping to a remembered position. Every step
  // that already did its work answers that there is nothing to do, and a machine somebody touched
  // in between is measured again instead of assumed. What the identifier is for is the record: it
  // joins the two halves of one story, which two unrelated runs would not.
  final String? continues = options.option('resume');
  RunId? resumes;
  if (continues != null && continues.isNotEmpty) {
    final RunRecord? earlier = await store.read(RunId(continues));
    if (earlier == null) {
      reason.refuse('there is no run called "$continues" to continue', 65);
    }
    if (earlier.fingerprint != fingerprint) {
      reason.refuse(
        'run "$continues" was a different input, so this would not be continuing it\n'
        'start a fresh run instead, or say why the input changed',
        65,
      );
    }
    resumes = earlier.id;
  }

  final RunRecord header = RunRecord(
    id: id,
    program: program,
    mode: mode,
    argv: argv,
    start: machine.clock.now(),
    stage: Stage(options.option(stageOption) ?? 'dev'),
    role: Role(options.option(roleOption) ?? 'master'),
    fqdn: Fqdn(options.option(fqdnOption) ?? ''),
    commit: commit,
    fingerprint: fingerprint,
    resumes: resumes,
    waived: _waivedIn(options),
  );

  // Built from the VALUES of everything declared secret, on BOTH surfaces a value arrives by.
  // Everything on its way into the record passes through here, which is what makes a record safe to
  // read and to paste into a message when something has gone wrong.
  //
  // An ANSWER is the surface an operator fills in. An ARGUMENT is the surface a program row writes,
  // and a step may declare one secret too - a token a row carries, a key a plugin needs. Built from
  // the answers alone, a secret argument's value would reach a world-readable record through the
  // command line a step composes and through the plan it prints, while ArgumentSpec.secret says the
  // value is never sent back out.
  final Redactor redactor = Redactor(<String>[
    // The password that raises a command to root, whichever route it came by. It is not an answer
    // and not an argument, so neither list below reaches it — and a step whose command echoes it,
    // or a shell that reports it in a failure, would otherwise put it in a world-readable record.
    if (elevation.password case final String password) password,
    for (final String name in resolved.declared.answers.secretNames)
      if (answers.optionalText(name) case final String value) value,
    for (final ResolvedStep step in resolved.steps)
      for (final ArgumentSpec spec in step.registered.arguments)
        if (spec.secret)
          if (step.entry.arguments.optionalText(spec.name) case final String value) value,
  ]);

  final FileRecorder recorder = await FileRecorder.open(
    id: id,
    directory: directory,
    clock: machine.clock,
    redactor: redactor,
  );

  // The header goes to disk before the first step. A run that is killed a minute later is then
  // still a run somebody can find and read — and without this, nothing would answer `GET /runs`
  // and the gate could never find the dry run it is looking for.
  await recorder.save(header);

  final RunRecord record = await Runner(
    machine: machine,
    recorder: recorder,
    redactor: redactor,
    logLevel: logLevel,
    unwindDisabledBy: unwindDisabledBy,
  ).run(program: resolved, mode: mode, header: header, answers: answers);
  await recorder.save(record);

  stdout.writeln(
    '${record.id}  ${record.program} ${record.mode.name}  exit ${record.exitCode}  ${record.standings.summary}',
  );
  for (final String issue in record.issues) {
    stdout.writeln('  issue: $issue');
  }
  return record.exitCode ?? 1;
}

/// The rows of [resolved] whose `on_failure` says the run carries on when they fail.
///
/// Named the way a plan and a refusal already name a row — the step, and its place counted from
/// one, because somebody reading the program file counts its first row as the first one.
List<String> _rowsCarryingTheRunPastTheirOwnFailure(ResolvedProgram resolved) => <String>[
  for (int at = 0; at < resolved.steps.length; at++)
    if (resolved.steps[at].entry.onFailure == OnFailure.continueRun)
      'step ${at + 1} ${resolved.steps[at].entry.step}',
];

/// The proofs the run was started without, as the command line names them.
///
/// Every value is one of [Mode.flag] — the parser refuses the rest — so a name that is not a mode
/// cannot reach here, and the lookup throws rather than falling back where one somehow did. The
/// fallback [_modeNamed] has is right for `--mode`, where the safe mode is the sensible answer to
/// silence; here it would turn a name nobody meant into a waiver the header states as a fact.
List<Mode> _waivedIn(ArgResults options) => <Mode>[
  for (final String flag in options.multiOption('waived'))
    Mode.values.firstWhere((Mode each) => each.flag == flag),
];

Mode _modeNamed(String? name) {
  for (final Mode mode in Mode.values) {
    if (mode.flag == name) {
      return mode;
    }
  }
  // No default that acts. A run started without saying which of the three it is would be a run
  // whose safety nobody chose, so the safe one is the only sensible answer.
  return Mode.test;
}

RunId newRunId(Machine machine) {
  final DateTime now = machine.clock.now();
  final String stamp = now.toIso8601String().replaceAll(RegExp(r'[-:.]'), '').split('T').join('T');
  // THE STAMP AND THE PROCESS ARE NOT ENOUGH, and it took a resident service to show it. A stamp
  // reaching seconds and the process id identify a run uniquely only while one process starts at
  // most one run per second — true of a person at a command line, false of a service a manager
  // drives: two runs asked for in the same second came back with ONE id and wrote over each other's
  // record. Four random bytes are what make the id the run's own rather than the second's.
  return RunId('${stamp.substring(0, 15)}Z-$pid-${machine.entropy.hex(4)}');
}

/// The commit this installation's branch is on, which is part of what makes an input the same.
///
/// Empty when this is not a checkout — a machine that was given a built binary and no repository
/// still runs, and its fingerprint simply carries no commit.
Future<String> commitOf(Machine machine) async {
  final CommandResult head = await machine.shell.run(
    const Command.observing('git', arguments: <String>['rev-parse', 'HEAD']),
  );
  return head.ok ? head.trimmed : '';
}

/// The answers of this run, with the caller's elevation password among them where the program asked
/// for it by name.
///
/// **ONE VALUE, ONE NAME, ONE PLACE ON THE WIRE.** A program that has to PERSIST the password — put
/// it in the platform's store so something else can raise a command to root later — needs to reach
/// it, and the value is already in this run: the caller sent it beside the answers. Making the
/// program declare a second answer for the same thing would put it on the wire twice, and two
/// spellings of one value drift apart exactly once and then quietly disagree for ever.
///
/// So a program that wants it declares an answer under [elevationPasswordAnswer], and it is filled
/// from what the caller already sent. Nothing else may fill it: an answer of that name arriving in
/// the envelope is refused, because a run whose password and whose stored password could differ is
/// the drift this exists to prevent.
///
/// A program declaring it while the configuration does not take the password from the caller is
/// refused too — the answer could never be filled, and a required answer nobody can give is a run
/// that refuses at its first gate for a reason nobody can act on.
Map<String, Object?> _withElevationPassword(
  CallerInputs inputs,
  ResolvedProgram resolved,
  ElevationSource? source,
) {
  final bool wanted = resolved.declared.answers.specs.any(
    (ArgumentSpec spec) => spec.name == CallerInputs.elevationPasswordField,
  );
  if (wanted && source is! ElevationFromCaller) {
    throw const ElevationUnavailable(
      'this program declares the answer "${CallerInputs.elevationPasswordField}", which is filled '
      'from the password the caller hands over — and this installation does not take it from the '
      'caller\n'
      'say "elevation: {password_from_caller: true}" in the configuration, or stop declaring it',
    );
  }
  return inputs.filledFor(resolved.declared.answers);
}

/// The one name a program writes when it wants the password this run was started with.
///
/// The same word the envelope uses, on purpose: a value that is called two things is a value two
/// people describe differently in the same conversation.
const String elevationPasswordAnswer = 'elevation_password';
