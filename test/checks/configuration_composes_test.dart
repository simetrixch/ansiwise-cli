import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_checks_tree/ansiwise_checks_tree.dart';
import 'package:ansiwise_cli/plugins.dart';
import 'package:test/test.dart';

/// configuration-composes — the installation's own configuration file composes into a registry this
/// binary can actually offer.
///
/// THE FAILURE THIS EXISTS FOR IS THE EARLIEST ONE THERE IS. Composing the registry is the first
/// thing `bin/ansiwise.dart` does after reading the file, before a program is loaded and long before
/// a machine is touched. A name that is not compiled in ends the binary at start-up for every
/// program on every machine — and a configuration is written in one repository while the binary is
/// built from another, so nothing but a check that reads both can notice.
///
/// It composes the registry the way the binary composes it and in the same order: the plugins the
/// file turns on, then the conditions the same file names bound onto them. Both halves refuse the
/// same way and at the same moment, which is why they are one check and not two.
///
/// The installation is found through the one resolution every audit here uses, so this suite and the
/// program checks beside it cannot come to disagree about which tree they are judging.
Future<void> main() async {
  // SKIPPED WHERE THERE IS NO INSTALLATION TO READ, and the reason is printed rather than passed
  // over. This suite reads the programs of an INSTALLATION, and an installation lives in its own
  // repository — so a clone of this one standing alone has nothing here to be right or wrong about.
  // Refusing would call a sound repository broken; passing silently would let a green gate claim a
  // check that never ran. Saying so is the only honest third thing.
  if (!installationIsFindable) {
    test('configuration-composes', () {}, skip: installationNotFound);
    return;
  }
  final String file = '$installationRoot/${Configuration.defaultFileName}';
  final Configuration active = await Configuration.load(files: const RealFiles(), path: file);

  /// The registry [configuration] composes to, or the refusal an operator would meet at start-up.
  ///
  /// The two calls the binary makes, in the order it makes them. Written here rather than in each
  /// probe so what is planted below meets exactly what the installation meets.
  Registry compose(Configuration configuration) => bindConditions(
    registry: compiledPlugins.activate(configuration.plugins),
    named: configuration.conditions,
    where: file,
  );

  test('$file turns on at least one plugin', () {
    // The denominator of everything below. A configuration naming nothing would compose an empty
    // registry, every probe would pass over it, and the check would report green having measured
    // nothing.
    expect(
      active.plugins,
      isNotEmpty,
      reason: 'a check over a configuration that turns nothing on judges nothing',
    );
  });

  test('every name it turns on is compiled into this binary', () {
    final Registry composed = compose(active);

    print(
      'configuration-composes read ${active.plugins.length} plugin name(s) '
      '(${active.plugins.join(', ')}) and ${active.conditions.length} condition(s) '
      'out of $file, composing ${composed.steps.length} step(s) and '
      '${composed.predicates.length} condition(s)',
    );
    expect(
      composed.steps,
      isNotEmpty,
      reason: 'the composed registry holds no step, so every program would be refused',
    );
  });

  test('every condition it names binds to a condition this binary carries', () {
    final Registry composed = compose(active);

    for (final String named in active.conditions.keys) {
      expect(
        composed.predicate(PredicateName(named)),
        isNotNull,
        reason:
            '"$named" stands behind "when:" in the shipped programs and nothing in this binary '
            'answers it',
      );
    }
  });

  group('counter-probe', () {
    // Five configurations written here and put through the same composition. Four must be refused
    // and one must be accepted: a composition that refused everything would turn this whole file
    // red for the wrong reason, and one that accepted everything would report an installation
    // correct against a binary that cannot run it.

    Future<Configuration> planted(String yaml) => Configuration.load(
      files: FakeFiles(<String, String>{'planted.yaml': yaml}),
      path: 'planted.yaml',
    );

    String listing(Iterable<String> names) =>
        <String>[for (final String name in names) '  - $name'].join('\n');

    test('the compiled plugin names, exactly as they are, compose', () async {
      final Configuration honest = await planted('plugins:\n${listing(compiledPlugins.names)}\n');

      expect(
        () => compose(honest),
        returnsNormally,
        reason: 'this composition refuses everything, so the refusals below prove nothing',
      );
    });

    test('a name the binary does not carry is refused, saying what it carries', () async {
      final Configuration wrong = await planted(
        'plugins:\n${listing(<String>[...compiledPlugins.names, 'no-such-plugin'])}\n',
      );

      expect(
        () => compose(wrong),
        throwsA(
          isA<PluginRejected>()
              .having(
                (PluginRejected refused) => refused.message,
                'message',
                contains('"no-such-plugin" is not compiled into this binary'),
              )
              // A different BUILD is the fix, not a different line in the file, and a bare "unknown
              // plugin" would send the operator editing configuration forever.
              .having(
                (PluginRejected refused) => refused.message,
                'message',
                contains('it carries: ${compiledPlugins.names.join(', ')}'),
              ),
        ),
      );
    });

    test('a list that turns nothing on is refused', () async {
      final Configuration empty = await planted('plugins: []\n');

      expect(
        () => compose(empty),
        throwsA(
          isA<PluginRejected>().having(
            (PluginRejected refused) => refused.message,
            'message',
            contains('no plugin is active'),
          ),
        ),
      );
    });

    test('a name written twice is refused rather than read once', () async {
      final Configuration twice = await planted(
        'plugins:\n${listing(<String>[compiledPlugins.names.first, compiledPlugins.names.first])}\n',
      );

      expect(
        () => compose(twice),
        throwsA(
          isA<PluginRejected>().having(
            (PluginRejected refused) => refused.message,
            'message',
            contains('"${compiledPlugins.names.first}" is activated twice'),
          ),
        ),
      );
    });

    test('a condition bound to a generic one nothing registers is refused', () async {
      final Configuration unbound = await planted(
        'plugins:\n${listing(compiledPlugins.names)}\n'
        'conditions:\n'
        '  planted_condition:\n'
        '    predicate: no_such_condition\n',
      );

      expect(
        () => compose(unbound),
        throwsA(
          isA<PluginRejected>().having(
            (PluginRejected refused) => refused.message,
            'message',
            contains('no_such_condition'),
          ),
        ),
      );
    });
  });
}
