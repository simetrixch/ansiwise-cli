import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:ansiwise_cli/plugins.dart';
import 'package:test/test.dart';

/// config-validity — every program file of the installation loads and binds every name to the
/// registry this binary ships.
///
/// The registry is the shipped one, composed exactly the way the binary composes it at start-up:
/// every plugin compiled in, activated by the installation's own configuration file. A check
/// reading the programs against one plugin's registry would report every step of the others as
/// unregistered — and narrowed until that passes, it would prove the programs correct against a
/// set of steps nobody ships.
///
/// The programs are the installation's, found through the one resolution every audit uses, so this
/// suite and the answer-declaration probes cannot come to disagree about where the installation is.
Future<void> main() async {
  final Configuration active = await Configuration.load(
    files: const RealFiles(),
    path: '$installationRoot/${Configuration.defaultFileName}',
  );
  final Registry shipped = compiledPlugins.activate(active.plugins);
  final ConfigValidity check = ConfigValidity(
    files: const RealFiles(),
    registry: shipped,
    directory: installationProgramsRoot,
  );
  final List<String> onDisk = await check.programFiles();
  final ProgramReading reading = await check.read();

  test('$installationPrograms holds program files to judge', () {
    expect(
      onDisk,
      isNotEmpty,
      reason: 'a check that read no program file would pass over a tree it never opened',
    );
  });

  test('every program file on disk was read', () {
    // The files are counted here and the outcomes there, and the two have to agree. A reading that
    // walked the directory and found nothing would otherwise report no refusal and be taken for
    // agreement.
    expect(
      reading.outcomes.map((ProgramOutcome outcome) => outcome.file),
      unorderedEquals(onDisk),
      reason: 'some file in $installationPrograms was never read',
    );
  });

  test('every program file loads and binds to the registry', () {
    expect(
      reading.findings,
      isEmpty,
      reason:
          'no unknown step, no unknown predicate, no undeclared argument, no missing required '
          'argument and no value of the wrong kind — this is what an operator would meet on the '
          'machine at the moment they least want to read a refusal',
    );
  });

  test('the reading states how much it covered', () {
    // The denominator, said out loud in the gate log: a run that reports no refusal AND what it
    // read can be told apart from a run that read nothing.
    for (final ProgramOutcome outcome in reading.outcomes) {
      print(outcome);
    }
    print(
      'config-validity read ${reading.outcomes.length} program file(s), '
      '${reading.stepCount} step(s)',
    );
    expect(
      reading.stepCount,
      greaterThan(0),
      reason: 'every program resolved to nothing, so the binding was never exercised',
    );
  });

  group('counter-probe', () {
    // Three programs written here and run through the same resolver. Two must be refused and one
    // must be accepted: a resolver that accepted everything would pass a tree whose programs are
    // all broken, and one that refused everything would be caught only by the third — which is why
    // the accepted one is generated FROM the registry rather than typed out. It carries whatever
    // the first registered step declares, so it stays a true program on the day that step gains an
    // argument.

    final ProgramResolver resolver = ProgramResolver(shipped);
    final String validProgramText = _programTextFor(shipped.steps.values.first);

    test('the registry holds a step a program could name', () {
      expect(
        shipped.steps,
        isNotEmpty,
        reason: 'a program can name nothing, so nothing below was measured',
      );
    });

    test('a step no registry holds is refused', () {
      expect(
        resolve(resolver, _namesAnUnknownStep, 'planted-unknown-step.yaml'),
        isA<ProgramRefused>(),
      );
    });

    test('a program built from the registry resolves', () {
      expect(
        resolve(resolver, validProgramText, 'planted-program.yaml'),
        isA<ProgramResolved>(),
        reason: 'this resolver refuses everything, so the refusals above prove nothing',
      );
    });

    test('an argument no step declares is refused', () {
      expect(
        resolve(
          resolver,
          '$validProgramText    no_step_declares_this_argument: 1\n',
          'planted-extra-argument.yaml',
        ),
        isA<ProgramRefused>(),
      );
    });

    test('a refusal names every problem it found, one line each', () {
      final ProgramOutcome outcome = resolve(
        resolver,
        _namesAnUnknownStep,
        'planted-unknown-step.yaml',
      );
      expect(
        (outcome as ProgramRefused).problems,
        isNotEmpty,
        reason: 'a refusal with no lines in it tells the person fixing the file nothing',
      );
    });
  });
}

const String _namesAnUnknownStep = '''
name: planted-unknown-step
roles: [master]
steps:
  - step: no_step_is_registered_under_this_name
    on_failure: exit
''';

/// A program file naming [entry], with a value for every argument it declares and a declaration
/// for every answer it reads.
String _programTextFor(RegisteredStep entry) {
  final Arguments given = plausibleArguments(entry.arguments);
  final StringBuffer text = StringBuffer()..writeln('name: planted-program');
  // Every answer the step reads, declared the way a real program declares it. Without this the
  // planted program is refused for the one thing it is not being probed for — a step reading an
  // answer nothing declares — and which step that hits depends on what stands first in the
  // registry, so leaving it out makes this probe pass or fail on the order of a map.
  if (entry.answers.isNotEmpty) {
    text.writeln('answers:');
    for (final String answer in entry.answers) {
      text
        ..writeln('  - name: $answer')
        ..writeln('    kind: text')
        ..writeln('    describes: what the step under probe reads out of the run');
    }
  }
  text
    ..writeln('roles: [master]')
    ..writeln('steps:')
    ..writeln('  - step: ${entry.name.value}')
    ..writeln('    on_failure: exit');
  for (final ArgumentSpec spec in entry.arguments) {
    text.writeln('    ${spec.name}: ${_asYaml(given.raw(spec.name))}');
  }
  return text.toString();
}

/// [value] written the way a program file writes it.
///
/// Text is always quoted, so a value that YAML would read as a number, as a date or as true stays
/// the text the step declared. The quote inside is doubled, which is how a single-quoted YAML
/// scalar carries one.
String _asYaml(Object? value) => switch (value) {
  final String text => "'${text.replaceAll("'", "''")}'",
  final List<String> texts => '[${texts.map(_asYaml).join(', ')}]',
  null => 'null',
  _ => '$value',
};
