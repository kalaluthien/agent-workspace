# Close gotchas, in full

The evidence behind the one-line gotchas in `SKILL.md`. Each is a failure that
raises no error.

## An unmatched `repos/*/` glob fails two different ways

This skill is run by hand in whatever shell the person is in, which is why step 2
enumerates with `find` (all three probed):

| shell | what an unmatched `repos/*/` does |
| --- | --- |
| bash, sh | leaves the glob literal, so the loop runs once on `.../repos/*/` and six git commands fail against a path that does not exist — output that reads as an unresolvable repository blocking the close |
| zsh | `no matches found`, and the whole `for` never runs — a gate that reported nothing because it tested nothing, and an abort outright under `set -e` |

`find` has neither failure in any of the three, and over a `repos/` that exists
but is empty it simply prints nothing. Do not reach for `nullglob` or a zsh `(N)`
qualifier: each fixes one shell and breaks the other.

## `dropped` covers four closes

`not planned`, `duplicate`, `completed, no merged pull request`, and `closed, no
reason recorded`. All four are settled — settled is "the issue is closed" — and
only the first is abandonment, so quote the note, not the word.

## `state_reason` case differs by command

Lowercase from `gh api`, uppercase from `gh issue list --json stateReason`. A
comparison against the wrong one matches nothing and reads every subtask as
unsettled — half of why the reading lives in one script rather than in prose.

## After a squash merge, ancestry is the wrong test

Squash is the default merge here. `git branch --no-merged <base>` walks ancestry,
and a squash merge writes a *new* commit onto the base, so the topic branch stays
"unmerged" forever; pair that with `--delete-branch` and it is absent from the
remote too — the exact signature of work that exists only on this machine — so a
fully landed campaign reports one false blocker per member repository.

The discriminator is content: `git -C <repo> diff --stat <base>..<branch>` empty
means the branch changes nothing the base lacks, however ancestry reads. Check
the paths the subtask touched too, since a branch cut before the base moved on
diffs non-empty on files it never edited.

## `set -- $var` does not word-split in zsh

And this skill is made of gates. Unquoted parameters stay unsplit, so `for pair
in a:1 b:2; do set -- $pair` leaves `$2` empty. Here it failed loudly — `gh`
answered `invalid issue format: ""` — but the same construct inside a check whose
empty result reads as "nothing to report" passes having tested nothing.

## `diff` is shadowed in a Claude Code shell on this machine

By a zsh autoload stub with no file behind it, so a plain `diff` dies with
`(eval):1: diff: function definition file not found` — which reads like a missing
input file, not a shadowed name. Write `command diff`; `cmp`, `sed`, `grep` and
`cp` are unaffected.

## `git status --porcelain` never lists ignored files

So the obvious command for "nothing local is left" answers clean over a checkout
holding a `.env`, a build directory, or a downloaded fixture — every one of which
dies with the directory. Only `--ignored` is evidence.
