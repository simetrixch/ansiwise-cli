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
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)][string] $Version,
  [Parameter(Mandatory = $true, Position = 1)][string] $Channel
)

$ErrorActionPreference = 'Stop'

function Die([string] $Message) { Write-Error "release: $Message"; exit 1 }
function Say([string] $Message) { Write-Host "release: $Message" }

if ($Version -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
  Die "version must be x.y.z with no leading zeros (got '$Version')"
}
if ($Channel -notin @('stable', 'beta', 'alpha')) {
  Die "channel must be stable|beta|alpha (got '$Channel')"
}

Set-Location (git rev-parse --show-toplevel)

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
  # carried, by naming each one.
  #
  # ONE PLACE PER REPOSITORY, however many packages it holds: ansiwise-plugins is a dozen packages
  # in one tree and every one of them is named out of the same checkout. A rewrite that matched a
  # loose version string instead would reach the neighbouring repository's ref as well — measured
  # on 2026-09-01, when exactly that overwrote the ansiwise-core ref with a plugins tag.
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
    [System.IO.File]::WriteAllLines((Resolve-Path 'pubspec.yaml'), $out)
    Say "  $repo at $($sha.Substring(0,12))"
  }
  if (Select-String -Path pubspec.yaml -Pattern 'ref: master' -Quiet) {
    Die 'a part is still named by a branch rather than a commit. Nothing has been minted or pushed'
  }

  # ── mint, which is what starts the one build ───────────────────────────────
  $tag = "$Version-$Channel-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
  $manifest = [System.IO.File]::ReadAllText('pubspec.yaml')
  $manifest = [regex]::Replace($manifest, '(?m)^version:\s*\S+', "version: $Version", 1)
  [System.IO.File]::WriteAllText((Resolve-Path 'pubspec.yaml'), $manifest)

  git add -- pubspec.yaml
  git commit --quiet -m "release: $tag"
  if ($LASTEXITCODE -ne 0) { Die 'the version bump could not be committed' }
  git tag $tag
  git push --quiet origin HEAD
  git push --quiet origin $tag
  Say "the tag $tag is on origin — the one build has started"

  # ── wait at that build, asked for BY NAME ──────────────────────────────────
  # NEVER `gh run list --limit 1`. In the seconds after a push the newest run is still the PREVIOUS
  # release's, and reading it reports a verdict that belongs to another tag. Measured on
  # 2026-09-01: a script did exactly that and announced a green build for a release that had not
  # started.
  $state = ''
  for ($i = 0; $i -lt 120; $i++) {
    $state = (gh run list --limit 15 --json displayTitle,status,conclusion `
        -q ".[] | select(.displayTitle | contains(`"$tag`")) | .status+`" `"+(.conclusion//`"`")" |
      Select-Object -First 1)
    if ($state -like 'completed*') { break }
    Start-Sleep -Seconds 20
  }
  if ($state -ne 'completed success') {
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
finally {
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
