# Open gotchas, in full

The evidence behind the one-line gotchas in `SKILL.md`. Each is a failure that
raises no error.

## An inline `sha=$(git rev-parse origin/main)` sends the literal string up as a sha

Without that ref — a single-branch clone, a repository whose default branch is not
`main`, a fetch that has not run — `git rev-parse` exits non-zero and *still
prints* `origin/main`, and inside `$(...)` on the `gh` line nothing reads that
exit status. GitHub answers `422`, and this skill teaches that `422` means the
subtask is already claimed, so the subtask is abandoned by an executor that
believes somebody else holds it.

`--verify` plus `|| exit 1` into a variable is what turns that into a stop. A
repo-less campaign takes the sha from `gh api .../commits/main` because it has no
checkout to ask.

## A request that sounds new is usually a follow-up

Step 1 is the step this procedure exists for; skipping it produces a second
campaign over the same scope, and nothing errors — you get two anchor issues that
both look right. Two sessions each running step 1 honestly produce the same pair,
which is why step 3 surveys a second time.

## You may not be this campaign's session

The two reads in step 1 decide it, in that order, because a campaign bound
elsewhere is not yours to read a holder file for. Everything durable is written
as read-then-write against GitHub rather than as "mine because I made it": the
anchor body is compared before it is overwritten, the directory may already
exist, and the shared checkout is left on its default branch so a re-run cannot
move it under somebody's delegate.

## Order: the anchor issue before the directory

Filing the anchor after scaffolding gives the directory a slug with no ID behind
it and branches named for a number you have not got yet. Order matters here and
nowhere else in the procedure.

## A delegate does not inherit the campaign `AGENTS.md`

It does not pick the file up from its parent directories. It reaches the delegate
only through `--append-system-prompt-file <campaign>/AGENTS.md` at launch;
without that flag the delegate reads the repository's own file and nothing else,
and reports nothing wrong. Where the campaign file does arrive, it sits beside
the repository's own conventions: adding a principle is free, contradicting one
hands the delegate a conflict it cannot resolve, and it will pick a side without
telling you.

## `gh issue create` without `--parent` succeeds

It returns a URL and a live issue that belongs to no campaign, and only a later
listing that comes back short shows anything is wrong.

## `noclobber` on this machine

This machine's zsh sets `noclobber` and leaves `APPEND_CREATE` unset. Plain `>`
onto a file that exists fails with `file exists`, and plain `>>` onto a file that
does not exist yet fails with `no such file or directory`, which reads like a
missing directory. Write `>|` and `>>|`. Neither failure stops the steps around
it, so a fill that never happened still reports success.

## The campaign directory is invisible to `git status`

`git status` in the container root will never show it. That is the allowlist
working, not a missing file. And never run one git command across `repos/*`:
each is its own repository with its own remote.
