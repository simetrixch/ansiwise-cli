import 'dart:io';

import 'package:test/test.dart';

import '../support/bare_origin.dart';
import '../support/starts_ansiwise.dart';

/// release-tag — the stamp of the programs pin carries the release's tag, or the release stops.
///
/// `ai-core status-sync` counts a commit of the programs repository as released only when a tag
/// carries it, so a release that stamped the pin and tagged only its own repository left every
/// card of the programs repository in `testing` for good. The release sets the same tag on the
/// commit that carries the pin, pushes it, and reads it back from origin.
///
/// Two layers. `tag_pin` of release/write_pin.sh is called alone on a clone of a bare origin: the
/// tag goes on the stamp commit, and on the commit already carrying the pin where no stamp is
/// written. Then release/release.sh itself runs, from a checkout of a stand-in ansiwise-cli, over
/// stand-ins of every repository it writes to: git redirects the GitHub URLs it names to bare
/// repositories in a temporary directory, a stand-in `curl` answers the manifest Zot would hold, and
/// a stand-in `dart` resolves nothing.
///
/// THE PLANTED INNOCENTS are (c), a tag already standing at the pin's commit, and the platform
/// repository, which the release writes a pin into and must leave without a tag. THE PLANTED
/// DEFECTS are the stamp left untagged, a tag standing at another commit, and an origin that
/// refuses the tag.
void main() {
  // SKIPPED WHERE THE REPOSITORY'S RULE SAYS SO, printed rather than passed over: every suite that
  // starts a process skips where ANSIWISE_TESTS_MAY_SKIP=1 (test/support_starts_ansiwise_test.dart).
  if (startsAnsiwiseSkip != null) {
    test('release-tag', () {}, skip: startsAnsiwiseSkip);
    return;
  }
  const String tag = '0.8.200-stable-20261011000000';
  const String pin = 'ansiwise/programs/deploy-cluster.yaml';
  String pinFile(String version) => 'steps:\n  - packages:\n      - ansiwise=$version\n';

  group('tag_pin', () {
    test('(a) a stamp written by write_pin is the commit the tag stands on', () async {
      final BareOrigin origin = await BareOrigin.holding(<String, String>{
        pin: pinFile('0.8.100-stable-20261001000000'),
      });
      final String before = await origin.head();

      final ProcessResult ran = await _stampAndTag(origin, tag: tag);

      expect(ran.exitCode, 0, reason: '${ran.stderr}');
      expect(await origin.count('$before..master'), 1);
      expect(await origin.tags(), <String>[tag]);
      expect(await origin.commitOf(tag), await origin.head());
      expect(await origin.show(tag, pin), contains('- ansiwise=$tag\n'));
    });

    test('(b) a pin already standing is tagged where it stands, with no commit written', () async {
      final BareOrigin origin = await BareOrigin.holding(<String, String>{pin: pinFile(tag)});
      final String before = await origin.head();

      final ProcessResult ran = await _stampAndTag(origin, tag: tag);

      expect(ran.exitCode, 0, reason: '${ran.stderr}');
      expect(await origin.head(), before);
      expect(await origin.tags(), <String>[tag]);
      expect(await origin.commitOf(tag), before);
    });

    test('(c) innocent: a tag already standing on the pin\'s commit passes', () async {
      final BareOrigin origin = await BareOrigin.holding(<String, String>{pin: pinFile(tag)});
      final String before = await origin.head();
      await runGit(<String>['-C', origin.bare, 'tag', tag, before], origin.environment);

      final ProcessResult ran = await _stampAndTag(origin, tag: tag);

      expect(ran.exitCode, 0, reason: '${ran.stderr}');
      expect(await origin.head(), before);
      expect(await origin.tags(), <String>[tag]);
      expect(await origin.commitOf(tag), before);
    });

    test('(d) defect: a tag standing on another commit is refused, naming it', () async {
      final BareOrigin origin = await BareOrigin.holding(<String, String>{
        pin: pinFile('0.8.100-stable-20261001000000'),
      });
      final String seed = await origin.head();
      await runGit(<String>['-C', origin.bare, 'tag', tag, seed], origin.environment);

      final ProcessResult ran = await _stampAndTag(origin, tag: tag);

      expect(ran.exitCode, 1);
      expect('${ran.stderr}', allOf(contains(tag), contains('simetrixch/hostyour-deploy')));
      expect(await origin.commitOf(tag), seed, reason: 'the tag stays where it stood');
    });

    test('(e) defect: an origin that refuses the tag stops the release, naming it', () async {
      final BareOrigin origin = await BareOrigin.holding(<String, String>{
        pin: pinFile('0.8.100-stable-20261001000000'),
      });
      await _refuseTags(origin);

      final ProcessResult ran = await _stampAndTag(origin, tag: tag);

      expect(ran.exitCode, 1);
      expect('${ran.stderr}', allOf(contains(tag), contains('simetrixch/hostyour-deploy')));
      expect(await origin.tags(), isEmpty);
    });
  });

  group('release.sh', () {
    test(
      '(f) the tag of the release stands on the stamp commit of the programs repository',
      () async {
        final _Release release = await _Release.prepare();

        final ProcessResult ran = await release.run();

        expect(ran.exitCode, 0, reason: '${ran.stdout}${ran.stderr}');
        final List<String> released = await release.engine.tags();
        expect(released, hasLength(1));
        expect(released.single, startsWith('0.8.200-stable-'));
        expect(await release.programs.tags(), released);
        final String stamp = await release.programs.head();
        expect(await release.programs.commitOf(released.single), stamp);
        expect(
          await release.programs.show(stamp, pin),
          contains('- ansiwise=${released.single}\n'),
        );
        expect(
          await runGit(<String>[
            '-C',
            release.programs.bare,
            'log',
            '-1',
            '--format=%s',
            stamp,
          ], release.programs.environment),
          'release: stamp the ansiwise 0.8.200 stable pin into deploy-cluster',
        );
        expect(await release.platform.tags(), isEmpty, reason: 'the platform pin carries no tag');
      },
    );

    test(
      '(g) defect: a programs origin that refuses the tag stops the release, and says what stands',
      () async {
        final _Release release = await _Release.prepare(refuseProgramsTags: true);

        final ProcessResult ran = await release.run();

        expect(ran.exitCode, 1);
        final List<String> released = await release.engine.tags();
        expect(released, hasLength(1));
        expect(
          '${ran.stderr}',
          allOf(
            contains('could not be pushed to simetrixch/hostyour-deploy'),
            contains('the tag ${released.single} stands'),
            contains('simetrixch/hostyour-deploy are pinned'),
            contains('no tag ${released.single} stands on simetrixch/hostyour-deploy'),
          ),
        );
        expect(await release.programs.tags(), isEmpty);
      },
    );
  });
}

/// Runs write_pin and then tag_pin of release/write_pin.sh on [origin]'s clone, as release.sh does
/// for the programs repository.
Future<ProcessResult> _stampAndTag(BareOrigin origin, {required String tag}) {
  const String pinShape = r'[0-9]+\.[0-9]+\.[0-9]+-[a-z]+-[0-9]{14}';
  final String release = Directory('release').absolute.path;
  return Process.run('bash', <String>[
    '-c',
    r'die() { echo "release: $*" >&2; exit 1; }; say() { echo "release: $*"; }; '
        r'TAG="$1"; source "$2"; '
        r'write_pin simetrixch/hostyour-deploy "$3" ansiwise/programs/deploy-cluster.yaml '
        '"s|- ansiwise=$pinShape|- ansiwise=\$TAG|" "release: stamp"; '
        r'tag_pin simetrixch/hostyour-deploy "$3"',
    'tag_pin',
    tag,
    '$release/write_pin.sh',
    origin.clone,
  ], environment: origin.environment);
}

/// Makes [origin] refuse every push of a tag and accept every other push.
Future<void> _refuseTags(BareOrigin origin) async {
  final File hook = File('${origin.bare}/hooks/pre-receive')
    ..writeAsStringSync(
      '#!/bin/sh\n'
      'while read old new ref; do\n'
      '  case "\$ref" in refs/tags/*) echo "tags are refused here" >&2; exit 1 ;; esac\n'
      'done\n',
    );
  final ProcessResult chmod = await Process.run('chmod', <String>['+x', hook.path]);
  expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
}

/// A checkout of a stand-in ansiwise-cli that release/release.sh runs in, over a stand-in for every
/// repository the release reads or writes.
final class _Release {
  _Release._(this.engine, this.programs, this.platform, this.path);

  static Future<_Release> prepare({bool refuseProgramsTags = false}) async {
    final Directory root = await Directory.systemTemp.createTemp('release-tag-');
    addTearDown(() => root.delete(recursive: true));
    final Map<String, String> scripts = <String, String>{
      for (final File each in Directory('release').listSync().whereType<File>())
        'release/${each.uri.pathSegments.last}': each.readAsStringSync(),
    };
    final BareOrigin engine = await BareOrigin.holding(
      <String, String>{...scripts, 'pubspec.yaml': _pubspec},
      root: root,
      name: 'ansiwise-cli',
    );
    for (final String part in <String>['ansiwise-core', 'ansiwise-checks', 'ansiwise-plugins']) {
      await BareOrigin.holding(<String, String>{'README.md': part}, root: root, name: part);
    }
    final BareOrigin platform = await BareOrigin.holding(
      <String, String>{
        'clusters/platform/versions.yaml':
            'ansiwise:\n  version: "0.8.100-stable-20261001000000"\n',
      },
      root: root,
      name: 'hostyour-cloud',
    );
    final BareOrigin programs = await BareOrigin.holding(
      <String, String>{
        'ansiwise/programs/deploy-cluster.yaml':
            'steps:\n  - packages:\n      - ansiwise=0.8.100-stable-20261001000000\n',
        'ci-sources.json': '{\n  "git": {\n    "ansiwise-cli": "${'a' * 40}"\n  }\n}\n',
      },
      root: root,
      name: 'hostyour-deploy',
    );
    if (refuseProgramsTags) {
      await _refuseTags(programs);
    }
    // Every GitHub URL the release names is answered by a bare repository of the temporary root.
    File('${root.path}/gitconfig').writeAsStringSync(
      '[url "${root.path}/"]\n\tinsteadOf = https://github.com/simetrixch/\n',
      mode: FileMode.append,
    );
    final Directory standIns = Directory('${root.path}/bin')..createSync();
    File('${standIns.path}/dart').writeAsStringSync('#!/bin/sh\nexit 0\n');
    File('${standIns.path}/curl').writeAsStringSync(_curl);
    for (final String each in <String>['dart', 'curl']) {
      final ProcessResult chmod = await Process.run('chmod', <String>[
        '+x',
        '${standIns.path}/$each',
      ]);
      expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
    }
    return _Release._(
      engine,
      programs,
      platform,
      '${standIns.path}:${Platform.environment['PATH']}',
    );
  }

  /// The stand-in ansiwise-cli: the checkout the release runs in, and the origin it tags.
  final BareOrigin engine;

  /// The stand-in programs repository.
  final BareOrigin programs;

  /// The stand-in platform repository.
  final BareOrigin platform;

  /// The PATH that puts the stand-in `dart` and `curl` first.
  final String path;

  Future<ProcessResult> run() => Process.run(
    'bash',
    <String>['release/release.sh', '0.8.200', 'stable'],
    workingDirectory: engine.clone,
    environment: <String, String>{...engine.environment, 'PATH': path},
  );
}

/// The manifest of the stand-in ansiwise-cli: the version the release bumps and the three parts it
/// brings onto their masters.
const String _pubspec = '''
name: stand_in
version: 0.8.100
dependencies:
  ansiwise_core:
    git:
      url: https://github.com/simetrixch/ansiwise-core.git
      ref: master
  ansiwise_plugins:
    git:
      url: https://github.com/simetrixch/ansiwise-plugins.git
      ref: master
  ansiwise_checks:
    git:
      url: https://github.com/simetrixch/ansiwise-checks.git
      ref: master
''';

/// A `curl` that answers 200 and writes, to the file `-o` names, the manifest Zot holds for the tag
/// at the end of the URL: one layer for each binary the release's build.sh names.
final String _curl =
    '''
#!/bin/sh
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) out="\$2"; shift ;;
    -w|-H|--max-time) shift ;;
    -*) ;;
    *) url="\$1" ;;
  esac
  shift
done
tag="\${url##*/}"
printf '{"layers":[{"digest":"sha256:${'a' * 64}","annotations":{"org.opencontainers.image.title":"ansiwise-%s-linux-x64"}},{"digest":"sha256:${'b' * 64}","annotations":{"org.opencontainers.image.title":"ansiwise-rest-%s-linux-x64"}}]}' "\$tag" "\$tag" > "\$out"
printf 200
''';
