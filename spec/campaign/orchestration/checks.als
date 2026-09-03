/*
 * What must hold of orchestration/system, and the floor that says its events are
 * reachable at all. github/system.als is spec/'s entry point.
 */
module orchestration/checks

open orchestration/scenarios

/* ---------------- properties ---------------- */

/* Nothing written in THIS file carries it, so it tests the composition idiom:
   dropping `githubFrame` from github/system's fall-through branch reddens it. */
assert NoLostWork {
  always all i: Issue |
    (complete[i] and Now.event in AgentDie + DeleteDir) implies after complete[i]
}

/* The counterexample: two machines hold the campaign, the agent is live on
   one, the tree is deleted from the other. The rule is a local check blind to
   the other machine. */
pred noOrphanNow {
  all a: Agent | a in Live implies (some c: Campaign | a.task in c.memberIssues and a.host in machinesHolding[c])
}

assert NoOrphan { always noOrphanNow }

// Dropping the RemoveMember clause reddens it.
assert NoOrphanIfGuarded {
  ((always (Now.event = DeleteDir implies (no a: Agent | a in Live and a.host = Where.machine)))
   and (always (Now.event = RemoveMember implies (no a: Agent | a in Live and a.task = Now.issue))))
  implies (always noOrphanNow)
}

/* A REPORT says nothing about a change made after it. Its counterexample also
   refutes the unguarded protocol, which is why that has no command of its own. */
assert OneStepShutdownSuffices { oneStepShutdown implies noWorkDestroyed }

/* THE REMOTE HOLE: step 2 run from the wrong machine. R5b and R5c pin its
   axis. */
assert TwoStepShutdownSuffices { twoStepShutdown implies noWorkDestroyed }

/* `Confirmed` cleared by any later `work` is what makes this green survive an
   agent that keeps working after being confirmed. */
assert TwoStepCoLocatedSuffices {
  (twoStepShutdown and coLocatedShutdown) implies noWorkDestroyed
}

/* Dropping the ANSWER is safe as long as the confirmation is kept and read on
   the right machine. */
assert SilenceResolutionStaysSafe {
  (resolveSilenceExternally and coLocatedShutdown) implies noWorkDestroyed
}

/* ---------------- reachability floor ---------------- */

pred Cov_LaunchAgent      { eventually (Now.event = Launch and some Target.agent) }
pred Cov_Work             { eventually Now.event = Work }
pred Cov_Push             { eventually Now.event = Push }
pred Cov_Status           { eventually Now.event = Status }
pred Cov_Answer           { eventually Now.event = Answer }
pred Cov_Report           { eventually Now.event = Report }
pred Cov_Blocked          { eventually Now.event = Blocked }
pred Cov_Decide           { eventually Now.event = Decide }
pred Cov_Confirm          { eventually Now.event = Confirm }
pred Cov_ConfirmElsewhere { eventually Now.event = ConfirmElsewhere }
pred Cov_Review           { eventually Now.event = Review }
pred Cov_StandDown        { eventually Now.event = StandDown }
pred Cov_StoodDownPosted  { eventually Now.event = StoodDownPosted }
pred Cov_Retire           { eventually Now.event = Retire }
pred Cov_AgentDie         { eventually Now.event = AgentDie }
pred Cov_GuardedRelease   { eventually Now.event = Release }

/* ---------------- commands ---------------- */

-- a death or a delete never un-completes
check NoLostWork        for 3 Issue, 2 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 2 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 0
-- nothing enforces the retirement rule
check NoOrphan          for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 2 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
-- it does hold once enforced
check NoOrphanIfGuarded for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 2 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 0

-- the defect the design records
check OneStepShutdownSuffices    for 2 Issue, 1 PullRequest, 1 Campaign, 2 Session, 2 Agent, 2 Machine, 2 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
-- two steps run from the wrong machine
check TwoStepShutdownSuffices    for 2 Issue, 1 PullRequest, 1 Campaign, 2 Session, 2 Agent, 2 Machine, 2 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
-- the contract as AGENTS.md states it
check TwoStepCoLocatedSuffices   for 2 Issue, 1 PullRequest, 1 Campaign, 2 Session, 2 Agent, 2 Machine, 2 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 0
-- rule 3's repair reopens nothing
check SilenceResolutionStaysSafe for 2 Issue, 1 PullRequest, 1 Campaign, 2 Session, 2 Agent, 2 Machine, 2 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 0

-- every own event fires in some trace
run Cov_LaunchAgent      for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
run Cov_Work             for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
run Cov_Push             for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
run Cov_Status           for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
run Cov_Answer           for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
run Cov_Report           for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
run Cov_Blocked          for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
run Cov_Decide           for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
run Cov_Confirm          for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
run Cov_ConfirmElsewhere for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
run Cov_Review           for 3 Issue, 2 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 12 steps expect 1
run Cov_StandDown        for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
run Cov_StoodDownPosted  for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
run Cov_Retire           for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
run Cov_AgentDie         for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
run Cov_GuardedRelease   for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
