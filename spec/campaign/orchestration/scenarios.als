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

/* R4g drops `claimAtomic` alone and the collision returns, so create-ref's
   server-side refusal -- not the ritual -- is the load-bearing half. */
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
   this relation. The guard reads that target where it can -- a file tool's
   path, and a shell's write targets, which are the operands of the changing
   forms that matched and never the words that merely look like paths -- and
   falls back to this rule where it cannot, an unread target not being a target
   read as elsewhere -- per PART of the command, since a part whose target it
   cannot read is not answered for by a part it can. A write to the campaign
   plane through `gh` has no filesystem target at all and is always `Work`. No
   atom here carries a path, so the reading itself is the script's and is
   stated in its docstring; the model says only that a write on nothing this
   campaign owns is outside `Work`. */
pred claimBeforeWork {
  always (Now.event = Work and some Target.agent.peer
            implies Now.issue in Target.agent.peer.claimedIssues)
}

/* The rule as written, the honest local reading, and the reading a session
   can actually perform. */
pred closeDisciplineFull[c: Campaign] {
  always ((Now.event = CloseIssue and Now.issue = c.campaignIssue) implies closableWithAgents[c])
}
pred closeDisciplineLocal[c: Campaign] {
  always ((Now.event = CloseIssue and Now.issue = c.campaignIssue) implies closableLocally[Who.session, c])
}
pred closeDisciplineAsRead[c: Campaign] {
  always ((Now.event = CloseIssue and Now.issue = c.campaignIssue) implies closableAsRead[Who.session, c])
}

/* Where session/scenarios.als's R3 is answered: keyed on the record, which is the thing
   a deleting session can actually read. */
pred noDeleteUnderAddressableAgent {
  always (Now.event = DeleteDir implies
            no a: Agent | a in Live and a.host = Where.machine and addressable[a]
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

/* =================== the claim record =================== */

/* A1. Liveness was never the missing half; attribution was. Closed BY
   CONSTRUCTION and not by a discipline, since the claimant writes its own
   record before any agent exists. What remains outside it is the
   post-delete window: A9, gated by A10-A12, measured by A14/A15. */
pred A1_UnrecordedAgentAtTheClose {
  some c: Campaign, disj s1, s2: Session, a: Agent {
    a.peer = s2 and a.task in c.memberIssues
    always a not in Addressable                   -- a claim with no record
    closeDisciplineAsRead[c]                    -- s1 obeys the gate it can read
    eventually (a in Live and a.task in Claimed
                and Now.event = CloseIssue and Now.issue = c.campaignIssue and Who.session = s1
                and liveUnderLocally[c, s1.machine])
  }
}

/* A3. Control for A1: UNSAT here would mean A1 went green by forbidding the
   agent's life altogether. */
pred A3_RecordedAgentRunsTheWholeProtocol {
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

/* =================== the record, and what it is worth =================== */

/* A9. The lifetime exercised rather than asserted. Its cost is A10. */
pred A9_RecordDiesWithTheDirectory {
  some a: Agent {
    some a.peer                        -- a delegate's address is its --name
    eventually (addressable[a] and Now.event = DeleteDir and Where.machine = a.host
                and after not addressable[a])
  }
}

/* A10. session/scenarios.als's R3 with the missing half supplied: the record names the
   working session and nothing reads it. */
pred A10_DeleteUnderRecordedAgent {
  some c: Campaign, a: Agent {
    some a.peer                        -- a session working its own claim
    a.task in c.memberIssues
    eventually (a in Live and addressable[a] and a in LocalOnly
                and Now.event = DeleteDir and Where.machine = a.host)
  }
}

/* A11. Keying the gate on `no a.peer` instead of `addressable[a]` turns it SAT
   again. */
pred A11_AddressableGateBlocksTheDelete {
  noDeleteUnderAddressableAgent and A10_DeleteUnderRecordedAgent
}

/* A12. UNSAT here would mean the directory could never be deleted at all. */
pred A12_AddressableGateAdmitsTheDelete {
  noDeleteUnderAddressableAgent
  some a: Agent |
    eventually (addressable[a] and eventually (a not in Live and Now.event = DeleteDir
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

/* A20. StoodDownCommentPosted is set by its event and by nothing else:
   unframed in any step,
   or uncleared at init, this goes SAT. */
pred A20_StoodDownCommentOnlyByPosting {
  eventually some StoodDownCommentPosted
  always Now.event != StoodDownPosted
}
/* The comment is never over local-only work: no trace posts it while the
   agent is LocalOnly. */
pred A19_StoodDownCommentNeverOverLocalOnlyWork {
  eventually (Now.event = StoodDownPosted and Target.agent in LocalOnly)
}

/* A14. An agent whose record died is still retirable, on the confirmation
   alone. Restoring the `addressable` guard on `confirm` turns this UNSAT. */
pred A14_UnaddressableAgentIsRetirable {
  resolveSilenceExternally and coLocatedShutdown
  some a: Agent {
    some a.peer
    eventually (a not in Addressable and Now.event = Confirm and Target.agent = a)
    eventually (a not in Addressable and Now.event = Retire and Target.agent = a)
  }
}

/* A14b. And it cannot be stood down: `standDown` carries a message and
   nothing re-creates an address after the delete. So A14's ending is a
   stand-down taken while the record stood, or `retire`'s second disjunct. */
pred A14b_UnaddressableAgentCannotBeStoodDown {
  A14_UnaddressableAgentIsRetirable
  some a: Agent {
    some a.peer
    eventually (a not in Addressable and Now.event = StandDown and Target.agent = a)
  }
}

/* A15. And its pull request still lands. Gating `confirm` on `addressable` made
   a record-less agent's work permanently unmergeable, which `gh pullRequest merge`
   does not do. */
pred A15_UnaddressableAgentPullRequestLands {
  mergedOnCurrentReview
  some a: Agent {
    some a.peer
    eventually (a not in Addressable and Now.event = Confirm and Target.agent = a)
    eventually (Now.event = MergePullRequest and Now.issue = a.task)
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

/* A17. Seen live, no longer attributable: the pane proves the agent ALIVE
   and cannot say WHOSE CLAIM it is. */
pred A17_PaneSeesWhatTheRecordLost {
  some c: Campaign, a: Agent {
    some a.peer
    a.task in c.memberIssues
    eventually (a in Live and liveUnderLocally[c, a.host]
                and not liveAndAddressable[c, a.host])
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
-- the claim closes it
run R4f_ClaimClosesSameSubIssue    for 4 Issue, 1 PullRequest, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 0
-- control: the 422 is load-bearing
run R4g_ClaimWithoutAtomicityStillShared for 4 Issue, 1 PullRequest, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
-- the own-hands hole, the guard that closes it, and the control
run R4h_OwnHandsWorkWithoutClaim for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
run R4i_GuardClosesOwnHandsGap   for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 0
run R4j_GuardAdmitsClaimedWork   for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1

-- the gap TwoStepShutdownSuffices rests on
run R5b_PushedButStillLocalOnly         for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 12 steps expect 1
-- co-location, not ownership, is the axis
run R5c_NonLauncherSameMachineIsFine for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
-- a local release under a remote agent
run R6_ReleaseUnderRemoteAgent   for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 12 steps expect 1
-- a dangling claim is reclaimable
run R6b_ReclaimAfterDeath        for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 14 steps expect 1

/* A1 and A3 run at two roles, where the gap they measure was widest. A9-A12
   need a CampaignDir to delete; A14-A15 need one to delete mid-trace. A16, A16b, A18
   and A18b run at exactly ONE Session, because the absence of a second merger
   is their subject. */
-- closed BY CONSTRUCTION: the claimant writes its own record, so no live claim is unattributable
run A1_UnrecordedAgentAtTheClose          for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 0
-- control: the whole run still happens
run A3_RecordedAgentRunsTheWholeProtocol  for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 14 steps expect 1

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

-- the record has the tree's lifetime
run A9_RecordDiesWithTheDirectory            for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
-- session/scenarios.als's R3, reached from here
run A10_DeleteUnderRecordedAgent          for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
-- and closed by reading the record
run A11_AddressableGateBlocksTheDelete          for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 0
-- control
run A12_AddressableGateAdmitsTheDelete          for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
-- a push retires a review
run A13_PushAfterReviewUnReviews             for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 14 steps expect 1
-- a record dead with its directory still ends in a lawful retire
run A14_UnaddressableAgentIsRetirable       for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 14 steps expect 1
-- and never a stand-down: that one carries a message, so it stays gated
run A14b_UnaddressableAgentCannotBeStoodDown for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 14 steps expect 0
-- and its pull request still lands
run A15_UnaddressableAgentPullRequestLands           for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 16 steps expect 1
-- the one-session landing
run A16_AuthorLandsOwnReviewedWork           for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 14 steps expect 1
-- and a push retires that permission
run A16b_AuthorCannotMergeOnStaleReview      for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 14 steps expect 0
-- attribution, not liveness, is the split's subject
run A17_PaneSeesWhatTheRecordLost            for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
-- hands-on work, reviewed and merged by one session, at `0 Agent`
run A18_AgentLessLandingIsAdmitted           for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 0 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
-- and unreviewed it does not land. The pair matters because the confirm conjunct is VACUOUS at `0 Agent`, so the review half holds the rule up alone
run A18b_AgentLessUnreviewedMergeIsBlocked   for 3 Issue, 1 PullRequest, 1 Campaign, 1 Session, 0 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 0

-- the floor's two negative controls
run A19_StoodDownCommentNeverOverLocalOnlyWork for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 0
run A20_StoodDownCommentOnlyByPosting  for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 0
