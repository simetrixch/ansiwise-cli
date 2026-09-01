# ansiwise-cli

The two binaries an operator actually starts.

`bin/ansiwise.dart` runs a declared program of steps against the machine it is on. `bin/ansiwise_rest.dart`
is the same engine behind a REST surface, so a deployment can be started by something other than a
person at a terminal — it stands on an address and demands a service token, or speaks over the pipes
of a session sshd has already authenticated.

This repository holds no steps and no engine. It is the composition root: the one place that decides
which real implementation each port gets, built once and handed down. The engine is
[ansiwise-core](https://github.com/simetrixch/ansiwise-core), the steps are
[ansiwise-plugins](https://github.com/simetrixch/ansiwise-plugins), the criteria every gate judges
by are [ansiwise-checks](https://github.com/simetrixch/ansiwise-checks) — and all three are named
here by COMMIT.

## This is the only thing released, and the only place anything is built

Those three are passive parts: they carry no version, cut no tag, publish nothing and build nothing.
A release of this repository names the commit of each it was built from, and `release/release.sh`
writes those commits before it mints anything.

The one workflow of the family lives here. It loads all four trees at those commits, lints and tests
every one of them, and only then compiles the two binaries for linux-x64 and attaches them — which
is what a machine downloads. A part that is red stops the release before a binary exists.

    release/release.sh <x.y.z> <stable|beta|alpha>    cut a release, end to end
    release/release.ps1 <x.y.z> <stable|beta|alpha>   the same on Windows

The script waits at the build it started, and writes the two pins downstream — the engine version in
hostyour-cloud and the tool stamp in the deployment catalogue — only once the binaries exist.

    dart run tool/ci.dart               the gate, on this machine
    ansiwise <program> --mode test|dry|run
