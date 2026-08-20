/// The process the launcher-options check has the launcher start, in place of this binary.
///
/// **Why the argv has to be taken from a real start.** `DetachedLauncher` composes the child's
/// command line inside its own call to `Process.start`, and hands back a run identifier and nothing
/// else. Reading the composed words out of its source would be a second reading of an interface,
/// which is the defect class the check exists for; so the launcher is run, and what it started
/// writes down what it was handed.
///
/// It is copied into the directory the launcher is told to work in and named as the program, because
/// the first word the launcher composes is the program and the executable it starts is the Dart
/// toolchain. Nothing about the OPTIONS it composes depends on either: the run identifier, the run
/// it continues, the gates it waives and whether there is anything to send over standard input are
/// what decide them.
///
/// It imports nothing but `dart:`, so it runs from a directory where no package has been resolved.
library;

import 'dart:convert';
import 'dart:io';

/// What the composed argv is written to, in the directory the launcher started the child in.
const String composedArgvFileName = 'composed-argv.json';

/// The name it is written under before it is put in place.
const String pendingArgvFileName = '$composedArgvFileName.writing';

Future<void> main(List<String> argv) async {
  // DRAINED BEFORE ANYTHING IS WRITTEN. The launcher writes the run's envelope to this process's
  // standard input and closes it; a child that had already exited would leave that write on a pipe
  // nobody holds open, and the check would report a launcher that cannot start rather than an argv.
  await stdin.drain<void>();

  // WRITTEN BESIDE AND RENAMED OVER, which is what the run records do and for the same reason. The
  // reader is watching for this file and has nothing else to wait on, so a file created empty and
  // filled a moment later is a reader holding half a word — it read one that was not there yet.
  final File pending = File(pendingArgvFileName)..writeAsStringSync(jsonEncode(argv));
  pending.renameSync(composedArgvFileName);
}
