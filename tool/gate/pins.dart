/// The one toolchain the checks of this repository are true against.
///
/// The version is pinned so a red run is a finding in the tree and not a tool that moved underneath
/// it. It was read from the source named beside it, on the date given: a version recalled from
/// memory is as old as whoever recalled it, which is why the source is part of the record.
///
/// The pin names a requirement, not an installation: tool/gate/version_guard.dart reads the SDK the
/// gate is running on and refuses the run where the two differ, naming what was found and what was
/// expected.
library;

/// The Dart SDK the checks are true against, and the only tool the gate starts.
///
/// storage.googleapis.com/dart-archive/channels/stable/release/latest/VERSION — read 2026-08-17,
/// which answered version 3.13.0, released 2026-08-05, revision da6595cd6bb5. The previous pin was
/// 3.12.2, read from the same source on 2026-08-08; the toolchain on the machine moved under it and
/// this guard refused every run, which is the guard working rather than failing.
const String dartVersion = '3.13.0';
