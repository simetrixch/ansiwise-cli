import 'package:ansiwise_cli/rest.dart';
import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:test/test.dart';

import 'doubles.dart';

/// A 404 from this door means one thing, and a caller no longer has to guess which.
///
/// **THE DEFECT THIS EXISTS FOR WAS MEASURED.** `POST /runs` answers `202` with an identifier the
/// moment the child is spawned, and the child writes its first header much later. `GET /runs/{id}`
/// answered the same 404 for a run that had died before its first step and for an identifier nobody
/// ever issued — on apps6 on 2026-09-04 a run refused because three declared answers were not given,
/// wrote all three to `<id>.startup.log` in the run root, and the caller polled for 180 seconds and
/// then reported, correctly, that it cannot tell whether the run is still starting or is gone.
///
/// **BOTH ARE STILL 404**, because in neither case is there a run to open. What separates them is
/// the reason, which is the field the caller acts on.
///
/// **A SLOW RUN IS NOT COVERED AND CANNOT BE.** A run that is merely still starting has written no
/// reason either, so it stays the plain 404 that a caller's own wait is for.
void main() {
  const String refused = '20260903T234009Z-547069-7b5dc756';
  const String neverIssued = '20260903T234009Z-000000-deadbeef';
  const String said =
      'deploy-branch: needs the answer "build_platform_repo_write_pat" -- a token that may '
      'write to the platform repository';

  late RefusalsAtStartup startup;
  late MemoryRunStore store;

  setUp(() {
    startup = RefusalsAtStartup(<String, String>{refused: said});
    store = MemoryRunStore();
  });

  /// The door, reading refusals out of the run root [startup] stands for.
  DeploymentApi door() => DeploymentApi(
    programs: ProgramsEndpoint(FixedCatalogue(<ResolvedProgram>[])),
    runs: RunsEndpoint(
      store: store,
      launcher: RecordingLauncher(),
      catalogue: FixedCatalogue(<ResolvedProgram>[]),
      gate: Gate(store),
      json: const PlainRecordJson(),
      commit: () async => 'abc1234',
      startupReason: startup.of,
    ),
    events: EventsEndpoint(store: store, json: const PlainRecordJson()),
  );

  /// What the door refuses `GET /runs/[id]` with, or a failure where it answered instead.
  Future<Refused> asks(String id) async {
    final ApiResponse answer = await door().call(ApiRequest('GET', Uri.parse('/runs/$id')));
    return switch (answer) {
      final Refused refusal => refusal,
      final ApiResponse other => throw StateError('GET /runs/$id answered $other'),
    };
  }

  group('GET /runs/{id} where there is no record', () {
    test('a run that refused before its first step is refused with what it said', () async {
      final Refused refusal = await asks(refused);

      expect(refusal.status, 404);
      expect(
        refusal.reason,
        contains(said),
        reason:
            'the sentence the child wrote is the whole point — a caller told only that there is no '
            'record learns nothing it did not already have',
      );
      expect(
        refusal.reason,
        contains(refused),
        reason: 'a caller holding several accepted runs has to know which of them this is about',
      );
    });

    test('an identifier nobody issued keeps the answer it has always had', () async {
      final Refused refusal = await asks(neverIssued);

      expect(refusal.status, 404);
      expect(
        refusal.reason,
        'no run is called "$neverIssued"',
        reason:
            'the sentence itself and not merely a 404 — a door that carried the words of the run '
            'above into this answer as well would have removed nothing',
      );
    });
  });

  test('a run that has a record is answered from it, and the run root is not opened', () async {
    store.runs.add(
      runRecord(id: refused, program: 'deploy-branch', mode: Mode.run, fingerprint: 'f1'),
    );

    final ApiResponse answer = await door().call(ApiRequest('GET', Uri.parse('/runs/$refused')));

    expect(answer, isA<Answered>());
    expect(
      startup.asked,
      isEmpty,
      reason:
          'the record is the answer, and a file opened per read of a run that has one is a file '
          'opened for every read this door serves',
    );
  });
}

/// The run root, as the door reads it: a reason per run that refused before writing a header.
///
/// It records what it was asked about as well as what it answered, because a door that reads the
/// run root for a run whose record it already has is doing per-request file work for nothing, and an
/// answer that happens to be right proves nothing about that.
final class RefusalsAtStartup {
  /// Holds [said], the reason each run left behind, by run identifier.
  RefusalsAtStartup(this.said);

  /// What each run that refused wrote, by run identifier.
  final Map<String, String> said;

  /// The runs this was asked about, in order.
  final List<String> asked = <String>[];

  /// What run [id] said, or null where it left nothing.
  Future<String?> of(RunId id) async {
    asked.add(id.value);
    return said[id.value];
  }
}
