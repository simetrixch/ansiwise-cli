import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/starts_ansiwise.dart';

/// release-digests — the digests a release pins are read out of the manifest Zot holds for its tag.
///
/// release/release.sh writes these lines into hostyour-cloud's `clusters/platform/ansiwise.sha256`,
/// and a machine is placed only the bytes they name. So the reading refuses every manifest that
/// does not carry exactly one SHA-256 for every binary of the tag, and nothing else.
///
/// THE PLANTED INNOCENT is case (a): a manifest as the publish pipeline writes it, with both binaries
/// in an unsorted order. THE PLANTED DEFECTS are cases (b) to (g): a binary missing, a digest that
/// is not `sha256:<64 hex>`, a layer titled for another tag, a binary named by another tag only, a
/// binary twice, and a manifest naming no layers. Each must be refused by the function release.sh
/// sources, run here under bash with jq; a missing bash or jq fails the case.
void main() {
  // SKIPPED WHERE THE REPOSITORY'S RULE SAYS SO, printed rather than passed over: every suite that
  // starts a process skips where ANSIWISE_TESTS_MAY_SKIP=1 (test/support_starts_ansiwise_test.dart).
  if (startsAnsiwiseSkip != null) {
    test('release-digests', () {}, skip: startsAnsiwiseSkip);
    return;
  }
  const String tag = '0.8.312-stable-20261014120000';
  const String otherTag = '0.8.311-stable-20261012090928';
  const List<String> binaries = <String>['ansiwise', 'ansiwise-rest'];
  final String hexA = 'a' * 64;
  final String hexB = '0123456789abcdef' * 4;

  test('(a) innocent: one line `<hex>  <title>` per binary, sorted by title', () async {
    final ProcessResult ran = await _manifestDigests(
      _manifest(<(String, String)>[
        ('ansiwise-rest-$tag-linux-x64', 'sha256:$hexB'),
        ('ansiwise-$tag-linux-x64', 'sha256:$hexA'),
      ]),
      tag,
      binaries,
    );

    expect(ran.exitCode, 0, reason: '${ran.stderr}');
    expect(
      '${ran.stdout}',
      '$hexA  ansiwise-$tag-linux-x64\n'
          '$hexB  ansiwise-rest-$tag-linux-x64\n',
    );
  });

  test('(b) defect: a manifest missing one binary is refused, naming it', () async {
    final ProcessResult ran = await _manifestDigests(
      _manifest(<(String, String)>[('ansiwise-$tag-linux-x64', 'sha256:$hexA')]),
      tag,
      binaries,
    );

    expect(ran.exitCode, 1);
    expect('${ran.stderr}', contains('ansiwise-rest-$tag-linux-x64'));
    expect('${ran.stdout}', isEmpty);
  });

  for (final String digest in <String>[
    'sha512:$hexA',
    'sha256:${hexA.substring(1)}',
    'sha256:${hexA.toUpperCase()}',
    hexA,
  ]) {
    test('(c) defect: a layer whose digest is "$digest" is refused', () async {
      final ProcessResult ran = await _manifestDigests(
        _manifest(<(String, String)>[
          ('ansiwise-$tag-linux-x64', digest),
          ('ansiwise-rest-$tag-linux-x64', 'sha256:$hexB'),
        ]),
        tag,
        binaries,
      );

      expect(ran.exitCode, 1);
      expect('${ran.stderr}', contains('SHA-256'));
      expect('${ran.stdout}', isEmpty);
    });
  }

  test('(d) defect: a layer titled for another tag beside both binaries is refused', () async {
    final ProcessResult ran = await _manifestDigests(
      _manifest(<(String, String)>[
        ('ansiwise-$tag-linux-x64', 'sha256:$hexA'),
        ('ansiwise-rest-$tag-linux-x64', 'sha256:$hexB'),
        ('ansiwise-$otherTag-linux-x64', 'sha256:$hexB'),
      ]),
      tag,
      binaries,
    );

    expect(ran.exitCode, 1);
    expect('${ran.stderr}', contains('ansiwise-$otherTag-linux-x64'));
    expect('${ran.stdout}', isEmpty);
  });

  test('(e) defect: a binary named only by another tag is refused', () async {
    final ProcessResult ran = await _manifestDigests(
      _manifest(<(String, String)>[
        ('ansiwise-$otherTag-linux-x64', 'sha256:$hexA'),
        ('ansiwise-rest-$tag-linux-x64', 'sha256:$hexB'),
      ]),
      tag,
      binaries,
    );

    expect(ran.exitCode, 1);
    expect('${ran.stderr}', contains('ansiwise-$otherTag-linux-x64'));
    expect('${ran.stdout}', isEmpty);
  });

  test('(f) defect: a binary standing twice is refused', () async {
    final ProcessResult ran = await _manifestDigests(
      _manifest(<(String, String)>[
        ('ansiwise-$tag-linux-x64', 'sha256:$hexA'),
        ('ansiwise-$tag-linux-x64', 'sha256:$hexB'),
        ('ansiwise-rest-$tag-linux-x64', 'sha256:$hexB'),
      ]),
      tag,
      binaries,
    );

    expect(ran.exitCode, 1);
    expect('${ran.stderr}', contains('exactly one digest for ansiwise-$tag-linux-x64'));
    expect('${ran.stdout}', isEmpty);
  });

  for (final (String what, String body) in <(String, String)>[
    ('no layers at all', '{"schemaVersion":2}'),
    ('an empty list of layers', _manifest(<(String, String)>[])),
    ('no JSON', '<html>404</html>'),
  ]) {
    test('(g) defect: a manifest with $what is refused', () async {
      final ProcessResult ran = await _manifestDigests(body, tag, binaries);

      expect(ran.exitCode, 1);
      expect('${ran.stderr}', contains(tag));
      expect('${ran.stdout}', isEmpty);
    });
  }
}

/// A manifest as the contract with the publish pipeline spells it, carrying [layers] as
/// `(title, digest)`.
String _manifest(List<(String, String)> layers) => jsonEncode(<String, Object>{
  'schemaVersion': 2,
  'mediaType': 'application/vnd.oci.image.manifest.v1+json',
  'artifactType': 'application/vnd.simetrixch.binaries.v1',
  'config': <String, Object>{
    'mediaType': 'application/vnd.oci.empty.v1+json',
    'digest': 'sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a',
    'size': 2,
  },
  'layers': <Map<String, Object>>[
    for (final (String title, String digest) in layers)
      <String, Object>{
        'mediaType': 'application/octet-stream',
        'digest': digest,
        'size': 1024,
        'annotations': <String, String>{'org.opencontainers.image.title': title},
      },
  ],
  'annotations': <String, String>{
    'org.opencontainers.image.revision': 'c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00',
    'org.opencontainers.image.source': 'https://github.com/simetrixch/ansiwise-cli',
    'org.opencontainers.image.version': 'the tag',
  },
});

/// Runs release/manifest_digests.sh on [manifest] for [tag] and [binaries], as release.sh does.
Future<ProcessResult> _manifestDigests(String manifest, String tag, List<String> binaries) async {
  final Directory root = await Directory.systemTemp.createTemp('release-digests-');
  addTearDown(() => root.delete(recursive: true));
  final File file = File('${root.path}/manifest.json')..writeAsStringSync(manifest);
  return Process.run('bash', <String>[
    '-c',
    r'die() { echo "release: $*" >&2; exit 1; }; source "$1"; shift; manifest_digests "$@"',
    'manifest_digests',
    '${Directory('release').absolute.path}/manifest_digests.sh',
    file.path,
    tag,
    ...binaries,
  ]);
}
