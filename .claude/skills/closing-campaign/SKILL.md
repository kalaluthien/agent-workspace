---
name: closing-campaign
description: Closes a campaign — binds the campaign directory, refuses when the anchor is BOUND to another machine or another live session holds it, refuses while an agent is live or while work exists only on this machine, refuses while any open subtask lacks a disposition, syncs the README into the anchor issue, then closes the issue and deletes the directory. Use when a person says a campaign is finished, done, over, or wrapped up, or asks to close, retire, archive, or clean up a campaign or its directory. Not for closing a single subtask issue or retiring one repository agent; not for opening or scaffolding a campaign, which is opening-campaign.
---

# Closing a campaign

Delete a campaign directory only after everything in it also exists somewhere
else. The directory is a scratch assembly of things versioned elsewhere, so
closing is a checked demolition, not a decision.

Finished when all eight hold:

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
  written;
- the closing comment on the anchor carries the listing taken immediately
  before the delete: every entry under the directory outside `runtime/` and
  `repos/`, files and directories and symlinks alike, because `rm -rf` destroys
  all of them;
- every `campaign-<N>/` claim ref on the container that still sits at
  `origin/main` is released, and any that holds commits is reported rather than
  deleted.

Where this machine holds no directory for the campaign, the first three and the
last are the real conditions — the binding, and three GitHub facts that read the
same from any machine — and the middle four are about a cache that does not
exist. Step 0 says what to skip.

## Procedure

The order is load-bearing: each gate is cheaper than the one after it, and step
5 is irreversible. Run 0–4 without asking, with one exception — step 3 reads and
refuses on its own, but an open subtask's disposition is the person's choice and
this skill acts on GitHub only once they have made it. Run 5 only on explicit
confirmation.

### 0. Bind the campaign, once

**The ID first.** Every step from 3 on reads `$N`, and nothing in the directory
carries it: the README *is* the anchor body, and a body does not know its own
issue number. Take it from the person, or resolve it from the open anchors and
say which one you matched — the `campaign` label is what they are listed by.

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
5, where the delete then has nothing to do. Closing the issue is what closes the
campaign; deleting a directory is dropping a cache.

Every later step reads `$CAMPAIGN_DIR`, and two fail silently if it is relative
or wrong: step 1 compares it against herdr's absolute `cwd`, so a relative value
matches nothing and the refusal passes having found nothing; step 5 then deletes
relative to whatever directory the session happens to hold. Bind it here, from
the slug the person gave, and never rebuild it later in the run.

**Bind it on both paths — including the one where there is no directory.** Step
5 has to tell three states apart, and *unset* is not one of them: unset means
nobody ran this step, which is a different problem from a campaign this machine
holds no cache of. So the no-directory path binds the empty string, explicitly.

```sh
CONTAINER=$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd -P)

CAMPAIGN_DIR=$(cd "$CONTAINER/$SLUG" && pwd -P)   # this machine has one
CAMPAIGN_DIR=                                     # or it has none
```

On the empty path steps 1, 2 and 4 are skipped and so are the two assertions
below; step 5 posts its announcement with nothing to list. On the bound path,
assert both facts `AGENTS.md` already pins, so the assertions cost nothing:

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
its work in a checkout.

**The container checkout first.** A container subtask — the one kind an executor
session works with its own hands — is worked there or in a worktree of it, never
under `repos/`, so the loop below cannot see it. No `--ignored` here: the
container ignores every campaign directory and would report each as a blocker.
The delete spares this work, but step 5 closes the anchor indexing it. For a
repo-less campaign this is the whole of step 2: the sweep below has no `repos/`
to enumerate, and this is where its executors' work actually is.

**Scope it to `campaign-$N/`.** One container serves every campaign at once, so
an unscoped read makes another campaign's live worktree a blocker on this close
— and the refusal then tells the person to clear a row that is somebody else's
work in flight.

```sh
git -C "$CONTAINER" for-each-ref --format='%(refname:short)' "refs/heads/campaign-$N/" |
  while read -r B; do
    git -C "$CONTAINER" log --oneline "$B" --not --remotes | sed "s|^|$B  |"
  done
git -C "$CONTAINER" worktree list | tail -n +2 | grep "\[campaign-$N/" || true
git -C "$CONTAINER" status --porcelain
```

The last line is the one that cannot be scoped: the container has a single
working tree and an uncommitted edit in it carries no campaign. Print it, name it
as unattributed, and do not count it as a blocker — this close deletes nothing
that holds it. The first two are this campaign's own, and they are blockers.

**Then every checkout under `repos/`**, one at a time — never one git command
across member repositories — reading `$CAMPAIGN_DIR/runtime/handover/` beside
them and saying which briefs you cannot account for.

```sh
if [ -d "$CAMPAIGN_DIR/repos" ]; then
find "$CAMPAIGN_DIR/repos" -mindepth 1 -maxdepth 1 -type d >| /tmp/checkouts-$N ||
  echo "REFUSE: repos/ did not enumerate; nothing was checked"
while read -r R; do
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
done < /tmp/checkouts-$N
fi
```

`find` rather than a `repos/*/` glob is a portability fix; the gotcha below says
what each shell does with an unmatched one.

**The `[ -d ]` wrapper is what tells "no member repository" from "cannot look".**
A campaign with no member repository has no `repos/` at all, and that is
legitimate — the wrapper skips the sweep and says nothing. A `repos/` that
exists but cannot be read is not legitimate, and it looked identical while
`find` carried `2>/dev/null`: an `EACCES` printed nothing, the loop ran zero
times, and the close read a repo-less campaign where there were checkouts it was
not allowed to see. The two are now different branches.

**And the enumeration goes to a file, not through a pipe.** A pipeline's exit
status is its last command's, so `find | while read` discards whatever `find`
said; writing to `/tmp/checkouts-$N` puts `find`'s own failure back where a
`||` can catch it. `-type d` is the per-row guard the loop used to repeat.

Each line finds what the others miss: `--ignored=matching` reaches a `.env` or a
downloaded fixture that plain `status` hides; `HEAD` alongside `--branches` reaches
a commit on a detached head; `tail -n +2` drops the main worktree, which always
prints. A repository whose default branch will not resolve is reported, not skipped.

Report one row per thing at risk, never one per check: an unpushed commit is
found twice, by `log --not --remotes` and by `branch --no-merged`, and is still
one blocker. Keep both — the overlap is what makes them hard to fool — and merge
only the report. A branch `--no-merged` names is not a blocker if it is pushed,
nor if it was squash-merged, which looks exactly like the real thing (see the
gotcha); say which of the three each row is.

Refuse in this shape, so two refusals written on different days can be read side
by side:

```text
REFUSE: <count> item(s) exist only on this machine: under <CAMPAIGN_DIR>, or on
this campaign's own campaign-<N>/ branches in <CONTAINER>.

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
whether the campaign is closable. Keep it in a file: the rest of this step is
read off it by machine.

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

`command diff`, not `diff` — see the gotcha below. A `<` line is an open subtask
nobody disposed of and it stops the close; a `>` line names one that is not open,
so the list was written against a stale reading and the script must be re-run.

```text
REFUSE: <count> open subtask(s) under #<N> have no disposition.

  <owner/repo>#<issue>  <title>

Nothing was closed. Give each one finish, not-planned with a reason, or
reparent with the anchor that inherits it, then re-run.
```

`/tmp/dispositions-$N` is scratch and dies with the run; the durable record of
each disposition is the act itself — the merged pull request, the reason in the
close comment, the new parent. Nothing here is written into the anchor body:
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

`; closable$` and not `closable`, because the failing line ends `NOT closable:
open subtasks remain` and a bare match reads it as a pass. The empty-index line
is the second accepted reading: a campaign with no subtasks prints no settlement
count at all, and refusing it would leave such a campaign unclosable.

A `-- REPORT:` line about nested sub-issues is not covered by this gate. A
subtask that is itself an anchor hides its own members, so run the script on it
and dispose of those rows too before you count this one settled.

### 4. Validate the README, compare, then overwrite the anchor issue body

The README and the anchor body are the same anchor template filled in —
`.claude/skills/opening-campaign/assets/README.md` — so the sync is an overwrite.
That makes the README the only thing standing between a malformed heading and the
loss of the repository index whose last copy step 5 deletes. Validate first.

```sh
README="$CAMPAIGN_DIR/README.md"
rm -f /tmp/repos-before /tmp/repos-after
"$CONTAINER/scripts/campaign-repos" "$README" >| /tmp/repos-before.tmp &&
  mv /tmp/repos-before.tmp /tmp/repos-before ||
  { rm -f /tmp/repos-before.tmp
    echo "REFUSE: the ## Repos list did not read; nothing was written"; }
```

`scripts/campaign-repos` is the one reader of that list; its refusals are listed
in `AGENTS.md` § Running a campaign. It prints one `owner/repo` per line, prints
nothing and exits 0 for a list that is exactly `- none`, and exits 1 with one
line on stderr. Stop on a non-zero exit, and do not re-derive the list with
`sed` here.

**`.tmp` then `mv`, and both files removed first.** A refusal that has already
truncated `/tmp/repos-before` leaves a zero-length file, and zero-length is what
a legitimate `- none` leaves — so a failed read reads as a repo-less campaign,
which is the one shape whose index is *meant* to be empty. Worse, the read-back
below compares the two files: two failures leave two empty files and `cmp -s`
prints "index survived" over a body nobody managed to read. Absent files make
`cmp -s` exit 2, and the pre-emptive `rm -f` stops a leftover from an earlier
run standing in for either of them.

Empty output is therefore not a failure and not a special case. A repo-less
campaign reads as no repositories, step 2's loop is guarded and finds no
checkouts, and the comparison below compares nothing with nothing.

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

`command diff`, not `diff` — see the gotcha below. Read the diff and not the
exit status alone: it names what the other session did.

```text
REFUSE: the anchor body has moved since this README was derived from it.

  <the diff above>

Nothing was written. Fold those changes into <CAMPAIGN_DIR>/README.md, refresh
runtime/anchor-body-derived.md from /tmp/body-now, then re-run.
```

Refuse the same way when `runtime/anchor-body-derived.md` is missing — a campaign
scaffolded before the file existed, or a directory built by hand. There is no
cheap substitute: without it "has the body moved?" has no answer, and guessing it
has not is the write this step exists to stop. Say so, read the body and the
README side by side yourself, then write `/tmp/body-now` to the derived path and
re-run.

Only then overwrite — reading the index back out of what GitHub actually stored,
and refreshing the derived copy so the next write compares against this one:

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

### 5. Say you are closing, then close, then delete the directory

Only after the person confirms.

**Say it on the anchor issue first, and read who answers.** Step 1's gate is
local, and under the principle that covers everything legitimate: every agent
and every executor session of this campaign is on the machine it is `BOUND` to,
and step 1 saw every one that announced, while step 2 read the container and
`repos/` for the work of one that did not. What neither can see is a machine
working this campaign against the binding, and no cheap local check can. The
anchor issue is the one place every machine can read, so announce there and read
the comments back —
this is the guard for a broken principle, not a routine handshake.

**Say in the same comment what the delete will destroy.** The listing is every
entry under the campaign directory outside `runtime/` and `repos/`: `runtime/`
is scratch by design and `repos/` is clones with their own remotes, and what is
left is the scaffold plus whatever this campaign built on top of it. It is the
record of what the delete destroys, posted where it outlives the tree. One
comment, not two: the announcement carries it.

```sh
HOST=$(hostname -s)
case "${CAMPAIGN_DIR-unset}" in
  unset)
    echo "REFUSE: CAMPAIGN_DIR was never bound; step 0 did not run"; exit 1 ;;
  "")
    BODY=$(printf 'Closing campaign #%s from %s. Say so here if you are still in it.\n\nNo campaign directory on %s: nothing here to delete, and nothing to list.\n' \
      "$N" "$HOST" "$HOST") ;;
  *)
    [ -d "$CAMPAIGN_DIR/runtime" ] ||
      { echo "REFUSE: $CAMPAIGN_DIR holds no runtime/; not a campaign directory"; exit 1; }
    LEFTOVERS=$(find "$CAMPAIGN_DIR" -mindepth 1 \
      \( -path "$CAMPAIGN_DIR/runtime" -o -path "$CAMPAIGN_DIR/repos" \) -prune -o -print \
      | sed "s|^$CAMPAIGN_DIR/||" | sort \
      | grep . || echo "no entries outside runtime/ and repos/")
    BODY=$(printf 'Closing campaign #%s from %s. Say so here if you are still in it.\n\nThe delete destroys these entries under the campaign directory, `runtime/` and `repos/` excluded:\n\n```\n%s\n```\n' \
      "$N" "$HOST" "$LEFTOVERS") ;;
esac
gh issue comment "$N" -R kalaluthien/agent-workspace --body "$BODY"
gh issue view "$N" -R kalaluthien/agent-workspace --comments
```

**Three states, and the announcement is posted in two of them.** `unset` is not
a campaign without a directory — it is step 0 not having run, and it is the
wrong-cwd hazard this guard exists for, so it refuses. The empty string is what
step 0 binds when this machine holds no directory: there is nothing to list and
nothing to delete, and the announcement still goes up, because the announcement
is what a machine working this campaign against its `BOUND` would answer. A
non-empty value must hold `runtime/`, which is the cheap test that it is a
campaign directory and not the container root.

**`-prune` on the two exact paths, not a `*/runtime*` pattern.** A pattern also
hides `scripts/repos-helper.sh` and anything else whose name merely contains
`repos` or `runtime` — an omission from a listing whose whole job is to omit
nothing (probed: the pattern form drops exactly that file). And `-print` without
`-type f`, because `rm -rf` destroys directories, symlinks and FIFOs too, and a
file-only listing would not have named them.

**`grep . || echo` rather than a `${LEFTOVERS:-...}` default**, so the words are
written by a listing that really ran rather than by an assignment that never
happened. That branch fires only for a directory whose scaffold was taken out by
hand: an intact one always lists at least `AGENTS.md`, `CLAUDE.md`, `README.md`
and `scripts/`.

**Read the listing, and read it knowing what is on it.** Those four are the
scaffold, copied from the skill's own `assets/` at open, so they appear on every
listing and are the rows to skip. The listing omits nothing on purpose — telling
a template copy from the one file this campaign wrote is a reader's job, not a
filter's, because a filter that guessed would be the thing that dropped the file
somebody wanted. And it is a record, not a to-do: the close is where the tree
stops existing, so anything a person wants out of it is saved before they say
close, not after they read the list.

Another session's note saying it is working or closing: stop, name it, let the
person resolve it, and say it should not have been there, because the campaign is
bound here. This narrows the window rather than closing it — a session that never
comments is invisible either way — and what keeps that survivable is the rule
that a delegate pushes as soon as it has one commit, so a tree deleted underneath
it costs uncommitted work and nothing more.

**Release the campaign's own claim refs on the container.** A repo-less
campaign's subtasks are claimed by `campaign-<N>/<issue>-<topic>` branches on
`kalaluthien/agent-workspace`, and a subtask that landed no commits leaves that
branch sitting at `origin/main` forever — the campaign is closed and the claim
outlives it. What makes this release sighted rather than blind is step 3, not
step 1: every subtask is settled or disposed of by now, so no claim ref here can
be an executor's live workspace — and step 3 runs on the no-directory path too,
where step 1 was skipped, and it sees hands and subagent executors that no
`herdr agent list` row would. `AGENTS.md` forbids deleting a claim ref while an
agent on your machine works it; this is the one place where that has been
established for every ref at once.

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

**Ancestry, not equality.** A claim ref is created at the `main` of claim time,
and `main` moves on; a zero-commit claim compared against today's `main` sha
reads unequal and would be refused as holding work — which is exactly the ref
this step exists to release. `compare/main...<sha>` answers the right question:
`ahead_by` is the commits the ref holds that `main` does not, and `0` releases
whatever `behind_by` says (probed: a claim four commits behind reads
`ahead_by=0 behind_by=4 status=behind`).

Print a row that holds commits; never delete it. Its branch is somebody's
unlanded work and the anchor closing does not make it disposable — that is the
person's call, and it is the one row of this step that stops and asks.
`matching-refs` returns an empty array rather than a 404 when a campaign claimed
nothing (probed), so the loop runs zero times and says nothing. Member
repositories' claim refs are out of scope here: theirs are released by the pull
request merge that closes the subtask, and reaching into another repository's
refs from a close is exactly the cross-repository sweep this container forbids.

Then close, in this order — the issue first, because a failed close leaves the
directory to retry from, while the reverse leaves nothing. The comment states
only what has already happened at the moment it is written.

```sh
gh issue close "$N" -R kalaluthien/agent-workspace --comment "Campaign closed."
```

**Where this machine holds no directory, stop here** — `$CAMPAIGN_DIR` is empty
from step 0, the delete has nothing to do, and every command below would run
against `""` and print an error where every abnormal line of this skill is a
refusal. Everything from here to the end of the step is under this guard:

```sh
[ -n "$CAMPAIGN_DIR" ] || { echo "no directory on this machine; nothing to delete"; exit 0; }
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

`runtime/` goes with it — `holder`, every `executors/<issue>` record, every
handover brief — by design and not as a loss: nothing off this machine reads
them, which is why they were allowed to be files. Say so rather than assuming
the person knows.

## Gotchas

- **An unmatched `repos/*/` glob fails two different ways, and this skill is run
  by hand in whatever shell the person is in** — which is why step 2 enumerates
  with `find` (all three probed):

  | shell | what an unmatched `repos/*/` does |
  | --- | --- |
  | bash, sh | leaves the glob literal, so the loop runs once on `.../repos/*/` and six git commands fail against a path that does not exist — output that reads as an unresolvable repository blocking the close |
  | zsh | `no matches found`, and the whole `for` never runs — a gate that reported nothing because it tested nothing, and an abort outright under `set -e` |

  `find` has neither failure in any of the three, and over a `repos/` that exists
  but is empty it simply prints nothing. Do not reach for `nullglob` or a zsh
  `(N)` qualifier: each fixes one shell and breaks the other.
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
  merge writes a *new* commit onto the base, so the topic branch stays "unmerged"
  forever; pair that with `--delete-branch` and it is absent from the remote too
  — the exact signature of work that exists only on this machine — so a fully
  landed campaign reports one false blocker per member repository. The
  discriminator is content: `git -C <repo> diff --stat <base>..<branch>` empty
  means the branch changes nothing the base lacks, however ancestry reads. Check
  the paths the subtask touched too, since a branch cut before the base moved on
  diffs non-empty on files it never edited. Report such a row as landed.
- **`set -- $var` does not word-split in zsh, and this skill is made of gates.**
  Unquoted parameters stay unsplit, so `for pair in a:1 b:2; do set -- $pair`
  leaves `$2` empty. Here it failed loudly — `gh` answered `invalid issue format:
  ""` — but the same construct inside a check whose empty result reads as
  "nothing to report" passes having tested nothing. Split with a parameter
  expansion (`repo=${spec%%:*}`, `num=${spec##*:}`), and make any gate that can
  return empty say which of the two it means.
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
