# Open gotchas, in full

The evidence behind the one-line gotchas in `SKILL.md`. Each is a failure that
raises no error.

## Why the claim sha comes from the API, and what the checkout form did

The claim block once read `git rev-parse --verify origin/main` in the subtask's
checkout, with a second form for a repo-less campaign that had none. Without
that ref — a single-branch clone, a repository whose default branch is not
`main`, a fetch that has not run — `git rev-parse` exits non-zero and *still
prints* `origin/main`, and inside `$(...)` on the `gh` line nothing read that
exit status. GitHub answered `422`, which this skill teaches means the subtask is
already claimed, so the subtask was abandoned by an executor that believed
somebody else held it; `--verify` plus `|| exit 1` into a variable turned it into
a stop.

`gh api repos/<owner>/<repo>/commits/main --jq .sha` retires the failure rather
than guarding it: the remote is what a claim is cut from, a repository with no
`main` fails loudly instead of printing a ref name, and the two forms collapse
into one block a repo-less subtask runs unchanged. The `|| exit 1` stays, for the
same reason it was added — the sha is read before it is used, never inline.

## A request that sounds new is usually a follow-up

The gate's survey (`AGENTS.md` § Not every request is a campaign) is what this
procedure rests on; skipping it produces a second campaign over the same scope,
and nothing errors — you get two anchor issues that both look right. Two sessions
each running that survey honestly produce the same pair, which is why step 3
surveys a second time.

## You may not be this campaign's session

The binding read in step 1 decides it, before anything else, because a campaign
bound elsewhere is not yours to scaffold, sync or launch into. Nothing after it
asks whose directory this is: every session of a bound campaign shares the one
tree, and the only files in it that belong to a single session are its claim
records. Everything durable is written
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
