import 'dart:convert';
import 'dart:io';

import 'package:ansiwise_checks_tree/ansiwise_checks_tree.dart';
import 'package:ansiwise_cli/service_installation.dart';
import 'package:ansiwise_cli/service_unit.dart';
import 'package:ansiwise_rest/ansiwise_rest.dart';
import 'package:test/test.dart';

import '../../tool/gate/service_unit.dart';

/// service-unit — the unit this binary installs itself under, and the command it starts.
///
/// **What is judged.** Four things, and each of them is a way the resident service can be installed
/// and then not be there. The unit the binary CARRIES is the unit file on disk, so a repair to one
/// cannot miss the other. The rendered unit says the three things that make it a service at all: it
/// is pulled in at boot, it comes back when it dies, and it does not take its detached runs with it
/// when it restarts. The address is inside the tailnet range, because that is the one network the
/// manager can reach it over and the one that keeps the service token off a wire anybody can read.
/// And the command the unit starts is a command THIS binary parses.
///
/// **The last one is the defect this check exists for.** A unit is a copy of the binary's option
/// names kept somewhere the compiler never looks. One naming an option the binary does not have
/// exits at start with a usage error — on every boot, for ever, restarted every few seconds — and
/// the only place that shows is a journal nobody is reading. So the composed command is handed to
/// the real binary here, and a planted misspelling of one option has to turn it red.
///
/// Nothing here needs an installation: what it judges is this repository's own file against this
/// repository's own binary.
Future<void> main() async {
  // The address the accepted cases use. Inside 100.64.0.0/10 and otherwise unremarkable.
  const String tailnetAddress = '100.64.0.7:8642';

  ServiceInstallation installationOn(
    String listen, {
    String unit = serviceUnit,
    String executable = '/usr/local/bin/ansiwise',
    String? startedFrom,
    String programs = '/srv/ansiwise-catalog/ansiwise/programs',
  }) => ServiceInstallation(
    unit: unit,
    executable: executable,
    // The compiled binary IS what it was started from, and a case that is about something else says
    // so by handing in a different one.
    startedFrom: startedFrom ?? executable,
    listen: listen,
    serviceTokenFile: '/etc/ansiwise/service-token',
    programs: programs,
    config: '/srv/ansiwise-catalog/ansiwise.yaml',
    runs: '/var/lib/ansiwise/runs',
    workingDirectory: '/srv/ansiwise-catalog',
  );

  String? refusalOf(ServiceInstallation installation) {
    try {
      installation.render();
      return null;
    } on ServiceInstallationRefused catch (refused) {
      return refused.because;
    }
  }

  group('the unit the binary carries', () {
    test('is exactly what $serviceUnitFileName says', () {
      // From the working directory, which `dart test` sets to the package. Platform.script points at
      // the test runner's own entry point under Windows and answers a path nowhere near the tree.
      final Directory package = Directory.current;
      final String generated = serviceUnitSource(
        File('${package.path}/$serviceUnitFileName').readAsStringSync(),
      );

      expect(
        File('${package.path}/lib/service_unit.dart').readAsStringSync().replaceAll('\r\n', '\n'),
        generated.replaceAll('\r\n', '\n'),
        reason:
            'lib/service_unit.dart is written by tool/build.dart from $serviceUnitFileName — edit '
            'the unit and build, rather than the file',
      );
    });

    test('is carried with the line endings the service manager reads', () {
      expect(
        serviceUnit,
        isNot(contains('\r')),
        reason:
            'the repository is edited on Windows and the unit runs on Linux, so a carriage return '
            'that reached the value would reach the file the service manager reads',
      );
    });

    test('a unit holding nothing is refused rather than carried', () {
      // A binary carrying an empty unit installs a file the service manager reads as a service that
      // starts nothing, on a machine where nobody is watching it come up.
      expect(() => serviceUnitSource('\n  \n'), throwsA(isA<ServiceUnitRefused>()));
    });
  });

  group('what the rendered unit has to say', () {
    // Rendered inside each test and not once for the group. A rendering that refuses is one of the
    // things judged here, and computed at group level it would take the whole file down as a load
    // failure instead of turning the test that asks about it red.
    String rendered() => installationOn(tailnetAddress).render();

    test('it starts the command out of the options the installer was given', () {
      expect(
        rendered(),
        contains(
          'ExecStart=/usr/local/bin/ansiwise ${ResidentService.program} '
          '--${ResidentService.addressOption} $tailnetAddress '
          '--${ResidentService.tokenFileOption} /etc/ansiwise/service-token',
        ),
      );
      expect(rendered(), contains('WorkingDirectory=/srv/ansiwise-catalog'));
    });

    test('THE PLANTED DEFECT: it does not start the door that serves one session', () {
      // The unit starts a RESIDENT service. A unit that named the session door would come up, read
      // its own standard input for a connection nobody opened, and be restarted for ever — with
      // nothing on the machine saying that the wrong one of two programs was placed.
      expect(
        rendered().split('\n').firstWhere((String each) => each.startsWith('ExecStart=')),
        isNot(contains(' ${ResidentService.sessionProgram} ')),
      );
    });

    for (final MapEntry<String, String> line in ServiceInstallation.requiredLines.entries) {
      test('it says ${line.key}', () {
        expect(rendered().split('\n').map((String each) => each.trim()), contains(line.key));
      });

      test('THE PLANTED DEFECT: a unit that lost ${line.key} is refused', () {
        // Removed from the text the binary carries, which is the only way this line can be lost: it
        // is not composed anywhere, it is written in the unit file and read from there.
        final String without = serviceUnit
            .split('\n')
            .where((String each) => each.trim() != line.key)
            .join('\n');

        expect(
          refusalOf(installationOn(tailnetAddress, unit: without)),
          allOf(isNotNull, contains(line.key), contains(line.value)),
          reason: 'the rendering lost ${line.key} and the installer took it',
        );
      });
    }

    test('THE INNOCENT NEIGHBOUR: the unit as it stands renders', () {
      expect(
        refusalOf(installationOn(tailnetAddress)),
        isNull,
        reason: 'every refusal above proves nothing if this one refuses too',
      );
    });
  });

  group('where the service listens', () {
    // Accepted and refused side by side, so a rule that refused everything and a rule that accepted
    // everything both turn this group red.
    const List<String> inside = <String>[
      '100.64.0.7:8642',
      '100.64.0.1:9953',
      '100.127.255.255:8642',
    ];
    const Map<String, String> outside = <String, String>{
      '0.0.0.0:8642': '100.64.0.0/10',
      '127.0.0.1:9953': '100.64.0.0/10',
      '5.75.181.4:8642': '100.64.0.0/10',
      '100.63.255.255:8642': '100.64.0.0/10',
      '100.128.0.1:8642': '100.64.0.0/10',
      '[::1]:9953': '100.64.0.0/10',
      'ansiwise.example.com:8642': '100.64.0.0/10',
      'unix:/run/ansiwise.sock': 'socket file',
      '100.64.0.7:0': 'port 0',
      'nonsense': 'host:port',
    };

    for (final String address in inside) {
      test('$address is inside the tailnet range and is served', () {
        expect(refusalOf(installationOn(address)), isNull);
      });
    }

    for (final MapEntry<String, String> address in outside.entries) {
      test('THE PLANTED DEFECT: ${address.key} is refused', () {
        expect(
          refusalOf(installationOn(address.key)),
          allOf(isNotNull, contains(address.value)),
          reason:
              'a resident surface on this address is either reachable by nobody that has to reach '
              'it, or reachable with the service token on a wire anybody can read',
        );
      });
    }

    test('the reading states how much it covered', () {
      print(
        'service-unit judged ${inside.length} address(es) inside the tailnet range and '
        '${outside.length} outside it, and ${ServiceInstallation.requiredLines.length} line(s) the '
        'rendered unit must carry',
      );
    });
  });

  group('what the unit may not name', () {
    test('THE PLANTED DEFECT: a process started from source refuses to install', () {
      expect(
        refusalOf(
          installationOn(
            tailnetAddress,
            executable: '/usr/lib/dart/bin/dart',
            startedFrom: '/home/somebody/ansiwise-cli/bin/ansiwise.dart',
          ),
        ),
        allOf(isNotNull, contains('not the compiled binary')),
        reason:
            'the unit would start the toolchain on a machine that has neither it nor the source it '
            'would run',
      );
    });

    test('THE PLANTED DEFECT: a path with a space in it is refused', () {
      expect(
        refusalOf(installationOn(tailnetAddress, programs: '/srv/ansiwise catalog/programs')),
        allOf(isNotNull, contains('/srv/ansiwise catalog/programs')),
        reason:
            'the service manager reads the command line under quoting rules of its own, so the '
            'path would arrive as two arguments',
      );
    });
  });

  group('the command the unit starts is one this binary parses', () {
    // Run against the real entry point, because that is where the option names actually live. The
    // configuration the command names is not on this machine, so the process gets as far as reading
    // it and stops there — which is exactly far enough to prove every option was understood.
    final ServiceInstallation installation = installationOn(tailnetAddress);

    Future<ProcessResult> ansiwise(List<String> arguments) async {
      final Process child = await Process.start('dart', <String>[
        'run',
        'bin/ansiwise.dart',
        ...arguments,
      ], workingDirectory: Directory.current.path);
      await child.stdin.close();
      // BOTH STREAMS ARE DRAINED AT ONCE. A process whose output fills a pipe buffer blocks on its
      // next write until somebody reads, so reading one to the end before starting on the other
      // waits for an exit the process cannot reach — and the refusal probed here is the one that
      // prints the whole usage, which is what fills the buffer.
      final Future<String> said = utf8.decodeStream(child.stdout);
      final Future<String> complained = utf8.decodeStream(child.stderr);
      return ProcessResult(child.pid, await child.exitCode, await said, await complained);
    }

    test('every option of it is one the binary has', () async {
      final ProcessResult answered = await ansiwise(installation.command.sublist(1));

      expect(
        answered.exitCode,
        isNot(64),
        reason:
            'the binary refused the command its own installer composed, as usage:\n'
            '${answered.stderr}',
      );
      expect(
        answered.stderr,
        contains('nothing says which plugins are active'),
        reason:
            'the command was understood and the process stopped at the configuration it names, '
            'which is what says the options were read rather than that the process died earlier',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('THE PLANTED DEFECT: one misspelled option name turns it red', () async {
      // The failure this whole group exists for, planted: a unit written by hand once said
      // --token-file, which this binary has never had. It would exit 64 at every boot for ever.
      final ProcessResult answered = await ansiwise(<String>[
        for (final String each in installation.command.sublist(1))
          if (each == '--service-token-file') '--token-file' else each,
      ]);

      expect(answered.exitCode, 64);
      expect(answered.stderr, contains('token-file'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  // WHAT THE SUBCOMMAND ITSELF REFUSES, judged through the real binary. Nothing here reaches the
  // machine: each case is turned away before the first file is written, which is what makes them
  // the cases a check on this operating system can judge at all. Placing the service is proven on a
  // machine, and the composition above is what this repository can prove without one.
  //
  // SKIPPED WHERE THERE IS NO INSTALLATION TO START UNDER, printed rather than passed over: the
  // entry loads the programs and the configuration of an installation before it reaches any
  // subcommand, and a clone of this repository standing alone has none.
  if (!installationIsFindable) {
    test('install-service', () {}, skip: installationNotFound);
    return;
  }

  group('install-service refuses before it changes anything', () {
    final String installation = installationRoot;
    late Directory held;

    setUp(() => held = Directory.systemTemp.createTempSync('ansiwise-install-service'));
    tearDown(() => held.deleteSync(recursive: true));

    // A password beside the token, because this installation says the caller hands over the one
    // that raises a command to root. Without it every case below would stop at that refusal instead
    // of the one it is about.
    const String envelope =
        '{"answers": {"service_token": "a-token-for-the-service-unit-check"}, '
        '"elevation_password": "not-a-real-password"}';

    Future<ProcessResult> ansiwise(List<String> arguments, {String stdinText = ''}) async {
      final Process child = await Process.start('dart', <String>[
        'run',
        'bin/ansiwise.dart',
        ...arguments,
        '--programs',
        '$installation/$installationPrograms',
        '--config',
        '$installation/ansiwise.yaml',
      ], workingDirectory: Directory.current.path);
      child.stdin.write(stdinText);
      await child.stdin.close();
      final Future<String> said = utf8.decodeStream(child.stdout);
      final Future<String> complained = utf8.decodeStream(child.stderr);
      return ProcessResult(child.pid, await child.exitCode, await said, await complained);
    }

    test('an address outside the tailnet range, and a process that is not the binary', () async {
      final ProcessResult answered = await ansiwise(<String>[
        'install-service',
        '--listen',
        '0.0.0.0:8642',
        '--service-token-file',
        '/etc/ansiwise/service-token',
        '--answers',
        '-',
      ], stdinText: envelope);

      expect(answered.exitCode, 64, reason: 'stderr:\n${answered.stderr}');
      expect(answered.stderr, contains(ServiceInstallation.tailnetRange));
      // Started by `dart run`, so the second refusal is true of this call as well and both are
      // reported at once — a caller with two things to correct learns both in one run.
      expect(answered.stderr, contains('not the compiled binary'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('an envelope carrying no service token', () async {
      final ProcessResult answered = await ansiwise(<String>[
        'install-service',
        '--listen',
        '100.64.0.7:8642',
        '--service-token-file',
        '/etc/ansiwise/service-token',
        '--answers',
        '-',
      ], stdinText: '{"answers": {}, "elevation_password": "not-a-real-password"}');

      expect(answered.exitCode, 64, reason: 'stderr:\n${answered.stderr}');
      expect(answered.stderr, contains('service_token'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a token read from a file instead of from standard input', () async {
      final String file = '${held.path}/envelope.json';
      File(file).writeAsStringSync(envelope);

      final ProcessResult answered = await ansiwise(<String>[
        'install-service',
        '--listen',
        '100.64.0.7:8642',
        '--service-token-file',
        '/etc/ansiwise/service-token',
        '--answers',
        file,
      ]);

      expect(answered.exitCode, 64, reason: 'stderr:\n${answered.stderr}');
      expect(answered.stderr, contains('standard input'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('THE INNOCENT NEIGHBOUR: a word the entry does not know is a different refusal', () async {
      // Every case above expects 64, and an entry that had never heard of `install-service` would
      // refuse them all too. It refuses differently: an unknown first word is read as the name of a
      // program, and that is 65 with a sentence naming the programs there are.
      final ProcessResult answered = await ansiwise(<String>[
        'install-a-service',
        '--listen',
        '100.64.0.7:8642',
        '--answers',
        '-',
      ], stdinText: envelope);

      expect(answered.exitCode, 65);
      expect(answered.stderr, contains('no program is called'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
