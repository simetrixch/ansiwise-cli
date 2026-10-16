# shellcheck shell=bash
# release/write_pin.sh — write one pin downstream and tag the commit that carries it, sourced by
# release/release.sh.
#
# A file of its own so a test can call it alone (test/checks/release_pin_test.dart and
# test/checks/release_tag_test.dart); it reads TAG, die and say from whoever sourced it.

# THE CLONE IS BROUGHT TO ORIGIN IMMEDIATELY BEFORE THE WRITE. Both trees were cloned before
# anything was minted, because the push rights they answer for have to be known then, and the wait
# at the build is up to forty minutes long. A commit landing on either trunk in that time makes
# this push non-fast-forward, and a green build then ends with no pin anywhere.
#
# `@{upstream}` AND NOT `origin/master`: it is the branch this clone checked out, which is whatever
# the remote's default branch is. `git push origin HEAD` below has the same property.
#
# TWO ATTEMPTS. The second answers a commit that landed during the first. A third would only answer
# a trunk being written faster than a push takes.
#
# THE PATTERN MATCHES THE SHAPE OF A TAG rather than the neighbouring words, so a file that renames
# its keys still pins — and a file carrying no pin at all says so instead of being silently left
# behind.
#
# THE SUBJECT OPENS WITH `release:`, which is what the organisation's push gate admits a commit
# naming no issue by. A temporary clone runs no hook, so nothing judges these two commits where they
# are written; the subject is what lets the same line be pushed from a configured checkout.
#
# THE PROGRAMS' CI MOVES WITH THEIR PIN. The programs repository's ci-sources.json pins ansiwise-cli
# at a fixed commit, and the master's ci binds every program to that registry. Left behind, it binds
# them to an older engine than the machines run, and a program using a new step goes red there. So
# a <sources> file given here has the commit it pins ansiwise-cli at moved to <release commit> in
# the same commit as the pin, and a file pinning no ansiwise-cli is refused as a missing pin is.
write_pin() { # <repo> <clone> <file> <sed expression> <subject> [<file beside> <its lines> [<sources> <release commit>]]
  local repo="$1" clone="$2" file="$3" expression="$4" subject="$5" beside="${6:-}" lines="${7:-}"
  local sources="${8:-}" commit="${9:-}" attempt
  for attempt in 1 2; do
    git -C "$clone" fetch --quiet origin \
      || die "${repo} could not be fetched, so this release could not write its pin onto its head"
    git -C "$clone" reset --hard --quiet '@{upstream}' \
      || die "${repo} could not be brought to its head, so this release could not write its pin"
    # A PIN THE HEAD ALREADY CARRIES IS WRITTEN, whoever wrote it, when the file beside it carries
    # these lines too, and the sources file this commit. Reached where a push landed and still reported a failure, and where a person
    # wrote the line by hand. Without this the attempt below reaches `commit -a` with nothing to
    # commit and the release refuses a pin that is on origin.
    if grep -qF "$TAG" "$clone/$file" \
      && { [ -z "$beside" ] || [ "$(cat "$clone/$beside" 2>/dev/null)" = "$lines" ]; } \
      && { [ -z "$sources" ] || grep -qE "\"ansiwise-cli\": *\"$commit\"" "$clone/$sources"; }; then
      say "${repo} ${file} already names $TAG"
      return 0
    fi
    sed -i -E "$expression" "$clone/$file"
    grep -qF "$TAG" "$clone/$file" \
      || die "${repo} ${file} carries no pin this release could write"
    if [ -n "$sources" ]; then
      sed -i -E "s|(\"ansiwise-cli\": *\")[0-9a-f]{40}(\")|\1${commit}\2|" "$clone/$sources"
      grep -qE "\"ansiwise-cli\": *\"$commit\"" "$clone/$sources" \
        || die "${repo} ${sources} pins no ansiwise-cli this release could write"
    fi
    if [ -n "$beside" ]; then
      printf '%s\n' "$lines" > "$clone/$beside"
      git -C "$clone" add -- "$beside" || die "${repo} ${beside} could not be staged"
    fi
    git -C "$clone" commit --quiet -a -m "$subject" \
      -m "Written by the release of ansiwise-cli, once its binaries were built." \
      || die "the pin of ${repo} could not be committed"
    if git -C "$clone" push --quiet origin HEAD; then
      return 0
    fi
  done
  die "the pin of ${repo} could not be pushed, so it is a pin only this machine believes"
}

# THE RELEASE'S TAG GOES ON THE COMMIT THAT CARRIES THE PIN, because `ai-core status-sync` counts a
# commit of this repository as released only when a tag carries it, and a repository the release
# stamped but never tagged leaves every card of it in `testing` for good. Called right after
# write_pin, the head of <clone> is that commit: the stamp write_pin pushed, or the head that
# already named this release where write_pin wrote nothing.
#
# READ BACK FROM ORIGIN, as release.sh does for its own tag: the clone already has the tag whatever
# origin thinks, and a zero exit of the push is the weaker fact. A tag standing at the head already
# is left alone, so a release run again over a stamp that landed passes; a tag standing at another
# commit is refused, because moving a tag a machine may have fetched is not this script's to do.
tag_pin() { # <repo> <clone>
  local repo="$1" clone="$2" head standing
  head="$(git -C "$clone" rev-parse HEAD)"
  standing="$(git -C "$clone" ls-remote --tags origin "refs/tags/$TAG" | cut -f1)"
  if [ -z "$standing" ]; then
    git -C "$clone" tag "$TAG" || die "the tag $TAG could not be created in ${repo}"
    git -C "$clone" push --quiet origin "$TAG" \
      || die "the tag $TAG could not be pushed to ${repo}, so its pin carries no tag"
    standing="$(git -C "$clone" ls-remote --tags origin "refs/tags/$TAG" | cut -f1)"
    [ -n "$standing" ] || die "${repo} does not carry $TAG after the push, so its pin carries no tag"
  fi
  [ "$standing" = "$head" ] \
    || die "${repo} carries $TAG at ${standing:0:12} and not at its pin ${head:0:12}, and a tag is not moved"
}
