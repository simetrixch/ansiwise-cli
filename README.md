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

On the release tag the Trigger `github-release-publish` of the owner's master (hostyour-cloud
`clusters/inventories/image-builder/templates/triggers/github-release-publish.yaml`) starts the
publish pipeline `ansiwise-cli-publish` (hostyour-cloud
`clusters/inventories/consumer-build/templates/pipeline-publish.yaml`), which clones this repository
at the tag and runs `release/build.sh`. It loads the three parts at those commits, runs each part's gate and then
this repository's, and only then compiles the two binaries for linux-x64 on a linux-x64 host; it
refuses a Dart other than the gate's pin and a binary that does not answer the tag. A part that is
red stops the release before a binary exists. The pipeline pushes the binaries as one manifest to
Zot, `zot.master.digitacloud.app/simetrixch/ansiwise-cli:<tag>`, which is what a machine downloads.

    release/release.sh <x.y.z> <stable|beta|alpha>    cut a release, end to end
    bash release/build.sh <tag> <out-dir>              build the binaries of one tag

The script waits for that manifest, and writes the two pins downstream — the engine version in
hostyour-cloud and the tool stamp in the programs repository — only once the binaries exist. Beside
the engine version it writes `clusters/platform/ansiwise.sha256`: the SHA-256 Zot holds for each
binary of the release's manifest, in the same commit as the pin, or in a commit of its own where the
head already names the tag without them. A machine is placed only the bytes those lines name, so a
release that lacks a digest for any binary release/build.sh builds is refused before anything is pinned.

    dart run tool/ci.dart               the gate, on this machine
    ansiwise <program> --mode test|dry|run

`release/release.sh` is the operator's command and the only one that mints a release of this
repository: the Manager does not call it.

`scripts/check.sh` runs on the machine before every push: the push gate of the pre-push hook runs
it, and a red check refuses the push. No ci runs it anywhere else.
The build of a release installs the Dart that `ci-tools.json` names before it runs `release/build.sh`.
