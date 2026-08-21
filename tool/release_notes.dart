/// The release page of one tag, written where the release is made: in the workflow.
///
/// ```
/// dart run tool/release_notes.dart <tag> <file>
/// ```
///
/// It writes the notes for the tag into the file and prints one line — `prerelease=true` or
/// `prerelease=false` — which .github/workflows/release.yml appends to `$GITHUB_OUTPUT` and reads
/// back to decide whether `gh release create` is given `--prerelease`. The two travel together
/// because both are read out of the same tag, and a step that read the channel a second way could
/// mark a release the notes contradict.
///
/// WHY A PROGRAM AND NOT A LINE OF SHELL IN THE WORKFLOW. The channel and the previous release are
/// read out of the tag grammar, which lives in tool/release_versions.dart and is checked there; a
/// `sed` in a `run:` block would be a second reading of the same grammar that no check can reach.
/// This one is driven by test/checks/release_test.dart over a scripted git.
///
/// IT IMPORTS NOTHING BUT `dart:` AND THIS DIRECTORY, like everything else under tool/, so the job
/// that runs it needs the SDK and no `dart pub get`.
library;

import 'dart:io';

import 'gate/paths.dart';
import 'release_git.dart';
import 'release_notes_command.dart';
import 'release_report.dart';
import 'release_tag_filter.dart';

/// Writes the notes of the tag named in [arguments], or refuses and writes nothing.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'release-notes: FAIL — ${arguments.length} arguments were given, and this program takes two: '
      'the tag the release is named by, and the file to write its notes into',
    );
    exit(2);
  }
  final String tag = arguments.first;
  final File notes = File(arguments.last);

  final Directory package = packageOfToolScript(Platform.script);
  final File workflow = File('${repositoryOf(package).path}/$releaseWorkflowPath');
  if (!workflow.existsSync()) {
    stderr.writeln(
      'release-notes: FAIL — ${workflow.path} is not in this checkout, so nothing here can say '
      'which of the tags standing here are releases this one follows',
    );
    exit(1);
  }

  final NotesOutcome outcome = await ReleaseNotesCommand(
    git: const GitOnThisMachine(),
    filter: TagFilter.ofWorkflow(workflow.readAsStringSync()),
  ).of(tag);

  if (outcome.refusal case final String why) {
    stderr.writeln('release-notes: FAIL — $why');
    exit(1);
  }
  notes.writeAsStringSync(outcome.page);
  stdout.writeln('prerelease=${outcome.isPreRelease}');
}
