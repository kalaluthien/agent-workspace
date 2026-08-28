# Alloy check of the campaign lifecycle

Three models of `spec/design-campaign.md`, `spec/agent-protocol.md` and the
rules in `AGENTS.md`. One question each.

| file | asks | commands | write-up |
| --- | --- | :-: | --- |
| `campaign-core.als` | can the design go wrong? | 15 checks, 2 runs | here |
| `campaign-e2e.als` | can a real campaign do this? | 25 runs | `e2e-scenarios.md` |
| `campaign-multi.als` | what breaks with several sessions? | 35 runs | `multi-session.md` |

```sh
alloy exec -f -o /tmp/alloy-core -t text -c '*' spec/alloy/campaign-core.als
```

The three share a signature-and-event skeleton — about a third of
`campaign-core` reappears in `campaign-e2e`. That is deliberate: each file is
read on its own, and the headers state what each kept, dropped and added from
the one before, so the two can be diffed.

## Verdicts

`X` is a counterexample; a check that passes reads UNSAT.

| # | assertion | | |
| --- | --- | :-: | --- |
| 1 | NoLostWork | pass | agent death and directory deletion never un-complete a subtask |
| 2a | NoFalseCompletion | pass | a tautology — `complete` is *defined* as closed-and-merged, so 2b and 2c carry its content |
| 2b | ClosedImpliesComplete | X | "the issue is closed" is not completion |
| 2c | IdleImpliesComplete | X | "the agent went idle" is not completion |
| 3a | IndexCoversMembers | pass | no member is missing from the index |
| 3b | IndexExact | pass | the index holds nothing but members |
| 3c | IndexExactStableMembership | pass | |
| 4 | MachineIndependence | pass | deleting a local directory changes no fact another machine reads |
| 5 | Reconstitution | pass | member repositories and open subtasks are recoverable from the anchor alone |
| 6 | NoOrphan | **X** | nothing enforces "no campaign closes while an agent is live under its tree" |
| 6b | NoOrphanIfGuarded | pass | it holds once that rule is enforced |
| 7a | Termination | X | nothing forces progress |
| 7b | TerminationUnderFairness | X | closed-and-merged cannot say "dropped" |
| 7c | TerminationDisciplined | pass | under a close-only-by-merge discipline |
| 7d | TerminationUnderSettlement | pass | under the settlement `AGENTS.md` adopted |

Every pass was proved able to fail by mutation, re-run 2026-08-28 against this
model: reopening the task in `agentDie` reddens 1; dropping `addMember`'s
sub-issue write reddens 3a and 5; letting `deleteDir` drop members reddens 4;
removing a guard clause reddens 6b and 7c; dropping `weakFairness` reddens 7d.

## Counterexamples that matter

**6.** Two machines hold campaign #N; an agent is live on machine 0; the
operator on machine 1 deletes its tree. "No campaign closes while an agent is
live under its tree" is a local check blind to the other machine. Enforcing it,
plus refusing to drop a member an agent is working, makes 6b pass — nothing
enforces either today.

**7b, and 7d's answer to it.** A member closed without a merged pull request
never reads complete, so the campaign never becomes closable: closed-and-merged
cannot say "dropped". `AGENTS.md` answers it by reading settlement both ways —
closed as completed, or closed as not planned — and 7d is that reading, checked.
Its control run `SettledWithoutMerge` is SAT, so settlement is strictly weaker
than completion here rather than a synonym for it.

## The three alternatives that lost

Four index schemes were modelled side by side before one was chosen; the losers
are deleted rather than kept as full models, since each was a ~90% copy of the
winner differing only in its index. What each was, and what killed it:

- **A — a `Campaign: <owner/repo>#N` line in the member issue body**, read back
  from the anchor's cross-reference timeline. The timeline is append-only and
  records any issue that names the anchor, so a subtask moved out stays indexed
  forever and the anchor reconstitutes a growing superset: 3b, 3c and 5 all red.
- **B — a checklist of member issues in the anchor body.** The index entry is a
  second write to a different object and may simply not happen, which loses the
  issue with nothing anywhere to contradict it. The only scheme where 3a was
  red, and the only silent total loss of the four.
- **C — a `campaign-<N>` label on every member issue.** Correct on totality and
  on staleness, but the label object must be created per repository before an
  issue there can carry it, and removing a subtask leaves the label behind as a
  stale mark: 3b red.

The `Campaign:` body line survives as prose for a human reading the raw issue.
Nothing queries it.

## Scenarios

`campaign-e2e.als` asks the opposite question of `campaign-core.als`: not "can
this go wrong?" but "can a real campaign do this?". Every command is a `run`, so
a SAT result is a witness trace — a script to follow — and an UNSAT is a finding
about the model. `e2e-scenarios.md` maps each one to the `gh`/`git`/protocol
steps that exercise it for real and the observable that decides pass or fail.

```sh
alloy exec -f -o /tmp/alloy-e2e -t text -c '*' spec/alloy/campaign-e2e.als
scripts/alloy-trace-digest /tmp/alloy-e2e/S1_HappyPath-solution-0.txt
```

Seventeen scenarios, twenty-five commands. All SAT but two.

`S13_ReopenAfterMerge` is UNSAT because an issue that ever had a pull request
can never return to `Open` — `addMember` guards on `no i.pr` and a PR link is
never undone — so the model cannot state "reopen a merged subtask for review
feedback", which GitHub permits. The gap is in the model, not the design.

`S16a_ContainerMemberUnderNarrowReading` is UNSAT because of the clause
described under "The widening" below.

Scenario 17 is the newest and states a rule that replaced one a live run
disproved: a clone cut while the container reads `0 0` is still stale by the
time the delegate starts, so the freshness check belongs inside the clone at
launch. `S17b` is the finding — the superseded rule, enforced for a whole trace,
does not prevent it.

## Several sessions

`campaign-multi.als` drops the assumption the other two share: that one campaign
session holds a campaign at a time. It makes `Session` a sig and asks what
breaks when several are live. Findings, witnesses and the recommendation are in
`multi-session.md`.

```sh
alloy exec -f -o /tmp/alloy-multi -t text -c '*' spec/alloy/campaign-multi.als
```

## The widening

`agent-workspace` gets cloned into `<campaign>/repos/agent-workspace/`, so the
container becomes a member of its own campaign. `WellFormed` said

```
all i: Issue | i.home = Container implies i in Campaign.anchor
```

which requires every container-homed issue to be *some campaign's anchor*. Read
precisely, that forbids an ordinary container subtask, while still permitting the
odd case of one campaign's anchor being another campaign's member — so a coarse
probe reads SAT and hides it. The probe that isolates the real claim is "a
container-homed member that is nobody's anchor", and on the original model it is
UNSAT. With a single campaign — the actual situation — the clause rules the case
out entirely. `addMember`'s `i.home != Container` was the same rule restated, and
it blocked the container joining mid-flight.

Both were widened on 2026-08-28: the clause to `Campaign.anchor +
Campaign.members`, and the redundant `addMember` guard dropped. Measured before
and after, at the model's own bounds:

| probe | before | after |
|---|:-:|:-:|
| a container-homed member that is nobody's anchor | UNSAT | **SAT** |
| a container-homed issue added mid-flight | UNSAT | **SAT** |

So the widened world is genuinely reachable, and "no verdict changed" is a real
result rather than a search that never got there. **All fifteen verdicts
measured then — the fourteen checks and the `Sanity` run — are identical before
and after**, and the greens were re-proved able to fail in the widened model.
7d was added later and has only ever been checked in the widened model.

`spec/design-campaign.md` is deliberately untouched.

## Unmodelled

Text well-formedness, `gh` latency and search-index consistency, herdr's
liveness derivation, issues in repositories the reader's token cannot see, the
delegation mechanics (`--append-system-prompt-file`, the canary, the 1024-byte
launch line), and whether a merged pull request does what was asked.
