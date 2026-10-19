/// What a release tag is made of.
///
/// A release of this repository IS a tag on origin: the publish pipeline on the owner's master
/// builds the binaries on a pushed release tag, and Zot holds them under that tag. The binaries
/// answer it through lib/release_stamp.dart, which tool/gate/release_stamp.dart writes only for a
/// tag this file reads.
///
/// THE TAG IS `<major>.<minor>.<patch>-<channel>-<ts14>`, one grammar for every release of
/// everything, and the file that owns it is hostyour-manager/shared/release.ts, as
/// `RELEASE_TAG_RE`. The ts14 is the UTC minute and second the tag was composed at, which is what
/// makes two releases of one version on one channel two tags instead of one name pushed twice.
///
/// WHAT THIS FILE STATES BESIDE THE SHAPE. [ReleasedTag.read] reads the shape of a tag, and what
/// that shape does not say is how each number is written: [numbersRefusalFor] is the one place that
/// closes it, because `01.2.3-stable-…` would be stamped into a binary and then refused by
/// `RELEASE_TAG_RE` as no release at all.
library;

/// Why [version] must not be released though its shape reads as three numbers, or null when it may
/// be.
///
/// THE ONE THING `[0-9]+` CANNOT SAY. [ReleasedTag.read] reads each number as `[0-9]+`, so `01.2.3`
/// reads and is no version: `RELEASE_TAG_RE` of hostyour-manager/shared/release.ts refuses it, and a
/// binary stamped with a tag the platform cannot parse answers a release nothing downstream can
/// read. The major and the minor are 0 or a digit from 1 to 9 followed by any digits. The patch is
/// either that or exactly three digits, leading zeros included (`0.3.000`), the form every version
/// line is written in. Everything else about the shape of a version — how many numbers, what stands
/// after the third — is left to the reader of the shape, so that no version is refused twice for one
/// reason, and one that does not open with three numbers is not judged here at all.
String? numbersRefusalFor(String version) {
  final RegExpMatch? opening = _openingNumbers.firstMatch(version);
  if (opening == null) {
    return null;
  }
  for (final (int group, String position, bool mayBeThreeDigits) in const <(int, String, bool)>[
    (1, 'major', false),
    (2, 'minor', false),
    (3, 'patch', true),
  ]) {
    final String number = opening.group(group)!;
    final bool hasLeadingZero = number.length > 1 && number.startsWith('0');
    if (hasLeadingZero && !(mayBeThreeDigits && number.length == 3)) {
      return '"$version" is no version: the $position "$number" carries a leading zero, and '
          'RELEASE_TAG_RE of hostyour-manager/shared/release.ts reads the major and the minor as 0 '
          'or a digit from 1 to 9 followed by any digits, and the patch as that or as exactly three '
          'digits';
    }
  }
  return null;
}

/// The three numbers a version opens with, and nothing after them: `0.1.0+7` opens with 0, 1 and 0,
/// and the `+7` is not a number with a leading zero but a shape the reader of the shape refuses.
final RegExp _openingNumbers = RegExp(r'^([0-9]+)\.([0-9]+)\.([0-9]+)');

/// A release tag, read for the one part a reader asks of it: its stamp.
final class ReleasedTag {
  const ReleasedTag._(this.stamp);

  /// [tag] read, or null when it does not have the shape of a release tag.
  ///
  /// The channel is read as whatever stands between the two hyphens and is NOT held to the three
  /// channels here: hostyour-manager/shared/release.ts:12 ranks them, and a tag on another channel
  /// is refused by name where that matters.
  static ReleasedTag? read(String tag) {
    final RegExpMatch? match = _parts.firstMatch(tag);
    return match == null ? null : ReleasedTag._(match.group(1)!);
  }

  /// The `yyyyMMddHHmmss` this tag was minted at, as the tag spells it.
  final String stamp;

  static final RegExp _parts = RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+-[^-]+-([0-9]+)$');
}
