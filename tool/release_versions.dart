/// What has been released, in what order, and what could be released next.
///
/// A release of this repository IS a tag on origin: .github/workflows/release.yml triggers on a
/// pushed tag and on nothing else, and the GitHub Release it then creates is named by that tag. So
/// the tags are what is read, and which of them is a release is asked of the [TagFilter] read from
/// that workflow — never decided here.
///
/// WHAT IS SPELLED HERE IS AN ORDER, NOT A GRAMMAR. A filter can say whether a tag starts a release;
/// it cannot say which of two releases is the later one, and a screen that proposes a next version
/// has to know. So the three numbers a released tag begins with are read and compared, a tag with
/// nothing after those numbers stands later than one carrying something after them, and what does
/// stand there is compared part by part — numerically where both parts are digits, so `-beta.10`
/// is later than `-beta.2` rather than earlier as text alone would have it. Nothing in this file
/// decides what may be released; it decides what a list is sorted by.
///
/// A TAG THE ORDER CANNOT READ IS CARRIED THROUGH, NOT DROPPED. Whoever is deciding a version has to
/// see everything already standing on the remote, including the thing this file cannot place.
library;

import 'release_tag_filter.dart';

/// A tag on origin the filter accepts, read far enough to be ordered against the others.
final class ReleasedTag implements Comparable<ReleasedTag> {
  const ReleasedTag._({
    required this.tag,
    required this.major,
    required this.minor,
    required this.patch,
    required this.after,
  });

  /// [tag] read as three numbers and whatever follows them, or null when its numbers cannot be read.
  static ReleasedTag? read(String tag) {
    final RegExpMatch? match = _numbers.firstMatch(tag);
    if (match == null) {
      return null;
    }
    final List<int> read = <int>[
      for (final int group in <int>[1, 2, 3])
        if (match.group(group) case final String digits)
          if (int.tryParse(digits) case final int number) number,
    ];
    if (read.length != 3) {
      return null;
    }
    return ReleasedTag._(
      tag: tag,
      major: read[0],
      minor: read[1],
      patch: read[2],
      after: tag.substring(match.end),
    );
  }

  /// The tag as it stands on the remote.
  final String tag;

  /// The first number.
  final int major;

  /// The second number.
  final int minor;

  /// The third number.
  final int patch;

  /// What stands after the third number — `-beta.2` for `0.1.0-beta.2` — and empty for a release.
  final String after;

  /// Whether something stands after the numbers, which is what a pre-release is.
  bool get isPreRelease => after.isNotEmpty;

  /// The release this leads to: `0.1.0-beta.2` leads to `0.1.0`.
  String get theRelease => '$major.$minor.$patch';

  /// A fix to what this release does.
  String get nextPatch => '$major.$minor.${patch + 1}';

  /// Something this release did not do.
  String get nextMinor => '$major.${minor + 1}.0';

  /// A break with how this release was used.
  String get nextMajor => '${major + 1}.0.0';

  @override
  int compareTo(ReleasedTag other) {
    for (final (int mine, int theirs) in <(int, int)>[
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final int decided = mine.compareTo(theirs);
      if (decided != 0) {
        return decided;
      }
    }
    if (after.isEmpty || other.after.isEmpty) {
      return after.isEmpty == other.after.isEmpty ? 0 : (after.isEmpty ? 1 : -1);
    }
    final List<String> mine = after.split('.');
    final List<String> theirs = other.after.split('.');
    for (int index = 0; index < mine.length && index < theirs.length; index++) {
      final int decided = _comparedParts(mine[index], theirs[index]);
      if (decided != 0) {
        return decided;
      }
    }
    return mine.length.compareTo(theirs.length);
  }

  static int _comparedParts(String mine, String theirs) {
    final int? number = int.tryParse(mine);
    final int? other = int.tryParse(theirs);
    if (number != null && other != null) {
      return number.compareTo(other);
    }
    return mine.compareTo(theirs);
  }

  static final RegExp _numbers = RegExp(r'^([0-9]+)\.([0-9]+)\.([0-9]+)');
}

/// A version that could be typed next, and what makes it the obvious one.
///
/// The reason travels with the version because three numbers on their own say nothing about why they
/// are being offered, and the person reading them is deciding rather than picking.
final class Proposal {
  /// [version] is proposed [because].
  const Proposal({required this.version, required this.because});

  /// What could be typed.
  final String version;

  /// Why it is offered.
  final String because;
}

/// The tags standing on origin, sorted into what has been released and what has not.
final class Releases {
  /// [releases] in ascending order, with [otherTags] holding what would start no release.
  const Releases({required this.releases, required this.otherTags});

  /// What [tags] are, asked of [filter] and of nothing else.
  factory Releases.ofTags(Iterable<String> tags, {required TagFilter filter}) {
    final List<ReleasedTag> releases = <ReleasedTag>[];
    final List<String> otherTags = <String>[];
    for (final String tag in tags) {
      final ReleasedTag? released = filter.accepts(tag) ? ReleasedTag.read(tag) : null;
      if (released == null) {
        otherTags.add(tag);
      } else {
        releases.add(released);
      }
    }
    releases.sort();
    otherTags.sort();
    return Releases(releases: releases, otherTags: otherTags);
  }

  /// Every release, oldest first.
  final List<ReleasedTag> releases;

  /// The tags on origin that would have started no release, and the ones whose numbers this order
  /// cannot read.
  final List<String> otherTags;

  /// The latest release, or null when nothing has been released.
  ReleasedTag? get latest => releases.isEmpty ? null : releases.last;

  /// Whether [tag] already stands on the remote, so that pushing it would be a second release of one
  /// name.
  bool holds(String tag) =>
      releases.any((ReleasedTag each) => each.tag == tag) || otherTags.contains(tag);

  /// The versions that could come next — offered, and none of them chosen.
  ///
  /// Nothing released yet is the first release, and the only version this repository states about
  /// itself is the one pubspec.yaml declares it at, so [declaredVersion] is what is offered and
  /// nothing is invented when there is none. After a pre-release the obvious next thing is the
  /// release it leads to. After a release there are three directions and no way for a program to
  /// know which of them a change deserves — that is exactly the decision this program refuses to
  /// take — so all three are shown and the person types one of them or something else entirely.
  List<Proposal> proposals({required String? declaredVersion}) {
    final ReleasedTag? released = latest;
    if (released == null) {
      return <Proposal>[
        if (declaredVersion != null)
          Proposal(
            version: declaredVersion,
            because: 'the first release — the version pubspec.yaml declares this package at',
          ),
      ];
    }
    if (released.isPreRelease) {
      return <Proposal>[
        Proposal(version: released.theRelease, because: 'the release ${released.tag} leads to'),
      ];
    }
    return <Proposal>[
      Proposal(
        version: released.nextPatch,
        because: 'the next patch — a fix to what ${released.tag} does',
      ),
      Proposal(
        version: released.nextMinor,
        because: 'the next minor — something ${released.tag} did not do',
      ),
      Proposal(
        version: released.nextMajor,
        because: 'the next major — a break with how ${released.tag} was used',
      ),
    ];
  }
}

/// The version [pubspec] declares this package at, or null when it declares none.
///
/// It is READ rather than restated for the same reason the filter is: pubspec.yaml is where this
/// package states its own version, and a first release proposed from a number typed here as well
/// would be two statements of one thing.
String? declaredVersionIn(String pubspec) => _declaredVersion.firstMatch(pubspec)?.group(1)?.trim();

final RegExp _declaredVersion = RegExp(r'^version:[ \t]*(\S+)[ \t]*$', multiLine: true);
