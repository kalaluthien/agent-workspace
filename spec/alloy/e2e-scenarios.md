# Running the e2e scenarios for real

`campaign-e2e.als` says each scenario is *possible*. This file says how to make
one *happen*, and what to look at to decide it passed. Hand a row to a campaign
session and it should need to invent nothing.

Every scenario is judged by one observable, and it is always GitHub:

```sh
scripts/campaign-settlement <anchor-number> [owner/repo]   # default repo: kalaluthien/agent-workspace
```

It prints one line per subtask — `complete`, `dropped`, or `open` — then whether
the campaign is closable. Nothing on a terminal screen counts, which is the rule
these scenarios exist to exercise.

## Fixture

The anchor goes in the real container repository, because the campaign ID *is* a
container issue number and a drill with a fake ID exercises nothing. The member
repositories are throwaway, because most scenarios end in a merged pull request
or a deliberately mangled close.

```sh
gh repo create <you>/e2e-fixture-a --private --add-readme
gh repo create <you>/e2e-fixture-b --private --add-readme
TITLE="Drill: e2e scenarios"
gh issue create -R kalaluthien/agent-workspace --title "$TITLE" \
  --body "Drill anchor. Close when done."
ANCHOR=$(gh issue list -R kalaluthien/agent-workspace \
  --search "$TITLE in:title" --limit 1 --json number --jq '.[0].number')
```

Every subtask is created as a sub-issue in one command — the whole index:

```sh
gh issue create -R <you>/e2e-fixture-a --parent https://github.com/kalaluthien/agent-workspace/issues/$ANCHOR \
  --title "..." --body "Campaign: kalaluthien/agent-workspace#$ANCHOR"
```

Tear down with `gh issue close $ANCHOR -R kalaluthien/agent-workspace` and
`gh repo delete <you>/e2e-fixture-{a,b}`.

## Where each one can run

| where | meaning |
| --- | --- |
| **real** | safe against repositories you care about; it writes nothing you would not write anyway |
| **fixture** | needs the throwaway repositories above; it merges, mangles a close, or destroys a workspace |
| **blocked** | cannot be run as written — see the row |

| # | scenario | where | pass observable |
| --- | --- | :-: | --- |
| 1 | two repos, two subtasks, both merged | fixture | both rows `complete`; `closable` |
| 2 | one subtask dropped as not planned | fixture | one `complete`, one `dropped`; `closable` |
| 3 | delegate dies after pushing | real | row goes `complete` with the agent already gone |
| 4 | delegate reports done, nothing pushed | real | row stays `open`; `NOT closable` |
| 5 | follow-up subtask after the rest settled | real | settled count drops back below total |
| 6 | a repository joins mid-flight | real | a new `owner/repo#n` appears in the listing |
| 7 | two machines, one deletes its tree | real | listing byte-identical before and after |
| 8 | anchor closed with a subtask open | fixture | the `REPORT:` line fires |
| 9 | tree deleted under a live agent | fixture | unpushed commits are gone and unrecoverable |
| 10 | subtask moved out of the campaign | real | the row disappears from the listing |
| 11 | PR merged, issue left open | fixture | row stays `open` though the PR is merged |
| 12 | two campaigns, one repository | real | two anchors, disjoint listings, no branch clash |
| 13 | reopen a merged subtask | blocked | model says impossible; GitHub does not — see below |
| 14 | follow-up after the anchor closed | fixture | a closed anchor gains an `open` subtask |
| 15 | run the whole campaign with no local directory | real | listing reaches `closable` from a machine that never cloned |
| 16 | the container is a member of its own campaign | real | container checkout is `0 0` against `origin/main` at every checkpoint |
| 17 | a clone current when cut, stale when the delegate starts | real | the clone reads `0 0` against `origin/main` in the same shell that launches |

## The steps

**1 — plain path.** Create two subtasks, one per fixture repo. In each: branch
`c$ANCHOR/<topic>`, one commit, `git push -u origin`, `gh pr create --body "Closes #<n>"`,
`gh pr merge --squash --delete-branch`. Then `scripts/campaign-settlement $ANCHOR`.
Both rows must read `complete`. Close the anchor only after that line says
`closable` — that ordering *is* the design's close rule.

**2 — dropped subtask.** Same as 1 for the first subtask. For the second, open no
pull request at all and run `gh issue close <n> -R <repo> --reason "not planned"`.
The listing must read `dropped`, and `closable` must still be reached. This is
the one the model's assertion 7b says closed-and-merged alone cannot express.

**3 — delegate dies after pushing.** Launch a delegate on a subtask. Wait until
it has pushed and opened a pull request (`gh pr list -R <repo> --head c$ANCHOR/<topic>`
returns a row). Kill the pane — `herdr agent list` to find it, then kill the
process. Merge the pull request yourself. The row must go `complete` with no
agent alive anywhere. Safe on real repositories: the branch is already pushed,
so nothing local is lost.

**4 — report without a push.** Launch a delegate; when it sends `REPORT`, do not
believe it. Run `scripts/campaign-settlement $ANCHOR` first. If the row is
`open`, the claim was not evidence and the scenario passed. Then confirm the
absence directly, which is the form the protocol requires:

```sh
git -C <campaign>/repos/<repo> status --porcelain          # must be empty
git -C <campaign>/repos/<repo> log --branches --not --remotes --oneline   # must be empty
```

Only after both are empty may `STAND DOWN` be sent. A run where the campaign
session closed the subtask on the strength of the message is a failure, however
the work turned out.

**5 — follow-up after settled.** Take a campaign whose listing reads `closable`
and do *not* close the anchor. Create one more sub-issue with `--parent`. Re-run
the script: the settled count must fall below the total. Pass means the campaign
went back to work instead of closing.

**6 — repository joins mid-flight.** As 5, but file the new subtask in a
repository no existing subtask lives in, and clone it into
`<campaign>/repos/<repo>/`. Pass: the listing shows a second `owner/repo` prefix
and the anchor's `## Repos` section is updated to match. The listing is the
index; the `Repos` section is only the clone list, so a mismatch between them is
the defect to look for.

**7 — two machines, one deletes.** Hold the campaign on two machines. Capture
`scripts/campaign-settlement $ANCHOR > /tmp/before`. Delete the campaign
directory on the machine with no live agent. Re-run into `/tmp/after` and `diff`
them: identical is the pass. Continue the other machine's work to completion.
With one machine, two campaign directories for the same anchor stand in and test
everything the model distinguishes — the model's `Machine` is only "a holder of
a local directory". What that stand-in does *not* cover is herdr liveness across
machines, which is exactly the blind spot scenario 9 is about.

**8 — anchor closed with a subtask open.** Settle one subtask, leave the other
open, then `gh issue close $ANCHOR -R kalaluthien/agent-workspace`. Pass: the
script prints `REPORT: the anchor is closed with subtasks still open`. Nothing
prevents this close — the point of the scenario is that the report exists, not
that the close is blocked. Fixture only: an anchor closed over live work is a
mess to explain on a real campaign.

**9 — tree deleted under a live agent.** Launch a delegate, let it commit but
*not* push, then delete `<campaign>/` from a second session. Pass is a
demonstration of loss: the commits are unrecoverable and GitHub never knew about
them. This is `campaign-core`'s assertion-6 counterexample made real, and it is
why `STATUS` question 3 exists. Fixture only, and never with a real delegate's
work in the tree.

**10 — subtask moved out.** `gh issue edit <n> -R <repo> --remove-parent`. Pass:
the row disappears from `scripts/campaign-settlement` immediately, and the issue
itself is untouched. That prunability is the whole reason the sub-issue link beat
a back-reference line, which can never un-say a mention.

**11 — merged but left open.** Open a pull request whose body omits `Closes #<n>`,
merge it, and leave the issue open. Pass: the row reads `open` while
`gh pr view <p> --json state` reads `MERGED`. The failure this drills is silent —
the campaign simply never becomes closable, with nothing anywhere saying why.

**12 — two campaigns, one repository.** Open two anchors, each with one subtask
in the same fixture repository, on branches `c<N1>/…` and `c<N2>/…`. Merge both.
Pass: each anchor's listing shows only its own subtask, and the two branches
never collided on the remote. Real-safe, and the reason the branch naming rule
carries the campaign number.

**13 — reopen a merged subtask. Blocked, and the block is the finding.**
`campaign-e2e.als` reports `S13_ReopenAfterMerge` UNSAT: once a subtask has a
pull request, the model can never return it to `Open`. The controls pin the
cause — `S13b` (reopen a closed issue at all) is SAT, `S13c` (reopen an issue
that has a pull request) is UNSAT — so it is `addMember`'s `no i.pr` guard plus
`WellFormed`'s "a PR link is never undone", not the bound. GitHub has no such
restriction that this machine's `gh` documents: `gh issue reopen <n>` takes only
an optional comment and names no condition about a closing pull request
(`gh issue reopen --help`, gh 2.96.0). **Not verified by a write** — the one-line probe is
`gh issue reopen <n> -R <fixture-repo>` on an issue closed by a merged pull
request, and it needs a fixture repository and permission to write. Until it is
run, treat "GitHub permits it" as a hypothesis. If it holds, the model — not the
design — is what needs the reopen event, and `spec/design-campaign.md`'s
"review feedback gets a fresh session" is the design's answer to a case the
model cannot state.

**14 — follow-up after the close.** Close the anchor legitimately (listing reads
`closable`), then create a new sub-issue with `--parent` pointing at the closed
anchor. Pass: the command succeeds and the listing shows a closed anchor with an
`open` subtask. Nothing in the design guards against this, so it is worth knowing
it is reachable before a real campaign does it by accident.

**15 — no local directory.** Drive an entire two-subtask campaign from a machine
that never clones anything: create the subtasks, and have a delegate on another
machine (or the repository's own web editor) push the branches. Pass: the
listing reaches `closable` read from the machine with no directory. This
exercises the reconstitution claim rather than asserting it — the campaign
plane really does live in GitHub.

**16 — the container as a member of its own campaign.** `agent-workspace` is
cloned into `<campaign>/repos/agent-workspace/`, so one repository has two
checkouts: the **outer** container the campaign session runs from, and the
**inner** clone the delegate works in, which the container git-ignores. The
model had to be widened to admit this at all — see the finding below.

One command reads both hazards at once, and it belongs at three checkpoints:
before launching the delegate, immediately after merging its pull request, and
before the campaign session next edits anything in the container.

```sh
CONTAINER=$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd -P)
git -C "$CONTAINER" fetch origin -q
git -C "$CONTAINER" rev-list --left-right --count origin/main...HEAD   # "<behind>\t<ahead>"
```

- **`behind > 0` is hazard 1.** The delegate's pull request merged and the outer
  checkout has not caught up. Editing from here can silently revert the merged
  work, and nothing in `AGENTS.md` currently says to pull. Fix with
  `git -C "$CONTAINER" pull --ff-only` and re-read `0` before editing.
- **`ahead > 0` *before the clone* was written as hazard 2, and it is the
  wrong invariant.** A live run disproved it: the container read `0\t0`
  immediately before the clone, and three commits landed on `origin/main`
  between the clone and the launch. Pushing before cloning is still worth doing
  and is no longer sufficient; the check that matters is inside the clone at
  launch, and it is scenario 17.
- **Hazard 3 is safe, but do not read the model as proof.** Edits to
  `.claude/skills/` inside the clone cannot change the running campaign, because
  the loaded copy is the outer container's. The model agrees — but only because
  no event was written that writes the outer checkout from inside the clone, so
  it restates the assumption rather than testing it. The real check is one
  command: after editing a skill in the clone, confirm
  `git -C "$CONTAINER" status --porcelain .claude/` is still empty.

Pass for the whole scenario: `0\t0` at all three checkpoints, and the delegate's
subtask reads `complete` in `scripts/campaign-settlement`. Real-safe — every
step is a fetch, a compare, or an ordinary pull.

**The finding.** `S16a_ContainerMemberUnderNarrowReading` is UNSAT. `campaign-core`'s
`WellFormed` said `i.home = Container implies i in Campaign.anchor` — every
container-homed issue must be *some campaign's anchor*. Read precisely that
forbids an ordinary container subtask, and with a single campaign, which is the
real situation, it rules the case out entirely; `addMember`'s
`i.home != Container` restated the same rule and blocked joining mid-flight.
Both were widened here and, on 2026-08-28, in `campaign-core.als` itself, where all
fifteen verdicts came back identical. `spec/alloy/README.md` carries the
before/after probes that show the new states are genuinely reachable rather than
merely unvisited. `spec/design-campaign.md` is untouched.

**17 — current when cut, stale when launched.** The clone is cut from
`origin/main`, then `origin/main` moves, then the delegate starts. Nothing
reports it, and the delegate obeys an `AGENTS.md` this campaign session has
already superseded. Run it deliberately: clone `agent-workspace` into
`<campaign>/repos/`, merge any container pull request, then read the clone.

```sh
git -C <campaign>/repos/<repo> fetch origin -q
git -C <campaign>/repos/<repo> rev-list --left-right --count origin/main...HEAD
```

Pass: the pair reads `0\t0` in the same shell that then launches the delegate,
after a `git -C <campaign>/repos/<repo> pull --ff-only` if it did not.
Real-safe — a fetch, a compare and an ordinary pull.

`S17a_CloneBehindAtLaunch` is SAT, so the stale launch is reachable.
`S17b_OldCloneRuleInsufficient` is the finding: the same trace with the
superseded rule — never clone while the container is ahead — enforced for its
whole length is **still SAT**. The rule is not wrong, it is read in the wrong
place. `S17c_PullBeforeLaunchAdmitsLaunch` is SAT and is the control: checking
inside the clone at launch still admits a container pull request merging
mid-campaign and a delegate starting afterwards, so the repair is not green by
forbidding the scenario. The repair itself is not run as a check — a guard on
"behind at launch" that then finds no behind launch restates the guard.

## What the scenarios do not cover

- **Liveness.** Every observable here is a GitHub fact by design. Whether a
  delegate is thinking, stuck, or gone is a herdr question and no row decides
  it; scenarios 3, 4, 7 and 9 only check that the GitHub answer is unaffected
  by whatever the delegate is doing.
- **Adequacy.** A merged pull request that does not do what was asked reads
  `complete` in every row above. Verifying that the work exists is not
  reviewing it.
