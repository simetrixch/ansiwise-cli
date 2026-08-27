/// What both executables of this repository stand up before either of them does its own work.
///
/// **WHY IT IS HERE AND NOT IN AN ENTRY POINT.** This tree produces two programs — the one that
/// executes a config flow and the one that serves REST — and the machinery in front of both is the
/// same: read the configuration, activate the plugins the installation names, settle where the
/// password that raises a command to root comes from, build the machine those steps act through,
/// load the catalogue, and open the record directory. Written into one entry point and copied into
/// the other, the two would drift, and the first thing to drift would be which plugins are active —
/// which is the one difference a machine cannot see from the outside.
///
/// **IT ENDS THE PROCESS ON A REFUSAL, and that is deliberate rather than overlooked.** Everything
/// below is the composition root's own work, reached before either program has started doing
/// anything, and every refusal here is an operator's to fix: a configuration that is not there, a
/// plugin name nothing carries, a password file that cannot be read, a directory holding no
/// programs. Each states what is wrong and leaves through the exit code that says which kind of
/// wrong it was, exactly as it did when this stood inside one entry point. A caller that wanted to
/// carry on would be a caller with nothing to carry on with.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:ansiwise_core/ansiwise_core.dart';

import 'release_stamp.dart';

/// The one option every program of this repository reads, because each of them needs the
/// configuration that says which plugins are active.
const String configurationOption = 'config';

/// Where the program files stand.
const String programsOption = 'programs';

/// Where run records are kept.
const String runsOption = 'runs';

/// Where the envelope a run is told with is read from.
const String answersOption = 'answers';

/// The options that put a detached run where THIS process stands, as the words they arrived as.
///
/// THREE AND NOT ALL OF THEM. What a child must be told is what it cannot work out for itself and
/// would otherwise DEFAULT: where the programs are, which file names the active plugins, and where
/// records are kept. Everything else on this command line is either about serving — an address, a
/// token file — or about one run, and one run is told over its own envelope.
///
/// A value this process was NOT given is not passed on. Handing the default down explicitly would
/// read as a decision somebody made, and it would freeze a default that is the child's to resolve.
List<String> placementFrom(ArgResults options) => <String>[
  for (final String name in <String>[programsOption, configurationOption, runsOption])
    if (options.wasParsed(name))
      if (options.option(name) case final String value) ...<String>['--$name', value],
];

/// The quietest level a run writes.
const String logLevelOption = 'log-level';

/// The flag that makes a binary say which release it is.
///
/// **IT IS THE ONLY WAY TO ASK A PLACED BINARY WHAT IT IS.** A machine carries the executables and
/// nothing else — no checkout, no manifest — so anything holding one against a pin has to ask it.
/// `install_pinned_tool`, the step that keeps a tool at the version a program pins, decides its
/// skip on exactly this answer and refuses a tool it cannot ask.
const String versionFlag = 'version';

/// An installation, opened: its configuration read, its plugins active, and the machine its steps
/// act through built in front of it.
final class Installation {
  /// Holds what [openInstallation] composed.
  const Installation({
    required this.machine,
    required this.registry,
    required this.catalogue,
    required this.store,
    required this.directory,
    required this.elevation,
    required this.elevationSource,
    required this.inputs,
    required this.logLevel,
    required this.requireDryRun,
    required this.unwindDisabledBy,
  });

  /// The four ports every step acts through.
  final Machine machine;

  /// The steps and conditions this installation turned on, composed out of the active plugins.
  ///
  /// The catalogue below was already resolved against it. It is kept beside the catalogue because a
  /// run measures its answer conditions against the registry before it checks the answers, which is
  /// a question about what EXISTS rather than about what one program says.
  final Registry registry;

  /// The programs of this installation, each resolved against the active registry.
  final Catalogue catalogue;

  /// Where run records are written and read.
  final FileRunStore store;

  /// The directory [store] keeps them in, for whatever needs the path rather than the store.
  final RunDirectory directory;

  /// The password that raises a command to root, or unconfigured where this installation needs none.
  final Elevation elevation;

  /// WHICH route the configuration named, kept beside the password itself.
  ///
  /// The two are not one question: a run may hold no password because none was handed over, and the
  /// route is what says whether anything was ever going to arrive.
  ///
  /// What neither of them says is whether this run NEEDS root. That is a property of the steps it
  /// holds, and nothing on this side of the engine carries it — elevation is chosen per call, inside
  /// a step, while it runs.
  final ElevationSource? elevationSource;

  /// What the caller supplied for this run.
  final CallerInputs inputs;

  /// The quietest level this run writes, after the command line has had its say over the file.
  final LogLevel logLevel;

  /// Whether a real run still needs a clean dry run behind it.
  final bool requireDryRun;

  /// WHAT turned the unwind off, or null where it is on.
  ///
  /// The surface the decision came from and not merely the fact of it: a message about a
  /// command-line option, sent to an operator who set a key in a file, sends them to the wrong place.
  final String? unwindDisabledBy;
}

/// Answers [versionFlag] on [out] where it was given, and says whether it was.
///
/// ONE LINE AND NOTHING ELSE ON IT. Whatever asks reads the first line and takes the version out of
/// it, so a banner, a build date or a commit beside the value is a second thing that reader has to
/// be taught to skip. A binary built without a tag answers `unreleased`, which is deliberately not
/// shaped like a version: it must not be mistakable for a released one by anything comparing.
///
/// It is answered BEFORE a program name is looked for, because asking a binary what it is is not a
/// run and must work on a machine carrying no programs at all.
bool answeredVersion(ArgResults options, StringSink out) {
  if (!options.flag(versionFlag)) {
    return false;
  }
  out.writeln(releaseStamp);
  return true;
}

/// Adds the options every program of this repository reads to [parser].
///
/// Stated once so the two entry points cannot describe one option differently — a help text that
/// disagrees with the other binary's is a help text an operator has to test to trust.
void addSharedOptions(ArgParser parser) {
  parser
    ..addFlag(
      versionFlag,
      negatable: false,
      help: 'the release this binary was built at, and nothing else, on one line',
    )
    ..addOption(programsOption, defaultsTo: 'programs', help: 'where the program files are')
    ..addOption(
      configurationOption,
      defaultsTo: Configuration.defaultFileName,
      help: 'the file naming which plugins are active',
    )
    ..addOption(runsOption, defaultsTo: RunDirectory.defaultRoot, help: 'where records are kept')
    ..addOption(
      answersOption,
      help:
          'where this run is told what it needs: {"answers": {...}} and, where the configuration '
          'says the caller hands it over, "elevation_password" beside it — the same envelope '
          'POST /runs takes. A path, because a credential must not appear in a process listing. '
          '"-" reads it from standard input, which is how a run started over the API is told, '
          'since a file of raw answers would be the one thing beside a redacted record that is '
          'not redacted',
    )
    ..addOption(
      logLevelOption,
      allowed: <String>['debug', 'info', 'warn', 'error'],
      help:
          'the quietest level this run writes; overrides log_level in the configuration, which is '
          'where it normally stands so that handing this binary its config file is enough',
    );
}

/// Reads the configuration [options] names, activates [plugins], and builds everything in front of
/// a program.
///
/// [unwindDisabledBy] is what the caller's own flag would say when it turned the unwind off, or
/// null where it did not — the configuration can turn it off as well, and then the answer comes
/// from there instead.
Future<Installation> openInstallation({
  required ArgResults options,
  required PluginSet plugins,
  String? unwindDisabledBy,
}) async {
  // The file system is built first and on its own, because the configuration has to be read before
  // the rest of the machine can be built: what a command that has to run as root is elevated with
  // stands in that file, and a shell built before it was read would be a shell reaching for a path
  // nobody chose.
  const RealFiles files = RealFiles();

  final String configuration = options.option(configurationOption) ?? Configuration.defaultFileName;
  final Registry registry;
  Elevation elevation = const Elevation.unconfigured();
  CallerInputs inputs = const CallerInputs.none();
  ElevationSource? elevationSource;
  LogLevel logLevel = LogLevel.info;
  bool requireDryRun = true;
  String? unwoundBy = unwindDisabledBy;
  try {
    if (!await files.exists(configuration)) {
      throw PluginRejected(
        'there is no $configuration, so nothing says which plugins are active\n'
        'write one naming at least one of: ${plugins.names.join(', ')}',
      );
    }
    final Configuration active = await Configuration.load(files: files, path: configuration);
    // Two surfaces, composed in the order they depend on each other. Activating decides which steps
    // and which conditions EXIST at all; binding then points the generic conditions at the facts of
    // this installation and gives each the name a program row writes. A condition bound before its
    // plugin was activated would be bound to nothing.
    registry = bindConditions(
      registry: plugins.activate(active.plugins),
      named: active.conditions,
      where: configuration,
    );
    logLevel = active.logLevel;
    requireDryRun = active.requireDryRun;
    if (!active.allowUnwind) {
      unwoundBy = 'no_unwind: true in $configuration';
    }
    // Read at start-up and not at the first command that needs root. An installation whose password
    // FILE is missing learns it before anything has been looked at, rather than halfway through a
    // run that has already changed the machine.
    //
    // **THE CALLER'S ROUTE IS RESOLVED HERE AND REFUSED ELSEWHERE, and that is not a lapse.** Both
    // doors of the REST surface come through this same composition, and neither holds a password,
    // because neither executes a step — each starts a detached child per run, and the child is
    // handed its own password with its own answers. A refusal here would mean the surface cannot
    // start on the very installations that chose this route. What refuses a run with no password is
    // the run path, where a step is about to be taken.
    inputs = await callerInputsIn(files, options.option(answersOption));
    elevationSource = active.elevation;
    elevation = switch (active.elevation) {
      null => const Elevation.unconfigured(),
      ElevationFromFile(:final String path) => await Elevation.read(files: files, path: path),
      ElevationFromCaller() => switch (inputs.elevationPassword) {
        final String password => Elevation.of(password, from: 'the caller'),
        null => const Elevation.unconfigured(),
      },
    };
    if (inputs.elevationPassword != null && active.elevation is! ElevationFromCaller) {
      // A password handed to a run that will not use it is a credential somebody believes is in
      // effect. Refused rather than dropped, for the same reason a silently ignored key is.
      throw ElevationUnavailable(
        'an "elevation_password" was handed to this run, and $configuration does not say the '
        'caller is where the password comes from\n'
        'say "elevation: {password_from_caller: true}" there, or stop sending it',
      );
    }
  } on FormatException catch (unreadable) {
    stderr.writeln('--$answersOption: ${unreadable.message}');
    exit(65);
  } on PluginRejected catch (refused) {
    stderr.writeln(refused.message);
    exit(78);
  } on ElevationUnavailable catch (refused) {
    // Its own exit, and its own sentence. The operator has to be sent to the password file rather
    // than to the configuration that names it, and both are configuration problems.
    stderr.writeln(refused.message);
    exit(78);
  }

  // Not const: the entropy port holds the platform's cryptographic generator, which is created
  // once and cannot be built at compile time.
  // The file system a STEP is given can act as root; the one that read the configuration above
  // cannot, and did not need to. They are two instances of one class rather than one shared, because
  // what the second may do is decided by something the first had to be built before knowing.
  final RealShell shell = RealShell(elevation: elevation);
  final Machine machine = Machine(
    shell: shell,
    files: RealFiles(asRoot: shell),
    http: const RealHttp(),
    clock: const RealClock(),
    entropy: RealEntropy(),
  );

  if (options.option(logLevelOption) case final String asked) {
    logLevel = LogLevel.values.firstWhere((LogLevel each) => each.name == asked);
  }

  final String programs = options.option(programsOption) ?? 'programs';
  if (!await machine.files.exists(programs)) {
    // Named rather than thrown. This is what an operator meets when they run the binary from
    // somewhere other than the installation it belongs to, and a stack trace tells them nothing
    // about which of the two is wrong.
    stderr.writeln('there are no programs at "$programs"');
    stderr.writeln('run this where the installation is, or say --$programsOption <directory>');
    exit(66);
  }

  final Catalogue catalogue;
  try {
    catalogue = await LoadedCatalogue.load(
      files: machine.files,
      directory: programs,
      registry: registry,
    );
  } on ProgramInvalid catch (invalid) {
    // The first gate, before anything is looked at or touched. Every problem at once, so an
    // operator fixing a program file learns everything in one run.
    stderr.writeln(invalid.toString());
    exit(65);
  }

  final RunDirectory directory = RunDirectory(
    options.option(runsOption) ?? RunDirectory.defaultRoot,
  );

  return Installation(
    machine: machine,
    registry: registry,
    catalogue: catalogue,
    store: FileRunStore(directory: directory),
    directory: directory,
    elevation: elevation,
    elevationSource: elevationSource,
    inputs: inputs,
    logLevel: logLevel,
    requireDryRun: requireDryRun,
    unwindDisabledBy: unwoundBy,
  );
}

/// What the file at [path] says the caller supplied, or nothing when no file was named.
///
/// A PATH and not the values themselves. A credential handed on the command line stands in the
/// process listing for every account on the machine, and `Command` has no standard input by design —
/// so the one thing that crosses argv here is where to read, never what was read.
///
/// **The shape is an envelope, and it is the same one `POST /runs` takes.** The answers stand under
/// `answers`, and `elevation_password` beside them carries what raises a command to root where the
/// configuration says the caller hands it over. Two doors into one engine that disagreed about the
/// shape of a run's inputs would be two things to keep in step, and the client speaks the other one.
///
/// A bare object of answers is refused naming the envelope rather than read as one, because guessing
/// which of the two shapes arrived would misread a program that happens to declare an answer called
/// `answers`.
///
/// Throws [FormatException] when the payload is not that envelope, which is what the caller turns
/// into a refusal naming the file rather than a stack trace.
Future<CallerInputs> callerInputsIn(Files files, String? path) async {
  if (path == null || path.isEmpty) {
    return const CallerInputs.none();
  }

  final String text;
  if (path == '-') {
    // From standard input, which is how the launcher tells a detached run: not argv, where a
    // credential lands in every process listing, and not a file, which would be raw where the
    // record beside it is redacted — and would outlive the run unless somebody remembered it.
    //
    // Read here in the composition root rather than through the files port, because standard input
    // is not a file and there is nothing for that port to be asked about.
    text = await stdin.transform(utf8.decoder).join();
    if (text.trim().isEmpty) {
      throw const FormatException('--answers - was given and standard input was empty');
    }
  } else {
    if (!await files.exists(path)) {
      throw FormatException('there is no file at "$path"');
    }
    text = await files.read(path);
  }

  final String where = path == '-' ? 'standard input' : '"$path"';
  final Object? parsed = jsonDecode(text);

  // THE ONE READER, in the framework. The other door into this engine reads the same envelope with
  // the same call, which is what stops the two from learning things separately — three defects in
  // one day came out of each of them describing the shape itself.
  //
  // WHAT THIS DOOR ADDS is the one judgement only it can make: here the payload is WHOLLY the
  // envelope, so anything standing beside it is the older bare shape and is refused by name. The
  // API's body cannot say that — it carries the program and the mode there too.
  if (parsed is Map<String, Object?>) {
    final List<String> strangers = <String>[
      for (final String key in parsed.keys)
        if (key != CallerInputs.answersField && key != CallerInputs.elevationPasswordField) key,
    ];
    if (strangers.isNotEmpty) {
      throw FormatException(
        '$where carries ${strangers.map((String each) => '"$each"').join(', ')} beside the envelope, '
        'and a run is told by {"answers": {...}} with "elevation_password" next to it\n'
        'the answers go INSIDE "answers" — a bare map of them was the older shape and is not read as '
        'one any more, because guessing between the two would misread a program that declares an '
        'answer called "answers"',
      );
    }
  }

  try {
    return CallerInputs.of(parsed, where: where);
  } on InputsRejected catch (refused) {
    throw FormatException(refused.message);
  }
}

/// An identifier no other run of this installation carries, for a run nobody named one for.
///
/// Both programs mint one — the command line for a run somebody typed, the surface for a run a
/// caller asked for — and one of them minting it differently would put two runs in one record.
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

/// Why nothing here can raise a command to root, or null where something can.
///
/// One wording for both callers. An installation that named the caller's route and was handed
/// nothing is the same state whether a run or an installation of the service met it, and two
/// wordings of it are two things to keep in step.
///
/// **IT ANSWERS WHETHER ROOT IS REACHABLE, NEVER WHETHER IT IS NEEDED**, and the two callers differ
/// in exactly that. `install-service` knows it needs root — every file it places belongs to root —
/// so this answer is its refusal on its own. A RUN does not know: elevation is chosen per call
/// inside a step, and neither the registry entry nor the row says it, so a run treats this as need
/// unless whoever started it says the silence was meant.
String? elevationRefusal(ElevationSource? source, Elevation elevation) {
  if (source is! ElevationFromCaller || elevation.password != null) {
    return null;
  }
  return 'this installation says the caller hands over the password that raises a command to root, '
      'and none arrived\n'
      'put it beside the answers as "${CallerInputs.elevationPasswordField}", or name a '
      'password_file in the configuration where this machine is to hold one';
}
