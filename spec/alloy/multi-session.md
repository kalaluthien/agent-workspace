# Several campaign sessions at once

`campaign-multi.als` drops the one-session assumption the other models share:
`Session` is a sig and every event carries its actor. 34 commands, all run:

```sh
alloy exec -f -o /tmp/alloy-multi -t text -c '*' spec/alloy/campaign-multi.als
```

## What breaks

| run | | witness |
|---|:-:|---|
| `R1_LostBodyUpdate` | SAT | S1 files, adds R0 to its README; S0 adopts while the body is empty; S1 syncs (body `{R0}`); S0 syncs (body empty). R0 never returns. |
| `R1b_IndexOutlivesRepoList` | SAT | after that loss the index still names an open subtask homed in R0. |
| `R2_DuplicateCampaign` | SAT | Survey(S0), Survey(S1) — neither sees a covering campaign — FileAnchor(S1), FileAnchor(S0). Two anchors, one scope. |
| `R3_DeleteUnderWorkingSession` | SAT | same slug, same date, one directory. S1 deletes it while S0 holds the campaign with checkouts on disk and **no agent is live anywhere**. |
| `R3b_CloseFromAnotherMachine` | SAT | S0 closes the anchor from M0 while S1's delegate is live on M1; the local gate reads closable. |
| `R4_SameBranchTwice` | SAT | two subtasks in R0, two sessions, same `<topic>`: one branch, two delegates, one checkout. `R4d`: same subtask, even. |
| `R4c_CheckoutSwitchedUnderAgent` | SAT | S0's `acquire-repo` switches the shared checkout off S1's live delegate's branch. |
| `R5_RemoteStandDownLosesWork` | SAT | S0 on M0 stands an M1 agent down. The branch is on the remote, so S0's only check passes; work living only on M1 dies with the pane. |

Clean: `R4b` SAT — `c<N>` still separates campaigns; the collision is
intra-campaign only. `R5c` SAT — a non-launcher on the agent's own machine
retires it safely, so co-location is the axis, not ownership (`R5b` SAT:
on-the-remote without a clean tree is reachable).

**`## Repos` is not survivable; the sub-issue index is.** A body write cannot
touch a sub-issue link, which makes it worse: the index keeps naming work in a
repository the list has dropped, and step 5 deletes that list's last copy.

## Recommendation

**Compare-then-write on the anchor body.** Re-read it immediately before
`gh issue edit`; refuse if it moved since the README was derived from it.
`R1c` (`R1` plus `syncCAS`) is **UNSAT** at identical bounds, and `R1d` SAT
shows both sessions still sync — the green is not the scenario forbidden. Step
4 already reads the body back *after* writing, so this is free.

**It beats "write the body only at open and close."** `R1e` SAT: both sessions
reach close and the loss happens anyway, and meanwhile a repository added
mid-campaign sits in one README, invisible to the other session.

The same shape repairs finding 2: `R2b`, re-surveying at the moment of filing,
is UNSAT; `R2c` confirms filing still works. It narrows the window rather than
closing it — read and create are not atomic.

## Not expressed

- Settlement is "the issue is closed"; the merged-PR half stays campaign-D's.
- "Covers the request" is a static bit, not a judgement over Scope prose.
- No `gh` latency: each window measured is a minimum.
- Nothing repairs 3, 4 or 5 — each is a contract change, yours to write: a gate
  that sees a live *session*; `<topic>` chosen where both sessions read it;
  `STAND DOWN`'s pre-check named as local.
- `R3c` UNSAT restates the close rule, so `R3b` reads as that rule being
  unreadable, not failing.
