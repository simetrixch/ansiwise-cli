/// ONE fingerprint per job, whoever computes it.
///
///   dart test test/rest/one_fingerprint_test.dart
///
/// A run over this surface is fingerprinted TWICE: by this door, which needs a number to look a
/// clean dry run up by, and by the process that actually performs it, which writes its own into the
/// record. The gate can only ever admit a real run when those two agree — so the door computing its
/// number over anything other than what the run will carry is a real run that is refused for ever
/// after its own green dry.
///
/// **WHAT MAKES THEM DISAGREE.** `validate` does not only judge answers: it fills every answer that
/// has a default, fills every answer that FALLS BACK to another from the one it names, and works out
/// every derived answer. `ansiwise.dart` fingerprints exactly what that call returns. A door that
/// calls it for the judgement and throws the answer away, fingerprinting the caller's raw map
/// instead, stops the platform: `deploy-cluster` declares `books_fqdn` with a `default_from`, the
/// manager's master arm sends neither it nor the value it falls back from, and the two numbers come
/// out `ca14d4f14aea…` (door) against `4bfda385e985…` (machine). A retry cannot clear it — the next
/// dry records the same number the door does not ask for.
///
/// WHAT IS HELD is the outcome and never the wording: a dry run recorded with the number the RUN
/// computes is a dry run this door admits the run against.
library;

import 'dart:convert';

import 'package:ansiwise_cli/rest.dart';
import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:test/test.dart';

import '../support/example_steps.dart';
import '../support/harness.dart';
import 'doubles.dart';

void main() {
  const String commit = 'abc1234';

  /// A program shaped like the one that exposed this: an answer the caller states, and one that
  /// FALLS BACK to it and is normally left out.
  ///
  /// `books_fqdn` is the real name and the real shape (digita-deploy
  /// ansiwise/programs/deploy-cluster.yaml): the cluster whose books this installation keeps,
  /// which for a master IS the master, so nothing sends it.
  ResolvedProgram deployCluster() =>
      ProgramResolver(
        registryOf(
          steps: <String, (String, Step Function(Arguments))>{
            'writes_a_file': (
              'deployment/lib/steps/writes_a_file.dart:12',
              (Arguments a) => WritesAFile(path: a.text('path'), content: 'the content'),
            ),
          },
          arguments: <String, List<ArgumentSpec>>{
            'writes_a_file': const <ArgumentSpec>[
              ArgumentSpec(
                name: 'path',
                kind: ArgumentKind.text,
                describes: 'the file to write',
                defaultValue: '/etc/thing',
              ),
            ],
          },
        ),
      ).resolve(
        programOf(
          'deploy-cluster',
          <(String, OnFailure, List<String>)>[('writes_a_file', OnFailure.exit, <String>[])],
          arguments: <String, Arguments>{
            'writes_a_file': const Arguments(<String, Object>{'path': '/etc/thing'}),
          },
          answers: const DeclaredAnswers(<ArgumentSpec>[
            ArgumentSpec(name: 'fqdn', kind: ArgumentKind.text, describes: 'this installation'),
            ArgumentSpec(
              name: 'books_fqdn',
              kind: ArgumentKind.text,
              describes: 'the cluster this installation keeps its books on',
              defaultFrom: 'fqdn',
            ),
          ]),
        ),
      );

  ({DeploymentApi api, MemoryRunStore store, RecordingLauncher launcher}) build(
    ResolvedProgram program,
  ) {
    final MemoryRunStore store = MemoryRunStore();
    final RecordingLauncher launcher = RecordingLauncher();
    final FixedCatalogue catalogue = FixedCatalogue(<ResolvedProgram>[program]);
    return (
      api: DeploymentApi(
        programs: ProgramsEndpoint(catalogue),
        runs: RunsEndpoint(
          store: store,
          launcher: launcher,
          catalogue: catalogue,
          gate: Gate(store, requireDryRun: true),
          json: const PlainRecordJson(),
          commit: () async => commit,
        ),
        events: EventsEndpoint(store: store, json: const PlainRecordJson()),
      ),
      store: store,
      launcher: launcher,
    );
  }

  ApiRequest post(String path, Map<String, Object?> body) =>
      ApiRequest('POST', Uri.parse(path), body: jsonEncode(body));

  /// The number the RUN computes, worked out the way `ansiwise.dart` works it out: over what
  /// validation ANSWERED, not over what the caller wrote.
  String asTheRunComputesIt(ResolvedProgram program, Map<String, Object?> given) => fingerprintOf(
    program: program,
    commit: commit,
    answers: program.declared.answers.validate(given, program: program.declared.name.value),
  );

  // THE CASE THIS IS ABOUT. The caller states `fqdn` and leaves `books_fqdn` out, exactly as the
  // manager's master arm does. The run fills it from `fqdn`; the door has to fingerprint the same
  // filled shape, or the dry the machine recorded is a dry this door can never find.
  test('a dry recorded by the RUN admits the real run when an answer fell back', () async {
    final ResolvedProgram program = deployCluster();
    final ({DeploymentApi api, MemoryRunStore store, RecordingLauncher launcher}) it = build(
      program,
    );
    const Map<String, Object?> given = <String, Object?>{'fqdn': 'apps4.example.com'};

    it.store.runs.add(
      runRecord(
        id: 'the-dry-one',
        program: 'deploy-cluster',
        mode: Mode.dry,
        fingerprint: asTheRunComputesIt(program, given),
        exitCode: 0,
      ),
    );

    final ApiResponse answer = await it.api.call(
      post('/runs', <String, Object?>{
        'program': 'deploy-cluster',
        'mode': 'run',
        'answers': given,
      }),
    );

    expect(
      answer,
      isA<Answered>(),
      reason: answer is Refused
          ? 'the door computed a different number from the run: ${answer.reason}'
          : '',
    );
    expect(switch ((answer as Answered).payload) {
      final Map<String, Object?> body => body['admitted_by'],
      final Object other => throw StateError('answered with $other'),
    }, 'the-dry-one');
    expect(it.launcher.started, <(ProgramName, Mode)>[
      (const ProgramName('deploy-cluster'), Mode.run),
    ]);
  });

  // THE SAME JOB SAID TWO WAYS. Leaving the falling-back answer out and stating the value it would
  // fall back to are one input, so they are one number — which is what makes the fill part of the
  // job rather than a detail of how it was asked for.
  test('stating what an answer falls back to is the same input as leaving it out', () async {
    final ResolvedProgram program = deployCluster();
    final ({DeploymentApi api, MemoryRunStore store, RecordingLauncher launcher}) it = build(
      program,
    );

    it.store.runs.add(
      runRecord(
        id: 'the-dry-one',
        program: 'deploy-cluster',
        mode: Mode.dry,
        fingerprint: asTheRunComputesIt(program, <String, Object?>{'fqdn': 'apps4.example.com'}),
        exitCode: 0,
      ),
    );

    final ApiResponse answer = await it.api.call(
      post('/runs', <String, Object?>{
        'program': 'deploy-cluster',
        'mode': 'run',
        'answers': <String, Object?>{
          'fqdn': 'apps4.example.com',
          'books_fqdn': 'apps4.example.com',
        },
      }),
    );

    expect(answer, isA<Answered>());
  });

  // THE INNOCENT NEIGHBOUR, and it is what keeps the gate a gate: filling an answer in must not
  // make two DIFFERENT jobs hash alike. A run against another installation is another input, and
  // the dry above says nothing about it.
  test('a dry run of another installation still does not admit it', () async {
    final ResolvedProgram program = deployCluster();
    final ({DeploymentApi api, MemoryRunStore store, RecordingLauncher launcher}) it = build(
      program,
    );

    it.store.runs.add(
      runRecord(
        id: 'the-dry-one',
        program: 'deploy-cluster',
        mode: Mode.dry,
        fingerprint: asTheRunComputesIt(program, <String, Object?>{'fqdn': 'apps3.example.com'}),
        exitCode: 0,
      ),
    );

    final ApiResponse answer = await it.api.call(
      post('/runs', <String, Object?>{
        'program': 'deploy-cluster',
        'mode': 'run',
        'answers': <String, Object?>{'fqdn': 'apps4.example.com'},
      }),
    );

    expect(answer, isA<Refused>());
    expect((answer as Refused).status, 409);
    expect(it.launcher.started, isEmpty, reason: 'the run must not have been started');
  });
}
