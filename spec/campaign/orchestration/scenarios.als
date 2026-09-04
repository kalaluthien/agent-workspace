/*
 * The disciplines a shutdown, a claim, a delete and a merge might follow, and
 * the witnesses that measure each. github/system.als is spec/'s entry point.
 */
module orchestration/scenarios

open orchestration/system

/* ---------------- the property ---------------- */

/* The one thing the protocol is for. */
pred noWorkDestroyed {
  always (Now.event = Retire implies Target.agent not in LocalOnly)
}

/* ---------------- disciplines: the shutdown, three ways ---------------- */

/* The agent's own account as the basis for destroying its workspace. */
pred oneStepShutdown {
  always (Now.event in StandDown + Retire implies Target.agent in Reported)
}

/* Both conjuncts are load-bearing: the answer names work only the agent
   can see, the confirmation is the session looking for itself. */
pred twoStepShutdown {
  always (Now.event in StandDown + Retire implies
            (Target.agent in Answered and Target.agent in Confirmed))
}

/* Narrowing this to `StandDown + Retire` reddens TwoStepCoLocatedSuffices: a
   remote session can then run the confirmation a local one acts on. */
pred coLocatedShutdown {
  always (Now.event in Confirm + ConfirmElsewhere + StandDown + Retire
            implies coLocated[Who.session, Target.agent])
}

/* Rule 3: an agent that is gone may be stood down on the confirmation
   alone, and only on it. */
pred resolveSilenceExternally {
  always (Now.event in StandDown + Retire implies
            (Target.agent in Confirmed
             and (Target.agent in Answered or Target.agent not in Live)))
}

/* The rule it replaces: wait for the answer. */
pred waitForAnswer {
  always (Now.event in StandDown + Retire implies Target.agent in Answered)
}

/* What only a session on the agent's own machine can check. */
pred localCheckedShutdown { always (Now.event = StandDown implies Target.agent not in LocalOnly) }

/* THE FRESH CLAIM, and the hole `agentRelease` leaves. Its two guards are both
   over AGENTS -- nothing on this issue is pushed, and nothing of it is live
   here -- so a claim cut before any agent exists satisfies both VACUOUSLY and
   is releasable by anyone. That is not a modelling artefact: a claim is cut
   before the delegate that will work it is launched, so every claim passes
   through exactly this state, and on GitHub it is indistinguishable from
   finished work -- both are a branch level with main.

   The discipline: release only what some agent has actually been launched on,
   or what is complete. NOT MODELLED is the escape the script keeps for the
   case a person has established the holder is gone (`--confirmed-absent`),
   because no atom here carries a person's word; R7c is the ordinary release
   that must stay reachable without it.

   R7c IS WIDER THAN THE SCRIPT, and #187 owns the gap. `Launched` is a fact
   about an agent, and the script has no reader for it: on GitHub R7c's state
   -- launched, dead, nothing pushed -- is a ref 0 ahead of the base whose
   branch was never a merged pull request's head, which is the one shape
   `cmd_release` refuses without `--confirmed-absent WHO`. And that is the SECOND
   refusal that state hits, not the first: `launch` checks the branch out and
   neither `agentDie` nor `retire` undoes it, so the dead delegate's clone still
   holds the branch and the occupant check refuses before the merge question is
   ever asked -- a refusal `--confirmed-absent` does not lift, since removing a
   worktree is not something a person's word stands in for. So the model's
   "ordinary release" is, at this sha, a worktree removal and then a release
   that asks a person. What
   would close the gap is a durable fact saying a holder was launched at all,
   which is what #187 is deciding. */
pred releaseNeedsAWorker {
  always (Now.event = Release implies
            (complete[Now.issue]
             or some a: Agent | a.task = Now.issue and a in Launched))
}

/* R4g drops `claimAtomic` alone and the collision returns, so the server-side
   half -- not the ritual -- is load-bearing. `claimAtomic` is keyed on the
   ISSUE, and create-ref is keyed on the ref NAME, which carries a topic this
   model does not have; github/system.als's `claim` says what closes the
   difference. */
pred claimBeforeLaunch { always (Now.event = Launch implies Now.issue in Who.session.claimedIssues) }
pred claimAtomic       { always (Now.event = Claim  implies Now.issue not in Claimed) }

/* The gate on LAUNCH covers the agent a session starts and says nothing
   about the agent a session IS: `work` carries no `Who.session`, so a session
   working its own claim reaches the same sub-issue along an edge
   `claimBeforeLaunch` never touches. R4h is that hole and R4i is its repair --
   scripts/check-campaign-claim.py, a PreToolUse guard refusing a changing call
   from a session holding no claim. Keyed on `a.peer` because a delegate has no
   session to hold one; its launcher was gated already.

   `Work` is what the gate is on, and what makes a call `Work` is its TARGET,
   not where the session sits: a change landing outside every base tree
   and every campaign directory is not work on a sub-issue and is no step of
   this relation. The guard reads the target over two bounded languages and
   no other: a file tool's path, and a `gh` command, which is one program with
   a stable grammar -- a write to the campaign plane through it has no
   filesystem target at all and is always `Work`, and a `gh` call the guard
   READS AS A CALL and cannot parse is refused, never guessed. The narrower
   verb is deliberate and was bought twice: a `gh` write can always be hidden
   from a bounded reader by a shell that is not read -- a here-string, a pipe
   into a shell, an interpreter's `-c`, a script file, all of them unread and
   listed here so the boundary has one statement -- so a sentence
   promising that no `gh` write escapes is a sentence the code cannot make
   true, and it produced a CONTRADICTS on every audit that checked it. What
   the guard does promise: a `gh` TOKEN it can see and cannot resolve to a
   call is refused rather than guessed at. A shell command is NOT read for a
   target: an arbitrary shell string is an unbounded language, and every
   reader of it was one more alternation for the next bypass. Such a call is
   allowed at the moment it is made, printing that it was unread, and its
   write is `Work` at the moment it LANDS -- `claimBeforeCommit` below, the
   pre-commit gate. R4k states the gap that leaves open until the commit. No
   atom here carries a path, so the reading itself is the script's and is
   stated in its docstring; the model says only that a write on nothing this
   campaign owns is outside `Work`. */
pred claimBeforeWork {
  always (Now.event = Work and some Target.agent.peer
            implies Now.issue in Target.agent.peer.claimedIssues)
}

/* The commit half of the same gate: scripts/check-commit-claim.py, a
   pre-commit hook refusing a commit on a base tree or under a campaign
   directory whose branch is not a claim. Keyed on `a.peer` for the same
   reason as `claimBeforeWork`: a delegate's launch was gated already. */
pred claimBeforeCommit {
  always (Now.event = CommitLocal and some Target.agent.peer
            implies Now.issue in Target.agent.peer.claimedIssues)
}

/* The rule as written, and the honest local reading a session can perform.
   There is no third: the close reads `herdr agent list`, which sees every
   live session on this machine, so what it can read and what it can attribute
   are now the same set. */
pred closeDisciplineFull[c: Campaign] {
  always ((Now.event = CloseIssue and Now.issue = c.campaignIssue) implies closableWithAgents[c])
}
pred closeDisciplineLocal[c: Campaign] {
  always ((Now.event = CloseIssue and Now.issue = c.campaignIssue) implies closableLocally[Who.session, c])
}

/* Where session/scenarios.als's R3 is answered: keyed on LIVENESS, which is
   what `herdr agent list` hands a deleting session directly. It used to be
   keyed on a record that died with the very tree it was about to delete. */
pred noDeleteUnderLiveAgent {
  always (Now.event = DeleteDir implies
            no a: Agent | a in Live and a.host = Where.machine
                          and campaignOf[a.task] in (OnDisk - OnDisk').campaign)
}

/* Empty for a sub-issue a session did with its own hands, which is what makes
   `mergedOnCurrentReview`'s second conjunct vacuous there -- see A18/A18b. A
   planner atom on the issue is in it: `confirm` needs only `a not in
   LocalOnly`, which a planner always satisfies, so the discipline is reachable
   unweakened and keeps its co-location conjunct over the planner too. */
fun agentsOf[i: Issue]: set Agent { task.i }

/* A MERGE REQUIRES A CURRENT REVIEW, and the author may then merge as anyone
   else may: an identity rule would make the one-session landing unreachable
   and call it safety. CURRENT is encoded as `Reviewed` cleared by `push`,
   which pins the revision THE REVIEW WAS READ AT rather than the merged
   commit, so a squash merge of a reviewed head stays reviewed. The second
   conjunct is UNIVERSAL, not existential, and vacuous with no Agent. */
pred mergedOnCurrentReview {
  always (Now.event = MergePullRequest implies
            (Now.issue.pullRequest in Reviewed
             and (all a: agentsOf[Now.issue] |
                    a in Confirmed and coLocated[Who.session, a])))
}

/* ---------------- witnesses ---------------- */

/* SAT means the disciplines forbid a counterexample rather than the protocol. */
pred Sanity {
  coLocatedShutdown and twoStepShutdown
  and eventually (some a: Agent | a in Retired)
  and eventually Now.event = Work
  and eventually Now.event = Push
}

/* The claim leaves the local fact and the GitHub fact exactly as they were. A
   signal weaker than an explicit REPORT says even less. */
pred ReportIsNotEvidence {
  some a: Agent | eventually (Now.event = Report and Target.agent = a
    and a in LocalOnly and a in LocalOnly'
    and not complete[a.task] and after always not complete[a.task])
}

pred BlockedAgentDoesNotProceed {
  some a: Agent | eventually (a in Waiting and always (a in Waiting and Now.event != Work))
}

/* THE FAILURE RULE 3 FORBIDS: under wait-for-the-answer there is no such
   trace, so the session waits for a reply that cannot come. */
pred SilentAgentIsRetirableUnderWait {
  waitForAnswer
  and (some a: Agent |
         eventually (a in Asked and a not in Live and a in Retired)
         and always a not in Answered)
}

/* The repair is a repair and not a prohibition. */
pred SilentAgentStillRetired {
  resolveSilenceExternally and coLocatedShutdown
  and (some a: Agent | eventually a in Retired and always a not in Answered)
}

/* Completion is a GitHub fact, so it survives the death and never undoes. */
pred S3_DelegateDiesAfterPushing {
  one c: Campaign | one a: Agent {
    a.task in c.memberIssues
    always Now.event not in AddMember + RemoveMember
    mergeClosed[c.memberIssues]
    eventually (Now.event = OpenPullRequest and Now.issue = a.task)
    eventually (Now.event = AgentDie and some a.task.pullRequest and a.task.pullRequest not in Merged)
    eventually complete[a.task]
    always (complete[a.task] implies always complete[a.task])
  }
}

/* The claim never becomes a GitHub fact on its own. */
pred S4_ReportWithoutPush {
  one c: Campaign | one a: Agent {
    a.task in c.memberIssues
    always Now.event not in AddMember + RemoveMember
    eventually (Now.event = Report and Now.issue = a.task)
    eventually (a in Reported and no a.task.pullRequest and a.task in Open)
    eventually always (not complete[a.task])
    always not closable[c]
  }
}

/* Live with nothing pushed is the only state where local-only work is
   actually destroyed. */
pred S9_OrphanedByLocalDelete {
  one c: Campaign | one a: Agent {
    a.task in c.memberIssues
    eventually (Now.event = DeleteDir and Where.machine = a.host and a in Live
                and a in LocalOnly and no a.task.pullRequest)
    eventually (a in Live and a.host not in machinesHolding[c])
  }
}

/* =================== a close during another session's work =================== */

/* R3b. The local gate reads closable; the campaign is not. */
pred R3b_CloseFromAnotherMachine {
  some c: Campaign, disj s1, s2: Session, a: Agent {
    s1.machine != s2.machine
    a.launcher = s1
    closeDisciplineLocal[c]
    eventually (Now.event = CloseIssue and Who.session = s2 and Now.issue = c.campaignIssue
                and a in Live and not closableWithAgents[c])
  }
}

/* R3c. The global rule, if it could be read, blocks it. The RemoveMember
   scope is a finding, not a convenience: `liveUnder` reads membership OR
   co-location, so moving the sub-issue out and deleting the tree turns the rule
   permissive while the agent still runs, and nothing guards that. */
pred R3c_GlobalCloseRuleBlocks {
  some c: Campaign, disj s1, s2: Session, a: Agent {
    s1.machine != s2.machine
    a.launcher = s1
    always Now.event != RemoveMember
    closeDisciplineFull[c]
    eventually (Now.event = CloseIssue and Now.issue = c.campaignIssue and Who.session = s2 and a in Live)
  }
}

/* =================== two sessions, one repository =================== */

/* R4c. Pinned to one step, so the switch is attributable to s2 and not to an
   earlier acquire by the launching session itself. */
pred R4c_CheckoutSwitchedUnderAgent {
  some c: Campaign, disj s1, s2: Session, a: Agent, r: Repo {
    r != Base
    s1.machine = s2.machine
    a.launcher = s1 and a.host = s1.machine and a.task.repo = r
    eventually (Now.event = Acquire and Who.session = s2 and Where.repo = r
                and a in Live and a not in PushedToRemote
                and campaignDirAt[c, a.host].checkedOut[r] = a.branch
                and after (campaignDirAt[c, a.host].checkedOut[r] != a.branch))
  }
}

/* R4e. The issue number separates two sub-issues and there is only ever one of
   it per sub-issue, so two sessions on the SAME sub-issue still share a branch. */
pred R4e_NumberedBranchStillShared {
  some disj a1, a2: Agent {
    a1.launcher != a2.launcher
    eventually (a1 in Live and a2 in Live
                and some campaignOf[a1.task] and sameBranch[a1, a2])
  }
}

/* R4f. The second session's claim fails before a second agent exists. */
pred R4f_ClaimClosesSameSubIssue {
  claimBeforeLaunch and claimAtomic
  R4e_NumberedBranchStillShared
}

/* R4g. CONTROL: the ritual without the refusal. */
pred R4g_ClaimWithoutAtomicityStillShared {
  claimBeforeLaunch
  some disj s1, s2: Session, i: Issue |
    eventually (i in s1.claimedIssues and i in s2.claimedIssues)
  R4e_NumberedBranchStillShared
}

/* R4h. THE HOLE, and the one this campaign actually fell into: a session works
   its own sub-issue and no claim of it ever exists, so every peer reading the
   records sees an open sub-issue indistinguishable from one nobody started. */
pred R4h_OwnHandsWorkWithoutClaim {
  some s: Session, a: Agent {
    a.peer = s
    eventually (Now.event = Work and Target.agent = a)
    always a.task not in s.claimedIssues
  }
}

/* R4i. The guard closes it. */
pred R4i_GuardClosesOwnHandsGap {
  claimBeforeWork
  R4h_OwnHandsWorkWithoutClaim
}

/* R4j. CONTROL for R4i: UNSAT there would mean the guard forbids the session
   from working at all rather than from working unclaimed. */
pred R4j_GuardAdmitsClaimedWork {
  claimBeforeWork
  some s: Session, a: Agent {
    a.peer = s
    eventually (Now.event = Claim and Who.session = s and Now.issue = a.task
                and eventually (Now.event = Work and Target.agent = a))
  }
}

/* R4k. THE HOLE THE PRE-TOOL-USE HALF LEAVES OPEN, stated rather than hidden:
   under `claimBeforeWork` alone a session with no claim still reaches a
   commit, because a shell write is not read as `Work` at the moment it is
   made. Reachable on purpose -- this is the accepted cost of reading only
   bounded languages. */
pred R4k_UnclaimedShellWriteThenCommit {
  claimBeforeWork
  some s: Session, a: Agent {
    a.peer = s
    eventually (Now.event = CommitLocal and Target.agent = a)
    always a.task not in s.claimedIssues
  }
}

/* R4l. The commit gate closes it. */
pred R4l_CommitGateClosesIt {
  claimBeforeCommit
  R4k_UnclaimedShellWriteThenCommit
}

/* R4m. CONTROL for R4l: UNSAT there would mean the gate forbids committing at
   all rather than committing unclaimed. */
pred R4m_GateAdmitsClaimedCommit {
  claimBeforeCommit
  some s: Session, a: Agent {
    a.peer = s
    eventually (Now.event = Claim and Who.session = s and Now.issue = a.task
                and eventually (Now.event = CommitLocal and Target.agent = a))
  }
}

/* =================== retiring another session's delegate =================== */

/* R5b. The gap TwoStepShutdownSuffices rests on is reachable at all. */
pred R5b_PushedButStillLocalOnly { some a: Agent | eventually (a in PushedToRemote and a in LocalOnly) }

/* R5c. Ownership is not the axis; co-location is. */
pred R5c_NonLauncherSameMachineIsFine {
  localCheckedShutdown
  some disj s1, s2: Session, a: Agent {
    a.launcher = s1 and a.host = s1.machine and s2.machine = a.host
    eventually (Now.event = StandDown and Who.session = s2 and Target.agent = a)
  }
}

/* R6. A live agent on another machine that has not pushed loses its claim
   under a rule correctly followed. */
pred R6_ReleaseUnderRemoteAgent {
  some s: Session, a: Agent {
    a.host != s.machine
    eventually (a in Live and a not in PushedToRemote
                and Now.event = Release and Who.session = s and Now.issue = a.task)
  }
}

/* R6b. A dangling claim does not outlive its usefulness. */
pred R6b_ReclaimAfterDeath {
  some disj s1, s2: Session, a: Agent {
    a.launcher = s1
    eventually (a in Launched and a not in Live and a not in PushedToRemote
                and eventually (Now.event = Release
                and eventually (Now.event = Claim and Who.session = s2 and Now.issue = a.task)))
  }
}

/* R7a. THE HOLE: a sub-issue is claimed, no agent is ever launched on it, and
   the claim is released -- which on the remote is the ref deleted, so a second
   `take` succeeds and two executors reach one sub-issue. */
pred R7a_FreshClaimReleasedWithNoAgent {
  some i: Issue {
    /* NEVER LAUNCHED, not "no atom exists". An `Agent` atom on the sub-issue
       that was never started IS the fresh claim -- the delegate the branch was
       cut for, before `agent start` -- so this is both the truer witness and
       the one that pins the rule's `in Launched`: written as "no atom", the
       weakened rule still forbade the trace and the disjunct went untested. */
    always no a: Agent | a.task = i and a in Launched
    /* NOT complete, and this conjunct is what makes the witness the fresh
       claim rather than hands-on work. Without it the trace closes the
       sub-issue and merges its pull request first, which is a landing nobody
       needed an Agent atom for and is releasable on purpose -- so R7b came
       back SAT over a legitimate trace and pinned nothing. */
    always not complete[i]
    eventually (Now.event = Claim and Now.issue = i
                and after eventually (Now.event = Release and Now.issue = i))
  }
}

/* R7b. The discipline closes it. */
pred R7b_WorkerRuleClosesTheFreshClaim {
  releaseNeedsAWorker and R7a_FreshClaimReleasedWithNoAgent
}

/* R7c. CONTROL FOR THE `Launched` DISJUNCT: an agent was launched on this
   sub-issue and is gone, which is the release the sweep actually makes.
   `always not complete` is load-bearing -- without it the solver satisfies
   this through the OTHER disjunct, and deleting `Launched` from the rule left
   both this and R7b green, pinning neither. */
pred R7c_WorkerRuleAdmitsTheOrdinaryRelease {
  releaseNeedsAWorker
  some a: Agent {
    always not complete[a.task]
    eventually (a in Launched and a not in Live and a not in PushedToRemote
                and Now.event = Release and Now.issue = a.task)
  }
}

/* R7d. CONTROL FOR THE `complete` DISJUNCT: hands-on work is no Agent at all
   (A18's shape), so a landed sub-issue nobody was launched on must still be
   releasable -- otherwise the rule strands every branch a session worked with
   its own hands. Deleting `complete` from the rule turns this UNSAT. */
pred R7d_WorkerRuleAdmitsTheAgentLessLanding {
  releaseNeedsAWorker
  no Agent
  some i: Issue |
    eventually (complete[i] and Now.event = Release and Now.issue = i)
}

/* =================== whose session is that =================== */

/* N1. A session named for ANOTHER campaign, live on the machine that holds
   this one, does not block this campaign's close. Machine-wide alone made the
   peer set identical for every campaign here, so closing one asked another's
   sessions to stand down. */
pred N1_ForeignNamedSessionDoesNotBlock {
  some disj c1, c2: Campaign, s: Session, a: Agent, m: Machine {
    a.peer = s and a.host = m and s.machine = m
    always s.campaignNamed = c2
    /* BOTH INSIDE THE `eventually`, and that is what makes this pin the
       exemption. `machinesHolding` is derived from `OnDisk`, which is var, so a
       membership stated outside is read at time zero and the witness can
       satisfy `not liveUnderLocally` at an instant when the directory is simply
       not on disk -- a trace the exemption plays no part in. Deleting the
       exemption then left this green. */
    eventually (a in Live and m in machinesHolding[c1]
                and a.task not in c1.memberIssues
                and not liveUnderLocally[c1, m])
  }
}

/* N2. CONTROL, and the direction that must NOT be exempted: a session whose
   name says nothing is not evidence, so it still blocks. Making the absent
   name exempt too would empty the gate. */
pred N2_UnnamedSessionStillBlocks {
  some c: Campaign, s: Session, a: Agent, m: Machine {
    a.peer = s and a.host = m and s.machine = m
    always no s.campaignNamed
    /* `a.task not in c.memberIssues` is load-bearing: without it the witness
       blocks through the FIRST disjunct -- an agent on a sub-issue of this
       campaign blocks whatever it is called -- and says nothing about whether
       an absent name exempts the machine-wide one. Making the absent name
       exempt then left this green. */
    eventually (a in Live and m in machinesHolding[c]
                and a.task not in c.memberIssues
                and liveUnderLocally[c, m])
  }
}

/* N3. CONTROL for N1: an agent on a sub-issue OF THIS CAMPAIGN blocks whatever
   its session is called. The name exempts the machine-wide disjunct and
   nothing else -- otherwise a misnamed executor could close over its own work. */
pred N3_ForeignNameDoesNotExemptOwnSubIssue {
  some disj c1, c2: Campaign, s: Session, a: Agent, m: Machine {
    a.peer = s and a.host = m and s.machine = m
    a.task in c1.memberIssues
    always s.campaignNamed = c2
    eventually (a in Live and liveUnderLocally[c1, m])
  }
}

/* =================== the refs a close leaves behind =================== */

/* github's `closable` reads `settled` and nothing else, so a campaign whose
   sub-issues are all closed is closable with claim refs still standing on the
   remote. Most are harmless -- a merged pull request's head outlives it here,
   `delete_branch_on_merge` being off -- and the rest are a claim nobody
   retired, which the next `take` on that sub-issue then refuses forever. */
pred noStrayClaims[c: Campaign] {
  all i: c.memberIssues | i in Claimed implies complete[i]
}

/* N4. THE STRAY: every sub-issue settled, one of them dropped rather than
   completed, and its ref still on the remote at the close. */
pred N4_DroppedSubIssueLeavesItsRef {
  some c: Campaign, i: Issue |
    /* MEMBERSHIP READ AT THE CLOSE, not at time zero. `memberIssues` is `var`,
       so a witness stated outside the `eventually` can satisfy this by having
       the sub-issue removed from the campaign before the close -- and then the
       rule, which ranges over members, never sees it. That trace is
       `RemoveMember`'s hole and not this one's. */
    eventually (Now.event = CloseIssue and Now.issue = c.campaignIssue
                and i in c.memberIssues
                and closable[c] and dropped[i] and i in Claimed)
}

/* N5. The rule closes it. */
pred N5_NoStrayClaimsClosesIt {
  (always all c: Campaign |
     (Now.event = CloseIssue and Now.issue = c.campaignIssue)
       implies noStrayClaims[c])
  and N4_DroppedSubIssueLeavesItsRef
}

/* N6. CONTROL: a ref left by a MERGED pull request is the ordinary residue and
   blocks nothing, so the rule must still admit a close over one. UNSAT here
   would mean it demanded every ref be deleted before any campaign could end. */
pred N6_NoStrayClaimsAdmitsAMergedResidue {
  (always all c: Campaign |
     (Now.event = CloseIssue and Now.issue = c.campaignIssue)
       implies noStrayClaims[c])
  some c: Campaign, i: Issue |
    eventually (Now.event = CloseIssue and Now.issue = c.campaignIssue
                and i in c.memberIssues
                and complete[i] and i in Claimed)
}

/* =================== attribution, derived =================== */

/* A1. WHO HOLDS THE CLAIM, read with no record anywhere: the agent is live
   and the checkout in its campaign directory is on the claim's branch. Two
   sessions, so `holder` is picking one of them out and not answering
   vacuously. */
pred A1_HolderReadFromTheCheckout {
  some c: Campaign, disj s1, s2: Session, a: Agent {
    a.peer = s2 and a.task in c.memberIssues
    s1.machine = s2.machine
    eventually (a in Live and a in holder[a.task]
                and Now.event = Status and Who.session = s1 and Target.agent = a)
  }
}

/* A3. Control for A1: the derived reading did not buy itself by making the
   agent unable to run. UNSAT here would mean the whole protocol went with the
   record. */
pred A3_HolderRunsTheWholeProtocol {
  coLocatedShutdown and twoStepShutdown
  some c: Campaign, disj s1, s2: Session, a: Agent {
    a.peer = s2 and a.task in c.memberIssues
    s1.machine = s2.machine
    eventually (Now.event = Status and Who.session = s1 and Target.agent = a)
    eventually a in Retired
  }
}

/* A13. Without it, a fresh agent briefed from a bad review lands new
   commits under the old review's bit. */
pred A13_PushAfterReviewUnReviews {
  some a: Agent |
    eventually (Now.event = Review and Now.issue = a.task
                and after eventually (Now.event = Push and Target.agent = a
                                      and after (a.task.pullRequest not in Reviewed)))
}

/* =================== who merges, and who reviews =================== */

/* A4. BUILT SO THAT ONLY ONE THING IS WRONG: the agent is confirmed and a
   REPORT preceded the merge, so A5 turns on the review conjunct alone.
   `always s2.worksOn = c` keeps the merger a campaign session. */
pred A4_AgentMergesItsOwnPullRequest {
  some c: Campaign, s2: Session, a: Agent {
    a.peer = s2 and a.task in c.memberIssues
    always s2.worksOn = c
    eventually (Now.event = Report and Target.agent = a)
    eventually (Now.event = MergePullRequest and Who.session = s2 and Now.issue = a.task
                and a in Confirmed and no a.task.pullRequest & Reviewed)
  }
}

/* A5. Dropping `Now.issue.pullRequest in Reviewed` from the rule turns this SAT. */
pred A5_ReviewRuleBlocksTheCollision {
  mergedOnCurrentReview and A4_AgentMergesItsOwnPullRequest
}

/* =================== deleting a tree under an agent =================== */

/* A10. session/scenarios.als's R3 reached from here: a directory is deleted
   while a live agent on that machine still holds local-only work. */
pred A10_DeleteUnderLiveAgent {
  some c: Campaign, a: Agent {
    some a.peer                        -- a session working its own claim
    a.task in c.memberIssues
    eventually (a in Live and a in LocalOnly
                and Now.event = DeleteDir and Where.machine = a.host)
  }
}

/* A11. The liveness gate closes it. Keying the gate on `some a.peer` instead
   of on `a in Live` turns it SAT again, which is the reading that would let a
   delegate's tree go. */
pred A11_LiveGateBlocksTheDelete {
  noDeleteUnderLiveAgent and A10_DeleteUnderLiveAgent
}

/* A12. UNSAT here would mean the directory could never be deleted at all. */
pred A12_LiveGateAdmitsTheDelete {
  noDeleteUnderLiveAgent
  some a: Agent |
    eventually (a in Live and eventually (a not in Live and Now.event = DeleteDir
                                          and Where.machine = a.host))
}

/* A6. The other chair. A confirmation checks that the work EXISTS, never that
   it is right, so with A4 this pair says the rule's subject is the review. */
pred A6_UnreviewedMerge {
  some c: Campaign, s: Session, a: Agent {
    a.task in c.memberIssues
    s != a.peer
    always s.worksOn = c
    eventually (Now.event = MergePullRequest and Who.session = s and Now.issue = a.task
                and a in Confirmed and no a.task.pullRequest & Reviewed)
  }
}

pred A7_ReviewRuleBlocksUnreviewed { mergedOnCurrentReview and A6_UnreviewedMerge }

/* A8. Control for A5 and A7: neither is green by forbidding merges. */
pred A8_ReviewRuleAdmitsTheLanding {
  mergedOnCurrentReview
  some c: Campaign, disj s1, s2: Session, a: Agent {
    a.peer = s2 and a.task in c.memberIssues
    s1.machine = s2.machine and always s1.worksOn = c
    eventually (Now.event = Report and Target.agent = a)
    eventually (Now.event = Confirm and Who.session = s1 and Target.agent = a)
    eventually (Now.event = Review and Who.session = s1 and Now.issue = a.task)
    eventually (Now.event = MergePullRequest and Who.session = s1 and Now.issue = a.task)
  }
}

/* A16. THE ONE-SESSION LANDING, admitted. Run at exactly one Session so the
   absence of a second merger is the scope and not an accident. */
pred A16_AuthorLandsOwnReviewedWork {
  mergedOnCurrentReview
  some s: Session, a: Agent {
    a.peer = s
    eventually (Now.event = Push and Target.agent = a)
    eventually (Now.event = Review and Who.session = s and Now.issue = a.task)
    eventually (Now.event = Confirm and Who.session = s and Target.agent = a)
    eventually (Now.event = MergePullRequest and Who.session = s and Now.issue = a.task)
  }
}

/* A16b. The author gets no special door. Letting `push` keep `Reviewed` turns
   this SAT, so the currency half of the rule is `push`'s clearing line. */
pred A16b_AuthorCannotMergeOnStaleReview {
  mergedOnCurrentReview
  some s: Session, a: Agent {
    a.peer = s
    eventually (Now.event = Review and Now.issue = a.task
                and after eventually (Now.event = Push and Target.agent = a
                                      and after ((always Now.event != Review)
                                                 and eventually (Now.event = MergePullRequest
                                                                 and Now.issue = a.task))))
  }
}

/* A18. Hands-on work is no Agent at all. It matters because the confirm
   conjunct ranges over `agentsOf[Now.issue]`, empty here, so it is
   VACUOUSLY true and the review half holds the rule up alone -- which A16,
   having an Agent, cannot see. */
pred A18_AgentLessLandingIsAdmitted {
  mergedOnCurrentReview
  no Agent
  some s: Session, i: Issue {
    eventually (Now.event = Review  and Who.session = s and Now.issue = i)
    eventually (Now.event = MergePullRequest and Who.session = s and Now.issue = i)
  }
}

/* A18b. The direction a vacuous conjunct could have swallowed: weaken the
   review half as the confirm half is vacated here and hands-on work lands
   unreviewed with every rule obeyed. */
pred A18b_AgentLessUnreviewedMergeIsBlocked {
  mergedOnCurrentReview
  no Agent
  always Now.event != Review
  some i: Issue | eventually (Now.event = MergePullRequest and Now.issue = i)
}

/* A17. THE RESIDUAL GAP OF THE DERIVED READING, and the only one: an agent
   is live and listed, and the checkout it was attributed by has moved off its
   branch, so `holder` no longer names it. R4c is how the checkout moves;
   AttributionIsSound is the same fact as a property. */
pred A17_LiveButNoLongerTheHolder {
  some c: Campaign, a: Agent {
    a.task in c.memberIssues
    eventually (a in Live and liveUnderLocally[c, a.host]
                and a not in holder[a.task])
  }
}
/* =================== the planner =================== */

/* P1. THE ONE-EXECUTOR SHAPE: a request of one sub-issue is filed and worked by
   one session, and settles with no Planner atom anywhere. Requiring a planner
   of every launch, not only a delegate's, turns this UNSAT. */
pred P1_SimpleRequestSettlesWithoutPlanner {
  no role.Planner
  some s: Session, a: Agent {
    a.peer = s
    eventually (Now.event = Work and Target.agent = a)
    eventually settled[a.task]
  }
}

/* P2. THE TWO-ROLE SHAPE, admitted: a planner launches a delegate onto a
   sub-issue and that delegate works it. Control for DelegateLaunchedByPlanner,
   whose UNSAT could otherwise mean delegates are forbidden altogether. */
pred P2_PlannerLaunchesDelegate {
  some p, a: Agent {
    p.role = Planner and no a.peer
    p.peer = a.launcher and p.task = a.task
    eventually (Now.event = Launch and Target.agent = a and p in Live)
    eventually (Now.event = Work and Target.agent = a)
  }
}

/* ---------------- commands ---------------- */

-- one sub-issue, one session, no planner
run P1_SimpleRequestSettlesWithoutPlanner for 3 Issue, 1 PullRequest, 1 Campaign, exactly 1 Session, exactly 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 14 steps expect 1
-- a planner's delegate does work
run P2_PlannerLaunchesDelegate           for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 2 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1

-- the whole retirement procedure runs
run Sanity                          for exactly 2 Issue, 1 PullRequest, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Branch, 1 CampaignDir, 12 steps expect 1
-- a REPORT changes nothing durable
run ReportIsNotEvidence             for exactly 2 Issue, 1 PullRequest, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Branch, 1 CampaignDir, 10 steps expect 1
-- BLOCKED stops the agent
run BlockedAgentDoesNotProceed      for exactly 2 Issue, 1 PullRequest, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Branch, 1 CampaignDir, 10 steps expect 1
-- wait-for-the-answer strands a pane
run SilentAgentIsRetirableUnderWait for exactly 2 Issue, 1 PullRequest, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Branch, 1 CampaignDir, 12 steps expect 0
-- rule 3's repair still retires it
run SilentAgentStillRetired         for exactly 2 Issue, 1 PullRequest, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Branch, 1 CampaignDir, 12 steps expect 1

run S3_DelegateDiesAfterPushing for exactly 2 Issue, 1 PullRequest, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Branch, 1 CampaignDir, 12 steps expect 1
run S4_ReportWithoutPush        for exactly 2 Issue, 1 PullRequest, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Branch, 1 CampaignDir, 12 steps expect 1
run S9_OrphanedByLocalDelete    for exactly 2 Issue, 1 PullRequest, exactly 1 Campaign, exactly 2 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Branch, 1 CampaignDir, 12 steps expect 1

-- a close over a delegate on M1
run R3b_CloseFromAnotherMachine  for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 12 steps expect 1
-- the global rule would block it
run R3c_GlobalCloseRuleBlocks    for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 12 steps expect 0

-- an acquire moves a live role's HEAD
run R4c_CheckoutSwitchedUnderAgent for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 2 Branch, 1 CampaignDir, 12 steps expect 1
-- what the numbered branch leaves
run R4e_NumberedBranchStillShared for 4 Issue, 1 PullRequest, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
-- a session named for another campaign does not block this campaign's close
run N1_ForeignNamedSessionDoesNotBlock       for 3 Issue, 1 PullRequest, 2 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
-- control: a session whose name says nothing still blocks
run N2_UnnamedSessionStillBlocks             for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 10 steps expect 1
-- control: the name exempts the machine-wide disjunct and nothing else
run N3_ForeignNameDoesNotExemptOwnSubIssue   for 3 Issue, 1 PullRequest, 2 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1

-- a dropped sub-issue's ref outlives the close, and the next take refuses forever
run N4_DroppedSubIssueLeavesItsRef           for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
-- the rule closes it
run N5_NoStrayClaimsClosesIt                 for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 0
-- control: a merged pull request's leftover ref still admits the close
run N6_NoStrayClaimsAdmitsAMergedResidue     for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 14 steps expect 1

-- a claim nobody was ever launched on is released, and the ref goes with it
run R7a_FreshClaimReleasedWithNoAgent    for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
-- the discipline closes it
run R7b_WorkerRuleClosesTheFreshClaim    for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 0
-- control: the ordinary release still happens, through the `Launched` disjunct
run R7c_WorkerRuleAdmitsTheOrdinaryRelease for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 14 steps expect 1
-- ...and hands-on work still releases, through the `complete` one, at `0 Agent`
run R7d_WorkerRuleAdmitsTheAgentLessLanding for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 0 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 14 steps expect 1
-- the claim closes it
run R4f_ClaimClosesSameSubIssue    for 4 Issue, 1 PullRequest, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 0
-- control: the 422 is load-bearing
run R4g_ClaimWithoutAtomicityStillShared for 4 Issue, 1 PullRequest, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
-- the own-hands hole, the guard that closes it, and the control
run R4h_OwnHandsWorkWithoutClaim for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
run R4i_GuardClosesOwnHandsGap   for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 0
run R4j_GuardAdmitsClaimedWork   for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
-- the shell hole the pre-tool-use half leaves, the commit gate that closes it, and the control
run R4k_UnclaimedShellWriteThenCommit for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
run R4l_CommitGateClosesIt           for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 0
run R4m_GateAdmitsClaimedCommit      for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1

-- the gap TwoStepShutdownSuffices rests on
run R5b_PushedButStillLocalOnly         for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 12 steps expect 1
-- co-location, not ownership, is the axis
run R5c_NonLauncherSameMachineIsFine for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
-- a local release under a remote agent
run R6_ReleaseUnderRemoteAgent   for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 12 steps expect 1
-- a dangling claim is reclaimable
run R6b_ReclaimAfterDeath        for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 14 steps expect 1

/* A1 and A3 run at two Sessions, so the derived reading is choosing between
   them. A10-A12 need a CampaignDir to delete mid-trace. A16, A16b, A18 and
   A18b run at exactly ONE Session, because the absence of a second merger is
   their subject. */
-- the holder read off the checkout, with no record anywhere
run A1_HolderReadFromTheCheckout          for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
-- control: the whole run still happens
run A3_HolderRunsTheWholeProtocol         for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 14 steps expect 1
-- the live collision: a self-merge with NO review
run A4_AgentMergesItsOwnPullRequest                for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 14 steps expect 1
-- still caught, by what was missing
run A5_ReviewRuleBlocksTheCollision          for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 14 steps expect 0
-- the same merge from the other chair
run A6_UnreviewedMerge                       for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
-- nobody merges unread
run A7_ReviewRuleBlocksUnreviewed            for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 0
-- control: two-session landing runs
run A8_ReviewRuleAdmitsTheLanding            for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 14 steps expect 1

-- session/scenarios.als's R3, reached from here
run A10_DeleteUnderLiveAgent      for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
-- and closed by reading liveness
run A11_LiveGateBlocksTheDelete   for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 0
-- control
run A12_LiveGateAdmitsTheDelete   for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
-- a push retires a review
run A13_PushAfterReviewUnReviews             for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 14 steps expect 1
-- the one-session landing
run A16_AuthorLandsOwnReviewedWork           for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 14 steps expect 1
-- and a push retires that permission
run A16b_AuthorCannotMergeOnStaleReview      for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 14 steps expect 0
-- the derived reading's one residual gap: live, listed, checkout moved off
run A17_LiveButNoLongerTheHolder             for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
-- hands-on work, reviewed and merged by one session, at `0 Agent`
run A18_AgentLessLandingIsAdmitted           for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 0 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
-- and unreviewed it does not land. The pair matters because the confirm conjunct is VACUOUS at `0 Agent`, so the review half holds the rule up alone
run A18b_AgentLessUnreviewedMergeIsBlocked   for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 0 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 0

