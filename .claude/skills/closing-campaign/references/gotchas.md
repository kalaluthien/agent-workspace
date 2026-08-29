# Close gotchas, in full

The evidence behind the one-line gotchas in `SKILL.md`. Each is a failure that
raises no error.

## Step 2's three silent failures live in the script

An unmatched `repos/*/` glob, a squash merge making a landed branch read
unmerged forever, and `git status --porcelain` never listing an ignored file:
each was a check in step 2 that could report nothing while testing nothing.
Step 2 is one call to `scripts/campaign-local-work` now, so the three are the
script's to get right and its docstring states each with its evidence. Nothing
of them is restated here — two copies of a probe is how one of them goes stale.

## `dropped` covers four closes

`not planned`, `duplicate`, `completed, no merged pull request`, and `closed, no
reason recorded`. All four are settled — settled is "the issue is closed" — and
only the first is abandonment, so quote the note, not the word.

## `state_reason` case differs by command

Lowercase from `gh api`, uppercase from `gh issue list --json stateReason`. A
comparison against the wrong one matches nothing and reads every subtask as
unsettled — half of why the reading lives in one script rather than in prose.

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

