/// What the release program does, decided over a git it is handed rather than one it starts.
///
/// Two things happen here and they are deliberately unequal. [ReleaseCommand.show] READS: it asks
/// git for the tags on the remote and for what HEAD is, and writes a screen. [ReleaseCommand.release]
/// is the only thing in this repository that WRITES to a remote, and it writes exactly one thing — a
/// tag — because .github/workflows/release.yml triggers on a pushed tag and on nothing else.
///
/// A FAILED READ IS NEVER AN EMPTY REMOTE. `git ls-remote` answering non-zero and a repository with
/// no tags produce the same empty list, and one of them means "nothing has been released" while the
/// other means nothing at all — so the status is read before the output is, and a failed read
/// refuses instead of proposing a first release to somebody who already released 1.4.2.
library;

import 'release_git.dart';
import 'release_report.dart';
import 'release_tag_filter.dart';
import 'release_versions.dart';

/// The release program's two acts, over a [Git] and against one remote.
final class ReleaseCommand {
  /// Asks [git], holds what is typed against [filter], and reads and writes tags on [remote].
  const ReleaseCommand({
    required this.git,
    required this.filter,
    this.declaredVersion,
    this.remote = 'origin',
  });

  /// The git the commands are run through.
  final Git git;

  /// Which tags start a release, as .github/workflows/release.yml states it.
  final TagFilter filter;

  /// The version pubspec.yaml declares this package at, offered as the first release.
  final String? declaredVersion;

  /// The remote whose tags are the releases of this binary.
  final String remote;

  /// What has been released, what a release would name, and what could come next — changing nothing.
  Future<ReleaseOutcome> show() async {
    if (filter.unreadable case final String why) {
      return ReleaseOutcome.refused(why);
    }
    final GitAnswer tags = await git.run(<String>['ls-remote', '--tags', remote]);
    if (!tags.isGreen) {
      return ReleaseOutcome.refused(_theTagsCouldNotBeRead(tags));
    }
    final GitAnswer branch = await git.run(<String>['rev-parse', '--abbrev-ref', 'HEAD']);
    final GitAnswer commit = await git.run(<String>['rev-parse', '--short', 'HEAD']);
    if (!branch.isGreen || !commit.isGreen) {
      return ReleaseOutcome.refused(
        'this checkout could not say which commit HEAD is at, so a release could not say what it '
        'would name — git said: ${_quoted(branch.isGreen ? commit : branch)}',
      );
    }
    return ReleaseOutcome.shown(
      listingOf(
        Releases.ofTags(tagNamesIn(tags.output), filter: filter),
        filter: filter,
        declaredVersion: declaredVersion,
        remote: remote,
        branch: _firstLineOf(branch),
        commit: _firstLineOf(commit),
      ),
    );
  }

  /// Pushes the tag [typed] names, or refuses and touches nothing.
  ///
  /// The filter is asked before the remote is: a tag that would start nothing is answered without a
  /// network at all, and the person is told where in what they typed the filter stopped reading.
  Future<ReleaseOutcome> release(String typed) async {
    if (filter.refusalFor(typed) case final String refusal) {
      return ReleaseOutcome.refused(refusal);
    }

    final GitAnswer tags = await git.run(<String>['ls-remote', '--tags', remote]);
    if (!tags.isGreen) {
      return ReleaseOutcome.refused(_theTagsCouldNotBeRead(tags));
    }
    if (Releases.ofTags(tagNamesIn(tags.output), filter: filter).holds(typed)) {
      return ReleaseOutcome.refused(
        '$typed has already been released — it is a tag on $remote, and a second tag of one name is '
        'a release nobody could tell from the first one',
      );
    }

    final GitAnswer tagged = await git.run(<String>['tag', typed]);
    if (!tagged.isGreen) {
      return ReleaseOutcome.refused(
        'the tag $typed could not be created in this checkout, so nothing was pushed — git said: '
        '${_quoted(tagged)}',
      );
    }
    final GitAnswer pushed = await git.run(<String>['push', remote, 'refs/tags/$typed']);
    if (!pushed.isGreen) {
      return ReleaseOutcome.refused(
        '$remote refused the tag $typed, so no release was started — git said: ${_quoted(pushed)}. '
        'The tag exists in this checkout; `git tag -d $typed` removes it again',
      );
    }
    return ReleaseOutcome.pushed(tag: typed, remote: remote);
  }

  String _theTagsCouldNotBeRead(GitAnswer answer) =>
      'the tags on $remote could not be read, so what has been released is unknown and an empty '
      'answer must not be read as an empty remote — git said: ${_quoted(answer)}';

  static String _quoted(GitAnswer answer) =>
      answer.lines.isEmpty ? '(nothing at all)' : answer.lines.join(' / ');

  static String _firstLineOf(GitAnswer answer) => answer.lines.isEmpty ? '' : answer.lines.first;
}
