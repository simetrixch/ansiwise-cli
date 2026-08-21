/// What the release notes of one tag are, decided over a git the program is handed.
///
/// WHY THIS EXISTS AT ALL, and why `gh release create --generate-notes` was not enough. Generated
/// notes are built from the pull requests merged between two releases and the new contributors among
/// them. This repository has no pull requests: `git log --merges` over its whole history answers
/// with nothing, and every commit is a commit on master. So generated notes had nothing to list and
/// the page carried a compare link and no line about what changed — which is the empty page the
/// release notes are supposed to replace. Unique tags per release did not change that: the tag
/// grammar decides how many releases there are, not where the sentences come from.
///
/// WHAT IT READS. `git tag --list` for what has been released before this one — held against the
/// same [TagFilter] read from .github/workflows/release.yml that decides everything else here — and
/// `git log --format=%s <previous>..<tag>` for the commit subjects in between. The job that runs it
/// checks out with `fetch-depth: 0`, because a shallow checkout has neither the tags nor the range.
///
/// WHAT IT REFUSES. A tag whose parts cannot be read, and a tag on a channel [ReleaseChannel] does
/// not rank. Both would otherwise end as a release marked by a guess: an unranked channel is not
/// knowably a pre-release, and publishing it plainly would tell everyone reading the releases page
/// that an alpha is finished.
library;

import 'release_git.dart';
import 'release_report.dart';
import 'release_tag_filter.dart';
import 'release_versions.dart';

/// The notes of one release, read from the history behind its tag.
final class ReleaseNotesCommand {
  /// Asks [git] for the history, and [filter] which of the tags it names are releases.
  const ReleaseNotesCommand({required this.git, required this.filter});

  /// The git the commands are run through.
  final Git git;

  /// Which tags are releases, as .github/workflows/release.yml states it.
  final TagFilter filter;

  /// The notes for [tag], or a refusal naming what could not be read.
  Future<NotesOutcome> of(String tag) async {
    if (filter.unreadable case final String why) {
      return NotesOutcome.refused(why);
    }
    if (filter.refusalFor(tag) case final String refusal) {
      return NotesOutcome.refused(refusal);
    }
    final ReleasedTag? release = ReleasedTag.read(tag);
    if (release == null) {
      return NotesOutcome.refused(
        '"$tag" is a tag $releaseWorkflowPath triggers on, and its parts could not be read as '
        '<major>.<minor>.<patch>-<channel>-<ts14> — so nothing here can say which channel it is on',
      );
    }
    final ReleaseChannel? channel = release.channel;
    if (channel == null) {
      return NotesOutcome.refused(
        '"$tag" is on the channel "${release.channelName}", which is not one of '
        '${ReleaseChannel.spelled.join(', ')} — nothing here can say whether that is a pre-release, '
        'and a release marked by a guess tells everyone reading the releases page something nobody '
        'checked. $releaseWorkflowPath and tool/release_versions.dart disagree about the channels, '
        'and one of the two is wrong',
      );
    }

    final GitAnswer tags = await git.run(<String>['tag', '--list']);
    if (!tags.isGreen) {
      return NotesOutcome.refused(
        'the tags of this checkout could not be read, so what this release follows is unknown and '
        'an empty answer must not be read as a first release — git said: ${_quoted(tags)}',
      );
    }
    final ReleasedTag? previous = _theOneBefore(release, _linesOf(tags.output));

    final GitAnswer log = await git.run(<String>[
      'log',
      '--format=%s',
      if (previous == null) tag else '${previous.tag}..$tag',
    ]);
    if (!log.isGreen) {
      return NotesOutcome.refused(
        'the commits behind $tag could not be read, so the notes would say nothing changed when '
        'nobody looked — git said: ${_quoted(log)}. A checkout without `fetch-depth: 0` has neither '
        'the tags nor the range',
      );
    }

    return NotesOutcome.written(
      page: notesFor(
        release: release,
        channel: channel,
        previous: previous?.tag,
        subjects: _linesOf(log.output),
      ),
      isPreRelease: channel.isPreRelease,
    );
  }

  /// The latest release standing before [release] among [tags], or null when it is the first.
  ReleasedTag? _theOneBefore(ReleasedTag release, List<String> tags) {
    ReleasedTag? before;
    for (final ReleasedTag each in Releases.ofTags(tags, filter: filter).releases) {
      if (each.compareTo(release) < 0) {
        before = each;
      }
    }
    return before;
  }

  static List<String> _linesOf(String output) => output
      .split('\n')
      .map((String line) => line.trim())
      .where((String line) => line.isNotEmpty)
      .toList(growable: false);

  static String _quoted(GitAnswer answer) =>
      answer.lines.isEmpty ? '(nothing at all)' : answer.lines.join(' / ');
}
