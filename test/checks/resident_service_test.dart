import 'dart:convert';
import 'dart:io';

import 'package:ansiwise_checks_tree/ansiwise_checks_tree.dart';
import 'package:test/test.dart';

/// the resident service — `service --listen <address>` binds, says where
/// it stands, and answers over that address.
///
/// This is the door a manager uses on an INSTALLED machine, where nobody holds an SSH session open
/// for it — the session form of `serve` stays beside it and is covered by subcommands-start. What
/// is judged here is the whole path through the real binary against the real installation: the
/// option reaches the bind, the bind's actual port is announced on standard output (asked for as
/// port 0, so the announcement is the only place the truth exists), and the same catalogue the
/// channel form serves comes back over the wire.
///
/// The refusal is judged with the same weight: an address in no accepted shape must stop the
/// service at start with a usage exit, because a resident unit that came up listening nowhere — or
/// somewhere it guessed — is a service an operator believes is standing and is not.
Future<void> main() async {
  // SKIPPED WHERE THERE IS NO INSTALLATION TO READ, printed rather than passed over: what is judged
  // here is this binary against an installation's configuration, and a clone of this repository
  // standing alone has none.
  if (!installationIsFindable) {
    test('service', () {}, skip: installationNotFound);
    return;
  }

  final String installation = installationRoot;
  final String programs = '$installation/$installationPrograms';
  final String configuration = '$installation/ansiwise.yaml';

  // The credential the address door demands. Written to a file because that is how the service is
  // given one: the PATH may stand in argv, the VALUE never may.
  late Directory held;
  late String tokenFile;
  const String tokenValue = 'a-token-for-the-resident-service-check';

  setUp(() {
    held = Directory.systemTemp.createTempSync('ansiwise-resident-service');
    tokenFile = '${held.path}/token';
    File(tokenFile).writeAsStringSync(tokenValue);
  });

  tearDown(() => held.deleteSync(recursive: true));

  group('service', () {
    test('binds the address, announces where it stands, and answers over it', () async {
      final Process service = await Process.start('dart', <String>[
        'run',
        'bin/ansiwise_rest.dart',
        'service',
        '--listen',
        '127.0.0.1:0',
        '--service-token-file',
        tokenFile,
        '--programs',
        programs,
        '--config',
        configuration,
      ], workingDirectory: Directory.current.path);
      await service.stdin.close();
      final StringBuffer complained = StringBuffer();
      service.stderr.transform(utf8.decoder).listen(complained.write);

      try {
        final String announced = await service.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .firstWhere((String line) => line.startsWith('serving on '))
            .timeout(
              const Duration(seconds: 110),
              onTimeout: () =>
                  fail('the service never said where it stands\nstderr so far:\n$complained'),
            );
        final int port = int.parse(announced.split(':').last);

        final HttpClient client = HttpClient();
        try {
          final HttpClientRequest ask = await client.getUrl(
            Uri.parse('http://127.0.0.1:$port/programs'),
          );
          ask.headers.set(HttpHeaders.authorizationHeader, 'Bearer $tokenValue');
          final HttpClientResponse answer = await ask.close();
          final String body = await utf8.decodeStream(answer);
          expect(answer.statusCode, 200);
          expect(
            body,
            contains('deploy-host'),
            reason: 'the resident form must serve the same catalogue the session form does',
          );
        } finally {
          client.close(force: true);
        }
      } finally {
        service.kill();
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('an address in no accepted shape is refused at start, as usage', () async {
      final ProcessResult refused = await Process.run('dart', <String>[
        'run',
        'bin/ansiwise_rest.dart',
        'service',
        '--listen',
        'nonsense',
        '--service-token-file',
        tokenFile,
        '--programs',
        programs,
        '--config',
        configuration,
      ], workingDirectory: Directory.current.path);

      expect(
        refused.exitCode,
        64,
        reason:
            'a service that cannot know where to stand must fail at start where an operator is '
            'looking\nstderr:\n${refused.stderr}',
      );
      expect(refused.stderr, contains('host:port'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'THE INNOCENT NEIGHBOUR: serve without --listen still speaks over its own stdio',
      () async {
        // A closed standard input is a session that ends immediately; what matters is that the
        // session form still starts and returns rather than demanding an address it never needed.
        final Process session = await Process.start('dart', <String>[
          'run',
          'bin/ansiwise_rest.dart',
          'serve',
          '--programs',
          programs,
          '--config',
          configuration,
        ], workingDirectory: Directory.current.path);
        await session.stdin.close();
        final List<String> out = <String>[
          await utf8.decodeStream(session.stdout),
          await utf8.decodeStream(session.stderr),
        ];
        expect(await session.exitCode, 0, reason: 'stderr:\n${out.last}');
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
    test('an address with no token file behind it refuses to start at all', () async {
      // The one failure this whole seam exists to make impossible: a surface standing on an address
      // while nothing decides who may reach it. It is refused as usage, before a bind.
      final Process service = await Process.start('dart', <String>[
        'run',
        'bin/ansiwise_rest.dart',
        'service',
        '--listen',
        '127.0.0.1:0',
        '--programs',
        programs,
        '--config',
        configuration,
      ], workingDirectory: Directory.current.path);
      await service.stdin.close();
      final String complained = await utf8.decodeStream(service.stderr);

      expect(await service.exitCode, 64);
      expect(complained, contains('authenticated by nothing'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a token file named but not there refuses by its path, not with a stack trace', () async {
      // What a unit enabled before install-service ran meets, and what an operator who cleared the
      // machine of credentials meets. The path they have to put back is the whole of the answer.
      final ProcessResult refused = await Process.run('dart', <String>[
        'run',
        'bin/ansiwise_rest.dart',
        'service',
        '--listen',
        '127.0.0.1:0',
        '--service-token-file',
        '${held.path}/never-placed',
        '--programs',
        programs,
        '--config',
        configuration,
      ], workingDirectory: Directory.current.path);

      expect(refused.exitCode, 66, reason: 'stderr:\n${refused.stderr}');
      expect(refused.stderr, contains('never-placed'));
      expect(refused.stderr, contains('install-service'));
      expect(
        refused.stderr,
        isNot(contains('#0')),
        reason: 'a stack frame is what stands where the sentence belongs',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a token file holding nothing refuses rather than serving openly', () async {
      final String empty = '${held.path}/empty-token';
      File(empty).writeAsStringSync('   \n');

      final ProcessResult refused = await Process.run('dart', <String>[
        'run',
        'bin/ansiwise_rest.dart',
        'service',
        '--listen',
        '127.0.0.1:0',
        '--service-token-file',
        empty,
        '--programs',
        programs,
        '--config',
        configuration,
      ], workingDirectory: Directory.current.path);

      expect(refused.exitCode, 66, reason: 'stderr:\n${refused.stderr}');
      expect(refused.stderr, contains('holds no token'));
      expect(refused.stderr, isNot(contains('#0')));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a caller on the address without the token is refused, and told nothing else', () async {
      final Process service = await Process.start('dart', <String>[
        'run',
        'bin/ansiwise_rest.dart',
        'service',
        '--listen',
        '127.0.0.1:0',
        '--service-token-file',
        tokenFile,
        '--programs',
        programs,
        '--config',
        configuration,
      ], workingDirectory: Directory.current.path);
      await service.stdin.close();

      try {
        final String announced = await service.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .firstWhere((String line) => line.startsWith('serving on '));
        final int port = int.parse(announced.split(':').last);

        final HttpClient client = HttpClient();
        try {
          Future<int> statusOf(String? presented) async {
            final HttpClientRequest ask = await client.getUrl(
              Uri.parse('http://127.0.0.1:$port/programs'),
            );
            if (presented != null) {
              ask.headers.set(HttpHeaders.authorizationHeader, presented);
            }
            final HttpClientResponse answer = await ask.close();
            await utf8.decodeStream(answer);
            return answer.statusCode;
          }

          expect(await statusOf(null), 401, reason: 'the door stood open');
          expect(await statusOf('Bearer not-the-token'), 401);
          expect(await statusOf('Bearer '), 401);
          // THE INNOCENT NEIGHBOUR: the right token still gets through, so the refusals above are
          // the gate deciding and not the surface being broken.
          expect(await statusOf('Bearer $tokenValue'), 200);
        } finally {
          client.close(force: true);
        }
      } finally {
        service.kill();
        await service.exitCode;
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
