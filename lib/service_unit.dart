// GENERATED from ansiwise.service by tool/build.dart. Do not edit.
//
// The unit's ExecStart is composed from this binary's own option names, so a unit
// kept anywhere else is a second statement of an interface only this repository
// decides. It travels inside the binary, and this file is how it gets in.
//
// The text is ansiwise.service. Edit that and build; a check reports a copy
// here that says anything else.
library;

/// The name the service manager knows the service by.
///
/// The unit file's own base name, so the file this repository keeps, the file a
/// machine holds and the name a `systemctl` line mentions are one value.
const String serviceUnitName = 'ansiwise.service';

/// The unit the binary installs itself under, slots and all.
const String serviceUnit =
    '[Unit]\n'
    'Description=ansiwise deployment surface\n'
    '# WHAT THIS FILE IS. The unit the binary compiled from this repository installs\n'
    '# itself under, and the reason it lives beside that binary rather than beside an\n'
    '# installation\'s programs: its ExecStart is composed of this binary\'s own options,\n'
    '# and a unit kept anywhere else drifts from them with nothing reporting it. Its\n'
    '# BASE NAME is the name the service manager knows the service by, so the file, the\n'
    '# unit and the name a `systemctl` line mentions are one value.\n'
    '#\n'
    '# The two slots below are filled by lib/service_installation.dart with the whole\n'
    '# started command and the directory it starts in. Nothing else in this file is\n'
    '# per-installation, and a slot named here in a comment would be filled too.\n'
    '#\n'
    '# The service manager reads a unit only from its own directory. This copy is the\n'
    '# source; the one it reads is written to /etc/systemd/system by the installer.\n'
    '#\n'
    '# Every run this service starts reaches a network — a catalogue to clone, a chart\n'
    '# to pull, an image registry to read. network-online.target is what the service\n'
    '# manager offers for "an address can be bound and a name can be resolved";\n'
    '# network.target is up well before that is true.\n'
    'After=network-online.target\n'
    'Wants=network-online.target\n'
    '\n'
    '[Service]\n'
    '# WHERE THIS LISTENS STANDS IN THE COMMAND, AND IT IS THE MACHINE\'S TAILNET ADDRESS.\n'
    '#\n'
    '# The caller is the manager, and it speaks plain HTTP and presents the service token\n'
    '# in an Authorization header. So the address decides whether that credential crosses\n'
    '# a wire somebody else can read: the tailnet carries it inside WireGuard between two\n'
    '# members and nowhere else, while a public port puts the same header on the open\n'
    '# internet with one bearer token in front of it.\n'
    '#\n'
    '# The node-local address was the other candidate and it reaches nobody that has to\n'
    '# reach this. The manager runs as a workload in the cluster, where 127.0.0.1 is its\n'
    '# own pod and not this machine — so a node-local bind would be reachable only\n'
    '# through an SSH tunnel, which is the held-open session this resident service exists\n'
    '# to stop needing. What node-local WOULD serve is somebody standing on the machine,\n'
    '# and they have `ansiwise serve` over their own session for that.\n'
    '#\n'
    '# lib/service_installation.dart refuses every address outside the tailnet range, so\n'
    '# the paragraph above is a rule and not a preference.\n'
    'ExecStart=<command>\n'
    'WorkingDirectory=<working-directory>\n'
    '# It comes back when it dies, and it keeps coming back while the tailnet address it\n'
    '# binds is not there yet — the state a machine is in for the first seconds after a\n'
    '# restart, where the bind fails and this is the only thing that tries again.\n'
    'Restart=always\n'
    'RestartSec=5\n'
    '# THE LINE THIS SERVICE EXISTS AROUND. Every run is started DETACHED so it outlives\n'
    '# the surface that accepted it. The default kill mode takes the unit\'s whole control\n'
    '# group with every stop, a restart is a stop, and a detached process gets a new\n'
    '# session rather than a new control group — so without this line a 45-minute\n'
    '# deployment dies with the restart of the service that launched it, and nothing on\n'
    '# the machine says why.\n'
    'KillMode=process\n'
    '\n'
    '[Install]\n'
    '# What makes it start on boot: the target the service manager reaches on its way up\n'
    '# pulls this unit in.\n'
    'WantedBy=multi-user.target\n';
