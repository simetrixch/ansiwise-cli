import 'dart:io';

import 'package:test/test.dart';

/// A bare origin holding one commit, and the clone a release writes in.
final class BareOrigin {
  BareOrigin._(this.bare, this.clone, this.environment);

  /// A new origin named [name] whose master holds [files], with a clone of it standing on master.
  ///
  /// Under [root] where one is given, so that several origins share a root and one git
  /// configuration; in a root of its own otherwise.
  static Future<BareOrigin> holding(
    Map<String, String> files, {
    Directory? root,
    String name = 'origin',
  }) async {
    final Directory base = root ?? await Directory.systemTemp.createTemp('bare-origin-');
    if (root == null) {
      addTearDown(() => base.delete(recursive: true));
    }
    final File config = File('${base.path}/gitconfig');
    if (!config.existsSync()) {
      config.writeAsStringSync('[user]\n\tname = release\n\temail = release@example.org\n');
    }
    final Map<String, String> environment = <String, String>{
      // The machine's own git configuration stays out: a global hooks path would run a push gate on
      // a push into a temporary directory.
      'GIT_CONFIG_GLOBAL': config.path,
      'GIT_CONFIG_NOSYSTEM': '1',
    };
    final String bare = '${base.path}/$name.git';
    final String seed = '${base.path}/$name-seed';
    final String clone = '${base.path}/$name-clone';
    await runGit(<String>[
      'init',
      '--quiet',
      '--bare',
      '--initial-branch=master',
      bare,
    ], environment);
    await runGit(<String>['clone', '--quiet', bare, seed], environment);
    for (final MapEntry<String, String> each in files.entries) {
      File('$seed/${each.key}')
        ..createSync(recursive: true)
        ..writeAsStringSync(each.value);
    }
    await runGit(<String>['-C', seed, 'add', '--all'], environment);
    await runGit(<String>['-C', seed, 'commit', '--quiet', '-m', 'seed'], environment);
    await runGit(<String>['-C', seed, 'push', '--quiet', 'origin', 'HEAD:master'], environment);
    await runGit(<String>['clone', '--quiet', bare, clone], environment);
    return BareOrigin._(bare, clone, environment);
  }

  /// The bare repository the clone pushes to.
  final String bare;

  /// The clone a release writes in.
  final String clone;

  /// The environment every git and the release's scripts run under.
  final Map<String, String> environment;

  /// The commit origin's master stands on.
  Future<String> head() => runGit(<String>['-C', bare, 'rev-parse', 'master'], environment);

  /// How many commits [range] holds on origin.
  Future<int> count(String range) async =>
      int.parse(await runGit(<String>['-C', bare, 'rev-list', '--count', range], environment));

  /// The files [commit] on origin changed, sorted.
  Future<List<String>> changedIn(String commit) async => (await runGit(<String>[
    '-C',
    bare,
    'diff-tree',
    '--no-commit-id',
    '--name-only',
    '-r',
    commit,
  ], environment)).split('\n')..sort();

  /// [path] as [commit] on origin holds it.
  Future<String> show(String commit, String path) =>
      runGit(<String>['-C', bare, 'show', '$commit:$path'], environment, trim: false);

  /// The tags origin carries, sorted.
  Future<List<String>> tags() async {
    final String listed = await runGit(<String>['-C', bare, 'tag', '--list'], environment);
    return listed.isEmpty ? <String>[] : (listed.split('\n')..sort());
  }

  /// The commit the tag [tag] names on origin.
  Future<String> commitOf(String tag) =>
      runGit(<String>['-C', bare, 'rev-parse', '$tag^{commit}'], environment);
}

/// Runs git, failing the test on a non-zero exit.
Future<String> runGit(
  List<String> arguments,
  Map<String, String> environment, {
  bool trim = true,
}) async {
  final ProcessResult ran = await Process.run('git', arguments, environment: environment);
  if (ran.exitCode != 0) {
    fail('git ${arguments.join(' ')} exited ${ran.exitCode}: ${ran.stderr}');
  }
  return trim ? '${ran.stdout}'.trim() : '${ran.stdout}';
}
