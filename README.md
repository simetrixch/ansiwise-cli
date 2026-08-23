# ansiwise-cli

The two binaries an operator actually starts.

`bin/ansiwise.dart` runs a declared program of steps against the machine it is on. `bin/ansiwise_rest.dart`
is the same engine behind a REST surface, so a deployment can be started by something other than a
person at a terminal — it stands on an address and demands a service token, or speaks over the pipes
of a session sshd has already authenticated.

This repository holds no steps and no engine. It is the composition root: the one place that decides
which real implementation each port gets, built once and handed down. The engine is
[ansiwise-core](https://github.com/simetrixch/ansiwise-core), the steps are
[ansiwise-plugins](https://github.com/simetrixch/ansiwise-plugins), and both are named here by
release tag.

A release compiles the two binaries for linux-x64 and attaches them, which is what a machine
downloads. Nothing else in the family produces a file.

    dart run tool/release.dart          what has been released, and what could come next
    ansiwise <program> --mode test|dry|run
