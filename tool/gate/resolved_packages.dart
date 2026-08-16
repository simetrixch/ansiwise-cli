/// Where each package this binary is composed from actually answered, and whether it is one place.
///
/// THE DEFECT THIS EXISTS FOR. This repository names the framework and plugin packages of other
/// repositories by a git ref, and a gitignored `pubspec_overrides.yaml` re-points them at working
/// checkouts beside this one. The same commit therefore resolves to two different binaries — one
/// built from the working trees, one from what was pushed — and both are legitimate. What is not
/// legitimate is the third state: SOME packages overridden and some not, so the binary is built
/// half from the working tree and half from pushed commits, with nothing saying which half is
/// which. A green check over such a composition is green about no binary anybody can name.
///
/// WHY REFUSING THE MIX RATHER THAN DESCRIBING IT. Naming a commit for one half and "the working
/// tree" for the other would state the split accurately and let it stand. The working tree has no
/// revision — it is a commit plus whatever is uncommitted, which is the whole reason somebody is
/// running the gate — so nothing true can be recorded about a binary built from both at once.
/// Either uniform composition passes, and the log says which one it was.
///
/// HOW IT IS READ. `dart pub get` writes `.dart_tool/package_config.json` beside the package. Every
/// entry carries a `rootUri` relative to that file, and the file's own `pubCache` value names the
/// cache. A composed package whose resolved directory lies under the cache answered from a pushed
/// commit; one outside it answered from a working checkout. The composed packages are the ones the
/// manifest names with a git source PLUS every entry that answered from a working checkout or from
/// the cache's git area — the second group catches a package that a git-named dependency itself
/// names by git, which no manifest of this repository declares. Hosted pub.dev dependencies stay
/// under the cache by design and are not judged.
///
/// THE INTRA-REPOSITORY QUESTION STAYS. [inRepositoryResolutionOf] and [splitResolutions] ask which
/// package OF ONE REPOSITORY answered another package of it. With one package here they measure
/// nothing, and they start measuring again the day a second package arrives.
///
/// It imports nothing but `dart:`, like everything else the gate reaches before `dart pub get`.
library;

import 'dart:convert';
import 'dart:io';

import 'dart_packages.dart';

/// Where one package resolved one dependency to.
final class ResolvedDependency {
  /// Records that [inPackage] resolved [name] to the directory [root].
  const ResolvedDependency({required this.inPackage, required this.name, required this.root});

  /// The package whose resolution this is.
  final String inPackage;

  /// The name of the dependency, as an import says it after `package:`.
  final String name;

  /// The directory it resolved to, as this operating system names it.
  final String root;

  @override
  String toString() => '$inPackage resolved $name from $root';
}

/// Every dependency of [package] that this repository also holds on disk, and where it came from.
///
/// A dependency this repository does not hold is not listed: it resolves through the pub cache by
/// design, and nothing here judges it. An unresolved package answers with nothing, which is what a
/// package whose `pub get` failed is — and that failure is already the gate's own finding.
List<ResolvedDependency> inRepositoryResolutionOf(
  DartPackage package,
  List<DartPackage> repositoryPackages,
) {
  final File config = File('${package.directory}/.dart_tool/package_config.json');
  if (!config.existsSync()) {
    return const <ResolvedDependency>[];
  }
  final Map<String, String> heldHere = <String, String>{
    for (final DartPackage held in repositoryPackages) held.name: held.directory,
  };
  final Object? read = jsonDecode(config.readAsStringSync());
  if (read is! Map<String, Object?>) {
    return const <ResolvedDependency>[];
  }
  final Object? entries = read['packages'];
  if (entries is! List<Object?>) {
    return const <ResolvedDependency>[];
  }
  final List<ResolvedDependency> found = <ResolvedDependency>[];
  for (final Object? entry in entries) {
    if (entry is! Map<String, Object?>) {
      continue;
    }
    final Object? name = entry['name'];
    final Object? rootUri = entry['rootUri'];
    if (name is! String || rootUri is! String || !heldHere.containsKey(name)) {
      continue;
    }
    // A package never resolves itself somewhere else, and listing it would say nothing.
    if (name == package.name) {
      continue;
    }
    found.add(
      ResolvedDependency(
        inPackage: package.name,
        name: name,
        root: _directoryNamedBy(rootUri, from: '${package.directory}/.dart_tool/'),
      ),
    );
  }
  found.sort((ResolvedDependency a, ResolvedDependency b) => a.name.compareTo(b.name));
  return found;
}

/// Every resolution of [resolutions] that came from outside this repository's own checkouts.
///
/// The refusal names the package, the dependency, where it came from and where it should have come
/// from — the four things somebody needs to write the override file that fixes it.
List<String> splitResolutions({
  required List<ResolvedDependency> resolutions,
  required List<DartPackage> repositoryPackages,
}) {
  final Map<String, String> heldHere = <String, String>{
    for (final DartPackage held in repositoryPackages) held.name: held.directory,
  };
  return <String>[
    for (final ResolvedDependency resolved in resolutions)
      if (heldHere[resolved.name] case final String checkout)
        if (!sameDirectory(resolved.root, checkout))
          '${resolved.inPackage} was composed from ${resolved.name} at ${resolved.root}, and the '
              'checks of ${resolved.name} judge $checkout — two different copies, so a green '
              'verdict is green about neither',
  ];
}

/// One package this binary is composed from, and which side answered it.
final class ComposedPackage {
  /// Records that [name] answered from the directory [root].
  const ComposedPackage({required this.name, required this.root, required this.fromCache});

  /// The package, as an import says it after `package:`.
  final String name;

  /// The directory it answered from, with forward slashes.
  final String root;

  /// True when [root] lies under the pub cache — a pushed commit — and false when it is a working
  /// checkout outside it.
  final bool fromCache;

  @override
  String toString() => '$name from $root';
}

/// The dependency names [pubspecText] declares with a `git:` source, in both dependency blocks.
///
/// Dev dependencies count: the audits judging working-tree code while they themselves resolved
/// from a commit is the same split one level down, even though nothing of them is compiled in.
List<String> gitNamedDependencies(String pubspecText) {
  final List<String> found = <String>[];
  bool inDependencyBlock = false;
  String? awaitingSource;
  for (final String raw in pubspecText.split('\n')) {
    final String line = raw.replaceAll('\r', '');
    final String content = line.trimLeft();
    if (content.isEmpty || content.startsWith('#')) {
      continue;
    }
    final int indent = line.length - content.length;
    if (indent == 0) {
      inDependencyBlock = content == 'dependencies:' || content == 'dev_dependencies:';
      awaitingSource = null;
      continue;
    }
    if (!inDependencyBlock) {
      continue;
    }
    if (indent == 2) {
      // `name:` opens a block source that may turn out to be git; `name: ^1.0.0` is hosted.
      final String trimmed = content.trimRight();
      awaitingSource = trimmed.endsWith(':') ? trimmed.substring(0, trimmed.length - 1) : null;
      continue;
    }
    if (indent == 4 && content.trimRight() == 'git:' && awaitingSource != null) {
      found.add(awaitingSource);
      awaitingSource = null;
    }
  }
  found.sort();
  return found;
}

/// Where each package the binary is composed from answered, read out of a package config.
///
/// [packageConfigText] is the JSON `dart pub get` wrote, [configDirectory] the directory it sits in
/// — what every `rootUri` is relative to — and [members] the names the manifest declares with a git
/// source. Listed are the members plus every other entry that answered from a working checkout or
/// from the cache's git area; the package's own entry and hosted dependencies under the cache are
/// not composition, and a config that does not name its cache classifies nothing, so everything
/// declared comes back missing rather than half-guessed.
List<ComposedPackage> compositionOf({
  required String packageConfigText,
  required String configDirectory,
  required List<String> members,
}) {
  final Object? read = jsonDecode(packageConfigText);
  if (read is! Map<String, Object?>) {
    return const <ComposedPackage>[];
  }
  final Object? entries = read['packages'];
  final Object? cacheValue = read['pubCache'];
  if (entries is! List<Object?> || cacheValue is! String) {
    return const <ComposedPackage>[];
  }
  final Uri base = Uri.directory(configDirectory, windows: Platform.isWindows);
  final String cache = _withoutTrailingSlash(cacheValue);
  final String ownRoot = _withoutTrailingSlash(base.resolveUri(Uri.parse('../')).toString());
  final List<ComposedPackage> found = <ComposedPackage>[];
  for (final Object? entry in entries) {
    if (entry is! Map<String, Object?>) {
      continue;
    }
    final Object? name = entry['name'];
    final Object? rootUri = entry['rootUri'];
    if (name is! String || rootUri is! String) {
      continue;
    }
    final String resolved = _withoutTrailingSlash(base.resolveUri(Uri.parse(rootUri)).toString());
    final bool fromCache = resolved.startsWith('$cache/');
    final bool fromCacheGit = resolved.startsWith('$cache/git/');
    final bool composed =
        members.contains(name) || (resolved != ownRoot && (fromCacheGit || !fromCache));
    if (composed) {
      found.add(ComposedPackage(name: name, root: _shownDirectory(resolved), fromCache: fromCache));
    }
  }
  found.sort((ComposedPackage a, ComposedPackage b) => a.name.compareTo(b.name));
  return found;
}

/// Empty on a uniform composition; one refusal per finding otherwise.
///
/// Refused are a mixed composition — packages from both sides at once — and a member of [members]
/// that [composition] has no answer for, which means the manifest and the resolution disagree and
/// nothing true can be said about what a build would compile.
List<String> compositionRefusals({
  required List<ComposedPackage> composition,
  required List<String> members,
}) {
  final List<String> refusals = <String>[];
  final Set<String> present = <String>{
    for (final ComposedPackage composed in composition) composed.name,
  };
  for (final String member in members) {
    if (!present.contains(member)) {
      refusals.add(
        '$member is declared with a git source and the resolution does not say where it answered '
        'from, so nothing true can be said about what a build would compile',
      );
    }
  }
  final List<ComposedPackage> fromCheckouts = <ComposedPackage>[
    for (final ComposedPackage composed in composition)
      if (!composed.fromCache) composed,
  ];
  final List<ComposedPackage> fromCommits = <ComposedPackage>[
    for (final ComposedPackage composed in composition)
      if (composed.fromCache) composed,
  ];
  if (fromCheckouts.isNotEmpty && fromCommits.isNotEmpty) {
    refusals.add(
      <String>[
        'mixed composition: the binary would be built half from the working tree and half from '
            'what was pushed, and nothing in it would say which half is which',
        '  from working checkouts: ${_named(fromCheckouts)}',
        '  from pushed commits: ${_named(fromCommits)}',
        '  all or none: name every one of them in pubspec_overrides.yaml, or delete that file and '
            'resolve again',
      ].join('\n'),
    );
  }
  return refusals;
}

/// The one line an operator learns the composition from.
String compositionLine(List<ComposedPackage> composition) {
  if (composition.isEmpty) {
    return 'composition: nothing here is composed from a git-named package';
  }
  if (composition.every((ComposedPackage composed) => composed.fromCache)) {
    return 'composition: every git-named package answered from a pushed commit in the pub cache — '
        'a pushed build, not the working trees';
  }
  if (composition.every((ComposedPackage composed) => !composed.fromCache)) {
    return 'composition: every git-named package answered from a working checkout beside this '
        'repository — a working-tree build, not what was pushed';
  }
  return 'composition: mixed — refused above';
}

String _named(List<ComposedPackage> composition) => composition
    .map((ComposedPackage composed) => '${composed.name} at ${composed.root}')
    .join('; ');

String _withoutTrailingSlash(String uri) =>
    uri.endsWith('/') ? uri.substring(0, uri.length - 1) : uri;

/// The directory a `file:` URI string names, shown with forward slashes and no scheme.
String _shownDirectory(String uri) {
  String path = Uri.parse(uri).path;
  if (path.length >= 3 && path[0] == '/' && path[2] == ':') {
    path = path.substring(1);
  }
  return path;
}

/// Whether [one] and [other] name the same directory.
///
/// Separators and a trailing one are how the same directory comes to be written two ways: a package
/// config carries a URI and the walk carries what this operating system wrote. Case is compared
/// exactly, because a path that differs only in case is a different path on the machine the product
/// runs on, and the gate is not the place to start treating the two as one.
bool sameDirectory(String one, String other) => _flattened(one) == _flattened(other);

String _flattened(String path) {
  final String forward = path.replaceAll(r'\', '/');
  return forward.endsWith('/') ? forward.substring(0, forward.length - 1) : forward;
}

/// The directory [rootUri] names, resolved against [from].
String _directoryNamedBy(String rootUri, {required String from}) {
  final Uri base = Uri.directory(from, windows: Platform.isWindows);
  return Directory.fromUri(base.resolveUri(Uri.parse(rootUri))).absolute.path;
}
