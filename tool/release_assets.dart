/// What a release of this repository carries, and the name each file is attached under.
///
/// TWO FILES AND NOT ONE, because tool/build.dart writes two executables and a machine needs both:
/// `ansiwise` runs a declared program, `ansiwise-rest` serves the REST surface and starts a run by
/// invoking `ansiwise` standing beside it (bin/ansiwise_rest.dart, `deploymentToolBeside`). A
/// machine that received one of the two comes up with a service that answers and runs nothing.
///
/// THE NAME IS THE BINARY, THE TAG AND THE SYSTEM, in that order, and the leading part is exactly
/// the name the binary carries on the machine. That is what lets ONE address compose both files:
/// `<name>-<version>-linux-x64` under the release named `<version>`, so a fetcher fills in the
/// binary it wants and the version it pinned and needs no second setting. hostyour-manager's
/// ANSIWISE_DOWNLOAD_URL carries `<version>` today (server/kernel/config.ts:147 refuses a URL
/// without it) and takes a `<name>` beside it to reach the second file; two settings, one URL each,
/// would let two of them name two different releases, and then what stands on a machine is no
/// longer what the one pin says.
///
/// WHY EACH FILE IS AN EXECUTABLE AND NOT AN ARCHIVE HOLDING BOTH: place-ansiwise unpacks nothing —
/// it runs `curl -fsSL` and `install -m0755` on what came back — and digita-deploy's
/// `install_pinned_tool` row fetches a file as well. An archive would move unpacking into every
/// fetcher for one fetch saved.
library;

import 'build.dart' show binaries;

/// The file a release named [tag] carries for the binary named [binary].
///
/// [binary] is a key of [binaries] — the name tool/build.dart writes and the name the binary is
/// found under on a machine. It is spelled here so that what tool/release.dart tells a person to
/// expect, what .github/workflows/release.yml attaches, and what hostyour-manager and digita-deploy
/// fetch are held against each other by a check rather than by three people reading three files.
String assetFor({required String binary, required String tag}) => '$binary-$tag-linux-x64';

/// Every file a release named [tag] carries, in the order tool/build.dart builds them.
List<String> assetsFor(String tag) => <String>[
  for (final String binary in binaries.keys) assetFor(binary: binary, tag: tag),
];

/// The binaries [workflow] builds and attaches, as its top-level `env.BINARIES` lists them.
///
/// READ AS LINES rather than as YAML, because everything under tool/ imports nothing but `dart:` and
/// this directory — the gate that resolves this tree is a program of the same directory and has to
/// start on a clone where no package has been resolved. A file that states no such key answers with
/// nothing, which is a set that matches no build and turns the check red rather than green.
List<String> binariesIn(String workflow) {
  const String key = 'BINARIES:';
  bool underEnv = false;
  for (final String line in workflow.split('\n')) {
    final String content = line.trimLeft();
    if (content.isEmpty || content.startsWith('#')) {
      continue;
    }
    if (content.length == line.length) {
      // A key of the workflow itself. Only the one that names the whole file's environment holds
      // the list; a job's or a step's `env` stands indented and is passed over here.
      underEnv = content.startsWith('env:');
      continue;
    }
    if (underEnv && content.startsWith(key)) {
      return content
          .substring(key.length)
          .split(' ')
          .where((String each) => each.isNotEmpty)
          .toList(growable: false);
    }
  }
  return const <String>[];
}
