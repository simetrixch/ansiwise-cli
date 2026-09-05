<#
.SYNOPSIS
  release.ps1 — the one command that releases ansiwise. Bash twin: release.sh in this folder.
  The two are held to answering identically.

.DESCRIPTION
  ansiwise-cli is the product. ansiwise-core, ansiwise-plugins and ansiwise-checks are its parts:
  they are released by nobody, they carry no workflow, and nothing is built in them. This script
  names the commit of each part this engine is built from, mints the tag, and waits at the one
  workflow that tag starts — the only place anything of ansiwise is built. That workflow loads all
  four trees, lints and tests every one of them, and builds the executable. When it comes back
  green this script writes the two pins downstream that make the new engine the one an
  installation takes.

  WHY IT WAITS. A release that ends when the tag is pushed hands back a number nobody has
  verified, and the pins downstream would then name an engine that may never exist. So the tag is
  the middle of this script, not its end.

  EVERYTHING IT WILL NEED IS CHECKED BEFORE ANYTHING IS MINTED. A tag is a public fact and a push
  cannot be taken back, so the foreseeable failures are met first: a dirty tree, a missing tool, no
  push rights on a repository this release has to write to. Those refusals all end with the same
  sentence, and that sentence is the point of their order.

.EXAMPLE
  release/release.ps1 0.8.105 stable
#>
# NEITHER IS Mandatory, and the usage refusal below is why. A mandatory parameter left out is
# answered by PowerShell with "missing mandatory parameters: Version Channel" — or, invoked any way
# but `-File`, with a PROMPT, which is a release script waiting for somebody to type. The bash twin
# answers a usage line, so this one does too.
[CmdletBinding()]
param(
  [Parameter(Position = 0)][string] $Version,
  [Parameter(Position = 1)][string] $Channel
)

$ErrorActionPreference = 'Stop'

# The refusals below carry an em dash, and both twins have to print it as the same characters.
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }

# WRITTEN, NOT RAISED. `Write-Error` under $ErrorActionPreference = 'Stop' is itself a terminating
# error, so every refusal below would be caught by the catch this script now has and reported a
# second time, wrapped in a stack frame. Written to standard error it is the one sentence the bash
# twin also prints, and `exit` from inside the try is not catchable — the finally still runs, so the
# temporary directory is still removed.
function Die([string] $Message) { [Console]::Error.WriteLine("release: $Message"); exit 1 }
function Say([string] $Message) { Write-Host "release: $Message" }

if (-not $Version -or -not $Channel) {
  Die 'usage: release/release.ps1 <x.y.z> <stable|beta|alpha>'
}
if ($Version -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
  Die "version must be x.y.z with no leading zeros (got '$Version')"
}
if ($Channel -notin @('stable', 'beta', 'alpha')) {
  Die "channel must be stable|beta|alpha (got '$Channel')"
}

Set-Location (git rev-parse --show-toplevel)
# THE SECOND HALF OF THAT MOVE, and the whole of ansiwise-cli#15. A PowerShell process carries TWO
# current directories: its own location, which the line above moves and which every cmdlet and every
# child process is answered from, and [Environment]::CurrentDirectory, which .NET resolves every
# relative path against and which `Set-Location` does not touch. Left apart, a relative path handed
# to [System.IO.*] names a file in whatever directory this shell was standing in earlier — and this
# script reads and rewrites pubspec.yaml. Measured on 2026-09-05 cutting 0.8.109 from a shell whose
# process directory was a sibling checkout: the read threw. Measured again against a sibling that
# HAS a pubspec.yaml: the read succeeded, and this repository's manifest was overwritten with that
# repository's — name, version, every dependency — with nothing said.
#
# ONE ASSIGNMENT AND NOT ABSOLUTE PATHS AT EVERY CALL. This is a rule and those are a list: a
# [System.IO.*] call written into this script later is correct under the assignment and wrong under
# the list. Nothing below moves either directory again.
[Environment]::CurrentDirectory = $PWD.ProviderPath

# ── everything this release will need, before it mints anything ──────────────
if (git status --porcelain) {
  Die 'the worktree is dirty — commit or stash first. Nothing has been minted or pushed'
}
foreach ($tool in @('git', 'gh')) {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    Die "$tool is not on this path and this release needs it. Nothing has been minted or pushed"
  }
}

$platformRepo = 'simetrixch/hostyour-cloud'
$catalogRepo = 'simetrixch/hostyour-deploy'
$platformPin = 'clusters/platform/versions.yaml'
$catalogPin = 'ansiwise/programs/deploy-cluster.yaml'

$work = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $work | Out-Null
# Whether the tag is public yet, which is the one thing the catch below cannot work out for itself
# and the only thing that changes what it may promise.
$minted = $false
try {
  foreach ($pair in @(@{ Repo = $platformRepo; At = 'platform' }, @{ Repo = $catalogRepo; At = 'catalog' })) {
    git clone --quiet "https://github.com/$($pair.Repo).git" (Join-Path $work $pair.At)
    if ($LASTEXITCODE -ne 0) {
      Die "$($pair.Repo) could not be cloned, so this release could not write its pin. Nothing has been minted or pushed"
    }
    $env:GIT_TERMINAL_PROMPT = '0'
    git -C (Join-Path $work $pair.At) push --dry-run --quiet origin HEAD 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
      Die "this machine may not push to $($pair.Repo), so this release could not write its pin. Nothing has been minted or pushed"
    }
  }
  Say 'both trees this release pins are reachable and would accept a push'

  # ── the exact commit of each part this engine is built from ────────────────
  # A COMMIT, NOT A TAG. The parts are released by nobody, so there is no tag of theirs to name —
  # and a commit is the stronger statement anyway: a tag can be moved onto another tree, a commit
  # cannot, because its name IS its content. The release notes give back the legibility a tag
  # carries, by naming each one.
  #
  # ONE PLACE PER REPOSITORY, however many packages it holds: ansiwise-plugins is a dozen packages
  # in one tree and every one of them is named out of the same checkout. A rewrite that matched a
  # loose version string instead would reach the neighbouring repository's ref as well,
  # overwriting the ansiwise-core ref with a plugins tag.
  foreach ($repo in @('ansiwise-core', 'ansiwise-plugins', 'ansiwise-checks')) {
    $sha = (git ls-remote "https://github.com/simetrixch/$repo.git" refs/heads/master) -split "`t" | Select-Object -First 1
    if (-not $sha) { Die "$repo has no master to build from. Nothing has been minted or pushed" }

    $lines = [System.IO.File]::ReadAllLines('pubspec.yaml')
    $inside = $false
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
      if ($line -match "url:\s*https://github\.com/simetrixch/$([regex]::Escape($repo))\.git") {
        $out.Add($line); $inside = $true; continue
      }
      if ($inside -and $line -match '^\s*ref:\s*') {
        $out.Add(($line -replace 'ref:\s*.*', "ref: $sha")); $inside = $false; continue
      }
      $out.Add($line)
    }
    # JOINED WITH LF AND NOT WriteAllLines, which ends every line with Environment.NewLine — CRLF on
    # the one platform this twin runs on. .gitattributes of this repository says `*.yaml text
    # eol=lf` for the WORKING COPY, and pubspec.yaml is the only file in the tree that carried
    # carriage returns: 107 of them, put there by this line, while the bash twin left none. git
    # normalises them out of the commit, so the two twins agree about what is pushed and disagree
    # about what is on disk — which is the same file named two ways this issue is about, one level
    # down.
    [System.IO.File]::WriteAllText('pubspec.yaml', ($out -join "`n") + "`n")
    Say "  $repo at $($sha.Substring(0,12))"
  }
  if (Select-String -Path pubspec.yaml -Pattern 'ref: master' -Quiet) {
    Die 'a part is still named by a branch rather than a commit. Nothing has been minted or pushed'
  }

  # ── the manifest is resolved before anything is minted ────────────────────
  # THE LAST FORESEEABLE FAILURE, and the one this script used to leave to the build.
  # Each part names its siblings as well, and nothing here moves those: a part that
  # names another at an older commit asks the resolver for one repository at two
  # commits through two paths, which it refuses. The refusal is reported against
  # whichever package it reached first, so it names one nobody edited, and it
  # arrives minutes after a tag is already public. Measured twice in one release on
  # 2026-09-03, each time costing a tag that named nothing and a build that read it.
  #
  # The cost is small where the failure is not: resolving fetches the four trees,
  # and this script has already asked every one of them for its master.
  Say 'resolving the parts named above, together, before anything is minted'
  $resolved = (& dart pub get 2>&1 | Out-String)
  if ($LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine($resolved)
    Die 'the parts this release names cannot be resolved together. The lines above are the resolver, and they name the two packages that disagree. Nothing has been minted or pushed'
  }

  # ── mint, which is what starts the one build ───────────────────────────────
  $tag = "$Version-$Channel-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
  $manifest = [System.IO.File]::ReadAllText('pubspec.yaml')
  $manifest = [regex]::Replace($manifest, '(?m)^version:\s*\S+', "version: $Version", 1)
  [System.IO.File]::WriteAllText('pubspec.yaml', $manifest)
  # READ BACK, because what is committed below is not looked at again. A manifest whose version line
  # is spelled in some way this pattern does not match is written unchanged and committed under a
  # tag naming a version it does not carry.
  if (-not (Select-String -Path pubspec.yaml -Pattern "^version: $([regex]::Escape($Version))$" -Quiet)) {
    Die 'the version could not be written into pubspec.yaml. Nothing has been minted or pushed'
  }

  git add -- pubspec.yaml
  # A BUMP THAT IS ALREADY THERE IS NOT A FAILURE. A release whose build went red
  # leaves this commit behind: the manifest names the version and the three parts,
  # and only the tag and the pins are missing. Running the release again then finds
  # nothing to commit, and refusing there is refusing the repair.
  #
  # WHAT IS COMMITTED IS STILL CHECKED: the lines above wrote the version and the
  # three refs and read them back, so an empty index here means the file already
  # says what this run means it to say.
  git diff --cached --quiet -- pubspec.yaml
  if ($LASTEXITCODE -ne 0) {
    git commit --quiet -m "release: $tag"
    if ($LASTEXITCODE -ne 0) { Die 'the version bump could not be committed' }
  }
  else {
    Say "the manifest already names $Version and these three parts, so there is nothing to commit"
  }
  git tag $tag
  git push --quiet origin HEAD
  git push --quiet origin $tag
  $minted = $true
  Say "the tag $tag is on origin — the one build has started"

  # ── wait at that build, asked for BY NAME ──────────────────────────────────
  # NEVER `gh run list --limit 1`. In the seconds after a push the newest run is still the PREVIOUS
  # release's, and reading it reports a verdict that belongs to another tag: a script that does
  # exactly that announces a green build for a release that has not started.
  $state = ''
  $runId = ''
  for ($i = 0; $i -lt 120; $i++) {
    # BY headBranch AND NOT BY THE COMMIT TITLE. A tag push names the tag there, and it is
    # the only field that says which tag a run belongs to. The title is the head commit's
    # message, which names whatever tag was last committed - so a release that had nothing
    # to commit looks for a run under the previous tag's name and never finds its own.
    #
    # THE RUN'S NUMBER IS TAKEN WITH ITS STATE, in one reading rather than a second one
    # afterwards. A later listing can answer about a different run, and the number is what
    # the log below is asked for by.
    $found = (gh run list --limit 15 --json headBranch,status,conclusion,databaseId `
        -q ".[] | select(.headBranch == `"$tag`") | .status+`" `"+(.conclusion//`"`")+`" `"+(.databaseId|tostring)" |
      Select-Object -First 1)
    if ($found) {
      $parts = $found -split ' '
      $runId = $parts[-1]
      $state = ($parts[0..($parts.Count - 2)] -join ' ')
    }
    if ($state -like 'completed*') { break }
    Start-Sleep -Seconds 20
  }
  if ($state -ne 'completed success') {
    # THE REASON IS PRINTED HERE, not left to a command somebody is told to run next. Whoever
    # reads this failure is standing at a terminal with the credential already in hand, and a
    # release that sends them one round trip away for the cause has answered nothing. The
    # FAILED STEPS are what the build refused on; the whole log is thousands of lines of green
    # and buries them.
    if ($runId) {
      [Console]::Error.WriteLine("----- the failed steps of run $runId -----")
      $log = (gh run view $runId --log-failed 2>&1 | Select-Object -Last 120)
      if ($log) { $log | ForEach-Object { [Console]::Error.WriteLine($_) } }
      else { [Console]::Error.WriteLine("the log of run $runId could not be read") }
      [Console]::Error.WriteLine("----- end of run $runId -----")
    }
    $said = if ($state) { $state } else { 'it never appeared' }
    Die "the build of $tag did not finish green ($said) — the tag stands, and the pins are NOT written"
  }
  Say "the build of $tag is green"

  $assets = (gh release view $tag --json assets -q '[.assets[].name]|join(", ")')
  if (-not $assets) { Die "the release $tag carries no binaries, so nothing may be pinned to it" }
  Say "binaries: $assets"

  # ── the two pins downstream ────────────────────────────────────────────────
  # MATCHED ON THE SHAPE OF A TAG rather than on the neighbouring words, so a file that renames its
  # keys still pins — and a file carrying no pin at all says so instead of being silently left
  # behind.
  function Write-Pin([string] $File, [string] $Pattern, [string] $Replacement) {
    $text = [System.IO.File]::ReadAllText($File)
    $next = [regex]::Replace($text, $Pattern, $Replacement)
    [System.IO.File]::WriteAllText($File, $next)
    if ($next -notlike "*$tag*") {
      Die "$File carries no pin this release could write — the tag stands, and that tree is unchanged"
    }
  }
  $shape = '[0-9]+\.[0-9]+\.[0-9]+-[a-z]+-[0-9]{14}'

  Write-Pin (Join-Path $work "platform/$platformPin") "version: `"$shape`"" "version: `"$tag`""
  git -C (Join-Path $work 'platform') commit --quiet -a `
    -m "Pin the engine at $Version $Channel" `
    -m 'Written by the release of ansiwise-cli, once its binaries were built.'
  git -C (Join-Path $work 'platform') push --quiet origin HEAD
  Say "pinned $platformRepo $platformPin"

  Write-Pin (Join-Path $work "catalog/$catalogPin") "- ansiwise=$shape" "- ansiwise=$tag"
  git -C (Join-Path $work 'catalog') commit --quiet -a `
    -m "Stamp the ansiwise $Version $Channel pin into the cluster deploy program" `
    -m 'Written by the release of ansiwise-cli, once its binaries were built.'
  git -C (Join-Path $work 'catalog') push --quiet origin HEAD
  Say "stamped $catalogRepo $catalogPin"

  Say "DONE — $tag is built, and every tree that names an engine names this one"
}
# WHAT WAS NEVER FORESEEN STILL ENDS IN A SENTENCE. Every refusal above is one this script went
# looking for; this is the rest. Without it a throw ends in a .NET stack frame and the release says
# nothing about where it stopped — which is how 0.8.109 ended, and is the promise at the top of this
# file failing rather than being kept.
catch {
  $standing = if ($minted) {
    " — the tag $tag stands, and the pins are NOT written"
  }
  else {
    '. Nothing has been minted or pushed'
  }
  Die "$_$standing"
}
finally {
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
