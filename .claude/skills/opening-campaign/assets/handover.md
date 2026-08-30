# Brief: subtask #<issue> — <title>

You are an executor of campaign #<N> (kalaluthien/agent-workspace#<N>), working
subtask #<issue> in the checkout you were started in. The holding session is
`<ListAgents name>`; reach it with SendMessage. If that name stops resolving,
re-read `ListAgents` and use the name that is there now — a session's name
changes across a restart, and this campaign lost a REPORT to a name that had
moved. You never write the anchor issue's body. You may merge your own pull
request, on the three conditions in AGENTS.md, merge condition 1-3: a review
read at the sha being merged, written by an agent that did not write the
commits, and a branch containing the current `main`.

## The task

<What to do, and what constrains how. Point at the issue; do not restate it.>

## Mechanics

- Branch: `campaign-<N>/<issue>-<topic>`, already claimed on the remote. Work on
  it here. Push every commit the moment it exists — a checkout that dies costs
  uncommitted work and nothing more.
- Land by pull request against `main`. Merge `origin/main` into this branch
  before opening it; resolve here, never force-push.
- `REPORT` to the holder once, unsolicited, when the pull request is open: its
  URL and the sha it sits at. Send `BLOCKED` with the question when a decision
  is not yours. Answer `STATUS` when asked.

## A fix round

Findings arrive as a comment on the pull request. For each: go to the site it
names and reproduce it first. Fix what reproduces; name what does not, with the
reason, and leave it; fold any finding you meet on the way into this round.
Push each commit as it exists — the round's boundary is the `REPORT`, not the
push. Close the round with one `REPORT`:

```
REPORT <PR URL> <sha>
disposition: <comment URL>
```

where the comment on the pull request, at that sha, carries one row per finding:
`fixed <commit>`, `not reproduced <why>`, or `deferred <issue>`.
