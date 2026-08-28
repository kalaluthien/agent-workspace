---
name: closing-campaign
description: Closes a campaign — refuses while an agent is live or local-only work exists, reports open subtasks, syncs the campaign README into the anchor issue, then closes the issue and deletes the directory. Use when a person says a campaign is finished, done, over, or wrapped up, or asks to close, retire, archive, or clean up a campaign or its directory. Not for closing a single subtask issue or retiring one repository agent; not for opening or scaffolding a campaign, which is opening-campaign.
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
- the anchor issue body is the campaign README.

## Procedure

The order is load-bearing: each gate is cheaper than the one after it, and step
5 is irreversible. Run 1–4 without asking. Run 5 only on explicit confirmation.

### 1. Refuse while an agent is live under the tree

Presence in `herdr agent list` is the signal, not `agent_status` — that reports
the screen and calls a mid-turn pause `idle`. An agent listed under the tree
blocks the close whatever its status says.

```sh
herdr agent list | jq -r --arg tree "$CAMPAIGN_DIR" \
  '.result.agents[] | select(.cwd | startswith($tree))
   | "\(.name // "unnamed")\t\(.agent_status)\t\(.cwd)"'
```

Any row: print the rows, say which agent holds the campaign, stop. The person
retires it; this skill never kills an agent.

No rows still leaves one case open — an agent that herdr has forgotten but
whose session is mid-turn. If the campaign's `runtime/handover/` names briefs
you cannot account for, say so before continuing.

### 2. Refuse while work exists only on this machine

Deleting the directory destroys these and nothing recovers them. Check every
checkout under `<campaign>/repos/`, one at a time — never one git command
across member repositories.

```sh
for R in "$CAMPAIGN_DIR"/repos/*/; do
  echo "== $R"
  git -C "$R" status --porcelain                       # uncommitted
  git -C "$R" log --branches --not --remotes --oneline # unpushed commits
  git -C "$R" worktree list                            # stray worktrees
  git -C "$R" stash list                               # stashed work
  git -C "$R" branch --no-merged "origin/$(git -C "$R" symbolic-ref --short refs/remotes/origin/HEAD | sed 's|origin/||')"
done
```

Enumerate everything found, repository by repository, and refuse until it is
pushed, merged, or the person says to discard it. A branch listed by
`--no-merged` that is pushed is not a blocker — it exists on the remote — so
say which of the two each finding is.

### 3. Report the open subtasks

Read the member repositories from the anchor issue's `## Repos` section, then
loop `gh issue list` over them with the campaign label.

```sh
gh issue view "$N" -R kalaluthien/agent-workspace --json body -q .body \
  | sed -n '/^## Repos/,$p' | grep -oE '[A-Za-z0-9._-]+/[A-Za-z0-9._-]+'
```

```sh
gh issue list -R "$REPO" --label "campaign-$N" --state open \
  --json number,title -q '.[] | "\(.number)\t\(.title)"'
```

An open subtask is not a blocker — a person may close a campaign over open work
— but show every one before they decide.

### 4. Sync the README into the anchor issue body

The README and the anchor body carry the same five sections, so this is a plain
overwrite with nothing to merge. The issue is what survives the directory, so
the README's last state has to land there before step 5.

```sh
gh issue edit "$N" -R kalaluthien/agent-workspace \
  --body-file "$CAMPAIGN_DIR/README.md"
```

### 5. Close the issue, then delete the directory

Only after the person confirms, in this order — the issue first, because a
failed close leaves the directory to retry from, while the reverse leaves
nothing.

```sh
gh issue close "$N" -R kalaluthien/agent-workspace \
  --comment "Campaign closed. Directory $CAMPAIGN_DIR deleted."
```

Before removing anything, list the directory and confirm it holds only the
campaign. Remove the named campaign directory itself, never its parent, never a
sibling, never a path built by expanding a wildcard.

## Gotchas

- `agent_status: idle` is a screen reading. A mid-turn pause looks identical to
  a finished agent, so presence in the list is the gate, never the status word.
- `git status` is clean in a checkout whose commits were never pushed, and a
  pushed branch can still hold uncommitted files. Every check in step 2 finds
  something the others miss; running a subset is worse than useless because it
  reads as an all-clear.
- Untracked files that were never added — a scratch script, a downloaded
  dump — show in `git status --porcelain` as `??` and are the easiest local-only
  work to skim past.
- The campaign directory is git-ignored, so nothing in it outside `repos/`
  is under version control at all. `runtime/` dies with the directory by design;
  say so rather than assuming the person knows.
- The sync is an overwrite, so a README that has lost its `## Repos` section
  takes the campaign's repository index down with it, without an error. That
  index is the one thing a campaign has to maintain, and nothing else holds a
  copy.
- Closing the anchor issue is what closes the campaign. A deleted directory
  with an open issue is a campaign that still exists and has lost its cache.
- A second machine may hold the same campaign under a directory whose date
  differs. Deleting this one does not touch that one, and the person there sees
  the issue close underneath them.
