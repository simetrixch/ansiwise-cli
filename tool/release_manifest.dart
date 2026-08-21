/// The file this package declares its version in, as something the release program is handed.
///
/// The same split tool/release_git.dart makes: what the release program DECIDES is one thing and
/// writing a file on this operating system is another. It is what lets the deciding half be driven
/// by a check — including the half that bumps — on a machine where no pubspec.yaml is edited, and
/// what was written is then readable as a value.
///
/// ONE PACKAGE IS ONE MANIFEST HERE. release.sh, the shape this program follows, walks a workspace
/// and bumps every package in lockstep; this repository holds a single Dart package — the gate names
/// it, `ci: OK — every check green for 1 package(s): ansiwise_cli` — so the lockstep is one file, and
/// a walker over one file would be a mechanism with nothing to walk.
library;

import 'dart:io';

/// A file declaring the version of this package.
abstract interface class Manifest {
  /// Where it is, as a refusal names it.
  String get path;

  /// What it holds, or null when there is no such file.
  String? get text;

  /// Replaces what it holds with [text].
  void write(String text);
}

/// pubspec.yaml, as a file of the machine the release program is running on.
final class PubspecFile implements Manifest {
  /// The pubspec.yaml at [path].
  const PubspecFile(this.path);

  @override
  final String path;

  @override
  String? get text {
    final File file = File(path);
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  @override
  void write(String text) => File(path).writeAsStringSync(text);
}
