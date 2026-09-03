/*
 * What must hold of role/system, and the floor that says its events are
 * reachable at all. github/system.als is spec/'s entry point.
 */
module role/checks

open role/scenarios

/* ---------------- properties ---------------- */

/* Nothing written in THIS file carries it, so it tests the composition idiom:
   dropping `githubFrame` from github/system's fall-through branch reddens it. */
assert NoLostWork {
  always all i: Issue |
    (complete[i] and Now.ev in RoleDie + DeleteDir) implies after complete[i]
}

/* The counterexample: two machines hold the campaign, the executor is live on
   one, the tree is deleted from the other. The rule is a local check blind to
   the other machine. */
pred noOrphanNow {
  all a: Role | a in Live implies (some c: Campaign | a.task in c.members and a.host in dirsOf[c])
}

assert NoOrphan { always noOrphanNow }

// Dropping the RemoveMember clause reddens it.
assert NoOrphanIfGuarded {
  ((always (Now.ev = DeleteDir implies (no a: Role | a in Live and a.host = Site.mach)))
   and (always (Now.ev = RemoveMember implies (no a: Role | a in Live and a.task = Now.issue))))
  implies (always noOrphanNow)
}

/* A REPORT says nothing about a change made after it. Its counterexample also
   refutes the unguarded protocol, which is why that has no command of its own. */
assert OneStepShutdownSuffices { oneStepShutdown implies noWorkDestroyed }

/* THE REMOTE HOLE: step 2 run from the wrong machine. R5b and R5c pin its
   axis. */
assert TwoStepShutdownSuffices { twoStepShutdown implies noWorkDestroyed }

/* `Confirmed` cleared by any later `work` is what makes this green survive an
   executor that keeps working after being confirmed. */
assert TwoStepCoLocatedSuffices {
  (twoStepShutdown and coLocatedShutdown) implies noWorkDestroyed
}

/* Dropping the ANSWER is safe as long as the confirmation is kept and read on
   the right machine. */
assert SilenceResolutionStaysSafe {
  (resolveSilenceExternally and coLocatedShutdown) implies noWorkDestroyed
}

/* ---------------- reachability floor ---------------- */

pred Cov_LaunchRole      { eventually (Now.ev = Launch and some Target.role) }
pred Cov_Work             { eventually Now.ev = Work }
pred Cov_Push             { eventually Now.ev = Push }
pred Cov_Status           { eventually Now.ev = Status }
pred Cov_Answer           { eventually Now.ev = Answer }
pred Cov_Report           { eventually Now.ev = Report }
pred Cov_Blocked          { eventually Now.ev = Blocked }
pred Cov_Decide           { eventually Now.ev = Decide }
pred Cov_Confirm          { eventually Now.ev = Confirm }
pred Cov_ConfirmElsewhere { eventually Now.ev = ConfirmElsewhere }
pred Cov_Review           { eventually Now.ev = Review }
pred Cov_StandDown        { eventually Now.ev = StandDown }
pred Cov_StoodDownPosted  { eventually Now.ev = StoodDownPosted }
pred Cov_Retire           { eventually Now.ev = Retire }
pred Cov_RoleDie         { eventually Now.ev = RoleDie }
pred Cov_GuardedRelease   { eventually Now.ev = Release }

/* ---------------- commands ---------------- */

-- a death or a delete never un-completes
check NoLostWork        for 3 Issue, 2 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps expect 0
-- nothing enforces the retirement rule
check NoOrphan          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps expect 1
-- it does hold once enforced
check NoOrphanIfGuarded for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps expect 0

-- the defect the design records
check OneStepShutdownSuffices    for 2 Issue, 1 PR, 1 Campaign, 2 Session, 2 Role, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps expect 1
-- two steps run from the wrong machine
check TwoStepShutdownSuffices    for 2 Issue, 1 PR, 1 Campaign, 2 Session, 2 Role, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps expect 1
-- the contract as AGENTS.md states it
check TwoStepCoLocatedSuffices   for 2 Issue, 1 PR, 1 Campaign, 2 Session, 2 Role, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps expect 0
-- rule 3's repair reopens nothing
check SilenceResolutionStaysSafe for 2 Issue, 1 PR, 1 Campaign, 2 Session, 2 Role, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps expect 0

-- every own event fires in some trace
run Cov_LaunchRole      for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_Work             for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_Push             for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_Status           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_Answer           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_Report           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_Blocked          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_Decide           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_Confirm          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_ConfirmElsewhere for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_Review           for 3 Issue, 2 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 1
run Cov_StandDown        for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_StoodDownPosted  for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_Retire           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_RoleDie         for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_GuardedRelease   for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Role, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
