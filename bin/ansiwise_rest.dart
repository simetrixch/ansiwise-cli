// The REST service: the surface of a deployment, and the two doors it is reached through.
//
// A SERVICE IN ITS OWN RIGHT, and not a flag on the tool that runs deployments. The two doors are
// two programs of this binary — one stands on an address and demands a service token, the other
// speaks over the pipes of a session sshd has already authenticated — and `install-service` is the
// third, which places the first on a machine so it outlives the session that installed it.
//
// WHAT IT SHARES WITH THE OTHER BINARY, AND WHY THAT IS THE WHOLE POINT. Everything in front of a
// program — the configuration, the active plugins, the elevation route, the machine, the catalogue,
// the record directory — is composed by `openInstallation` in lib/installation.dart, which both
// entry points call. So a served run and a run started at the command line resolve ONE registry
// built from ONE plugin list on that machine, and neither can quietly know a step the other does
// not.
//
// `dart:io` is used here for the process's own arguments, its exit code and its standard streams,
// and for nothing else. Everything this does to a machine goes through the same four ports every
// step uses.
import 'dart:io';

import 'package:args/args.dart';
import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_cli/installation.dart';
import 'package:ansiwise_cli/plugins.dart';
import 'package:ansiwise_cli/rest.dart';
import 'package:ansiwise_cli/service_installation.dart';
import 'package:ansiwise_cli/service_unit.dart';

/// The name this binary is invoked by, for the sentences that have to say it.
const String executableName = 'ansiwise-rest';

Future<void> main(List<String> argv) async {
  final ArgParser parser = ArgParser();
  addSharedOptions(parser);
  parser
    ..addOption(
      ResidentService.addressOption,
      help:
          'where `${ResidentService.program}` stands: host:port (127.0.0.1:9953, [::1]:9953) or '
          'unix:<path>. Required by that program and by `install-service`, which is given the same '
          'address and writes it into the unit it places — where the accepted shapes are narrower, '
          'because a service nobody can reach is worth less than a refusal. There is no default: '
          'which addresses may reach the surface is the installation\'s decision, not this '
          'binary\'s. It is NOT an option of `${ResidentService.sessionProgram}`, which serves one '
          'session over that session\'s own pipes and stands on no address at all',
    )
    ..addOption(
      ResidentService.tokenFileOption,
      help:
          'the file holding the tokens every caller of `${ResidentService.program}` must present. '
          'Required by it and meaningless to `${ResidentService.sessionProgram}`: a session is '
          'authenticated by sshd, an address by nothing until this says so. The PATH is here and '
          'the VALUE never is — a credential on a command line stands in every process listing on '
          'the machine. `install-service` is the one that puts the value there, and it is told it '
          'on standard input',
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
      ..writeln(
        '$executableName ${ResidentService.sessionProgram}'
        '                over this session\'s own stdin and stdout',
      )
      ..writeln(
        '$executableName ${ResidentService.program} '
        '--${ResidentService.addressOption} <address> '
        '--${ResidentService.tokenFileOption} <path>',
      )
      ..writeln(
        '$executableName install-service '
        '--${ResidentService.addressOption} <address> '
        '--${ResidentService.tokenFileOption} <path> --$answersOption -',
      )
      ..writeln()
      ..writeln(parser.usage);
    exit(rest.isEmpty && !options.flag('help') ? 64 : 0);
  }

  // A WORD THIS BINARY DOES NOT KNOW IS REFUSED BEFORE ANYTHING IS OPENED, and it is refused by
  // naming the other binary. `ansiwise-rest deploy-cluster` is what somebody types who meant the
  // deployment tool, and reading a configuration and a catalogue first would answer them with
  // whatever went wrong in that installation instead of with the one thing that is actually wrong.
  const Set<String> programs = <String>{
    ResidentService.program,
    ResidentService.sessionProgram,
    installServiceProgram,
  };
  if (!programs.contains(rest.first)) {
    stderr.writeln('$executableName has no program called "${rest.first}"');
    stderr.writeln('it serves: ${programs.join(', ')}');
    stderr.writeln(
      'a deployment program is run by the other binary: ansiwise ${rest.first} --mode test',
    );
    exit(64);
  }

  // Every plugin this binary was compiled with. Dart ahead of time loads no code that was not built
  // in, so this list is a fact of the build — and the configuration decides which of them are on,
  // which is a fact of the installation. It is the SAME list the deployment tool carries, out of
  // the same generated file, which is what makes one machine's two binaries agree about what a step
  // name means.
  const PluginSet plugins = compiledPlugins;

  final Installation installation = await openInstallation(options: options, plugins: plugins);

  // THE TWO DOORS ARE TWO PROGRAMS, and the surface they serve is composed once for both. Which of
  // them a machine runs is a word, never an option: a flag that turned one into the other meant a
  // machine asked for one could be given the other.
  if (rest.first == ResidentService.sessionProgram) {
    if (options.option(ResidentService.addressOption) != null ||
        options.option(ResidentService.tokenFileOption) != null) {
      stderr.writeln(
        '${ResidentService.sessionProgram} serves the session it was started in, over that '
        'session\'s own stdin and stdout — it stands on no address and demands no token, because '
        'sshd authenticated the caller before this process existed',
      );
      stderr.writeln(
        'the resident service is its own program: $executableName ${ResidentService.program} '
        '--${ResidentService.addressOption} <address> '
        '--${ResidentService.tokenFileOption} <path>',
      );
      exit(64);
    }
    // The session's own standard input and output are the connection. Nothing listens.
    await ChannelHttpServer(
      _surface(
        machine: installation.machine,
        catalogue: installation.catalogue,
        store: installation.store,
        requireDryRun: installation.requireDryRun,
      ),
      incoming: stdin,
      outgoing: stdout,
    ).serve();
    return;
  }

  if (rest.first == ResidentService.program) {
    await _residentService(
      machine: installation.machine,
      catalogue: installation.catalogue,
      store: installation.store,
      options: options,
      requireDryRun: installation.requireDryRun,
    );
    return;
  }

  // Reached with the catalogue already loaded, which is the point of installing from here: the
  // service is only placed on a machine whose programs resolve against the plugins this binary
  // carries, rather than started at boot and found broken at the first request.
  exit(
    await _installService(
      machine: installation.machine,
      options: options,
      inputs: installation.inputs,
      elevation: installation.elevation,
      elevationSource: installation.elevationSource,
    ),
  );
}

/// The REST surface both doors answer with, composed once out of what this binary carries.
///
/// ONE of these exists per process, and there is no second place that builds one. Which steps a
/// request can name is decided by [catalogue], which was resolved against the registry this binary
/// was compiled with — so a run started over the surface and a run started at this command line
/// cannot resolve different plugin sets, rather than resolving the same one by agreement.
DeploymentApi _surface({
  required Machine machine,
  required Catalogue catalogue,
  required FileRunStore store,
  required bool requireDryRun,
}) => DeploymentApi(
  programs: ProgramsEndpoint(catalogue),
  runs: RunsEndpoint(
    store: store,
    launcher: DetachedLauncher(
      executable: deploymentToolBesideThis(),
      workingDirectory: Directory.current.path,
      newRunId: () => newRunId(machine),
    ),
    catalogue: catalogue,
    gate: Gate(store, requireDryRun: requireDryRun),
    json: const RecordCodec(),
    commit: () => commitOf(machine),
  ),
  events: EventsEndpoint(store: store, json: const RecordCodec()),
);

/// Runs the resident service: the surface on an address, for callers that open no session.
///
/// What it stands on and what it demands are read here and judged by [ResidentService], which is
/// where those arguments and their refusals are stated. This function turns each refusal into the
/// exit code an operator's tooling reads and nothing else.
///
/// THE TOKEN FILE IS NAMED HERE AND READ THERE. `ListeningHttpServer.serve` reads it itself before
/// it binds, so a machine whose token was never placed refuses to start rather than standing on an
/// address while nothing guards it — and reading it there rather than here is what lets a token be
/// rotated under a running service (ansiwise-rest#1). There is no default and no way to waive it.
Future<void> _residentService({
  required Machine machine,
  required Catalogue catalogue,
  required FileRunStore store,
  required bool requireDryRun,
  required ArgResults options,
}) async {
  final ResidentService service;
  try {
    service = ResidentService.of(
      address: options.option(ResidentService.addressOption),
      serviceTokenFile: options.option(ResidentService.tokenFileOption),
    );
  } on ResidentServiceRefused catch (refused) {
    stderr.writeln(refused.because);
    exit(64);
  }

  try {
    await service.serve(
      _surface(machine: machine, catalogue: catalogue, store: store, requireDryRun: requireDryRun),
      // Written once the bind stands, because that is when the port is a fact: an address asked for
      // as port 0 is answered with the port the operating system chose, and a service's journal
      // says where the surface actually is rather than where it was asked to be.
      standing: (HttpServer bound) => stdout.writeln(ResidentService.announcement(bound)),
    );
  } on FormatException catch (bad) {
    stderr.writeln(bad.message);
    exit(64);
  } on SocketException catch (bad) {
    stderr.writeln('cannot serve on "${service.address}": ${bad.message}');
    exit(69);
  } on FileSystemException catch (unreadable) {
    // The file `install-service` is the one that puts there. Reaching this means the unit was
    // enabled without it, or something cleared the machine of credentials — and a stack trace names
    // a Dart call rather than the path an operator has to put back.
    stderr.writeln(
      'cannot read the tokens at "${service.serviceTokenFile}": ${unreadable.osError?.message ?? unreadable.message}',
    );
    stderr.writeln(
      'install-service writes that file; without it no caller can be told apart from any other',
    );
    exit(66);
    // Caught because `ServiceTokenFile.read` raises this for a file an operator wrote by hand, not
    // for a fault of the code, and its own contract names it as one of exactly two failures
    // anything acting on a failed start reads. A type neither of them names is a stack trace where
    // that sentence belongs.
    // ignore: avoid_catching_errors
  } on StateError catch (empty) {
    stderr.writeln('"${service.serviceTokenFile}" holds no token: ${empty.message}');
    stderr.writeln(
      'a service accepting every caller is not what an empty file asks for, so it refuses instead',
    );
    exit(66);
  }
}

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
  if (elevationRefusal(elevationSource, elevation) case final String refused) {
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

  // THE INSTALLER IS INVOKED THE WAY THE SERVICE IS TO BE INVOKED, and judged by the same type
  // that judges the service. A second wording of "these two are required" here would be a second
  // statement of the service's own arguments, kept by something that cannot see them change.
  final ResidentService service;
  try {
    service = ResidentService.of(
      address: options.option(ResidentService.addressOption),
      serviceTokenFile: options.option(ResidentService.tokenFileOption),
    );
  } on ResidentServiceRefused catch (refused) {
    stderr.writeln(refused.because);
    stderr.writeln(
      'they are what the unit starts the service with, and this call is where the '
      'unit is written',
    );
    return 64;
  }
  final String listen = service.address;
  final String tokenFile = service.serviceTokenFile;

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

/// The name `install-service` is told the service token under, inside the envelope.
///
/// Inside the envelope's answers rather than beside them, because the envelope's other field holds
/// the password that raises a command to root and both are needed in the same call: the token is
/// what the installation is told, the password is what lets it write.
const String serviceTokenAnswer = 'service_token';

/// The deployment tool this service starts a run with, found beside this binary.
///
/// **WHY IT IS NOT THIS PROCESS.** A run started over the surface is executed by a DETACHED CHILD,
/// so the child outlives the request and a restart of the service does not kill a deployment
/// half-way. Before the surface had a binary of its own, that child was this same executable started
/// with a program name — one binary, two roles. It cannot be that any more: this one serves and
/// refuses every word that is not one of its three programs, so a child started from it would be
/// turned away before it opened anything, and what an operator would see is a run that failed
/// instantly with a usage error naming a program they did know.
///
/// **BESIDE, and not a path somebody configures.** The two binaries of this repository are placed
/// together by the one mechanism that places either of them, so the deployment tool stands in the
/// directory this one was started from. A configurable path would be a way for an installation to
/// point the surface at a DIFFERENT build than the one it was installed with — two versions of the
/// engine on one machine, told apart by nothing a record would show.
///
/// **A MISSING SIBLING IS A REFUSAL AT START, not at the first request.** A service that comes up
/// and then fails every run it is asked for is a service an operator believes is working; the
/// journal would carry one line per run and none of them would say why.
///
/// **STARTED FROM SOURCE THERE IS NO SIBLING AND NONE IS DEMANDED.** Then this process is the
/// toolchain rather than a placed binary, `Platform.resolvedExecutable` is `dart`, and what stands
/// beside it is whatever else that toolchain ships. That case is refused nowhere because it is
/// already broken further down and always was: the launcher composes the executable followed by a
/// program name and `--mode`, with no room for the `run bin/…` a source invocation needs, so a run
/// started over the
/// surface from a checkout would invoke the toolchain with a program name. What that case IS for is
/// the suites, which start this binary from source to judge its refusals and never start a run.
String deploymentToolBesideThis() {
  final String here = File(Platform.resolvedExecutable).parent.path;
  final String suffix = Platform.isWindows ? '.exe' : '';
  final String beside = '$here${Platform.pathSeparator}ansiwise$suffix';
  if (File(beside).existsSync()) {
    return beside;
  }
  // The compiled binary of this repository, standing where a placement put it. Anything else is a
  // toolchain running this from source.
  final String file = Platform.resolvedExecutable.split(Platform.pathSeparator).last;
  if (file == executableName || file == '$executableName$suffix') {
    stderr.writeln(
      '$executableName serves runs by starting the deployment tool, and there is none at "$beside"',
    );
    stderr.writeln(
      'the two are placed together: a machine that carries one and not the other can answer for '
      'programs and run none of them',
    );
    exit(78);
  }
  return Platform.resolvedExecutable;
}
