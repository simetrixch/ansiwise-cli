// The composition root, and the only place that decides what the real implementations are.
//
// `dart:io` is used here for the process's own arguments, its exit code and its standard streams,
// and for nothing else. Everything this does to a machine goes through the same four ports every
// step uses, built once here and handed down.
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_rest/ansiwise_rest.dart';
import 'package:ansiwise_cli/plugins.dart';
import 'package:ansiwise_cli/service_installation.dart';
import 'package:ansiwise_cli/service_unit.dart';

Future<void> main(List<String> argv) async {
  final ArgParser parser = ArgParser()
    ..addOption(
      'mode',
      allowed: <String>['test', 'dry', 'run'],
      help: 'test measures the machine, dry says what would change, run does it',
    )
    ..addOption('run', help: 'the identifier of this run, when something else chose it')
    ..addOption('resume', help: 'the identifier of a run this one continues')
    ..addOption('programs', defaultsTo: 'programs', help: 'where the program files are')
    ..addOption(
      'config',
      defaultsTo: Configuration.defaultFileName,
      help: 'the file naming which plugins are active',
    )
    ..addOption('runs', defaultsTo: RunDirectory.defaultRoot, help: 'where records are kept')
    ..addOption(
      'answers',
      help:
          'where this run is told what it needs: {"answers": {...}} and, where the configuration '
          'says the caller hands it over, "elevation_password" beside it — the same envelope '
          'POST /runs takes. A path, because a credential must not appear in a process listing. '
          '"-" reads it from standard input, which is how a run started over the API is told, '
          'since a file of raw answers would be the one thing beside a redacted record that is '
          'not redacted',
    )
    ..addOption(
      'log-level',
      allowed: <String>['debug', 'info', 'warn', 'error'],
      help:
          'the quietest level this run writes; overrides log_level in the configuration, which is '
          'where it normally stands so that handing this binary its config file is enough',
    )
    ..addOption(
      'listen',
      help:
          'serve on this address as a resident service instead of over the session\'s own stdio: '
          'host:port (127.0.0.1:9953, [::1]:9953) or unix:<path>. There is no default, because '
          'which addresses may reach the surface is the installation\'s decision, not this '
          'binary\'s. `install-service` is given the same address and writes it into the unit it '
          'places, where the accepted shapes are narrower — a service nobody can reach is worth '
          'less than a refusal',
    )
    ..addOption(
      'service-token-file',
      help:
          'the file holding the token every caller on --listen must present. Required with '
          '--listen and meaningless without it: a session is authenticated by sshd, an address by '
          'nothing until this says so. The PATH is here and the VALUE never is — a credential on a '
          'command line stands in every process listing on the machine. `install-service` is the '
          'one that puts the value there, and it is told it on standard input',
    )
    ..addOption('role', defaultsTo: 'master', help: 'what this machine is')
    ..addOption('stage', defaultsTo: 'dev')
    ..addOption('fqdn', defaultsTo: '', help: 'the domain name of this installation')
    ..addFlag(
      'no-unwind',
      help: 'disable unwinding steps on failure so evidence is preserved for debugging',
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

  final List<String> rest = options.rest;
  if (options.flag('help') || rest.isEmpty) {
    stdout
      ..writeln('ansiwise <program> --mode test|dry|run [--answers <file>]')
      ..writeln('ansiwise serve [--listen <address>]')
      ..writeln(
        'ansiwise install-service --listen <address> --service-token-file <path> --answers -',
      )
      ..writeln()
      ..writeln(parser.usage);
    exit(rest.isEmpty && !options.flag('help') ? 64 : 0);
  }

  // The file system is built first and on its own, because the configuration has to be read before
  // the rest of the machine can be built: what a command that has to run as root is elevated with
  // stands in that file, and a shell built before it was read would be a shell reaching for a path
  // nobody chose.
  const RealFiles files = RealFiles();

  // Every plugin this binary was compiled with. Dart ahead of time loads no code that was not
  // built in, so this list is a fact of the build — and the configuration below decides which of
  // them are on, which is a fact of the installation.
  const PluginSet plugins = compiledPlugins;

  final String configuration = options.option('config') ?? Configuration.defaultFileName;
  final Registry registry;
  // Where the password that raises a command to root comes from. Unconfigured unless the file names
  // it: there is no path to fall back to, and an installation whose steps never need root names
  // nothing and is complete without it.
  Elevation elevation = const Elevation.unconfigured();
  // What the caller supplied for this run, read once. It is read up here rather than beside the
  // answer validation because one of the two elevation routes is in it, and elevation is settled
  // before the shell that carries it exists.
  CallerInputs inputs = const CallerInputs.none();
  // WHICH route this installation named, kept beside the password itself. The two are not the same
  // question: a run may hold no password because none was handed over, and only the route says
  // whether that is a refusal or an installation whose steps never need root.
  ElevationSource? elevationSource;
  // The configuration decides it and the command line overrides it, which is the ordinary
  // precedence: the file is what this installation always wants, the flag is what this one run
  // wants. Declared here so a refusal below cannot leave it unset.
  LogLevel logLevel = LogLevel.info;
  // Whether a real run still needs a clean dry run behind it. An installation may waive it, and
  // the waiver is read here rather than assumed, so the gate a run meets is the one this
  // installation configured rather than the one the code happens to default to.
  bool requireDryRun = true;
  // WHAT turned the unwind off, and not whether it is off. The record and the log both name the
  // surface the decision came from, because a message about a command-line option to an operator
  // who set a key in a file sends them looking in the wrong place.
  String? unwindDisabledBy;
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
      unwindDisabledBy = 'no_unwind: true in $configuration';
    }
    // Read at start-up and not at the first command that needs root. An installation whose password
    // FILE is missing learns it before anything has been looked at, rather than halfway through a
    // run that has already changed the machine.
    //
    // **THE CALLER'S ROUTE IS RESOLVED HERE AND REFUSED ELSEWHERE, and that is not a lapse.** This
    // is the entry of every subcommand, and `serve` is one of them: it holds no password because it
    // executes no step — it starts a detached child per run, and the child is handed its own
    // password with its own answers. A refusal here would mean the surface cannot start on the very
    // installations that chose this route, which is what it did until this line was written. What
    // refuses a run with no password is the run path, where a step is about to be taken.
    inputs = await _inputsIn(files, options.option('answers'));
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
    stderr.writeln('--answers: ${unreadable.message}');
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

  if (options.option('log-level') case final String asked) {
    logLevel = LogLevel.values.firstWhere((LogLevel each) => each.name == asked);
  }

  final String programs = options.option('programs') ?? 'programs';
  if (!await machine.files.exists(programs)) {
    // Named rather than thrown. This is what an operator meets when they run the binary from
    // somewhere other than the installation it belongs to, and a stack trace tells them nothing
    // about which of the two is wrong.
    stderr.writeln('there are no programs at "$programs"');
    stderr.writeln('run this where the installation is, or say --programs <directory>');
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

  final RunDirectory directory = RunDirectory(options.option('runs') ?? RunDirectory.defaultRoot);
  final FileRunStore store = FileRunStore(directory: directory);

  if (rest.first == 'serve') {
    await _serve(
      machine: machine,
      catalogue: catalogue,
      store: store,
      directory: directory,
      options: options,
      requireDryRun: requireDryRun,
    );
    return;
  }

  // Reached with the catalogue already loaded, which is the point of installing from here: the
  // service is only placed on a machine whose programs resolve against the plugins this binary
  // carries, rather than started at boot and found broken at the first request.
  if (rest.first == 'install-service') {
    exit(
      await _installService(
        machine: machine,
        options: options,
        inputs: inputs,
        elevation: elevation,
        elevationSource: elevationSource,
      ),
    );
  }

  exit(
    await _runProgram(
      machine: machine,
      catalogue: catalogue,
      store: store,
      directory: directory,
      options: options,
      argv: argv,
      program: ProgramName(rest.first),
      logLevel: logLevel,
      inputs: inputs,
      // Handed on so the password that raises a command to root is redacted like any other secret,
      // whichever route it came by, and so a run can refuse when the route named one and none came.
      elevation: elevation,
      elevationSource: elevationSource,
      // Handed on so the answer conditions can be measured before the answers are checked.
      registry: registry,
      requireDryRun: requireDryRun,
      // The option wins where both say it, because whoever typed it meant this run.
      unwindDisabledBy: options.flag('no-unwind') ? 'the --no-unwind option' : unwindDisabledBy,
    ),
  );
}

Future<void> _serve({
  required bool requireDryRun,
  required Machine machine,
  required Catalogue catalogue,
  required FileRunStore store,
  required RunDirectory directory,
  required ArgResults options,
}) async {
  final DeploymentApi api = DeploymentApi(
    programs: ProgramsEndpoint(catalogue),
    runs: RunsEndpoint(
      store: store,
      launcher: DetachedLauncher(
        executable: Platform.resolvedExecutable,
        workingDirectory: Directory.current.path,
        newRunId: () => _newRunId(machine),
      ),
      catalogue: catalogue,
      gate: Gate(store, requireDryRun: requireDryRun),
      json: const RecordCodec(),
      commit: () => _commit(machine),
    ),
    events: EventsEndpoint(store: store, json: const RecordCodec()),
  );

  // Two ways in, chosen by the caller. The channel form is how the operator app reaches a machine
  // it has an SSH session on — including the FIRST installation, where no service exists yet to
  // listen — and stays the default. The listening form is what an installed machine runs as a
  // resident service, so a manager can start a run and come back to it without holding a session
  // open for the whole of it.
  if (options.option('listen') case final String address) {
    // READ BEFORE THE BIND, so a machine whose token was never placed refuses to start rather than
    // standing on an address while nothing guards it. There is no default and no way to waive it:
    // the constructor below takes a token, not an optional one.
    final ServiceToken token;
    try {
      final String? path = options.option('service-token-file');
      if (path == null || path.isEmpty) {
        stderr.writeln(
          '--listen needs --service-token-file: an address is authenticated by nothing',
        );
        stderr.writeln('a session is authenticated by sshd; an address is authenticated by this');
        exit(64);
      }
      token = ServiceToken.fromFile(path);
    } on FileSystemException catch (missing) {
      stderr.writeln('the service token cannot be read: ${missing.message} (${missing.path})');
      exit(78);
      // An empty token file is refused by the token itself, as a StateError. Caught because on this
      // path it is not a fault of the code but a machine whose token was never written — and the
      // operator has to read that as the machine's state, not as a crash.
      // ignore: avoid_catching_errors
    } on StateError catch (empty) {
      stderr.writeln(empty.message);
      exit(78);
    }

    try {
      await ListeningHttpServer(api, address: address, token: token).serve(
        // Written once the bind stands, because that is when the port is a fact: an address asked
        // for as port 0 is answered with the port the operating system chose, and a service's
        // journal says where the surface actually is rather than where it was asked to be.
        onBound: (HttpServer bound) => stdout.writeln('serving on ${_boundName(bound)}'),
      );
    } on FormatException catch (bad) {
      stderr.writeln(bad.message);
      exit(64);
    } on SocketException catch (bad) {
      stderr.writeln('cannot serve on "$address": ${bad.message}');
      exit(69);
    }
    return;
  }

  // The session's own standard input and output are the connection. Nothing listens.
  await ChannelHttpServer(api, incoming: stdin, outgoing: stdout).serve();
}

/// Where [bound] stands, as a caller would dial it: `host:port`, or the path of a socket file.
String _boundName(HttpServer bound) => bound.address.type == InternetAddressType.unix
    ? bound.address.address
    : '${bound.address.address}:${bound.port}';

/// Places the service that makes this binary reachable after the machine restarts, and returns the
/// exit code the process ends with.
///
/// **THE ORDER IS THE TOKEN, THEN THE UNIT, THEN THE SWITCH.** The service refuses to start without
/// a token it can read, so a unit enabled before the file existed would come up failed and restart
/// until somebody noticed. Everything the surface needs is on the machine before the service
/// manager is told the service exists.
///
/// **The token arrives on standard input and never as a file or an argument.** A value on a command
/// line stands in every process listing on the machine, and a file of it beside the installation
/// would outlive this call with nobody left to remove it. The envelope is the one both doors into
/// this engine take, so the operator app writes what it already knows how to write.
Future<int> _installService({
  required Machine machine,
  required ArgResults options,
  required CallerInputs inputs,
  required Elevation elevation,
  required ElevationSource? elevationSource,
}) async {
  // Refused here for the reason a run refuses it here: this is where a command that has to run as
  // root is about to be taken, and every file this places belongs to root.
  if (_elevationRefusal(elevationSource, elevation) case final String refused) {
    stderr.writeln(refused);
    return 78;
  }

  if (options.option('answers') != '-') {
    stderr.writeln(
      'install-service is told the service token on standard input: --answers - carrying '
      '{"answers": {"$serviceTokenAnswer": "..."}}',
    );
    stderr.writeln(
      'a file of it would outlive this call with nobody left to remove it, and a value on the '
      'command line stands in every process listing on the machine',
    );
    return 64;
  }

  final Object? supplied = inputs.answers[serviceTokenAnswer];
  final String token = supplied is String ? supplied.trim() : '';
  if (token.isEmpty) {
    stderr.writeln(
      'no "$serviceTokenAnswer" arrived on standard input, and it is the whole authentication of '
      'the surface on an address',
    );
    stderr.writeln('a machine whose token was never placed must refuse to serve, not serve openly');
    return 64;
  }

  final String listen = options.option('listen') ?? '';
  final String tokenFile = options.option('service-token-file') ?? '';
  if (listen.isEmpty || tokenFile.isEmpty) {
    stderr.writeln(
      'install-service needs --listen and --service-token-file: they are what the unit starts the '
      'service with, and there is no default for either',
    );
    return 64;
  }

  final ServiceInstallation installation = ServiceInstallation(
    unit: serviceUnit,
    executable: Platform.resolvedExecutable,
    startedFrom: Platform.script.toFilePath(),
    listen: listen,
    serviceTokenFile: tokenFile,
    programs: options.option('programs') ?? 'programs',
    config: options.option('config') ?? Configuration.defaultFileName,
    runs: options.option('runs') ?? RunDirectory.defaultRoot,
    // The service resolves every relative path above from the same place this call did, so a
    // machine installed from its catalogue keeps working when the paths were written relative.
    workingDirectory: Directory.current.path,
  );

  final String unit;
  try {
    unit = installation.render();
  } on ServiceInstallationRefused catch (refused) {
    stderr.writeln(refused.because);
    return 64;
  }

  try {
    // The directory first: an elevated write copies a file into place and creates no parent for it.
    if (installation.tokenDirectory case final String held) {
      await machine.files.createDirectory(
        held,
        mode: ServiceInstallation.tokenDirectoryMode,
        elevated: true,
      );
    }
    await machine.files.write(
      tokenFile,
      token,
      mode: ServiceInstallation.tokenFileMode,
      elevated: true,
    );
    await machine.files.write(
      installation.unitPath,
      unit,
      mode: ServiceInstallation.unitMode,
      elevated: true,
    );
    // The service manager reads its directory once at start-up and once when it is told to. A file
    // written without telling it is a service that does not exist as far as it is concerned.
    await _mustRun(machine, const <String>['systemctl', 'daemon-reload']);
    // Enabled AND started: the first is what makes it come back after a restart, the second is what
    // makes it answer now, and either is true without the other.
    await _mustRun(machine, <String>['systemctl', 'enable', '--now', serviceUnitName]);
  } on ElevationUnavailable catch (refused) {
    stderr.writeln(refused.message);
    return 78;
  } on CommandFailed catch (failed) {
    stderr.writeln('the machine did not carry the installation out: $failed');
    return 69;
  } on FileSystemException catch (failed) {
    stderr.writeln('the machine did not carry the installation out: ${failed.message}');
    return 69;
  }

  // ASKED AND REPORTED, never assumed. Enabling a unit says it comes back after a restart; it does
  // not say the service is answering, and the ordinary reason it is not yet is an address that is
  // not on the machine at this second.
  final CommandResult standing = await machine.shell.run(
    const Command.observing('systemctl', arguments: <String>['is-active', serviceUnitName]),
  );
  stdout
    ..writeln('${installation.unitPath} is written and $serviceUnitName comes back after a restart')
    ..writeln('the service token stands at $tokenFile, readable by root alone')
    ..writeln('$serviceUnitName is ${standing.trimmed}')
    ..writeln(
      standing.trimmed == 'active'
          ? 'the surface answers on $listen'
          : 'it is not answering on "$listen" yet, and the unit is restarted until that address can '
                'be bound — which is what a machine does until its tailnet address is there',
    );
  return 0;
}

/// Runs [argv] as root, and throws [CommandFailed] carrying what the machine said when it refused.
Future<void> _mustRun(Machine machine, List<String> argv) async {
  final CommandResult answer = await machine.shell.run(
    Command.detailed(argv.first, arguments: argv.sublist(1), elevated: true),
  );
  if (!answer.ok) {
    throw CommandFailed(
      argv: argv,
      exitCode: answer.exitCode,
      stdout: answer.stdout,
      stderr: answer.stderr,
    );
  }
}

/// Why nothing here can raise a command to root, or null where something can.
///
/// One wording for both callers. An installation that named the caller's route and was handed
/// nothing is the same state whether a run or an installation of the service met it, and two
/// wordings of it are two things to keep in step.
String? _elevationRefusal(ElevationSource? source, Elevation elevation) {
  if (source is! ElevationFromCaller || elevation.password != null) {
    return null;
  }
  return 'this installation says the caller hands over the password that raises a command to root, '
      'and none arrived\n'
      'put it beside the answers as "${CallerInputs.elevationPasswordField}", or name a '
      'password_file in the configuration where this machine is to hold one';
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
  required Registry registry,
  required String? unwindDisabledBy,
}) async {
  final ResolvedProgram? resolved = catalogue.byName(program);
  if (resolved == null) {
    stderr.writeln('no program is called "$program"');
    stderr.writeln(
      'there is: ${catalogue.programs.map((ResolvedProgram p) => p.declared.name).join(', ')}',
    );
    return 65;
  }

  // Where the caller's route is refused, and it is refused HERE because here is where a step is
  // about to be taken. The process entry cannot refuse it: `serve` comes through the same entry and
  // holds no password by design, since it executes nothing itself.
  if (_elevationRefusal(elevationSource, elevation) case final String refused) {
    stderr.writeln(refused);
    return 78;
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
    stderr.writeln(refused.message);
    return 78;
  } on ConditionUnanswerable catch (refused) {
    // Its own exit and its own sentence: the operator has to be sent to the condition that could not
    // be answered, not to the answer it was deciding about.
    stderr.writeln(refused.because);
    return 65;
  } on AnswersRejected catch (refused) {
    stderr.writeln(refused.message);
    return 65;
  } on FormatException catch (unreadable) {
    stderr.writeln('--answers: ${unreadable.message}');
    return 65;
  }

  final String commit = await _commit(machine);
  final String fingerprint = fingerprintOf(program: resolved, commit: commit, answers: answers);

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
    stderr.writeln(refusal.message);
    return 69;
  }

  final String? chosen = options.option('run');
  final RunId id = chosen == null || chosen.isEmpty ? _newRunId(machine) : RunId(chosen);

  // Resuming runs the same program again rather than skipping to a remembered position. Every step
  // that already did its work answers that there is nothing to do, and a machine somebody touched
  // in between is measured again instead of assumed. What the identifier is for is the record: it
  // joins the two halves of one story, which two unrelated runs would not.
  final String? continues = options.option('resume');
  RunId? resumes;
  if (continues != null && continues.isNotEmpty) {
    final RunRecord? earlier = await store.read(RunId(continues));
    if (earlier == null) {
      stderr.writeln('there is no run called "$continues" to continue');
      return 65;
    }
    if (earlier.fingerprint != fingerprint) {
      stderr.writeln('run "$continues" was a different input, so this would not be continuing it');
      stderr.writeln('start a fresh run instead, or say why the input changed');
      return 65;
    }
    resumes = earlier.id;
  }

  final RunRecord header = RunRecord(
    id: id,
    program: program,
    mode: mode,
    argv: argv,
    start: machine.clock.now(),
    stage: Stage(options.option('stage') ?? 'dev'),
    role: Role(options.option('role') ?? 'master'),
    fqdn: Fqdn(options.option('fqdn') ?? ''),
    commit: commit,
    fingerprint: fingerprint,
    resumes: resumes,
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
Future<CallerInputs> _inputsIn(Files files, String? path) async {
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

RunId _newRunId(Machine machine) {
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
Future<String> _commit(Machine machine) async {
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

/// The name `install-service` is told the service token under, inside the envelope.
///
/// Inside the envelope's answers rather than beside them, because the envelope's other field holds
/// the password that raises a command to root and both are needed in the same call: the token is
/// what the installation is told, the password is what lets it write.
const String serviceTokenAnswer = 'service_token';
