---
name: closing-campaign
description: Closes a campaign — binds the campaign directory, refuses when the anchor is BOUND to another machine or another live session holds it, refuses while an agent is live or while work exists only on this machine, refuses while any open subtask lacks a disposition, syncs the README into the anchor issue, then closes the issue and deletes the directory. Use when a person says a campaign is finished, done, over, or wrapped up, or asks to close, retire, archive, or clean up a campaign or its directory. Not for closing a single subtask issue or retiring one repository agent; not for opening or scaffolding a campaign, which is opening-campaign.
---

# Closing a campaign

Delete a campaign directory only after everything in it also exists somewhere
else. The directory is a scratch assembly of things versioned elsewhere, so
closing is a checked demolition, not a decision.

Finished when all six hold:

- the anchor's latest `BOUND` comment names this machine;
- `gh issue view <N> -R kalaluthien/agent-workspace --json state` reports
  `CLOSED`;
- every subtask in the anchor's index reads settled or has moved to another
  anchor, each open one having been given a named disposition first;
- the campaign directory does not exist;
- no herdr agent's `cwd` was under the path that directory had, its
  `runtime/executors/` existed and held no live pid, and no `runtime/holder` in
  it named a live session other than this one;
- the anchor issue body is the campaign README, `## Repos` list included, and
  the body was compared against `runtime/anchor-body-derived.md` before it was
  written.

Where this machine holds no directory for the campaign, the first three are the
real conditions — the binding, and two GitHub facts that read the same from any
machine — and the other three are about a cache that does not exist. Step 0 says
what to skip.

## Procedure

The order is load-bearing: each gate is cheaper than the one after it, and step
5 is irreversible. Run 0–4 without asking — with one exception: step 3 reads and
refuses on its own, but the disposition of an open subtask is the person's
choice, and this skill acts on GitHub only once they have made it. Run 5 only on
explicit confirmation.

### 0. Bind the campaign, once

**The ID first.** Every step from 3 on reads `$N`, and nothing in the campaign
directory carries it: the README *is* the anchor body, and a body does not know
its own issue number. Take it from the person, or resolve it from the open
anchors and say which one you matched — the `campaign` label is what they are
listed by.

```sh
gh issue list -R kalaluthien/agent-workspace --label campaign --state open
```

**Then the binding, before any other gate.** A campaign runs on one machine at a
time, and closing is the most destructive thing a session can do to one it does
not hold:

```sh
gh api --paginate repos/kalaluthien/agent-workspace/issues/"$N"/comments \
  --jq '.[] | select(.body | startswith("BOUND ")) | .body' | tail -1
hostname -s
```

Another machine — refuse, naming the campaign, the machine that holds it and
this one, and say nothing was closed. No output at all means the campaign
predates the rule and is unbound, which is not consent either: let the person
bind it here, or close it from the machine that has been working it. The rule
and the two occasions a session may post `BOUND` are § Who is a campaign session
in the container's `AGENTS.md`.

**Then the directory, if this machine has one.** A campaign legitimately has
none here (§ Who is a campaign session, Directory). That is not a failure and
not a reason to stop: say so, skip steps 1, 2 and 4, and close the issue in step
5, where the delete then has nothing to do.

Every later step reads `$CAMPAIGN_DIR`, and two fail silently if it is relative
or wrong: step 1 compares it against herdr's absolute `cwd`, so a relative value
matches nothing and the refusal passes having found nothing; step 5 then deletes
relative to whatever directory the session happens to hold. Bind it here, from
the slug the person gave, and never rebuild it later in the run.

```sh
CONTAINER=$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd -P)
CAMPAIGN_DIR=$(cd "$CONTAINER/$SLUG" && pwd -P)
```

Then assert both facts `AGENTS.md` already pins, so the assertions cost nothing:

```sh
[ "$(dirname "$CAMPAIGN_DIR")" = "$CONTAINER" ] || echo "REFUSE: not a direct child of $CONTAINER"
case "${CAMPAIGN_DIR##*/}" in
  *-[0-9][0-9][0-9][0-9][0-9][0-9]) ;;
  *) echo "REFUSE: basename is not <slug>-<YYMMDD>" ;;
esac
```

Stop on either. They are what stop `..`, a nested path, and the container's own
`docs/` from reaching step 5.

### 1. Refuse while another session holds it, or an agent is live under the tree

**The holder first**, because it is a two-line read and it settles who this
directory belongs to. Only the holding session closes a campaign; an executor
session arrived to work one subtask and this skill is not its to run.

```sh
PID=$(awk '$1 == "pid" { print $2 }' "$CAMPAIGN_DIR/runtime/holder" 2>/dev/null)
kill -0 "$PID" 2>/dev/null && [ "$(ps -o comm= -p "$PID")" = claude ]
```

Alive and not this session — print the file and stop; that session is holding
the campaign and only it, or the person, may close it. Missing or dead — you are
the holding session by default, so say so, take the directory as
`opening-campaign` step 4 does, and carry on. A live PID that is some other
`claude` reads as held, which is the safe direction to be wrong in here.

**Then the agents, both records** — `herdr agent list` for the delegates,
`runtime/executors/` for the executor sessions (§ Completion and liveness in the
container's `AGENTS.md` says why one alone is not a reading). Presence is the
signal, not `agent_status`, which calls a mid-turn pause `idle`. Compare whole
path segments: a bare prefix test matches a sibling whose name merely starts the
same, and misses the directory itself.

```sh
herdr agent list | jq -r --arg tree "$CAMPAIGN_DIR" \
  '.result.agents[]
   | select(.cwd + "/" | startswith(($tree | sub("/$";"")) + "/"))
   | "\(.name // "unnamed")\t\(.agent_status)\t\(.cwd)"'

EXECDIR="$CAMPAIGN_DIR/runtime/executors"
if [ ! -d "$EXECDIR" ]; then
  echo "REFUSE: no $EXECDIR — executor sessions cannot be enumerated"
else
  find "$EXECDIR" -type f -print | while read -r F; do
    P=$(awk '$1 == "pid" { print $2 }' "$F")
    kill -0 "$P" 2>/dev/null && [ "$(ps -o comm= -p "$P")" = claude ] &&
      { echo "live executor: $(basename "$F")"; cat "$F"; }
  done
fi
```

**A missing directory is a refusal, not a pass.** An empty `runtime/executors/`
says no executor announced; an absent one — any campaign scaffolded before the
record existed — says nothing at all, and both read like a loop that skips what
it cannot find. `find` rather than a glob for the same reason: an unmatched zsh
glob aborts, and an aborted gate is a passed gate.

**Do not match `ListAgents` names against the branch.** An executor session keeps
whatever name its harness gave it and cannot rename itself, so a prefix test on
`campaign-<N>-` finds the delegates and misses what this record exists to catch.

Any row from either: print the rows, name the agent, stop. The person retires
it; this skill never kills an agent.

No rows still leaves two cases for step 2: an agent herdr has forgotten, and an
executor session that never sent `CLAIMED`. Neither is enumerable here, and both
leave one trace — work in a checkout that is not on a remote.

### 2. Refuse while work exists only on this machine

Deleting the directory destroys these and nothing recovers them, and step 1's
two unenumerable cases land here too: an executor nothing recorded still leaves
its work in a checkout. Check every checkout under `repos/`, one at a time —
never one git command across member repositories — and read
`$CAMPAIGN_DIR/runtime/handover/` beside it, saying which briefs you cannot
account for.

```sh
for R in "$CAMPAIGN_DIR"/repos/*/; do
  echo "== $R"
  git -C "$R" status --porcelain --ignored=matching
  git -C "$R" log --oneline --branches HEAD --not --remotes
  git -C "$R" stash list
  git -C "$R" worktree list | tail -n +2
  base=$(git -C "$R" symbolic-ref --quiet --short refs/remotes/origin/HEAD) ||
    base=origin/$(git -C "$R" ls-remote --symref origin HEAD |
                  sed -n 's|^ref: refs/heads/\([^[:space:]]*\).*|\1|p')
  [ "$base" != "origin/" ] || { echo "!! cannot resolve the default branch of $R"; continue; }
  git -C "$R" branch --no-merged "$base"
done
```

Each line finds what the others miss: `--ignored=matching` reaches a `.env` or a
downloaded fixture that plain `status` hides; `HEAD` alongside `--branches`
reaches a commit made on a detached head; `tail -n +2` drops the main worktree,
which always prints and would otherwise flag every repository. A repository
whose default branch will not resolve is reported, never skipped quietly.

Report one row per thing at risk, never one per check. An unpushed commit on a
topic branch is found twice — once by `log --not --remotes`, once by `branch
--no-merged` — and is still one blocker. Keep both checks and merge only the
report: the overlap is what makes the check hard to fool, while two rows make a
reader counting blockers see two problems where there is one.

A branch listed by `--no-merged` is not a blocker if it is pushed, and also not
a blocker if it was squash-merged — see the gotcha below, because that case is
gone from the remote and looks exactly like the real thing. Say which of the
three each row is.

Refuse in this shape, so two refusals written on different days can be read side
by side:

```text
REFUSE: <count> item(s) under <CAMPAIGN_DIR> exist only on this machine.

  <owner/repo>  <kind>  <identifier>
    found by  <check>[, <check>]
    clears by <push | merge | discard>

Nothing was deleted. Clear every row, or say to discard it, then re-run.
```

`<kind>` is one of: uncommitted, ignored, unpushed commit, stash, worktree,
unmerged branch. `<check>` is the command that found it, named as it appears
above. `<count>` counts rows, not checks.

### 3. Settle or dispose of every open subtask

**First, confirm `$N` is an anchor.** The container's tracker holds subtasks
under the same number sequence, so a subtask number handed in here reads as a
campaign with an empty index — and step 5 would then close somebody's subtask
and delete a directory over it.

```sh
gh issue view "$N" -R kalaluthien/agent-workspace --json labels,parent \
  -q '"\([.labels[].name] | join(","))\t\(.parent.number // "-")"'
```

Want `campaign` among the labels and `-` for the parent. Anything else, stop and
say which issue `$N` actually is — the three kinds and how body shape settles the
unlabelled case are § When the container is a member of its own campaign in the
container's `AGENTS.md`. `scripts/campaign-settlement "$N"` reports the mismatch
alongside step 3's verdicts.

Then one reader, and it is the container's script — never a second copy of the
settlement rule written out here as `gh` commands, which is the drift that rule
exists to stop and which did happen before this step was written this way.

```sh
"$CONTAINER/scripts/campaign-settlement" "$N" >| /tmp/settlement-$N
cat /tmp/settlement-$N
```

It reads the anchor's sub-issue index in one paginated call — every member
repository at once, public or private — and prints one row per subtask, then
whether the campaign is closable. Keep the output in a file: the rest of this
step is read off it by machine.

Read the note beside a `dropped` row before repeating the word: it covers four
closes and only one is an abandonment.
**Then every `open` row gets a disposition, and this step refuses without one.**
A campaign may close over unfinished work; it may not close over *unexamined*
work. A leftover nobody named is work that vanishes with the close — the anchor
is the only thing that indexes it, and step 5 closes that. The person chooses
one of three per row:

| disposition | the act | what the row becomes |
| --- | --- | --- |
| `finish` | do the work, land the pull request, close the issue | `complete` |
| `not-planned` | `gh issue close <issue> -R <repo> --reason "not planned" --comment "<why>"` | `dropped` |
| `reparent` | `gh issue edit <issue> -R <repo> --parent <URL of the inheriting anchor>` | gone from this index — the sub-issue link is prunable |

All three end with the row off this campaign's open list, which is what makes
the gate below a check rather than a promise.

Write one line per open row — `<owner/repo>#<issue>  <verb>  <reason or target>`
— then validate that list against the settlement output row for row. Do not read
the two side by side; a close is where an eye skips a line.

```sh
DISPOSITIONS=/tmp/dispositions-$N        # write it here, one line per open row
awk '$1 ~ /#[0-9]+$/ && $2 == "open" { print $1 }' /tmp/settlement-$N | sort >| /tmp/open-$N
awk 'NF { print $1 }' "$DISPOSITIONS" | sort >| /tmp/disposed-$N
command diff /tmp/open-$N /tmp/disposed-$N && echo "every open subtask has a disposition"
awk 'NF && $2 !~ /^(finish|not-planned|reparent)$/ { print "REFUSE: unknown disposition: " $0 }' "$DISPOSITIONS"
awk 'NF && $2 != "finish" && NF < 3 { print "REFUSE: no reason or target: " $0 }' "$DISPOSITIONS"
```

`command diff`, not `diff` — see the shadowed-`diff` gotcha below. A `<` line is
an open subtask nobody disposed of and it stops the close; a `>` line names a
subtask that is not open, so the list was written against a stale reading and
the script must be re-run before anything is acted on.

```text
REFUSE: <count> open subtask(s) under #<N> have no disposition.

  <owner/repo>#<issue>  <title>

Nothing was closed. Give each one finish, not-planned with a reason, or
reparent with the anchor that inherits it, then re-run.
```

`/tmp/dispositions-$N` is scratch and dies with the run. The durable record of
each disposition is the act itself: the merged pull request, the reason in the
close comment, or the new parent. Nothing here is written into the anchor body —
progress is derived from the index, and the body is a charter.

**Carry them out, then read the same script again.** The dispositions are
claims until GitHub shows them; this is the check that the close is not being
argued from the list rather than from the tracker.

```sh
"$CONTAINER/scripts/campaign-settlement" "$N" >| /tmp/settlement-after-$N
cat /tmp/settlement-after-$N
grep -q '; closable$' /tmp/settlement-after-$N ||
  grep -q 'the index is empty' /tmp/settlement-after-$N ||
  echo "REFUSE: open subtasks remain after the dispositions were carried out"
```

`; closable$` and not `closable`, because the failing line ends
`NOT closable: open subtasks remain` and a bare match reads it as a pass. The
empty-index line is the second accepted reading: a campaign with no subtasks
prints no settlement count at all, and refusing it would leave such a campaign
unclosable.

A `-- REPORT:` line about nested sub-issues is not covered by this gate. A
subtask that is itself an anchor hides its own members, so run the script on it
and dispose of those rows too before you count this one settled.

### 4. Validate the README, compare, then overwrite the anchor issue body

The README and the anchor body are the same anchor template filled in —
`.claude/skills/opening-campaign/assets/README.md` — so the sync is an
overwrite. That makes the README the only thing standing between a malformed
heading and the loss of the campaign's repository index, which step 5 then
deletes the last copy of. Validate before writing.

```sh
README="$CAMPAIGN_DIR/README.md"
grep -q '^## Repos' "$README" || echo "REFUSE: no ## Repos heading"
sed -n '/^## Repos/,/^## /{/^- /p;}' "$README" >| /tmp/repos-before
[ -s /tmp/repos-before ] || echo "REFUSE: the ## Repos list is empty"
grep -q '<' /tmp/repos-before && echo "REFUSE: placeholders survive in ## Repos"
```

The range is bounded to the section and takes only list items, so a link in an
adjacent section cannot be read as a member repository.

This step is also run mid-campaign, whenever a repository is added to the
`## Repos` list — `opening-campaign`'s "Filing a subtask issue" sends you here.
Those are the only two moments the body is written at: a scope change, of which
adding a repository is one, and the close. The body is a charter, not a status
board, so a settled subtask is never written back into it — nothing in step 3
edits the body, and `## Plan` is left exactly as it was at opening.

**Then compare before you write.** This README was derived from the body at some
earlier moment, and if anything has written the body since, an overwrite from
here silently discards it. Under one campaign, one machine the body has a single
structural writer, so what this catches is no longer a peer session on the
normal path: it is a person editing the charter straight on GitHub, which is
theirs to do, or a machine writing an anchor it is not `BOUND` to, which is the
principle broken — and from here the two look the same. The ceremony stays
because both are silent. `runtime/anchor-body-derived.md` is that earlier
moment, kept by `opening-campaign` step 4; re-read the body now and require the
two to match.

```sh
DERIVED="$CAMPAIGN_DIR/runtime/anchor-body-derived.md"
[ -f "$DERIVED" ] || echo "REFUSE: no runtime/anchor-body-derived.md to compare against"
gh issue view "$N" -R kalaluthien/agent-workspace --json body -q .body >| /tmp/body-now
command diff -u "$DERIVED" /tmp/body-now && echo "the body has not moved; safe to write"
```

`command diff`, not `diff` — see the shadowed-`diff` gotcha below.

Read the diff, not the exit status alone — it names what the other session did.

```text
REFUSE: the anchor body has moved since this README was derived from it.

  <the diff above>

Nothing was written. Fold those changes into <CAMPAIGN_DIR>/README.md, refresh
runtime/anchor-body-derived.md from /tmp/body-now, then re-run.
```

Refuse the same way when `runtime/anchor-body-derived.md` is missing — a
campaign scaffolded before the file existed, or a directory built by hand. There
is no cheap substitute: without it, "has the body moved?" has no answer, and
guessing it has not is exactly the write this step exists to stop. Say so, read
the body and the README side by side yourself, and once they agree write
`/tmp/body-now` to `runtime/anchor-body-derived.md` and re-run.

Only then overwrite — and read the index back out of what GitHub actually
stored, then refresh the derived copy so the next write compares against this
one:

```sh
gh issue edit "$N" -R kalaluthien/agent-workspace --body-file "$README"
gh issue view "$N" -R kalaluthien/agent-workspace --json body -q .body >| /tmp/body-after
sed -n '/^## Repos/,/^## /{/^- /p;}' /tmp/body-after >| /tmp/repos-after
cmp -s /tmp/repos-before /tmp/repos-after && echo "index survived"
cp /tmp/body-after "$DERIVED"
```

Not identical: say so and stop before step 5, while the README still exists.

### 5. Say you are closing, then close, then delete the directory

Only after the person confirms.

**Say it on the anchor issue first, and read who answers.** Step 1's gate is
local, and under the principle that covers everything legitimate: every agent
and every executor session of this campaign is on the machine it is `BOUND` to,
and step 1 saw them. What it cannot see is a machine working this campaign
against the binding, and no cheap local check can. The anchor issue is the one
place every machine can read, so announce there and read the comments back —
this is the guard for a broken principle, not a routine handshake.

```sh
gh issue comment "$N" -R kalaluthien/agent-workspace \
  --body "Closing campaign #$N from $(hostname -s). Say so here if you are still in it."
gh issue view "$N" -R kalaluthien/agent-workspace --comments
```

Another session's note saying it is working or closing: stop, name it, and let
the person resolve it — and say that it should not have been there, because the
campaign is bound here. This narrows the window rather than closing it: a
session that never comments is invisible either way. What keeps that survivable
is not this check but the rule that a delegate pushes its branch as soon as it
has one commit, so a tree deleted underneath it costs uncommitted work and
nothing more.

Then close, in this order — the issue first, because a failed close leaves the
directory to retry from, while the reverse leaves nothing. The comment states
only what has already happened at the moment it is written.

```sh
gh issue close "$N" -R kalaluthien/agent-workspace --comment "Campaign closed."
```

**Check nobody else on this machine is in the directory**, and only then remove
it. Two sessions given the same slug on the same day build the same path, so the
tree may be another session's workspace even with no agent anywhere near it —
step 1 would not have caught that, because a campaign session's own working
directory is the container root, not the campaign tree.

```sh
lsof +D "$CAMPAIGN_DIR" 2>/dev/null | tail -n +2
```

Any rows: name the processes and stop. `lsof` sees an open file, not a session
sitting idle between turns, so treat an empty result as weak evidence and pair
it with the announcement above rather than trusting it alone.

List the directory and confirm it holds only the campaign, then remove the bound
path itself — not a path retyped here, not its parent, not a wildcard.

```sh
ls -A "$CAMPAIGN_DIR"
rm -rf -- "$CAMPAIGN_DIR"
```

## Gotchas

- **`dropped` covers four closes and its note says which**: `not planned`,
  `duplicate`, `completed, no merged pull request`, and `closed, no reason
  recorded`. All four are settled — settled is "the issue is closed" — and only
  the first is abandonment, so quote the note, not the word.
- `state_reason` is lowercase from `gh api` and uppercase from `gh issue list
  --json stateReason`. A comparison against the wrong one matches nothing and
  reads every subtask as unsettled — half of why the reading lives in one script
  rather than in prose here.
- **After a squash merge, ancestry is the wrong test, and squash is the default
  merge here.** `git branch --no-merged <base>` walks ancestry, and a squash
  merge writes a *new* commit onto the base, so the topic branch stays
  "unmerged" forever. Pair that with `--delete-branch` and the branch is also
  absent from the remote — the exact signature of work that exists only on this
  machine — so a fully landed campaign reports one false blocker per member
  repository. The discriminator is content, not
  ancestry: `git -C <repo> diff --stat <base>..<branch>` empty means the branch
  changes nothing the base lacks, however the ancestry reads. Check the paths the
  subtask actually touched too, since a branch cut before the base moved on
  diffs non-empty on files it never edited. Report such a row as landed.
- **`set -- $var` does not word-split in zsh, and this skill is made of gates.**
  This machine's shell leaves unquoted parameters unsplit, so
  `for pair in a:1 b:2; do set -- $pair` leaves `$2` empty. Here it failed loudly
  — `gh` answered `invalid issue format: ""` — but the same construct inside a
  check whose empty result reads as "nothing to report" passes having tested
  nothing. Split with a parameter expansion (`repo=${spec%%:*}`,
  `num=${spec##*:}`), and make any gate that can return empty say which of the
  two it means.
- **`diff` is shadowed in a Claude Code shell on this machine** by a zsh
  autoload stub with no file behind it, so a plain `diff` dies with
  `(eval):1: diff: function definition file not found` — which reads like a
  missing input file, not a shadowed name, and a gate that errors out is a gate
  that tested nothing. Write `command diff`; `cmp`, `sed`, `grep` and `cp` are
  unaffected.
- `git status --porcelain` never lists ignored files, so the obvious command for
  "nothing local is left" answers clean over a checkout holding a `.env`, a build
  directory, or a downloaded fixture — every one of which dies with the
  directory. Only `--ignored` is evidence, which is why step 2 uses
  `--ignored=matching`.
- **Two sessions given the same slug on the same day build the same path**, so
  the directory this skill deletes may be another session's live workspace.
  `runtime/holder` catches that in step 1; the herdr gate cannot, because it
  matches an agent's `cwd` and a campaign session's `cwd` is the container root.
  Step 5's announcement and open-file check are the layer under it. A machine the
  campaign was `BOUND` to before a migration may still hold a directory of its
  own: a stale cache, untouched by this delete, with nothing durable in it.
