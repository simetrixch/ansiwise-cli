/// Writing `lib/service_unit.dart` out of the unit file the binary installs itself under.
///
/// **Why the unit is turned into source at all.** Its `ExecStart` is composed from this binary's
/// OWN option names — `--listen`, `--service-token-file`, `--answers` — so a unit kept anywhere else
/// is a second statement of an interface only this repository decides. Rename an option here and a
/// unit rendered from a template one repository over goes on writing the old one: the service then
/// starts, the process refuses the option it was handed, and what reports it is a dead service on a
/// machine nobody is watching. Carried as source, the unit is compiled against the same names, and
/// the check that reads it goes red in this tree instead.
///
/// **Why a unit FILE and not a string composed in Dart.** `ansiwise.service` is the text the service
/// manager reads, in the shape it reads it, so it can be diffed against what stands on a machine and
/// its base name is the name the service is known by. A Dart literal would be none of those things.
///
/// **Why the value is written as one escaped literal per line.** The repository is edited on Windows
/// and the unit runs on Linux. A literal spanning real newlines would carry whatever line ending the
/// working copy happens to hold into the file the service manager reads; a line ending written as
/// `\n` inside a single-line literal cannot, whatever the source file's own endings are.
///
/// This program is a gate program: it imports nothing but `dart:`, so it starts on a fresh clone
/// where no package has been resolved.
library;

import 'dart:io';

/// The unit file this repository owns, relative to the package root.
///
/// Its base name is the name the service manager knows the service by, so the file, the unit and
/// the name a `systemctl` line mentions are one value and cannot come apart.
const String serviceUnitFileName = 'ansiwise.service';

/// What a unit file that cannot be turned into source says about itself.
final class ServiceUnitRefused implements Exception {
  /// Refuses [because].
  const ServiceUnitRefused(this.because);

  /// What is wrong with the unit file, in the words whoever wrote it reads.
  final String because;

  @override
  String toString() => because;
}

/// The source of `lib/service_unit.dart` for the unit text [unit].
///
/// Written whole rather than patched, so the file on disk is a function of `ansiwise.service` and of
/// nothing else — which is what lets a check compare the two and report a hand edit.
///
/// Throws [ServiceUnitRefused] where [unit] holds nothing: a binary carrying an empty unit would
/// place a file the service manager rejects, on a machine where nobody is watching it start.
String serviceUnitSource(String unit) {
  final String text = unit.replaceAll('\r\n', '\n');
  if (text.trim().isEmpty) {
    throw const ServiceUnitRefused(
      'the unit file holds nothing, and it is the text the binary places on a machine — a service '
      'manager reads an empty unit as a unit that starts nothing',
    );
  }

  final List<String> lines = text.split('\n');
  // A file ends with a newline, which splits into a last empty element. Every line below is written
  // with its own trailing `\n`, so keeping that element would add a second one.
  if (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }

  final StringBuffer out = StringBuffer()
    ..writeln('// GENERATED from $serviceUnitFileName by tool/build.dart. Do not edit.')
    ..writeln('//')
    ..writeln("// The unit's ExecStart is composed from this binary's own option names, so a unit")
    ..writeln('// kept anywhere else is a second statement of an interface only this repository')
    ..writeln('// decides. It travels inside the binary, and this file is how it gets in.')
    ..writeln('//')
    ..writeln('// The text is $serviceUnitFileName. Edit that and build; a check reports a copy')
    ..writeln('// here that says anything else.')
    ..writeln('library;')
    ..writeln()
    ..writeln('/// The name the service manager knows the service by.')
    ..writeln('///')
    ..writeln("/// The unit file's own base name, so the file this repository keeps, the file a")
    ..writeln('/// machine holds and the name a `systemctl` line mentions are one value.')
    ..writeln("const String serviceUnitName = '$serviceUnitFileName';")
    ..writeln()
    ..writeln('/// The unit the binary installs itself under, slots and all.')
    ..writeln('const String serviceUnit =');
  for (int i = 0; i < lines.length; i++) {
    // Adjacent string literals are one string in Dart, so the value is written a line at a time and
    // the terminator goes on the last of them — which is where the formatter puts it.
    final String end = i == lines.length - 1 ? ';' : '';
    out.writeln("    '${_escaped(lines[i])}\\n'$end");
  }
  return out.toString();
}

/// [line] as the body of a single-quoted Dart string.
///
/// The backslash first, or every escape added after it would be escaped a second time.
String _escaped(String line) =>
    line.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$');

/// Writes `lib/service_unit.dart` of [package] from its unit file, and says whether it changed.
///
/// Returns true where the file on disk was not already what the unit says, so a build can report
/// that it wrote one rather than leaving it to be noticed in a diff.
bool writeServiceUnitSource(String package) {
  final File unit = File('$package/$serviceUnitFileName');
  if (!unit.existsSync()) {
    throw ServiceUnitRefused(
      'there is no $serviceUnitFileName in $package, and it is the unit the binary places on a '
      'machine to survive a restart',
    );
  }
  final String source = serviceUnitSource(unit.readAsStringSync());
  final File target = File('$package/lib/service_unit.dart');
  if (target.existsSync() && target.readAsStringSync().replaceAll('\r\n', '\n') == source) {
    return false;
  }
  target.writeAsStringSync(source);
  return true;
}
