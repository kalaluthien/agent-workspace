---
name: closing-campaign
description: Closes a campaign — binds the campaign directory, refuses when the anchor is BOUND to another machine, refuses while an agent is live or while work exists only on this machine, refuses while any open subtask lacks a disposition, syncs the README into the anchor issue, then closes the issue and deletes the directory. Use when a person says a campaign is finished, done, over, or wrapped up, or asks to close, retire, archive, or clean up a campaign or its directory. Not for closing a single subtask issue or retiring one repository agent; not for opening or scaffolding a campaign, which is opening-campaign.
---

# Closing a campaign

Delete a campaign directory only after everything in it also exists somewhere
else.

Finished when `gh issue view <N> -R kalaluthien/agent-workspace --json state`
reports `CLOSED`, `$CAMPAIGN_DIR` does not exist, and every step's `Holds when`
line held when that step ran — `grep '^Holds when' SKILL.md` is the whole list.

## Procedure

The order is load-bearing: each gate is cheaper than the next, and step 5 is
irreversible. Run 0–4 without asking, except step 3's disposition, which is the
person's choice; run 5 only on explicit confirmation. Why each guard is shaped
the way it is: `references/rationale.md`.

### 0. Bind the campaign, once

**The ID first**: every step from 3 on reads `$N`. Take it from the person, or
match it among the open anchors and say which.

```sh
CONTAINER=$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd -P)
"$CONTAINER"/scripts/campaign-tracker anchors
```

**Then the binding, before any other gate.**

```sh
"$CONTAINER"/scripts/campaign-tracker bound "$N"   # here | elsewhere <machine> | unbound
```

`here` — carry on. Anything else, including a failed read, refuses the close.
Another machine — refuse, naming both machines, and say nothing was closed. No
output means unbound, which is not consent either: let the person bind it here,
or close it from the machine that has been working it.

**Then the directory** — none yet is normal; take it first through
`opening-campaign`'s "No directory at all" arrival, **steps 2 and 4**. Bind
`$CAMPAIGN_DIR` here, absolute, and never rebuild it — steps 1 and 5 fail
silently on a relative value. If you created it in this step, set
`TOOK_IT_HERE=1`: steps 1 and 2 then report not-applicable rather than a pass
(`references/rationale.md`).

```sh
CONTAINER=$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd -P)
CAMPAIGN_DIR=$(cd "$CONTAINER/$SLUG" && pwd -P)
```

```sh
[ "$(dirname "$CAMPAIGN_DIR")" = "$CONTAINER" ] || echo "REFUSE: not a direct child of $CONTAINER"
case "${CAMPAIGN_DIR##*/}" in
  *-[0-9][0-9][0-9][0-9][0-9][0-9]) ;;
  *) echo "REFUSE: basename is not <slug>-<YYMMDD>" ;;
esac
```

Stop on either.

Holds when: the anchor's latest `BOUND` comment names this machine, and
`$CAMPAIGN_DIR` is absolute, a direct child of the container, and named
`<slug>-<YYMMDD>`.

### 1. Refuse while an agent is live under the tree

Whoever the person asked runs this skill, on the gates in steps 0 to 4. **If
`TOOK_IT_HERE` is set, this step and step 2 are not applicable — report that,
not a pass.** Run them anyway; they cost two commands (`references/rationale.md`).

`herdr agent list` gives liveness, not attribution — no row says which claim it
holds. `runtime/claims/` is the only source for that; every claimant writes
one, delegates included. Presence is the signal, not `agent_status`; compare
whole path segments, and never test a name against the branch.

```sh
herdr agent list | jq -r --arg tree "$CAMPAIGN_DIR" \
  '.result.agents[]
   | select(.cwd + "/" | startswith(($tree | sub("/$";"")) + "/"))
   | "\(.name // "unnamed")\t\(.agent_status)\t\(.cwd)"'

CLAIMDIR="$CAMPAIGN_DIR/runtime/claims"
if [ ! -d "$CLAIMDIR" ]; then
  echo "REFUSE: no $CLAIMDIR — claims cannot be enumerated"
else
  find "$CLAIMDIR" -type f -print | while read -r F; do
    P=$(awk '$1 == "pid" { print $2 }' "$F")
    V=$("$CONTAINER/scripts/campaign-claim" alive "$P" 2>&1) || V="unreadable ($V)"
    case "$V" in
      dead) ;;
      alive|other) echo "live claim: $(basename "$F") [$V]"; cat "$F" ;;
      *) echo "REFUSE: $(basename "$F") is $V"; cat "$F" ;;
    esac
  done
fi
```

**A missing `runtime/claims/` is a refusal, not a pass**: an empty one says no
claim was taken here, an absent one says nothing at all.

Any row from either: print the rows, name the agent, stop. The person retires
it; this skill never kills an agent. No rows still leaves two cases — an agent
herdr has forgotten, and a claim record whose `pid` reads `dead` because a
harness restart changed it while the session lives on — both leaving work in a
checkout.

Holds when: `runtime/claims/` existed, every record in it read `dead`, and no
herdr agent's `cwd` was under `$CAMPAIGN_DIR` — or `TOOK_IT_HERE` is set and this
step reported both as not applicable rather than as passed.

### 2. Refuse while work exists only on this machine

Deleting the directory destroys these and nothing recovers them. One reader
answers the whole question: `scripts/campaign-local-work`, over this campaign's
branches and worktrees, the container's working tree, and every checkout under
`repos/`. Do not re-derive any of that here.

```sh
"$CONTAINER/scripts/campaign-local-work" "$N" "$CAMPAIGN_DIR" >| /tmp/local-work-$N
cat /tmp/local-work-$N
```

**Exit 1 is the reading having failed, not a clean tree**: print the `-- REFUSE:`
line it ends on, stop, and conclude nothing. On exit 0 the last line is the
verdict and the rows above it are the report.

- An unmarked row is counted, and one counted row refuses the close: *Nothing
  was deleted. Clear every counted row, or say to discard it, then re-run.*
- A `~` row is named and not counted — pushed, landed over a squash merge, or a
  clean worktree.
- **A `-- REPORT:` line is one of two things.** A place the script *could not
  read* is a check that did not run — counted apart, refusing the close on its
  own (`… and <n> place(s) went unread; NOT clear`). Read it by hand, then
  re-run. Everything else it carries is for the person and blocks nothing.
- **Zero counted rows is not by itself a pass.** Read the last word:
  `0 item(s) … clear` is the pass.

Holds when: `campaign-local-work` exited 0 over this campaign and this directory,
and its last line read clear — either on the first run, or on a re-run after
every counted row was pushed, merged, or discarded on the person's word, and
every unread place was read by hand and either emptied or reported to the
person. A run that still says `NOT clear` with no counted row left is naming
places it could not reach, and the way out is to reach them, never to read past
the verdict.

### 3. Settle or dispose of every open subtask

**First, confirm `$N` is an anchor**, so step 5 does not close somebody's
subtask.

```sh
gh issue view "$N" -R kalaluthien/agent-workspace --json labels,parent \
  -q '"\([.labels[].name] | join(","))\t\(.parent.number // "-")"'
```

Want `campaign` among the labels and `-` for the parent. Anything else, stop and
say which issue `$N` actually is.

```sh
"$CONTAINER/scripts/campaign-tracker" settlement "$N" >| /tmp/settlement-$N
cat /tmp/settlement-$N
```

It prints one row per subtask, then whether the campaign is closable. Read the
note beside a `dropped` row before repeating the word.

**Every `open` row gets a disposition, and this step refuses without one** —
never over *unexamined* work. One of three per row, the person's choice:

| disposition | the act | what the row becomes |
| --- | --- | --- |
| `finish` | do the work, land the pull request, close the issue | `complete` |
| `not-planned` | `gh issue close <issue> -R <repo> --reason "not planned" --comment "<why>"` | `dropped` |
| `reparent` | `gh issue edit <issue> -R <repo> --parent <URL of the inheriting anchor>` | gone from this index — the sub-issue link is prunable |

Write one line per open row — `<owner/repo>#<issue>  <verb>  <reason or
target>` — then validate it against the settlement output by machine.

```sh
DISPOSITIONS=/tmp/dispositions-$N        # write it here, one line per open row
awk '$1 ~ /#[0-9]+$/ && $2 == "open" { print $1 }' /tmp/settlement-$N | sort >| /tmp/open-$N
awk 'NF { print $1 }' "$DISPOSITIONS" | sort >| /tmp/disposed-$N
command diff /tmp/open-$N /tmp/disposed-$N && echo "every open subtask has a disposition"
awk 'NF && $2 !~ /^(finish|not-planned|reparent)$/ { print "REFUSE: unknown disposition: " $0 }' "$DISPOSITIONS"
awk 'NF && $2 != "finish" && NF < 3 { print "REFUSE: no reason or target: " $0 }' "$DISPOSITIONS"
```

A `<` line is an open subtask with no disposition; a `>` line is stale — re-run
the script.

```text
REFUSE: <count> open subtask(s) under #<N> have no disposition.

  <owner/repo>#<issue>  <title>

Nothing was closed. Give each one finish, not-planned with a reason, or
reparent with the anchor that inherits it, then re-run.
```

**Carry them out, then read the same script again** — the dispositions are
claims until GitHub shows them.

```sh
"$CONTAINER/scripts/campaign-tracker" settlement "$N" >| /tmp/settlement-after-$N
cat /tmp/settlement-after-$N
grep -q '; closable$' /tmp/settlement-after-$N ||
  grep -q 'the index is empty' /tmp/settlement-after-$N ||
  echo "REFUSE: open subtasks remain after the dispositions were carried out"
```

`; closable$`, not `closable` — the failing line ends `NOT closable: open
subtasks remain`. The empty-index line is the other accepted reading. A
`-- REPORT:` line about nested sub-issues isn't covered here: a subtask that is
itself an anchor hides its own members — run the script on it too.

Holds when: `campaign-tracker settlement` reads every subtask in the anchor's index as
settled or moved to another anchor, each open one having been given a named
disposition and had that act carried out first.

### 4. Validate the README, compare, then overwrite the anchor issue body

The README and the anchor body are the same template filled in
(`.claude/skills/opening-campaign/assets/README.md`), so the sync is an
overwrite. Validate first.

```sh
README="$CAMPAIGN_DIR/README.md"
rm -f /tmp/repos-before /tmp/repos-after
"$CONTAINER/scripts/campaign-repos" "$README" >| /tmp/repos-before.tmp &&
  mv /tmp/repos-before.tmp /tmp/repos-before ||
  { rm -f /tmp/repos-before.tmp
    echo "REFUSE: the ## Repos list did not read; nothing was written"; }
```

`scripts/campaign-repos` is the one reader of that list. Stop on a non-zero
exit; read empty output as a repo-less campaign, not a failure. Keep the
`.tmp`-then-`mv` and the leading `rm -f`, or a failed read leaves what a
legitimate `- none` leaves.

This step also runs mid-campaign, when a repository is added to `## Repos`;
nothing in step 3 edits the body.

**Then compare before you write** — `runtime/anchor-body-derived.md` is the
body as it read when this README was derived; re-read the body now and require
the two to match.

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

**Name the cause before you repair it** — step 0 already read the binding, so
`elsewhere` never reaches this step. Ask the peers (`ListAgents`, then
`SendMessage` to each) whether one wrote it; if none claims it, ask the
person — this machine cannot otherwise tell their edit from one made on an
unbound machine. The full three-cause table and what each wants:
`references/rationale.md`.

Refuse the same way when the derived copy is missing — without it "has the body
moved?" has no answer. Read the body and the README side by side, write
`/tmp/body-now` to the derived path, and re-run.

Only then overwrite, then refresh the derived copy so the next write compares
against this one.

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

**Say it on the anchor issue first, and read who answers** — the anchor is the
one place a machine working this campaign against its `BOUND` could answer. Say
what the delete will destroy in the same comment.

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

**A directory and the file inside it both appear, and that is correct** —
`scripts/` ships a `.gitkeep`. Do not narrow the `find` to `-type f`: `rm -rf`
destroys files, directories and symlinks alike, and a guessed filter would drop
the wanted entry.

**Unset or empty is step 0 not having run**, and it refuses. The value must
hold `runtime/`, the cheap test that it is not the container root.

**Read the listing knowing what is on it.** `AGENTS.md`, `CLAUDE.md`,
`README.md`, `scripts/` are the scaffold — skip those rows. It is a record, not
a to-do: anything wanted out of the tree is saved before close. A peer's note
that it is working or closing: stop and name it.

**Release the campaign's own claim refs on the container** — an unlanded
subtask leaves its branch outliving the campaign; step 3 makes this sighted.

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

**No `--paginate`** — `git/matching-refs` returns every ref in one response
(`references/gotchas.md`); the flag would claim otherwise.

**Ancestry, not equality** — `main` moves after the claim, so `ahead_by` catches
what a sha comparison would miss. Print a row that holds commits and never
delete it. Member repositories' refs are released by their pull request merge.

Then close, in this order — the issue first.

```sh
gh issue close "$N" -R kalaluthien/agent-workspace --comment "Campaign closed."
```

**Check nobody else on this machine is in the directory.**

```sh
lsof +D "$CAMPAIGN_DIR" 2>/dev/null | tail -n +2
```

Any rows: name the processes and stop. `lsof` sees an open file, not an idle
session, so an empty result is weak evidence, paired with the announcement
above rather than trusted alone.

List the directory and confirm it holds only the campaign, then remove the bound
path itself — not a path retyped here, not its parent, not a wildcard.

```sh
ls -A "$CAMPAIGN_DIR"
rm -rf -- "$CAMPAIGN_DIR"
```

`runtime/` goes with it — nothing off this machine reads it. Say so.

Holds when: the closing comment carries the listing taken immediately before the
delete — every entry under the directory outside `runtime/` and `repos/`, files
and directories and symlinks alike, because `rm -rf` destroys all of them — and
every `campaign-<N>/` claim ref still sitting at `origin/main` is released, any
that holds commits reported and not deleted.

## Gotchas

The probes and the failures behind these: `references/gotchas.md`.

- The failures step 2 used to have to get right belong to
  `scripts/campaign-local-work` now. The one that stayed here is the unmatched
  `repos/*/` glob, because the script does not glob.
- `dropped` covers four closes and its note says which; only `not planned` is
  abandonment, so quote the note, not the word.
- `state_reason` is lowercase from `gh api` and uppercase from `gh issue list
  --json stateReason`, and the wrong one reads every subtask as unsettled.
- `set -- $var` does not word-split in zsh; split with `${spec%%:*}` and
  `${spec##*:}` instead.
- `diff` is shadowed in a Claude Code shell on this machine. Write `command diff`.
- Every session of a campaign shares its one directory, so this delete may hit a
  peer's live workspace — `runtime/claims/` catches that in step 1,
  `campaign-local-work` in step 2; the herdr `cwd` gate alone cannot, since a
  session working from the container root has the container as its `cwd`. A
  machine left at a migration may still hold a stale directory of its own
  (`references/rationale.md`, step 5).
