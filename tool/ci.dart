/// The gate of this repository, on this machine.
///
/// ```
/// dart run tool/ci.dart    run every check
/// ```
///
/// It has to end with `ci: OK — every check green`.
///
/// THE FIRST THING IT DOES IS REFUSE THE WRONG TOOLCHAIN. The pin names the one Dart version the
/// checks are true against, and every tool this gate starts is this process's own SDK — the real
/// toolchain launches `Platform.resolvedExecutable`. So the pin is enforced by reading this
/// process's version and refusing every other, with the found and the expected version in the
/// refusal.
///
/// THEN IT ASKS WHETHER EACH PACKAGE STILL SAYS WHAT IT CHECKS. `dart test` discovers what is on
/// disk, so a deleted check file simply is not there and the run reports that every check is green.
/// Each package answers that with a `checks.yaml` and a check that holds it against the disk; what
/// that check cannot notice is its own absence, and [undeclaredSuites] is where that is noticed —
/// the two files, for every package with a suite, before anything runs.
///
/// WHICH `ansiwise_api` ANSWERED IS SAID BY `dart pub get`, NOT BY THIS PROGRAM. A developer working
/// on the framework and the plugin at once writes a pubspec_overrides.yaml pointing at the checkout
/// beside this one, and pub names it in the line it prints — `from path ..\..\ansiwise-api
/// (overridden in .\pubspec_overrides.yaml)` — which [PackageGate] logs. Deriving that a second time
/// here would be a second answer that can disagree with the file which actually decides.
///
/// WHAT THE BINARY IS COMPOSED FROM IS DECIDED HERE, AND A MIX IS A REFUSAL. This package names
/// the framework and plugin packages of other repositories by a git ref, and a gitignored
/// pubspec_overrides.yaml re-points them at working checkouts beside this one. Either composition
/// is a legitimate binary and the gate logs which one this resolution is; a composition built half
/// from the working tree and half from pushed commits is refused, because nothing in such a binary
/// says which half is which.
///
/// WHAT IT IS MADE OF LIVES IN package:ansiwise_checks_gate, and this file is the composition root.
/// The gate was carried under tool/gate/ here and in ansiwise-core until eleven of the file names
/// stood in both and five of them had drifted. Nothing about the ORDER of a run needed the copy —
/// this program is started after the package it sits in has been resolved, by scripts/check.sh and
/// by .github/workflows/release.yml alike, and the resolution the gate itself performs is the one
/// over every package of the repository. What stays under tool/gate/ here is the RELEASE gate,
/// which belongs to this product and to no other repository.
library;

import 'dart:io';

import 'package:ansiwise_checks_gate/ansiwise_checks_gate.dart';

/// Runs the gate and answers non-zero when anything is wrong.
Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('ci: FAIL — unknown option ${arguments.first} (this gate takes no options)');
    exit(2);
  }

  final String? refusal = dartVersionRefusal(running: Platform.version, pinned: dartVersion);
  if (refusal != null) {
    stderr.writeln('ci: FAIL — $refusal');
    exit(1);
  }

  // The REPOSITORY, not the package this program sits in. The two were the same directory while
  // this repository held one package, which is why walking the package went unnoticed; the moment a
  // second arrived the gate went on checking the first and printed `every check green` over
  // sixty-four files it had never opened.
  final Directory package = packageOfToolScript(Platform.script);
  final Directory repository = repositoryOf(package);
  const GateLog log = StdoutGateLog();

  // BEFORE ANYTHING RUNS, because a suite cannot report a check that is not in it. Each package
  // declares its checks and carries the one that holds the declaration against the disk; what that
  // one cannot do is notice that the file holding it is gone, and this is where that is noticed.
  log.heading('declared checks');
  final List<String> undeclared = undeclaredSuites(dartPackagesIn(repository));
  if (undeclared.isNotEmpty) {
    for (final String refusal in undeclared) {
      stderr.writeln('  $refusal');
    }
    stderr.writeln('ci: FAIL — declared checks');
    exit(1);
  }
  log.note('every package with a suite declares its checks and carries the check that reads it');

  final GateVerdict verdict = await PackageGate(
    toolchain: const RealDartToolchain(),
    packages: dartPackagesIn(repository),
    log: log,
    // The analysis program is started in the package that HOLDS it, and judges the whole repository
    // from there. Starting it at the repository root would look tidier and find no tool/ at all.
    analysisRoot: package.path,
  ).run();

  log.heading('verdict');
  if (verdict.green) {
    stdout.writeln(verdict.line);
    return;
  }
  stderr.writeln(verdict.line);
  exitCode = 1;
}
