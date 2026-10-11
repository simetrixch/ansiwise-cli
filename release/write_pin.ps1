# release/write_pin.ps1 — write one pin downstream, dot-sourced by release/release.ps1.
#
# A file of its own so a test can call it alone (test/checks/release_pin_test.dart); it reads $tag,
# Die and Say from whoever dot-sourced it.

# THE CLONE IS BROUGHT TO ORIGIN IMMEDIATELY BEFORE THE WRITE. Both trees were cloned before
# anything was minted, because the push rights they answer for have to be known then, and the
# wait at the build is up to forty minutes long. A commit landing on either trunk in that time
# makes this push non-fast-forward, and a green build then ends with no pin anywhere.
#
# `@{upstream}` AND NOT `origin/master`: it is the branch this clone checked out, which is
# whatever the remote's default branch is. `git push origin HEAD` below has the same property.
#
# TWO ATTEMPTS. The second answers a commit that landed during the first. A third would only
# answer a trunk being written faster than a push takes.
#
# THE PATTERN MATCHES THE SHAPE OF A TAG rather than the neighbouring words, so a file that
# renames its keys still pins — and a file carrying no pin at all says so instead of being
# silently left behind.
#
# THE SUBJECT OPENS WITH `release:`, which is what the organisation's push gate admits a commit
# naming no issue by. A temporary clone runs no hook, so nothing judges these two commits where
# they are written; the subject is what lets the same line be pushed from a configured checkout.
#
# THE PROGRAMS' CI MOVES WITH THEIR PIN. The programs repository's workflow
# checks out ansiwise-cli at a fixed commit and binds every program to that registry. Left behind,
# it binds them to an older engine than the machines run, and a program using a new step goes red
# there. So a -Workflow given here has the `ref:` of its ansiwise-cli checkout moved to -Commit in
# the same commit as the pin, and a workflow carrying no such ref is refused as a missing pin is.
function Write-Pin([string] $Repo, [string] $Clone, [string] $File, [string] $Pattern,
  [string] $Replacement, [string] $Subject, [string] $Beside = '', [string] $Lines = '',
  [string] $Workflow = '', [string] $Commit = '') {
  $path = Join-Path $Clone $File
  foreach ($attempt in 1, 2) {
    git -C $Clone fetch --quiet origin
    if ($LASTEXITCODE -ne 0) {
      Die "$Repo could not be fetched, so this release could not write its pin onto its head"
    }
    git -C $Clone reset --hard --quiet '@{upstream}'
    if ($LASTEXITCODE -ne 0) {
      Die "$Repo could not be brought to its head, so this release could not write its pin"
    }
    # A PIN THE HEAD ALREADY CARRIES IS WRITTEN, whoever wrote it, when the file beside it
    # carries these lines too, and the workflow this commit. Reached where a push landed and still reported a failure, and where
    # a person wrote the line by hand. Without this the attempt below reaches `commit -a` with
    # nothing to commit and the release refuses a pin that is on origin.
    $text = [System.IO.File]::ReadAllText($path)
    $besidePath = if ($Beside) { Join-Path $Clone $Beside } else { '' }
    $besideStands = (-not $Beside) -or ((Test-Path $besidePath) -and
      ([System.IO.File]::ReadAllText($besidePath).TrimEnd("`n") -ceq $Lines))
    $workflowPath = if ($Workflow) { Join-Path $Clone $Workflow } else { '' }
    $workflowStands = (-not $Workflow) -or
      ([System.IO.File]::ReadAllText($workflowPath) -clike "*ref: $Commit*")
    if ($text -like "*$tag*" -and $besideStands -and $workflowStands) {
      Say "$Repo $File already names $tag"
      return
    }
    $next = [regex]::Replace($text, $Pattern, $Replacement)
    [System.IO.File]::WriteAllText($path, $next)
    if ($next -notlike "*$tag*") {
      Die "$Repo $File carries no pin this release could write"
    }
    if ($Workflow) {
      $moved = [regex]::Replace([System.IO.File]::ReadAllText($workflowPath),
        '(?m)(repository: simetrixch/ansiwise-cli\n *ref: )[0-9a-f]{40}$', "`${1}$Commit")
      [System.IO.File]::WriteAllText($workflowPath, $moved)
      if ($moved -cnotlike "*ref: $Commit*") {
        Die "$Repo $Workflow carries no ansiwise-cli ref this release could write"
      }
    }
    if ($Beside) {
      [System.IO.File]::WriteAllText($besidePath, "$Lines`n")
      git -C $Clone add -- $Beside
      if ($LASTEXITCODE -ne 0) { Die "$Repo $Beside could not be staged" }
    }
    git -C $Clone commit --quiet -a -m $Subject `
      -m 'Written by the release of ansiwise-cli, once its binaries were built.'
    if ($LASTEXITCODE -ne 0) { Die "the pin of $Repo could not be committed" }
    git -C $Clone push --quiet origin HEAD
    if ($LASTEXITCODE -eq 0) { return }
  }
  Die "the pin of $Repo could not be pushed, so it is a pin only this machine believes"
}
