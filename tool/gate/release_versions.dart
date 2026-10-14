/// What a release tag is made of.
///
/// A release of this repository IS a tag on origin: the publish pipeline on the owner's master
/// builds the binaries on a pushed release tag, and Zot holds them under that tag. The binaries
/// answer it through lib/release_stamp.dart, which tool/gate/release_stamp.dart writes only for a
/// tag this file reads.
///
/// THE TAG IS `<major>.<minor>.<patch>-<channel>-<ts14>`, one grammar for every release of
/// everything, and the file that owns it is hostyour-manager/shared/release.ts:22. The ts14 is the
/// UTC minute and second the tag was composed at, which is what makes two releases of one version on
/// one channel two tags instead of one name pushed twice.
///
/// WHAT THIS FILE STATES BESIDE THE SHAPE. [ReleasedTag.read] reads the shape of a tag, and a
/// number carries no leading zero, which that shape does not say: [numbersRefusalFor] is the one
/// place that closes it, because `01.2.3-stable-…` would be stamped into a binary and then refused
/// by hostyour-manager/shared/release.ts:22 as no release at all.
library;

/// Why [version] must not be released though its shape reads as three numbers, or null when it may
/// be.
///
/// THE ONE THING `[0-9]+` CANNOT SAY. [ReleasedTag.read] reads each number as `[0-9]+`, so `01.2.3`
/// reads and is no version: hostyour-manager/shared/release.ts:22 refuses it, and a binary stamped
/// with a tag the platform cannot parse answers a release nothing downstream can read. Everything
/// else about the shape of a version — how many numbers, what stands between them — is left to the
/// reader of the shape, so that no version is refused twice for one reason.
String? numbersRefusalFor(String version) {
  for (final String number in version.split('.')) {
    if (number.length > 1 && number.startsWith('0') && _readsAsANumber(number)) {
      return '"$version" is no version: "$number" carries a leading zero, and '
          'hostyour-manager/shared/release.ts:22 reads each number as 0 or a digit from 1 to 9 '
          'followed by any digits';
    }
  }
  return null;
}

/// Whether [segment] is the digits a number is written with and nothing else.
///
/// A segment carrying anything but digits is not a number with a leading zero — it is a version the
/// reader of the shape refuses, and the sentence above would name the wrong reason. `0.1.0+7`
/// splits into `0`, `1`, `0+7`.
bool _readsAsANumber(String segment) =>
    segment.runes.every((int rune) => rune >= 0x30 && rune <= 0x39);

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
