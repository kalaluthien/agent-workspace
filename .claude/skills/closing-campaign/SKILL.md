---
name: closing-campaign
description: Closes a campaign — binds the campaign directory, refuses while an agent is live or while work exists only on this machine, reports unsettled subtasks, syncs the README into the anchor issue, then closes the issue and deletes the directory. Use when a person says a campaign is finished, done, over, or wrapped up, or asks to close, retire, archive, or clean up a campaign or its directory. Not for closing a single subtask issue or retiring one repository agent; not for opening or scaffolding a campaign, which is opening-campaign.
---

# Closing a campaign

Delete a campaign directory only after everything in it also exists somewhere
else. The directory is a scratch assembly of things versioned elsewhere, so
closing is a checked demolition, not a decision.

Finished when all four hold:

- `gh issue view <N> -R kalaluthien/agent-workspace --json state` reports
  `CLOSED`;
- the campaign directory does not exist;
- no herdr agent's `cwd` is under the path that directory had;
- the anchor issue body is the campaign README, `## Repos` list included, and
  the body was compared against `runtime/anchor-body-derived.md` before it was
  written.

## Procedure

The order is load-bearing: each gate is cheaper than the one after it, and step
5 is irreversible. Run 0–4 without asking. Run 5 only on explicit confirmation.

### 0. Bind the campaign directory, once

Every later step reads `$CAMPAIGN_DIR`, and two of them fail silently if it is
relative or wrong: step 1 compares it against herdr's absolute `cwd`, so a
relative value matches nothing and the live-agent refusal passes while finding
nothing; step 5 then deletes relative to whatever directory the session happens
to hold. Bind it here, from the slug the person gave, and never rebuild it later
in the run.

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

### 1. Refuse while an agent is live under the tree

Presence in `herdr agent list` is the signal, not `agent_status` — that reports
the screen and calls a mid-turn pause `idle`. An agent listed under the tree
blocks the close whatever its status says.

Compare whole path segments. A bare prefix test matches a sibling whose name
merely starts the same, and misses the directory itself.

```sh
herdr agent list | jq -r --arg tree "$CAMPAIGN_DIR" \
  '.result.agents[]
   | select(.cwd + "/" | startswith(($tree | sub("/$";"")) + "/"))
   | "\(.name // "unnamed")\t\(.agent_status)\t\(.cwd)"'
```

Any row: print the rows, say which agent holds the campaign, stop. The person
retires it; this skill never kills an agent.

No rows still leaves one case open — an agent herdr has forgotten whose session
is mid-turn. If `$CAMPAIGN_DIR/runtime/handover/` names briefs you cannot
account for, say so before continuing.

### 2. Refuse while work exists only on this machine

Deleting the directory destroys these and nothing recovers them. Check every
checkout under `repos/`, one at a time — never one git command across member
repositories.

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

### 3. Report the unsettled subtasks

The index is the anchor's sub-issue list: one call, every member repository at
once, public or private. Pass `--paginate`, or a campaign past the first page
reports a truncated index as if it were complete.

```sh
gh api --paginate repos/kalaluthien/agent-workspace/issues/"$N"/sub_issues \
  -q '.[] | "\(.state)\t\(.state_reason // "-")\t\(.html_url)\t\(.title)"'
```

A subtask is settled when it is closed as completed with its pull request
merged, or closed as not planned — that second reading is what keeps a campaign
with a deliberately dropped subtask closable. So `closed` alone is not enough:
for each one closed as completed, confirm the pull request merged. The owner and
repository come from the `html_url` in the row above.

```sh
gh issue view "$NUM" -R "$REPO" --json closedByPullRequestsReferences \
  -q '.closedByPullRequestsReferences[].url'
```

```sh
gh pr view "$PR" -R "$REPO" --json state,mergedAt -q '"\(.state)\t\(.mergedAt)"'
```

Report every unsettled subtask. None of them blocks the close — a person may
close a campaign over unfinished work — but show them all before they decide.

### 4. Validate the README, compare, then overwrite the anchor issue body

The README and the anchor body carry the same five sections, so the sync is an
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
Closing is not the only time the anchor body is written; it is only the last.

**Then compare before you write.** You are not the only campaign session, and
this README was derived from the body at some earlier moment. If another session
has written the body since, an overwrite from here silently discards everything
it put there. `runtime/anchor-body-derived.md` is that earlier moment, kept by
`opening-campaign` step 4; re-read the body now and require the two to match.

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
local: it sees agents on this machine and nothing else. Another session may hold
this campaign on another machine with a delegate live in it, and no cheap local
check can see that. The anchor issue is the one place every session can read, so
announce there and read the comments back before going further.

```sh
gh issue comment "$N" -R kalaluthien/agent-workspace \
  --body "Closing campaign #$N from $(hostname -s). Say so here if you are still in it."
gh issue view "$N" -R kalaluthien/agent-workspace --comments
```

Another session's note saying it is working or closing: stop, name it, and let
the person resolve it. Otherwise carry on. This narrows the window rather than
closing it — a session that never comments is invisible either way. What keeps
that survivable is not this check but the rule that a delegate pushes its branch
as soon as it has one commit, so a tree deleted underneath it costs uncommitted
work and nothing more.

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

- `agent_status: idle` is a screen reading. A mid-turn pause looks identical to
  a finished agent, so presence in the list is the gate, never the status word.
- `state_reason` is spelled lowercase by `gh api` (`completed`, `not_planned`)
  and uppercase by `gh issue list --json stateReason` (`COMPLETED`,
  `NOT_PLANNED`). A comparison written against the wrong one matches nothing and
  reads every subtask as unsettled.
- A third value, `duplicate`, also appears. Treat it as settled — the work moved
  to another issue — and say that you did, since it is a reading the contract
  does not name.
- `state_reason` is `null` on an issue closed before GitHub added the field.
  Closed with no reason is not the same as unsettled; report it as unknown
  rather than folding it into either side.
- **After a squash merge, ancestry is the wrong test, and squash is the default
  merge here.** `git branch --no-merged <base>` walks ancestry, and a squash
  merge writes a *new* commit onto the base, so the topic branch stays
  "unmerged" forever. Pair that with `--delete-branch` and the local branch is
  also absent from the remote — which is the exact signature of work that exists
  only on this machine. A campaign whose work is fully landed then reports one
  false blocker per member repository. The discriminator is content, not
  ancestry: `git -C <repo> diff --stat <base>..<branch>` empty means the branch
  changes nothing the base does not already have, and it is safe however the
  ancestry reads. Check the paths the subtask actually touched too, since a
  branch cut before the base moved on will diff non-empty on files it never
  edited. Report such a row as landed, not as a blocker.
- **`set -- $var` does not word-split in zsh, and this skill is made of gates.**
  This machine's shell leaves unquoted parameters unsplit, so the common
  `for pair in a:1 b:2; do set -- $pair` idiom leaves `$2` empty. Here it failed
  loudly — `gh` answered `invalid issue format: ""` — but the same construct
  inside a check whose empty result reads as "nothing to report" passes the gate
  having tested nothing, and a silent pass is indistinguishable from a clean
  one. Split with a parameter expansion instead (`repo=${spec%%:*}`,
  `num=${spec##*:}`), and make any gate that can return empty say which of the
  two it means.
- **`diff` is shadowed in a Claude Code shell on this machine** by a zsh
  autoload stub with no file behind it, so a plain `diff` dies with
  `(eval):1: diff: function definition file not found`. That reads like a
  missing input file, not a shadowed name, and this step's whole purpose is a
  comparison — a gate that errors out is a gate that tested nothing. Write
  `command diff`. `cmp`, `sed`, `grep` and `cp` are unaffected.
- `git status --porcelain` never lists ignored files, so the obvious command for
  "nothing local is left" answers clean over a checkout holding a `.env`, a
  build directory, or a downloaded fixture — every one of which dies with the
  directory. Run both forms over any repository with a `.gitignore` and they
  disagree. Only `--ignored` is evidence, which is why step 2 uses
  `--ignored=matching`.
- The campaign directory is git-ignored, so nothing in it outside `repos/` is
  under version control at all. `runtime/` dies with the directory by design;
  say so rather than assuming the person knows.
- Closing the anchor issue is what closes the campaign. A deleted directory with
  an open issue is a campaign that still exists and has lost its cache.
- A second machine may hold the same campaign under a directory whose date
  differs. Deleting this one does not touch that one, and the person there sees
  the issue close underneath them.
- **On one machine, two sessions given the same slug on the same day build the
  same path**, so the directory this skill deletes may be another session's
  live workspace. Nothing in steps 0–4 catches that: the live-agent gate in step
  1 matches on an agent's `cwd`, and a campaign session's `cwd` is the container
  root. That is why step 5 announces on the issue and looks at open files before
  removing anything.
