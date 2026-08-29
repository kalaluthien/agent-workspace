---
name: closing-campaign
description: Closes a campaign — binds the campaign directory, refuses when the anchor is BOUND to another machine or another live session holds it, refuses while an agent is live or while work exists only on this machine, refuses while any open subtask lacks a disposition, syncs the README into the anchor issue, then closes the issue and deletes the directory. Use when a person says a campaign is finished, done, over, or wrapped up, or asks to close, retire, archive, or clean up a campaign or its directory. Not for closing a single subtask issue or retiring one repository agent; not for opening or scaffolding a campaign, which is opening-campaign.
---

# Closing a campaign

Delete a campaign directory only after everything in it also exists somewhere
else. The directory is a scratch assembly of things versioned elsewhere, so
closing is a checked demolition, not a decision.

Finished when the two facts no step owns hold — `gh issue view <N> -R
kalaluthien/agent-workspace --json state` reports `CLOSED`, and `$CAMPAIGN_DIR`
does not exist — and every step's `Holds when` line held when that step ran.
Those lines are the rest of the predicate, one per step and in order, and
`grep '^Holds when' SKILL.md` is the whole of them: the list is read off the
procedure rather than kept beside it, so a step that changes cannot leave a
predicate behind saying what it used to do.

A campaign bound here with no directory is taken first — `opening-campaign`
steps 2 and 4, nothing to acquire — because the holder and executor records have
no other home (§ Who is a campaign session, "Holding scaffolds"). One path, then.

## Procedure

The order is load-bearing: each gate is cheaper than the one after it, and step 5
is irreversible. Run 0–4 without asking, except that an open subtask's
disposition in step 3 is the person's choice. Run 5 only on explicit
confirmation. Why each guard is shaped the way it is: `references/rationale.md`.

### 0. Bind the campaign, once

**The ID first**: every step from 3 on reads `$N`, and the README *is* the anchor
body so nothing in the directory carries it. Take it from the person, or match it
among the open anchors and say which.

```sh
gh issue list -R kalaluthien/agent-workspace --label campaign --state open
```

**Then the binding, before any other gate**, because closing is the most
destructive thing a session can do to a campaign it does not hold (§ Who is a
campaign session in the container's `AGENTS.md`).

```sh
gh api --paginate repos/kalaluthien/agent-workspace/issues/"$N"/comments \
  --jq '.[] | select(.body | startswith("BOUND ")) | .body' | tail -1
hostname -s
```

Another machine — refuse, naming both machines, and say nothing was closed. No
output means unbound, which is not consent either: let the person bind it here,
or close it from the machine that has been working it.

**Then the directory.** A campaign bound here may have none yet — not taken on
this machine (§ Who is a campaign session, Directory). Take it first, through
`opening-campaign`'s "No directory at all" arrival: **steps 2 and 4**, because
step 4 needs a slug and a kind and step 2 is where they are chosen — neither is
recoverable from GitHub. That scaffolds the tree from the anchor body and writes
`runtime/holder`. The gates below read records that live only there, and step 1
says what they can and cannot see on this path.

Bind `$CAMPAIGN_DIR` here, absolute, and never rebuild it later — steps 1 and 5
both fail silently on a relative value. If you created it in this step, set
`TOOK_IT_HERE=1`: the gates in steps 1 and 2 then have nothing they *can* find,
and they must report that rather than a pass (`references/rationale.md`).

```sh
CONTAINER=$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd -P)
CAMPAIGN_DIR=$(cd "$CONTAINER/$SLUG" && pwd -P)
```

Then assert both facts `AGENTS.md` already pins.

```sh
[ "$(dirname "$CAMPAIGN_DIR")" = "$CONTAINER" ] || echo "REFUSE: not a direct child of $CONTAINER"
case "${CAMPAIGN_DIR##*/}" in
  *-[0-9][0-9][0-9][0-9][0-9][0-9]) ;;
  *) echo "REFUSE: basename is not <slug>-<YYMMDD>" ;;
esac
```

Stop on either. They are what stop `..`, a nested path, and the container's own
`docs/` from reaching step 5.

Holds when: the anchor's latest `BOUND` comment names this machine, and
`$CAMPAIGN_DIR` is absolute, a direct child of the container, and named
`<slug>-<YYMMDD>`.

### 1. Refuse while another session holds it, or an agent is live under the tree

**The holder first**, because only the holding session closes a campaign; an
executor session came to work one subtask and this skill is not its to run.

```sh
PID=$(awk '$1 == "pid" { print $2 }' "$CAMPAIGN_DIR/runtime/holder" 2>/dev/null)
kill -0 "$PID" 2>/dev/null && [ "$(ps -o comm= -p "$PID")" = claude ]
```

Alive and not this session — print the file and stop. Missing or dead — you are
the holding session, so say so, take the directory as `opening-campaign` step 4
does, and carry on.

**If `TOOK_IT_HERE` is set, this step and step 2 are not applicable, and that
is what to report.** Step 0 created the tree seconds ago, so no herdr `cwd` can
be under it, `runtime/executors/` is empty because it was just copied, and there
is nothing uncommitted in it: the gates cannot fail, and a gate that cannot fail
has not passed. Run them anyway — they cost two commands — and report "not
applicable: this session created the directory in step 0". Why that is sound,
and the one residue it leaves, is `references/rationale.md`.

**Then the agents, both records** — `herdr agent list` for the delegates,
`runtime/executors/` for the executor sessions, one alone being no reading at all
(§ Completion and liveness). Presence is the signal, not `agent_status`; compare
whole path segments, and never test a name against the branch.

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

**A missing `runtime/executors/` is a refusal, not a pass**: an empty one says no
executor announced, an absent one says nothing at all.

Any row from either: print the rows, name the agent, stop. The person retires
it; this skill never kills an agent. No rows still leaves two cases for step 2 — an agent herdr has forgotten, and an
executor that never sent `CLAIMED` — both leaving work in a checkout.

Holds when: `runtime/executors/` existed and held no live pid, no
`runtime/holder` named a live session other than this one, and no herdr agent's
`cwd` was under `$CAMPAIGN_DIR` — or `TOOK_IT_HERE` is set and this step reported
all three as not applicable rather than as passed.

### 2. Refuse while work exists only on this machine

Deleting the directory destroys these and nothing recovers them. One reader
answers the whole question — `scripts/campaign-local-work`, which reads this
campaign's own `campaign-$N/` branches and the worktrees on them in the
container, the container's single working tree, and every checkout under
`repos/` one at a time, with the briefs in `runtime/handover/` named beside
them. Do not re-derive any of that here; a second reader of one question is what
drifts (§ Completion and liveness).

```sh
"$CONTAINER/scripts/campaign-local-work" "$N" "$CAMPAIGN_DIR" >| /tmp/local-work-$N
cat /tmp/local-work-$N
```

**Exit 1 is the reading having failed, not a clean tree**: print the `-- REFUSE:`
line it ends on, stop, and conclude nothing. On exit 0 the last line is the
verdict and the rows above it are the report.

- An unmarked row is counted, and one counted row refuses the close. The refusal
  is the script's own output, then: *Nothing was deleted. Clear every counted
  row, or say to discard it, then re-run.*
- A `~` row is named and not counted — pushed, landed over a squash merge, or a
  clean worktree, which is the one the closer is usually standing in.
- A `-- REPORT:` line is for the person to read and blocks nothing: an
  unattributed edit in the container's one working tree, a handover brief
  nobody has accounted for, a repository whose default branch would not resolve.
- `0 item(s) … clear` is the pass.

Each row carries its `<kind>`, the `found by` checks that overlap on it and what
`clears` it, so two refusals written on different days read side by side without
the shape being retyped here.

Holds when: `campaign-local-work` exited 0 over this campaign and this directory,
and its last line read clear — either on the first run, or on a re-run after
every counted row was pushed, merged, or discarded on the person's word.

### 3. Settle or dispose of every open subtask

**First, confirm `$N` is an anchor**, because the tracker holds subtasks under
the same number sequence and step 5 would otherwise close somebody's subtask.

```sh
gh issue view "$N" -R kalaluthien/agent-workspace --json labels,parent \
  -q '"\([.labels[].name] | join(","))\t\(.parent.number // "-")"'
```

Want `campaign` among the labels and `-` for the parent. Anything else, stop and
say which issue `$N` actually is (§ When the container is a member of its own
campaign in the container's `AGENTS.md`).

Then one reader, and it is the container's script — never a second copy of the
settlement rule written out here as `gh` commands.

```sh
"$CONTAINER/scripts/campaign-settlement" "$N" >| /tmp/settlement-$N
cat /tmp/settlement-$N
```

It prints one row per subtask over the whole paginated index, then whether the
campaign is closable. Keep it in a file: the rest of this step is read off it by
machine. Read the note beside a `dropped` row before repeating the word.

**Then every `open` row gets a disposition, and this step refuses without one.** A
campaign may close over unfinished work, never over *unexamined* work, and step 5
closes the only thing that indexes it. One of three per row, the person's choice:

| disposition | the act | what the row becomes |
| --- | --- | --- |
| `finish` | do the work, land the pull request, close the issue | `complete` |
| `not-planned` | `gh issue close <issue> -R <repo> --reason "not planned" --comment "<why>"` | `dropped` |
| `reparent` | `gh issue edit <issue> -R <repo> --parent <URL of the inheriting anchor>` | gone from this index — the sub-issue link is prunable |

All three end with the row off this campaign's open list, which makes the gate
below a check rather than a promise. Write one line per open row —
`<owner/repo>#<issue>  <verb>  <reason or target>` — then validate it against the
settlement output by machine, because a close is where an eye skips a line.

```sh
DISPOSITIONS=/tmp/dispositions-$N        # write it here, one line per open row
awk '$1 ~ /#[0-9]+$/ && $2 == "open" { print $1 }' /tmp/settlement-$N | sort >| /tmp/open-$N
awk 'NF { print $1 }' "$DISPOSITIONS" | sort >| /tmp/disposed-$N
command diff /tmp/open-$N /tmp/disposed-$N && echo "every open subtask has a disposition"
awk 'NF && $2 !~ /^(finish|not-planned|reparent)$/ { print "REFUSE: unknown disposition: " $0 }' "$DISPOSITIONS"
awk 'NF && $2 != "finish" && NF < 3 { print "REFUSE: no reason or target: " $0 }' "$DISPOSITIONS"
```

A `<` line is an open subtask nobody disposed of and it stops the close; a `>`
line names one that is not open, so the list was written against a stale reading
and the script must be re-run.

```text
REFUSE: <count> open subtask(s) under #<N> have no disposition.

  <owner/repo>#<issue>  <title>

Nothing was closed. Give each one finish, not-planned with a reason, or
reparent with the anchor that inherits it, then re-run.
```

The durable record of a disposition is the act itself, never the scratch file and
never the anchor body: progress is derived from the index, and the body is a
charter.

**Carry them out, then read the same script again**, because the dispositions are
claims until GitHub shows them.

```sh
"$CONTAINER/scripts/campaign-settlement" "$N" >| /tmp/settlement-after-$N
cat /tmp/settlement-after-$N
grep -q '; closable$' /tmp/settlement-after-$N ||
  grep -q 'the index is empty' /tmp/settlement-after-$N ||
  echo "REFUSE: open subtasks remain after the dispositions were carried out"
```

`; closable$` and not `closable`, because the failing line ends `NOT closable:
open subtasks remain`. The empty-index line is the second accepted reading, for a
campaign with no subtasks at all.

A `-- REPORT:` line about nested sub-issues is not covered by this gate: a
subtask that is itself an anchor hides its own members, so run the script on it
and dispose of those rows too.

Holds when: `campaign-settlement` reads every subtask in the anchor's index as
settled or moved to another anchor, each open one having been given a named
disposition and had that act carried out first.

### 4. Validate the README, compare, then overwrite the anchor issue body

The README and the anchor body are the same template filled in
(`.claude/skills/opening-campaign/assets/README.md`), so the sync is an
overwrite, which leaves the README the only thing between a malformed heading and
the loss of the repository index step 5 deletes. Validate first.

```sh
README="$CAMPAIGN_DIR/README.md"
rm -f /tmp/repos-before /tmp/repos-after
"$CONTAINER/scripts/campaign-repos" "$README" >| /tmp/repos-before.tmp &&
  mv /tmp/repos-before.tmp /tmp/repos-before ||
  { rm -f /tmp/repos-before.tmp
    echo "REFUSE: the ## Repos list did not read; nothing was written"; }
```

`scripts/campaign-repos` is the one reader of that list (`AGENTS.md` § Running a
campaign lists its refusals). Stop on a non-zero exit, do not re-derive the list
with `sed` here, and read empty output as a repo-less campaign rather than a
failure. Keep the `.tmp`-then-`mv` and the leading `rm -f`, or a failed read
leaves what a legitimate `- none` leaves.

This step also runs mid-campaign, whenever a repository is added to the
`## Repos` list — `opening-campaign`'s "Filing a subtask issue" sends you here.
Those are the only two moments the body is written at (§ Running a campaign), so
nothing in step 3 edits the body.

**Then compare before you write.** `runtime/anchor-body-derived.md` is the body
as it read when this README was derived from it, kept by `opening-campaign` step
4; re-read the body now and require the two to match.

```sh
DERIVED="$CAMPAIGN_DIR/runtime/anchor-body-derived.md"
[ -f "$DERIVED" ] || echo "REFUSE: no runtime/anchor-body-derived.md to compare against"
gh issue view "$N" -R kalaluthien/agent-workspace --json body -q .body >| /tmp/body-now
command diff -u "$DERIVED" /tmp/body-now && echo "the body has not moved; safe to write"
```

Read the diff and not the exit status alone: it names what the other writer did.

```text
REFUSE: the anchor body has moved since this README was derived from it.

  <the diff above>

Nothing was written. Fold those changes into <CAMPAIGN_DIR>/README.md, refresh
runtime/anchor-body-derived.md from /tmp/body-now, then re-run.
```

Refuse the same way when the derived copy is missing, because without it "has the
body moved?" has no answer. Say so, read the body and the README side by side
yourself, then write `/tmp/body-now` to the derived path and re-run.

Only then overwrite, reading the index back out of what GitHub actually stored
and refreshing the derived copy so the next write compares against this one.

```sh
gh issue edit "$N" -R kalaluthien/agent-workspace --body-file "$README"
gh issue view "$N" -R kalaluthien/agent-workspace --json body -q .body >| /tmp/body-after
"$CONTAINER/scripts/campaign-repos" /tmp/body-after >| /tmp/repos-after.tmp &&
  mv /tmp/repos-after.tmp /tmp/repos-after ||
  { rm -f /tmp/repos-after.tmp
    echo "REFUSE: the body GitHub stored does not read; the index may be lost"; }
cmp -s /tmp/repos-before /tmp/repos-after && echo "index survived"
cp /tmp/body-after "$DERIVED"
```

Not identical: say so and stop before step 5, while the README still exists.

Holds when: the anchor issue body is this campaign's README, `## Repos` list
included, compared against `runtime/anchor-body-derived.md` before it was
written and read back through `campaign-repos` after.

### 5. Say you are closing, then close, then delete the directory

Only after the person confirms.

**Say it on the anchor issue first, and read who answers**, because the anchor is
the one place a machine working this campaign against its `BOUND` could answer.
**Say in the same comment what the delete will destroy**, one comment, posted
where it outlives the tree.

```sh
HOST=$(hostname -s)
[ -n "${CAMPAIGN_DIR-}" ] ||
  { echo "REFUSE: CAMPAIGN_DIR was never bound; step 0 did not run"; exit 1; }
[ -d "$CAMPAIGN_DIR/runtime" ] ||
  { echo "REFUSE: $CAMPAIGN_DIR holds no runtime/; not a campaign directory"; exit 1; }
LEFTOVERS=$(find "$CAMPAIGN_DIR" -mindepth 1 \
  \( -path "$CAMPAIGN_DIR/runtime" -o -path "$CAMPAIGN_DIR/repos" \) -prune -o -print \
  | sed "s|^$CAMPAIGN_DIR/||" | sort \
  | grep . || echo "no entries outside runtime/ and repos/")
BODY=$(printf 'Closing campaign #%s from %s. Say so here if you are still in it.\n\nThe delete destroys these entries under the campaign directory, `runtime/` and `repos/` excluded:\n\n```\n%s\n```\n' \
  "$N" "$HOST" "$LEFTOVERS")
gh issue comment "$N" -R kalaluthien/agent-workspace --body "$BODY"
gh issue view "$N" -R kalaluthien/agent-workspace --comments
```

**Unset or empty is step 0 not having run**, and it refuses; since #52 a
campaign bound here has a directory by the time this step runs. The value must
hold `runtime/`, the cheap test that it is not the container root. Keep `-prune`
on the two exact paths and `-print` without `-type f`, so the listing names
everything `rm -rf` destroys.

**Read the listing knowing what is on it.** `AGENTS.md`, `CLAUDE.md`, `README.md`
and `scripts/` are the scaffold copied at open and are the rows to skip; nothing
filters them, because telling a template copy from this campaign's one real file
is a reader's job. It is a record, not a to-do: anything a person wants out of
the tree is saved before they say close. Another session's note saying it is
working or closing: stop, name it, let the person resolve it, and say it should
not have been there, because the campaign is bound here.

**Release the campaign's own claim refs on the container**, because a subtask
that landed no commits leaves its branch at `origin/main` outliving the campaign.
Step 3 is what makes the sweep sighted: every subtask is settled by now, so no
claim ref here can be a live workspace.

```sh
gh api "repos/kalaluthien/agent-workspace/git/matching-refs/heads/campaign-$N/" \
  --jq '.[] | "\(.ref)\t\(.object.sha)"' |
while IFS="$(printf '\t')" read -r REF SHA; do
  AHEAD=$(gh api "repos/kalaluthien/agent-workspace/compare/main...$SHA" --jq .ahead_by) || exit 1
  if [ "$AHEAD" = 0 ]; then
    gh api -X DELETE "repos/kalaluthien/agent-workspace/git/$REF" && echo "released $REF"
  else
    echo "REFUSE-ROW: $REF holds $AHEAD commit(s) beyond main — push a PR or say to discard"
  fi
done
```

**Ancestry, not equality**: a claim ref is created at the `main` of claim time and
`main` moves on, so `ahead_by` answers what a sha comparison gets wrong. Print a
row that holds commits and never delete it — the one row here that stops and
asks. Member repositories' refs are released by their pull request merge.

Then close, in this order — the issue first, because a failed close leaves the
directory to retry from, while the reverse leaves nothing.

```sh
gh issue close "$N" -R kalaluthien/agent-workspace --comment "Campaign closed."
```

**Check nobody else on this machine is in the directory**, because two sessions
given the same slug on the same day build the same path and step 1 would not have
caught it.

```sh
lsof +D "$CAMPAIGN_DIR" 2>/dev/null | tail -n +2
```

Any rows: name the processes and stop. `lsof` sees an open file, not a session
idle between turns, so an empty result is weak evidence and is paired with the
announcement above rather than trusted alone.

List the directory and confirm it holds only the campaign, then remove the bound
path itself — not a path retyped here, not its parent, not a wildcard.

```sh
ls -A "$CAMPAIGN_DIR"
rm -rf -- "$CAMPAIGN_DIR"
```

`runtime/` goes with it — `holder`, every `executors/<issue>` record, every
handover brief — by design, since nothing off this machine reads them. Say so.

Holds when: the closing comment carries the listing taken immediately before the
delete — every entry under the directory outside `runtime/` and `repos/`, files
and directories and symlinks alike, because `rm -rf` destroys all of them — and
every `campaign-<N>/` claim ref still sitting at `origin/main` is released, any
that holds commits reported and not deleted.

## Gotchas

The probes and the failures behind these: `references/gotchas.md`.

- The failures step 2 used to have to get right — a squash merge making a
  landed branch read unmerged forever, `git status --porcelain` never listing
  an ignored file, an unreadable `repos/` reading as a repo-less campaign, and
  a checkout whose `.git` is a file leaving the verdict — belong to
  `scripts/campaign-local-work` now, and its docstring is where they are stated.
  The one that stayed here is the unmatched `repos/*/` glob, because the script
  does not glob and that failure is any shell line's, not the script's.
- `dropped` covers four closes and its note says which; only `not planned` is
  abandonment, so quote the note, not the word.
- `state_reason` is lowercase from `gh api` and uppercase from `gh issue list
  --json stateReason`, and the wrong one reads every subtask as unsettled.
- `set -- $var` does not word-split in zsh, so a gate built on it tests nothing;
  split with `${spec%%:*}` and `${spec##*:}` instead.
- `diff` is shadowed in a Claude Code shell on this machine, and a gate that
  errors out is a gate that tested nothing. Write `command diff`.
- Two sessions given the same slug on the same day build the same path, so this
  delete may hit another session's live workspace. `runtime/holder` catches that
  in step 1; the herdr gate cannot, because it matches an agent's `cwd`. A
  machine the campaign left at a migration may still hold a stale directory of
  its own — `references/rationale.md`, step 5.
