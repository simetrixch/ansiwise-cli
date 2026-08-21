/// The release of this binary, as a surface a person decides on.
///
/// ```
/// dart run tool/release.dart              what has been released, and what could come next
/// dart run tool/release.dart <version>    push the tag <version>, which starts the release
/// dart run tool/release.dart help         what a release is, and what it is not
/// ```
///
/// It never picks a version. Run with no arguments it reads the tags on origin, shows what has been
/// released, names the commit a release would carry and PROPOSES what could come next — and pushes
/// nothing. The version is then typed by hand, which is the whole point: which release a change
/// deserves is a decision, and a program that took it would hide it.
///
/// WHAT IT DOES WHEN A VERSION IS TYPED IS PUSH ONE TAG. Nothing is built here.
/// .github/workflows/release.yml triggers on that tag, runs the gate, compiles the binary for
/// linux-x64 and attaches it to a GitHub Release named by the tag.
///
/// WHICH VERSIONS IT ACCEPTS IS READ, NOT RESTATED. The workflow's `on.push.tags` is the only thing
/// that decides whether a tag starts anything, so it is read out of that file on every run —
/// tool/release_tag_filter.dart — and this program carries no grammar of its own. What is decided is
/// in tool/release_command.dart, the order a screen lists releases in is in
/// tool/release_versions.dart, what a person reads is in tool/release_report.dart, and git is
/// reached through tool/release_git.dart. This is the composition root: the arguments, the two files
/// that state anything about versions, the real git, and the status a person's shell reads.
library;

import 'dart:io';

import 'gate/paths.dart';
import 'release_command.dart';
import 'release_git.dart';
import 'release_report.dart';
import 'release_tag_filter.dart';
import 'release_versions.dart';

/// Shows or starts a release, and answers non-zero when nothing was done.
Future<void> main(List<String> arguments) async {
  if (arguments case <String>['help' || '--help' || '-h']) {
    stdout.writeln(helpText);
    return;
  }
  if (arguments.length > 1) {
    stderr.writeln(
      'release: FAIL — ${arguments.length} arguments were given, and this program takes one at '
      'most: the version to release, or `help`',
    );
    exit(2);
  }

  final Directory package = packageOfToolScript(Platform.script);
  final File workflow = File('${repositoryOf(package).path}/$releaseWorkflowPath');
  if (!workflow.existsSync()) {
    stderr.writeln(
      'release: FAIL — ${workflow.path} is not in this checkout, so nothing here can say which tag '
      'starts a release',
    );
    exit(1);
  }
  final File manifest = File('${package.path}/pubspec.yaml');

  final ReleaseCommand command = ReleaseCommand(
    git: const GitOnThisMachine(),
    filter: TagFilter.ofWorkflow(workflow.readAsStringSync()),
    declaredVersion: manifest.existsSync() ? declaredVersionIn(manifest.readAsStringSync()) : null,
  );

  final ReleaseOutcome outcome = arguments.isEmpty
      ? await command.show()
      : await command.release(arguments.single);

  (outcome.isGreen ? stdout : stderr).writeln(outcome.text);
  exitCode = outcome.isGreen ? 0 : 1;
}
