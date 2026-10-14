import 'dart:io';

import 'package:test/test.dart';

/// release-without-github-service — the release asks GitHub for nothing but git.
///
/// The binaries are built by release/build.sh in the publish pipeline on the owner's master and
/// held in Zot; release/release.sh waits for their manifest there and reads the digests out of it.
/// A script under release/ that still names the `gh` command, a workflow file, the GitHub API, raw
/// file hosting or a release download asks a service the release no longer has, and fails only on
/// the day it is cut. Cloning and pushing over git stays: the parts and the trees it pins live on
/// GitHub.
///
/// THE PLANTED DEFECTS are the lines in [_defects], each of which must be found. THE PLANTED
/// INNOCENTS are the lines in [_innocents] — a git URL, words that hold the letters `gh` — none of
/// which may be. Only then is every script under release/ read, and the count of scripts read is
/// asserted so an empty directory cannot pass.
void main() {
  test('every planted defect is found', () {
    for (final String defect in _defects) {
      expect(githubServicesNamedIn(defect), isNotEmpty, reason: defect);
    }
  });

  test('no planted innocent is found', () {
    for (final String innocent in _innocents) {
      expect(githubServicesNamedIn(innocent), isEmpty, reason: innocent);
    }
  });

  test('no script under release/ names a GitHub service other than git', () {
    final List<File> scripts =
        Directory(
            'release',
          ).listSync().whereType<File>().where((File each) => each.path.endsWith('.sh')).toList()
          ..sort((File a, File b) => a.path.compareTo(b.path));
    final List<String> found = <String>[
      for (final File script in scripts)
        for (final String named in githubServicesNamedIn(script.readAsStringSync()))
          '${script.path}: $named',
    ];
    expect(found, isEmpty, reason: 'read ${scripts.length} scripts under release/');
    expect(
      scripts.map((File each) => each.uri.pathSegments.last),
      containsAll(<String>['build.sh', 'manifest_digests.sh', 'release.sh', 'write_pin.sh']),
    );
  });
}

/// Every mention in [text] of a GitHub service other than git, as the line that names it.
List<String> githubServicesNamedIn(String text) => <String>[
  for (final String line in text.split('\n'))
    if (_services.any((RegExp service) => service.hasMatch(line))) line.trim(),
];

final List<RegExp> _services = <RegExp>[
  // The command, as a word of its own: `through` and `high` hold the letters and name nothing.
  RegExp(r'(^|[^A-Za-z0-9_.-])gh([^A-Za-z0-9_.-]|$)'),
  RegExp(r'release\.yml'),
  RegExp(r'\.github/workflows'),
  RegExp(r'api\.github\.com'),
  RegExp(r'raw\.githubusercontent\.com'),
  RegExp(r'/releases/download/'),
];

const List<String> _defects = <String>[
  r'assets="$(gh release view "$TAG" --json assets)"',
  r'found="$(gh run list --limit 15)"',
  'gh',
  r'''binaries="$(awk '/^  BINARIES:/' .github/workflows/release.yml)"''',
  'curl -fsSL https://api.github.com/repos/simetrixch/ansiwise-cli/releases',
  'curl -fsSL https://raw.githubusercontent.com/simetrixch/ansiwise-checks/x/gate/lib/src/pins.dart',
  'https://github.com/simetrixch/ansiwise-cli/releases/download/0.8.1-stable-20261001000000/ansiwise',
];

const List<String> _innocents = <String>[
  r'git clone --quiet "https://github.com/${PLATFORM_REPO}.git" "$WORK/platform"',
  r'git ls-remote "https://github.com/simetrixch/ansiwise-core.git" refs/heads/master',
  '# it goes through a high wall, and the length of a ghost',
  'curl -sS https://zot.master.digitacloud.app/v2/simetrixch/ansiwise-cli/manifests/x',
];
