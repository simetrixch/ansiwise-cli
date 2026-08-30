/// What a detached run is told about WHERE IT STANDS, composed out of what the surface was told.
///
///   dart test test/rest/placement_test.dart
///
/// THE DEFECT THIS EXISTS FOR SHIPPED, and it cost a whole evening to find. The manager starts a
/// machine's surface as
///
///     cd /srv/ansiwise-catalog && ansiwise-rest serve --programs /srv/ansiwise-catalog/ansiwise/programs
///
/// because the catalogue keeps its programs under `ansiwise/programs` and not at the default. The
/// surface listed them, served them, and accepted every run. The detached child was handed only the
/// working directory, resolved `programs` against it, found nothing, and exited 66 BEFORE writing a
/// header — so the caller was left holding a run id whose run answered 404 for ever, and the only
/// thing anybody could read was an absence:
///
///     machine run 20260827T110119Z-… (deploy-host) was accepted but never wrote its record —
///     it started and died before its first step
///
/// Every test in this repository stayed green, because not one of them started the surface the way a
/// machine does: with its programs somewhere other than beside it.
///
/// WHAT IS HELD HERE is the composition — which words are passed on and which are not. That the
/// launcher then hands them to the child is held where the launcher is
/// (ansiwise-core test/infrastructure/detached_launcher_test.dart), over a real detached process.
library;

import 'package:args/args.dart';
import 'package:ansiwise_cli/installation.dart';
import 'package:test/test.dart';

void main() {
  /// The command line as the binary itself parses it, so this measures the real parser's idea of
  /// what was given rather than a second one written here.
  ArgResults given(List<String> argv) {
    final ArgParser parser = ArgParser();
    addSharedOptions(parser);
    return parser.parse(argv);
  }

  test('what the surface was told about its placement is what the child is told', () {
    expect(
      placementFrom(
        given(<String>[
          'serve',
          '--programs',
          '/srv/ansiwise-catalog/ansiwise/programs',
          '--config',
          '/srv/ansiwise-catalog/ansiwise.yaml',
          '--runs',
          '/var/lib/ansiwise/runs',
        ]),
      ),
      <String>[
        '--programs',
        '/srv/ansiwise-catalog/ansiwise/programs',
        '--config',
        '/srv/ansiwise-catalog/ansiwise.yaml',
        '--runs',
        '/var/lib/ansiwise/runs',
      ],
    );
  });

  // THE EXACT SHAPE THE MANAGER USES, and the one that shipped broken: the working directory is the
  // catalogue and the programs are NOT under it at the default name.
  test('a surface told only where the programs are hands on only that', () {
    expect(
      placementFrom(
        given(<String>['serve', '--programs', '/srv/ansiwise-catalog/ansiwise/programs']),
      ),
      <String>['--programs', '/srv/ansiwise-catalog/ansiwise/programs'],
    );
  });

  // WHAT THE MACHINE IS, WHICH A CHILD CANNOT WORK OUT AND WOULD OTHERWISE DEFAULT. The engine
  // refuses a program whose `roles:` does not name the machine, and the option defaults to `master`
  // — so a served run never told the role claims to be a master. On the first slave this platform
  // ever deployed, fifteen steps passed and the sixteenth could not: `emit-cluster-credentials
  // applies to slave, and this machine is master`, thrown out of Runner.run before the child wrote
  // one event, leaving the caller on an event stream that would never carry anything.
  test('what the machine IS travels with the child, beside where it stands', () {
    expect(
      placementFrom(
        given(<String>[
          'serve',
          '--programs',
          '/srv/ansiwise-catalog/ansiwise/programs',
          '--role',
          'slave',
          '--stage',
          'dev',
          '--fqdn',
          'apps4.digitacloud.app',
        ]),
      ),
      <String>[
        '--programs',
        '/srv/ansiwise-catalog/ansiwise/programs',
        '--role',
        'slave',
        '--stage',
        'dev',
        '--fqdn',
        'apps4.digitacloud.app',
      ],
    );
  });

  // A ROLE OF TWO PARTS TRAVELS WHOLE. A machine can carry both jobs, and the engine reads a role's
  // parts — a program declared for either one applies (Program.appliesTo). Splitting it here would
  // be this composition deciding what a machine is.
  test('a role naming two parts is handed on as it stands', () {
    expect(placementFrom(given(<String>['serve', '--role', 'master+slave'])), <String>[
      '--role',
      'master+slave',
    ]);
  });

  // THE INNOCENT CASE. A surface standing where every default resolves was told nothing, so nothing
  // is handed on — and a child that resolves the same defaults against the same directory stands
  // exactly where its parent does. Passing the defaults down explicitly would read as a decision
  // somebody made and would freeze what is the child's to resolve.
  test('a surface told nothing hands on nothing, defaults included', () {
    expect(placementFrom(given(<String>['serve'])), isEmpty);
  });

  // WHAT IS ABOUT ONE RUN IS NOT PLACEMENT, and must not travel. `--answers` is the envelope ONE
  // caller handed ONE run, and a surface started with one would otherwise give every run it ever
  // launches the same answers — while `--log-level` is how loud THIS process was asked to be.
  test('what belongs to one run, or to this process alone, is not passed on as placement', () {
    final List<String> handed = placementFrom(
      given(<String>[
        'serve',
        '--programs',
        '/srv/ansiwise-catalog/ansiwise/programs',
        '--answers',
        '-',
        '--log-level',
        'debug',
      ]),
    );
    expect(handed, <String>['--programs', '/srv/ansiwise-catalog/ansiwise/programs']);
    for (final String never in <String>['--answers', '--log-level']) {
      expect(handed, isNot(contains(never)), reason: '$never is not where a run stands');
    }
  });
}
