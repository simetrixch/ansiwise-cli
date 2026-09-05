// The REST service: the surface of a deployment, and the one door it is reached through.
//
// A SERVICE IN ITS OWN RIGHT, and not a flag on the tool that runs deployments. The door is a
// program of this binary — `serve`, which speaks over the pipes of a session sshd has already
// authenticated. A manager reaches a machine over the session it already holds, and there is no
// second route: nothing here binds an address, and nothing here authenticates a caller.
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

/// The name this binary is invoked by, for the sentences that have to say it.
const String executableName = 'ansiwise-rest';

/// The word that starts the one program this binary has: the surface over the session's own
/// standard input and output.
///
/// A WORD AND NOT A FLAG, and it stays a word now that it is alone. A flag that turned the binary
/// into a server would be a machine asked for one thing and given another; and the manager composes
/// this word on the far side of an SSH session, where nothing in this repository can see it.
/// `test/checks/subcommands_start_test.dart` starts the real binary with it, which is what holds
/// the two together.
const String sessionProgram = 'serve';

Future<void> main(List<String> argv) async {
  final ArgParser parser = ArgParser();
  addSharedOptions(parser);
  parser.addFlag('help', abbr: 'h', negatable: false);

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
      ..writeln(
        '$executableName $sessionProgram'
        '                over this session\'s own stdin and stdout',
      )
      ..writeln()
      ..writeln(parser.usage);
    exit(rest.isEmpty && !options.flag('help') ? 64 : 0);
  }

  // A WORD THIS BINARY DOES NOT KNOW IS REFUSED BEFORE ANYTHING IS OPENED, and it is refused by
  // naming the other binary. `ansiwise-rest deploy-cluster` is what somebody types who meant the
  // deployment tool, and reading a configuration and a catalogue first would answer them with
  // whatever went wrong in that installation instead of with the one thing that is actually wrong.
  if (rest.first != sessionProgram) {
    stderr.writeln('$executableName has no program called "${rest.first}"');
    stderr.writeln('it serves: $sessionProgram');
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

  // The session's own standard input and output are the connection. Nothing listens, nothing is
  // bound, and nothing authenticates a second time: sshd authenticated the caller before this
  // process existed.
  await ChannelHttpServer(
    _surface(
      machine: installation.machine,
      catalogue: installation.catalogue,
      store: installation.store,
      requireDryRun: installation.requireDryRun,
      placement: placementFrom(options),
    ),
    incoming: stdin,
    outgoing: stdout,
  ).serve();
}

/// The REST surface this door answers with, composed out of what this binary carries.
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
  required List<String> placement,
}) => DeploymentApi(
  programs: ProgramsEndpoint(catalogue),
  runs: RunsEndpoint(
    store: store,
    launcher: DetachedLauncher(
      executable: deploymentToolBesideThis(),
      workingDirectory: Directory.current.path,
      newRunId: () => newRunId(machine),
      // WHERE THIS PROCESS STANDS, HANDED ON. Every child resolves its programs, its configuration
      // and its record directory itself, and each of those has a default relative to the working
      // directory — so a surface TOLD any of them and a child given only the directory stand in two
      // different places. Measured: `cd <catalogue> && ansiwise-rest serve --programs
      // <catalogue>/ansiwise/programs` served the catalogue and every run it accepted exited 66
      // with `there are no programs at "programs"` before writing a header.
      placement: placement,
    ),
    catalogue: catalogue,
    gate: Gate(store, requireDryRun: requireDryRun),
    json: const RecordCodec(),
    commit: () => commitOf(machine),
    // FROM THE STORE'S OWN DIRECTORY, so the door reads refusals out of the run root it answers
    // records from. Told a root of its own it would look for the reason of a run beside a different
    // machine's records, and answer that a run it had just accepted was never started.
    startupReason: (RunId id) => startupReasonOf(store.directory, id),
  ),
  events: EventsEndpoint(store: store, json: const RecordCodec()),
);

/// The deployment tool this service starts a run with, found beside this binary.
///
/// **WHY IT IS NOT THIS PROCESS.** A run started over the surface is executed by a DETACHED CHILD,
/// so the child outlives the request and a restart of the service does not kill a deployment
/// half-way. Before the surface had a binary of its own, that child was this same executable started
/// with a program name — one binary, two roles. It cannot be that any more: this one serves and
/// refuses every word that is not the one program it has, so a child started from it would be
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
