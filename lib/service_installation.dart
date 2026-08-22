/// What the binary places on a machine so the surface outlives the session that installed it.
///
/// **The whole of the first install is one act.** An operator app opens an SSH session, copies this
/// binary over and runs `install-service` on it. That call writes the service token where only root
/// can read it, writes the unit the service manager starts at boot, and switches the service on.
/// From then on the manager reaches the machine over an address instead of over a held-open
/// session, and a restart of the machine changes nothing.
///
/// **The command the unit starts is composed HERE, out of the options this binary was given.** The
/// installer is invoked the way the service is to be invoked — the address, the token file, the
/// programs, the configuration, the record directory — and turns that into the `ExecStart` line.
/// Composed anywhere else it is a copy of this binary's option names kept by somebody who cannot
/// see them change: a unit naming an option this binary does not have exits at start with a usage
/// error, on every boot, for ever, and the only place that is visible is a journal nobody reads.
///
/// **The address is a rule and not a preference**, and [ServiceInstallation.tailnetRange] is where
/// it is enforced.
library;

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_rest/ansiwise_rest.dart';

import 'service_unit.dart';

/// What stands in the way of installing the service.
final class ServiceInstallationRefused implements Exception {
  /// Refuses [because].
  const ServiceInstallationRefused(this.because);

  /// Everything that is wrong, one per line, in the words whoever invoked this reads.
  final String because;

  @override
  String toString() => because;
}

/// The service this binary installs itself as, and everything that has to hold for it.
final class ServiceInstallation {
  /// The installation that starts [executable] on [listen], reading its token from
  /// [serviceTokenFile].
  const ServiceInstallation({
    required this.unit,
    required this.executable,
    required this.startedFrom,
    required this.listen,
    required this.serviceTokenFile,
    required this.programs,
    required this.config,
    required this.runs,
    required this.workingDirectory,
  });

  /// The addresses the resident surface may stand on.
  ///
  /// The tailnet's own range. Every other address is refused, and the two that were considered and
  /// lost are named in the refusal rather than left for somebody to rediscover: a node-local
  /// address is reachable by nothing that has to reach this, and a public one carries the service
  /// token over a wire anybody can read, since the surface speaks plain HTTP and the token is a
  /// header.
  ///
  /// A constant and not an option. A range that could be widened from outside would be a guarantee
  /// this code claims and the caller decides, which is the same as no guarantee.
  static const String tailnetRange = '100.64.0.0/10';

  /// Where the service manager reads its units.
  static const String unitDirectory = '/etc/systemd/system';

  /// `0644` — a unit file the service manager reads.
  static const int unitMode = 0x1a4;

  /// `0600` — the token file, which root alone may read.
  ///
  /// The value is the whole authentication of the surface on an address. An account that can read
  /// it can do everything the surface offers on this machine, so nothing but root may.
  static const int tokenFileMode = 0x180;

  /// `0700` — the directory the token file stands in.
  ///
  /// The file's own bits are what protect the value; the directory's are what stop another account
  /// from replacing the file with one whose value it chose.
  static const int tokenDirectoryMode = 0x1c0;

  /// The lines the rendered unit must carry, and what each of them does.
  ///
  /// Read out of the RENDERED text rather than out of the file, because the file is a template and
  /// what the service manager reads is the rendering. A line lost to an edit here is a service that
  /// installs cleanly and then behaves in a way nothing on the machine explains.
  static const Map<String, String> requiredLines = <String, String>{
    'WantedBy=multi-user.target':
        'without it the unit is installed and never started at boot, so the machine comes back '
        'from a restart with no surface on it',
    'Restart=always':
        'without it the service is gone the first time it dies, including the ordinary case of a '
        'start before the tailnet address it binds exists',
    'KillMode=process':
        "without it the service manager's default takes the unit's whole control group at every "
        'stop, and every detached run started by this service dies with the restart',
  };

  /// The unit text with its slots still in it.
  ///
  /// Handed in rather than read from [serviceUnit] here, so what is rendered can be a text a check
  /// chose. The composition root hands in [serviceUnit] and nothing else does.
  final String unit;

  /// The executable the unit starts, which is this binary.
  final String executable;

  /// The file this process was started from.
  ///
  /// Equal to [executable] when this process IS the compiled binary, and the toolchain's own
  /// executable when it was started from source. The two are compared because a unit rendered from
  /// a checkout would name the toolchain, and a machine has neither it nor the source it would run.
  final String startedFrom;

  /// Where the resident surface is to listen, as `host:port`.
  final String listen;

  /// The file the service reads its token from.
  final String serviceTokenFile;

  /// Where the program files stand.
  final String programs;

  /// The file naming which plugins are active.
  final String config;

  /// Where the records of runs are kept.
  final String runs;

  /// The directory the service starts in, which is where every relative path above is resolved
  /// from — by the service exactly as it was by this installer.
  final String workingDirectory;

  /// The unit file this installs, at the path the service manager reads it from.
  String get unitPath => '$unitDirectory/$serviceUnitName';

  /// The directory [serviceTokenFile] stands in, or null where the path names no directory.
  String? get tokenDirectory {
    final int cut = serviceTokenFile.lastIndexOf('/');
    return cut < 1 ? null : serviceTokenFile.substring(0, cut);
  }

  /// The command the service runs, the executable first and each argument as its own entry.
  ///
  /// The same options this installer was given, which is what makes the running service and the
  /// invocation that installed it one statement rather than two that can disagree.
  ///
  /// **The service's own half is composed by the service**, in [ResidentService.commandOf]: the
  /// word that starts it and the names of its two arguments belong to the package the surface lives
  /// in, and a unit that spelled them out here would go on writing the old spelling after a rename
  /// there. The three that follow are this BINARY's — where the programs stand, which configuration
  /// is active, where records are kept — and only this repository can state them.
  List<String> get command => <String>[
    ...ResidentService.commandOf(
      executable: executable,
      address: listen,
      serviceTokenFile: serviceTokenFile,
    ),
    '--programs',
    programs,
    '--config',
    config,
    '--runs',
    runs,
  ];

  /// Everything that stands in the way, all of it at once.
  ///
  /// Every problem rather than the first, because each one is a thing somebody has to correct in
  /// the invocation and a refusal naming one of three costs three round trips.
  List<String> get problems => <String>[
    if (_addressProblem case final String wrong) wrong,
    if (startedFrom != executable)
      'this process was started from $startedFrom by $executable, so it is not the compiled '
          'binary — the unit would name the toolchain, and a machine has neither it nor a checkout '
          'for it to run\n'
          'build the binary and install the service by running that',
    for (final String entry in command)
      if (entry.contains(' '))
        'the started command carries "$entry", and it has a space in it — the service manager reads '
            'the command line under quoting rules of its own, so a path with a space in it would be '
            'read as two arguments',
  ];

  /// The unit as it is to stand on the machine.
  ///
  /// Throws [ServiceInstallationRefused] naming everything wrong with the invocation, everything
  /// the template and the values disagree about, and every line of [requiredLines] the rendering
  /// does not carry.
  String render() {
    if (problems.isNotEmpty) {
      throw ServiceInstallationRefused(problems.join('\n'));
    }

    final String rendered;
    try {
      rendered = Template(path: serviceUnitName, text: unit).filledWith(<String, String>{
        'command': command.join(' '),
        'working-directory': workingDirectory,
      });
    } on TemplateRefused catch (refused) {
      throw ServiceInstallationRefused(refused.message);
    }

    final List<String> lost = <String>[
      for (final MapEntry<String, String> line in requiredLines.entries)
        if (!_carries(rendered, line.key)) '${line.key} — ${line.value}',
    ];
    if (lost.isNotEmpty) {
      throw ServiceInstallationRefused(
        <String>['the unit rendered from $serviceUnitName does not say:', ...lost].join('\n'),
      );
    }
    return rendered;
  }

  /// What is wrong with [listen], or null where it is an address this service may stand on.
  String? get _addressProblem {
    if (listen.startsWith('unix:')) {
      return 'the resident surface cannot stand on a socket file: it is reached from another '
          'machine, and a socket file is reachable from this one alone\n'
          'say an address in $tailnetRange';
    }

    final int cut = listen.lastIndexOf(':');
    final int? port = cut < 0 ? null : int.tryParse(listen.substring(cut + 1));
    if (cut < 1 || port == null || port < 0 || port > 65535) {
      return '"$listen" does not name an address to serve on — say host:port, where the host is an '
          'address in $tailnetRange';
    }
    if (port == 0) {
      return '"$listen" asks for port 0, which the operating system chooses again at every start\n'
          'a resident service is dialed by a manager that was told where it stands, so the port is '
          'part of the installation and not of the boot';
    }

    String host = listen.substring(0, cut);
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    if (_isInTailnet(host)) {
      return null;
    }
    return '"$host" is not an address in $tailnetRange, and that is where this service listens\n'
        'the manager reaches this surface over plain HTTP and presents the service token in a '
        'header, so the tailnet is what keeps that credential between the two ends; a public '
        'address puts it on the open internet, and a node-local address is reached by nothing that '
        'has to reach this — the manager runs as a workload in the cluster, where 127.0.0.1 is its '
        'own pod';
  }

  /// Whether [host] stands in [tailnetRange], which spans 100.64.0.0 to 100.127.255.255.
  ///
  /// The address is read as four numbers rather than matched as text: 100.64.0.7 and 100.127.3.9
  /// are both in the range and share no prefix, so a comparison on the written form would answer
  /// about the spelling instead of about the address.
  static bool _isInTailnet(String host) {
    final List<String> written = host.split('.');
    if (written.length != 4) {
      return false;
    }
    final List<int> octets = <int>[];
    for (final String each in written) {
      final int? number = int.tryParse(each);
      if (number == null || number < 0 || number > 255) {
        return false;
      }
      octets.add(number);
    }
    return octets[0] == 100 && octets[1] >= 64 && octets[1] <= 127;
  }

  /// Whether [rendered] carries [line] as a line of its own.
  ///
  /// Whole lines, so a key that appears inside a comment or as part of a longer setting does not
  /// answer for the setting itself.
  static bool _carries(String rendered, String line) =>
      rendered.split('\n').any((String each) => each.trim() == line);
}
