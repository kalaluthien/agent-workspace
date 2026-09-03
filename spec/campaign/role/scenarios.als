/*
 * The disciplines a shutdown, a claim, a delete and a merge might follow, and
 * the witnesses that measure each. github/system.als is spec/'s entry point.
 */
module role/scenarios

open role/system

/* ---------------- the property ---------------- */

/* The one thing the protocol is for. */
pred noWorkDestroyed {
  always (Now.ev = Retire implies Target.role not in Local)
}

/* ---------------- disciplines: the shutdown, three ways ---------------- */

/* The executor's own account as the basis for destroying its workspace. */
pred oneStepShutdown {
  always (Now.ev in StandDown + Retire implies Target.role in Reported)
}

/* Both conjuncts are load-bearing: the answer names work only the executor
   can see, the confirmation is the session looking for itself. */
pred twoStepShutdown {
  always (Now.ev in StandDown + Retire implies
            (Target.role in Answered and Target.role in Confirmed))
}

/* Narrowing this to `StandDown + Retire` reddens TwoStepCoLocatedSuffices: a
   remote session can then run the confirmation a local one acts on. */
pred coLocatedShutdown {
  always (Now.ev in Confirm + ConfirmElsewhere + StandDown + Retire
            implies coLocated[By.actor, Target.role])
}

/* Rule 3: an executor that is gone may be stood down on the confirmation
   alone, and only on it. */
pred resolveSilenceExternally {
  always (Now.ev in StandDown + Retire implies
            (Target.role in Confirmed
             and (Target.role in Answered or Target.role not in Live)))
}

/* The rule it replaces: wait for the answer. */
pred waitForAnswer {
  always (Now.ev in StandDown + Retire implies Target.role in Answered)
}

/* What only a session on the executor's own machine can check. */
pred localCheckedShutdown { always (Now.ev = StandDown implies Target.role not in Local) }

/* R4g drops `claimAtomic` alone and the collision returns, so create-ref's
   server-side refusal -- not the ritual -- is the load-bearing half. */
pred claimBeforeLaunch { always (Now.ev = Launch implies Now.issue in By.actor.claims) }
pred claimAtomic       { always (Now.ev = Claim  implies Now.issue not in Claimed) }

/* The gate on LAUNCH covers the executor a session starts and says nothing
   about the executor a session IS: `work` carries no `By.actor`, so a session
   working its own claim reaches the same sub-issue along an edge
   `claimBeforeLaunch` never touches. R4h is that hole and R4i is its repair --
   scripts/check-campaign-claim.py, a PreToolUse guard refusing a changing call
   from a session holding no claim. Keyed on `a.peer` because a delegate has no
   session to hold one; its launcher was gated already. */
pred claimBeforeWork {
  always (Now.ev = Work and some Target.role.peer
            implies Now.issue in Target.role.peer.claims)
}

/* The rule as written, the honest local reading, and the reading a session
   can actually perform. */
pred closeDisciplineFull[c: Campaign] {
  always ((Now.ev = CloseIssue and Now.issue = c.campaignIssue) implies closableWithAgents[c])
}
pred closeDisciplineLocal[c: Campaign] {
  always ((Now.ev = CloseIssue and Now.issue = c.campaignIssue) implies closableLocally[By.actor, c])
}
pred closeDisciplineAsRead[c: Campaign] {
  always ((Now.ev = CloseIssue and Now.issue = c.campaignIssue) implies closableAsRead[By.actor, c])
}

/* Where session/scenarios.als's R3 is answered: keyed on the record, which is the thing
   a deleting session can actually read. */
pred noDeleteUnderReadableExecutor {
  always (Now.ev = DeleteDir implies
            no a: Role | a in Live and a.host = Site.mach and reachable[a]
                          and campaignOf[a.task] in (Present - Present').camp)
}

/* Empty for a sub-issue a session did with its own hands, which is what makes
   `mergedOnCurrentReview`'s second conjunct vacuous there -- see A18/A18b. */
fun executorsOf[i: Issue]: set Role { task.i }

/* A MERGE REQUIRES A CURRENT REVIEW, and the author may then merge as anyone
   else may: an identity rule would make the one-session landing unreachable
   and call it safety. CURRENT is encoded as `Reviewed` cleared by `push`,
   which pins the revision THE REVIEW WAS READ AT rather than the merged
   commit, so a squash merge of a reviewed head stays reviewed. The second
   conjunct is UNIVERSAL, not existential, and vacuous with no Role. */
pred mergedOnCurrentReview {
  always (Now.ev = MergePR implies
            (Now.issue.pr in Reviewed
             and (all a: executorsOf[Now.issue] |
                    a in Confirmed and coLocated[By.actor, a])))
}

/* ---------------- witnesses ---------------- */

/* SAT means the disciplines forbid a counterexample rather than the protocol. */
pred Sanity {
  coLocatedShutdown and twoStepShutdown
  and eventually (some a: Role | a in Retired)
  and eventually Now.ev = Work
  and eventually Now.ev = Push
}

/* The claim leaves the local fact and the GitHub fact exactly as they were. A
   signal weaker than an explicit REPORT says even less. */
pred ReportIsNotEvidence {
  some a: Role | eventually (Now.ev = Report and Target.role = a
    and a in Local and a in Local'
    and not complete[a.task] and after always not complete[a.task])
}

pred BlockedRoleDoesNotProceed {
  some a: Role | eventually (a in Waiting and always (a in Waiting and Now.ev != Work))
}

/* THE FAILURE RULE 3 FORBIDS: under wait-for-the-answer there is no such
   trace, so the session waits for a reply that cannot come. */
pred SilentAgentIsRetirableUnderWait {
  waitForAnswer
  and (some a: Role |
         eventually (a in Asked and a not in Live and a in Retired)
         and always a not in Answered)
}

/* The repair is a repair and not a prohibition. */
pred SilentAgentStillRetired {
  resolveSilenceExternally and coLocatedShutdown
  and (some a: Role | eventually a in Retired and always a not in Answered)
}

/* Completion is a GitHub fact, so it survives the death and never undoes. */
pred S3_DelegateDiesAfterPushing {
  one c: Campaign | one a: Role {
    a.task in c.members
    always Now.ev not in AddMember + RemoveMember
    mergeClosed[c.members]
    eventually (Now.ev = OpenPR and Now.issue = a.task)
    eventually (Now.ev = RoleDie and some a.task.pr and a.task.pr not in Merged)
    eventually complete[a.task]
    always (complete[a.task] implies always complete[a.task])
  }
}

/* The claim never becomes a GitHub fact on its own. */
pred S4_ReportWithoutPush {
  one c: Campaign | one a: Role {
    a.task in c.members
    always Now.ev not in AddMember + RemoveMember
    eventually (Now.ev = Report and Now.issue = a.task)
    eventually (a in Reported and no a.task.pr and a.task in Open)
    eventually always (not complete[a.task])
    always not closable[c]
  }
}

/* Live with nothing pushed is the only state where local-only work is
   actually destroyed. */
pred S9_OrphanedByLocalDelete {
  one c: Campaign | one a: Role {
    a.task in c.members
    eventually (Now.ev = DeleteDir and Site.mach = a.host and a in Live
                and a in Local and no a.task.pr)
    eventually (a in Live and a.host not in dirsOf[c])
  }
}

/* =================== a close during another session's work =================== */

/* R3b. The local gate reads closable; the campaign is not. */
pred R3b_CloseFromAnotherMachine {
  some c: Campaign, disj s1, s2: Session, a: Role {
    s1.smach != s2.smach
    a.launcher = s1
    closeDisciplineLocal[c]
    eventually (Now.ev = CloseIssue and By.actor = s2 and Now.issue = c.campaignIssue
                and a in Live and not closableWithAgents[c])
  }
}

/* R3c. The global rule, if it could be read, blocks it. The RemoveMember
   scope is a finding, not a convenience: `liveUnder` reads membership OR
   co-location, so moving the sub-issue out and deleting the tree turns the rule
   permissive while the executor still runs, and nothing guards that. */
pred R3c_GlobalCloseRuleBlocks {
  some c: Campaign, disj s1, s2: Session, a: Role {
    s1.smach != s2.smach
    a.launcher = s1
    always Now.ev != RemoveMember
    closeDisciplineFull[c]
    eventually (Now.ev = CloseIssue and Now.issue = c.campaignIssue and By.actor = s2 and a in Live)
  }
}

/* =================== two sessions, one repository =================== */

/* R4c. Pinned to one step, so the switch is attributable to s2 and not to an
   earlier acquire by the launching session itself. */
pred R4c_CheckoutSwitchedUnderRole {
  some c: Campaign, disj s1, s2: Session, a: Role, r: Repo {
    r != Container
    s1.smach = s2.smach
    a.launcher = s1 and a.host = s1.smach and a.task.home = r
    eventually (Now.ev = Acquire and By.actor = s2 and Site.repo = r
                and a in Live and a not in Visible
                and treeAt[c, a.host].checkout[r] = a.topic
                and after (treeAt[c, a.host].checkout[r] != a.topic))
  }
}

/* R4e. The issue number separates two sub-issues and there is only ever one of
   it per sub-issue, so two sessions on the SAME sub-issue still share a branch. */
pred R4e_NumberedBranchStillShared {
  some disj a1, a2: Role {
    a1.launcher != a2.launcher
    eventually (a1 in Live and a2 in Live
                and some campaignOf[a1.task] and sameBranch[a1, a2])
  }
}

/* R4f. The second session's claim fails before a second executor exists. */
pred R4f_ClaimClosesSameSubIssue {
  claimBeforeLaunch and claimAtomic
  R4e_NumberedBranchStillShared
}

/* R4g. CONTROL: the ritual without the refusal. */
pred R4g_ClaimWithoutAtomicityStillShared {
  claimBeforeLaunch
  some disj s1, s2: Session, i: Issue |
    eventually (i in s1.claims and i in s2.claims)
  R4e_NumberedBranchStillShared
}

/* R4h. THE HOLE, and the one this campaign actually fell into: a session works
   its own sub-issue and no claim of it ever exists, so every peer reading the
   records sees an open sub-issue indistinguishable from one nobody started. */
pred R4h_OwnHandsWorkWithoutClaim {
  some s: Session, a: Role {
    a.peer = s
    eventually (Now.ev = Work and Target.role = a)
    always a.task not in s.claims
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
  some s: Session, a: Role {
    a.peer = s
    eventually (Now.ev = Claim and By.actor = s and Now.issue = a.task
                and eventually (Now.ev = Work and Target.role = a))
  }
}

/* =================== retiring another session's delegate =================== */

/* R5b. The gap TwoStepShutdownSuffices rests on is reachable at all. */
pred R5b_VisibleNotPushed { some a: Role | eventually (a in Visible and a in Local) }

/* R5c. Ownership is not the axis; co-location is. */
pred R5c_NonLauncherSameMachineIsFine {
  localCheckedShutdown
  some disj s1, s2: Session, a: Role {
    a.launcher = s1 and a.host = s1.smach and s2.smach = a.host
    eventually (Now.ev = StandDown and By.actor = s2 and Target.role = a)
  }
}

/* R6. A live executor on another machine that has not pushed loses its claim
   under a rule correctly followed. */
pred R6_ReleaseUnderRemoteRole {
  some s: Session, a: Role {
    a.host != s.smach
    eventually (a in Live and a not in Visible
                and Now.ev = Release and By.actor = s and Now.issue = a.task)
  }
}

/* R6b. A dangling claim does not outlive its usefulness. */
pred R6b_ReclaimAfterDeath {
  some disj s1, s2: Session, a: Role {
    a.launcher = s1
    eventually (a in Launched and a not in Live and a not in Visible
                and eventually (Now.ev = Release
                and eventually (Now.ev = Claim and By.actor = s2 and Now.issue = a.task)))
  }
}

/* =================== the claim record =================== */

/* A1. Liveness was never the missing half; attribution was. Closed BY
   CONSTRUCTION and not by a discipline, since the claimant writes its own
   record before any executor exists. What remains outside it is the
   post-delete window: A9, gated by A10-A12, measured by A14/A15. */
pred A1_UnrecordedExecutorAtTheClose {
  some c: Campaign, disj s1, s2: Session, a: Role {
    a.peer = s2 and a.task in c.members
    always a not in Addressed                   -- a claim with no record
    closeDisciplineAsRead[c]                    -- s1 obeys the gate it can read
    eventually (a in Live and a.task in Claimed
                and Now.ev = CloseIssue and Now.issue = c.campaignIssue and By.actor = s1
                and liveUnderLocally[c, s1.smach])
  }
}

/* A3. Control for A1: UNSAT here would mean A1 went green by forbidding the
   executor's life altogether. */
pred A3_RecordedExecutorRunsTheWholeProtocol {
  coLocatedShutdown and twoStepShutdown
  some c: Campaign, disj s1, s2: Session, a: Role {
    a.peer = s2 and a.task in c.members
    s1.smach = s2.smach
    eventually (Now.ev = Status and By.actor = s1 and Target.role = a)
    eventually a in Retired
  }
}

/* A13. Without it, a fresh executor briefed from a bad review lands new
   commits under the old review's bit. */
pred A13_PushAfterReviewUnReviews {
  some a: Role |
    eventually (Now.ev = Review and Now.issue = a.task
                and after eventually (Now.ev = Push and Target.role = a
                                      and after (a.task.pr not in Reviewed)))
}

/* =================== who merges, and who reviews =================== */

/* A4. BUILT SO THAT ONLY ONE THING IS WRONG: the executor is confirmed and a
   REPORT preceded the merge, so A5 turns on the review conjunct alone.
   `always s2.holds = c` keeps the merger a campaign session. */
pred A4_ExecutorMergesItsOwnPR {
  some c: Campaign, s2: Session, a: Role {
    a.peer = s2 and a.task in c.members
    always s2.holds = c
    eventually (Now.ev = Report and Target.role = a)
    eventually (Now.ev = MergePR and By.actor = s2 and Now.issue = a.task
                and a in Confirmed and no a.task.pr & Reviewed)
  }
}

/* A5. Dropping `Now.issue.pr in Reviewed` from the rule turns this SAT. */
pred A5_ReviewRuleBlocksTheCollision {
  mergedOnCurrentReview and A4_ExecutorMergesItsOwnPR
}

/* =================== the record, and what it is worth =================== */

/* A9. The lifetime exercised rather than asserted. Its cost is A10. */
pred A9_RecordDiesWithTheDirectory {
  some a: Role {
    some a.peer                        -- a delegate's address is its --name
    eventually (reachable[a] and Now.ev = DeleteDir and Site.mach = a.host
                and after not reachable[a])
  }
}

/* A10. session/scenarios.als's R3 with the missing half supplied: the record names the
   working session and nothing reads it. */
pred A10_DeleteUnderRecordedExecutor {
  some c: Campaign, a: Role {
    some a.peer                        -- a session working its own claim
    a.task in c.members
    eventually (a in Live and reachable[a] and a in Local
                and Now.ev = DeleteDir and Site.mach = a.host)
  }
}

/* A11. Keying the gate on `no a.peer` instead of `reachable[a]` turns it SAT
   again. */
pred A11_ReadableGateBlocksTheDelete {
  noDeleteUnderReadableExecutor and A10_DeleteUnderRecordedExecutor
}

/* A12. UNSAT here would mean the directory could never be deleted at all. */
pred A12_ReadableGateAdmitsTheDelete {
  noDeleteUnderReadableExecutor
  some a: Role |
    eventually (reachable[a] and eventually (a not in Live and Now.ev = DeleteDir
                                             and Site.mach = a.host))
}

/* A6. The other chair. A confirmation checks that the work EXISTS, never that
   it is right, so with A4 this pair says the rule's subject is the review. */
pred A6_UnreviewedMerge {
  some c: Campaign, s: Session, a: Role {
    a.task in c.members
    s != a.peer
    always s.holds = c
    eventually (Now.ev = MergePR and By.actor = s and Now.issue = a.task
                and a in Confirmed and no a.task.pr & Reviewed)
  }
}

pred A7_ReviewRuleBlocksUnreviewed { mergedOnCurrentReview and A6_UnreviewedMerge }

/* A8. Control for A5 and A7: neither is green by forbidding merges. */
pred A8_ReviewRuleAdmitsTheLanding {
  mergedOnCurrentReview
  some c: Campaign, disj s1, s2: Session, a: Role {
    a.peer = s2 and a.task in c.members
    s1.smach = s2.smach and always s1.holds = c
    eventually (Now.ev = Report and Target.role = a)
    eventually (Now.ev = Confirm and By.actor = s1 and Target.role = a)
    eventually (Now.ev = Review and By.actor = s1 and Now.issue = a.task)
    eventually (Now.ev = MergePR and By.actor = s1 and Now.issue = a.task)
  }
}

/* A20. Stood is set by its event and by nothing else: unframed in any step,
   or uncleared at init, this goes SAT. */
pred A20_StoodOnlyByPosting {
  eventually some Stood
  always Now.ev != StoodDownPosted
}
/* The comment is never over local-only work: no trace posts it while Local. */
pred A19_StoodDownNeverLocal {
  eventually (Now.ev = StoodDownPosted and Target.role in Local)
}

/* A14. An executor whose record died is still retirable, on the confirmation
   alone. Restoring the `reachable` guard on `confirm` turns this UNSAT. */
pred A14_UnaddressedExecutorIsRetirable {
  resolveSilenceExternally and coLocatedShutdown
  some a: Role {
    some a.peer
    eventually (a not in Addressed and Now.ev = Confirm and Target.role = a)
    eventually (a not in Addressed and Now.ev = Retire and Target.role = a)
  }
}

/* A14b. And it cannot be stood down: `standDown` carries a message and
   nothing re-creates an address after the delete. So A14's ending is a
   stand-down taken while the record stood, or `retire`'s second disjunct. */
pred A14b_UnaddressedExecutorCannotBeStoodDown {
  A14_UnaddressedExecutorIsRetirable
  some a: Role {
    some a.peer
    eventually (a not in Addressed and Now.ev = StandDown and Target.role = a)
  }
}

/* A15. And its pull request still lands. Gating `confirm` on `reachable` made
   a record-less executor's work permanently unmergeable, which `gh pr merge`
   does not do. */
pred A15_UnaddressedExecutorPRLands {
  mergedOnCurrentReview
  some a: Role {
    some a.peer
    eventually (a not in Addressed and Now.ev = Confirm and Target.role = a)
    eventually (Now.ev = MergePR and Now.issue = a.task)
  }
}

/* A16. THE ONE-SESSION LANDING, admitted. Run at exactly one Session so the
   absence of a second merger is the scope and not an accident. */
pred A16_AuthorLandsOwnReviewedWork {
  mergedOnCurrentReview
  some s: Session, a: Role {
    a.peer = s
    eventually (Now.ev = Push and Target.role = a)
    eventually (Now.ev = Review and By.actor = s and Now.issue = a.task)
    eventually (Now.ev = Confirm and By.actor = s and Target.role = a)
    eventually (Now.ev = MergePR and By.actor = s and Now.issue = a.task)
  }
}

/* A16b. The author gets no special door. Letting `push` keep `Reviewed` turns
   this SAT, so the currency half of the rule is `push`'s clearing line. */
pred A16b_AuthorCannotMergeOnStaleReview {
  mergedOnCurrentReview
  some s: Session, a: Role {
    a.peer = s
    eventually (Now.ev = Review and Now.issue = a.task
                and after eventually (Now.ev = Push and Target.role = a
                                      and after ((always Now.ev != Review)
                                                 and eventually (Now.ev = MergePR
                                                                 and Now.issue = a.task))))
  }
}

/* A18. Hands-on work is no Role at all. It matters because the confirm
   conjunct ranges over `executorsOf[Now.issue]`, empty here, so it is
   VACUOUSLY true and the review half holds the rule up alone -- which A16,
   having an Role, cannot see. */
pred A18_RoleLessLandingIsAdmitted {
  mergedOnCurrentReview
  no Role
  some s: Session, i: Issue {
    eventually (Now.ev = Review  and By.actor = s and Now.issue = i)
    eventually (Now.ev = MergePR and By.actor = s and Now.issue = i)
  }
}

/* A18b. The direction a vacuous conjunct could have swallowed: weaken the
   review half as the confirm half is vacated here and hands-on work lands
   unreviewed with every rule obeyed. */
pred A18b_RoleLessUnreviewedMergeIsBlocked {
  mergedOnCurrentReview
  no Role
  always Now.ev != Review
  some i: Issue | eventually (Now.ev = MergePR and Now.issue = i)
}

/* A17. Seen live, no longer attributable: the pane proves the executor ALIVE
   and cannot say WHOSE CLAIM it is. */
pred A17_PaneSeesWhatTheRecordLost {
  some c: Campaign, a: Role {
    some a.peer
    a.task in c.members
    eventually (a in Live and liveUnderLocally[c, a.host]
                and not liveAndReadable[c, a.host])
  }
}

/* ---------------- commands ---------------- */

-- the whole retirement procedure runs
run Sanity                          for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Role, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps expect 1
-- a REPORT changes nothing durable
run ReportIsNotEvidence             for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Role, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 10 steps expect 1
-- BLOCKED stops the executor
run BlockedRoleDoesNotProceed      for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Role, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 10 steps expect 1
-- wait-for-the-answer strands a pane
run SilentAgentIsRetirableUnderWait for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Role, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps expect 0
-- rule 3's repair still retires it
run SilentAgentStillRetired         for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Role, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps expect 1

run S3_DelegateDiesAfterPushing for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Role, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps expect 1
run S4_ReportWithoutPush        for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Role, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps expect 1
run S9_OrphanedByLocalDelete    for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Session, exactly 1 Role, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps expect 1

-- a close over a delegate on M1
run R3b_CloseFromAnotherMachine  for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 1
-- the global rule would block it
run R3c_GlobalCloseRuleBlocks    for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 0

-- an acquire moves a live role's HEAD
run R4c_CheckoutSwitchedUnderRole for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 1 Machine, 3 Repo, 2 Topic, 1 Tree, 12 steps expect 1
-- what the numbered branch leaves
run R4e_NumberedBranchStillShared for 4 Issue, 1 PR, 1 Campaign, 2 Session, 2 Role, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps expect 1
-- the claim closes it
run R4f_ClaimClosesSameSubIssue    for 4 Issue, 1 PR, 1 Campaign, 2 Session, 2 Role, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps expect 0
-- control: the 422 is load-bearing
run R4g_ClaimWithoutAtomicityStillShared for 4 Issue, 1 PR, 1 Campaign, 2 Session, 2 Role, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps expect 1
-- the own-hands hole, the guard that closes it, and the control
run R4h_OwnHandsWorkWithoutClaim for 3 Issue, 1 PR, 1 Campaign, 1 Session, 1 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 1
run R4i_GuardClosesOwnHandsGap   for 3 Issue, 1 PR, 1 Campaign, 1 Session, 1 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 0
run R4j_GuardAdmitsClaimedWork   for 3 Issue, 1 PR, 1 Campaign, 1 Session, 1 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 1

-- the gap TwoStepShutdownSuffices rests on
run R5b_VisibleNotPushed         for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 1
-- co-location, not ownership, is the axis
run R5c_NonLauncherSameMachineIsFine for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps expect 1
-- a local release under a remote executor
run R6_ReleaseUnderRemoteRole   for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 1
-- a dangling claim is reclaimable
run R6b_ReclaimAfterDeath        for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 14 steps expect 1

/* A1 and A3 run at two roles, where the gap they measure was widest. A9-A12
   need a Tree to delete; A14-A15 need one to delete mid-trace. A16, A16b, A18
   and A18b run at exactly ONE Session, because the absence of a second merger
   is their subject. */
-- closed BY CONSTRUCTION: the claimant writes its own record, so no live claim is unattributable
run A1_UnrecordedExecutorAtTheClose          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 2 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 0
-- control: the whole run still happens
run A3_RecordedExecutorRunsTheWholeProtocol  for 3 Issue, 1 PR, 1 Campaign, 2 Session, 2 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps expect 1

-- the live collision: a self-merge with NO review
run A4_ExecutorMergesItsOwnPR                for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps expect 1
-- still caught, by what was missing
run A5_ReviewRuleBlocksTheCollision          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps expect 0
-- the same merge from the other chair
run A6_UnreviewedMerge                       for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 1
-- nobody merges unread
run A7_ReviewRuleBlocksUnreviewed            for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 0
-- control: two-session landing runs
run A8_ReviewRuleAdmitsTheLanding            for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps expect 1

-- the record has the tree's lifetime
run A9_RecordDiesWithTheDirectory            for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 1
-- session/scenarios.als's R3, reached from here
run A10_DeleteUnderRecordedExecutor          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 1
-- and closed by reading the record
run A11_ReadableGateBlocksTheDelete          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 0
-- control
run A12_ReadableGateAdmitsTheDelete          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 1
-- a push retires a review
run A13_PushAfterReviewUnReviews             for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps expect 1
-- a record dead with its directory still ends in a lawful retire
run A14_UnaddressedExecutorIsRetirable       for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps expect 1
-- and never a stand-down: that one carries a message, so it stays gated
run A14b_UnaddressedExecutorCannotBeStoodDown for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps expect 0
-- and its pull request still lands
run A15_UnaddressedExecutorPRLands           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 16 steps expect 1
-- the one-session landing
run A16_AuthorLandsOwnReviewedWork           for 3 Issue, 1 PR, 1 Campaign, 1 Session, 1 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps expect 1
-- and a push retires that permission
run A16b_AuthorCannotMergeOnStaleReview      for 3 Issue, 1 PR, 1 Campaign, 1 Session, 1 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps expect 0
-- attribution, not liveness, is the split's subject
run A17_PaneSeesWhatTheRecordLost            for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 1
-- hands-on work, reviewed and merged by one session, at `0 Role`
run A18_RoleLessLandingIsAdmitted           for 3 Issue, 1 PR, 1 Campaign, 1 Session, 0 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 1
-- and unreviewed it does not land. The pair matters because the confirm conjunct is VACUOUS at `0 Role`, so the review half holds the rule up alone
run A18b_RoleLessUnreviewedMergeIsBlocked   for 3 Issue, 1 PR, 1 Campaign, 1 Session, 0 Role, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 0

-- the floor's two negative controls
run A19_StoodDownNeverLocal for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 0
run A20_StoodOnlyByPosting  for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 0
