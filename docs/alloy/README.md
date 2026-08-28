# Alloy check of the campaign lifecycle

Four models of `docs/design-campaign.md`, identical but for the
campaign-to-issue index. Run one with
`alloy exec -f -o /tmp/alloy-run -t text -c '*' docs/alloy/campaign-A.als`.

| # | assertion | A body line | B checklist | C label | D sub-issue |
|---|---|:-:|:-:|:-:|:-:|
| 1 | NoLostWork | pass | pass | pass | pass |
| 2a | NoFalseCompletion (tautology) | pass | pass | pass | pass |
| 2b | ClosedImpliesComplete | X | X | X | X |
| 2c | IdleImpliesComplete | X | X | X | X |
| 3a | IndexCoversMembers | pass | **X** | pass | pass |
| 3b | IndexExact | X | X | X | pass |
| 3c | IndexExactStableMembership | X | X | pass | pass |
| 4 | MachineIndependence | pass | pass | pass | pass |
| 5 | Reconstitution | X | X | X | pass |
| 6 | NoOrphan | **X** | **X** | **X** | **X** |
| 6b | NoOrphanIfGuarded | pass | pass | pass | pass |
| 7a | Termination | X | X | X | X |
| 7b | TerminationUnderFairness | X | X | X | X |
| 7c | TerminationDisciplined | pass | pass | pass | pass |

`X` is a counterexample. 2a cannot fail — `complete` is *defined* as
closed-and-merged — so 2b and 2c carry its content. Each pass was proved able to
fail by mutation: reopening the task in `agentDie` reddens 1, dropping the
back-reference write reddens 3a, letting `deleteDir` drop members reddens 4,
removing a guard clause reddens 6b and 7c.

## Counterexamples that matter

**6.** Two machines hold campaign #N; an agent is live on machine 0; the
operator on machine 1 deletes its tree. "No campaign closes while an agent is
live under its tree" is a local check blind to the other machine. Enforcing it,
plus refusing to drop a member an agent is working, makes 6b pass — nothing
enforces either today.

**7b.** A member closed without a merged PR never reads complete, so the
campaign never becomes closable: closed-and-merged cannot say "dropped".

**3b/5, A.** Any issue naming the anchor joins the same append-only timeline, so
a subtask moved out stays indexed forever and the anchor reconstitutes a growing
superset. **3a, B.** The checklist is a second write to another object; skipping
it loses the issue with nothing to contradict it — the only silent total loss.

## Recommendation

**Index with D, GitHub's native sub-issue link.** Only there does the index
equal membership in every reachable state, so only there is reconstitution
exact — and it is cheaper than A, since `gh issue create --parent <url>` links
in the same command (probed, gh 2.96.0). Keep the `Campaign:` line as prose;
stop reading the timeline as an index. Unverified: cross-repository sub-issues
for this owner. If unavailable, fall back to C, which differs only by a stale
label after removal.

Unmodelled: text well-formedness, `gh search` consistency, herdr's liveness
derivation, and issues in repositories the reader's token cannot see.
