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

/* The three claims the Role docstring makes, one command each, since a fact
   or a guard deleted is invisible to the snapshot. Dropping `a.role = Executor`
   from `work` reddens the first, from `report` the second; deleting the
   `some a.peer` fact in AgentWellFormed reddens the third. */
assert PlannerNeverLocalOnly { always no plannerAgents & LocalOnly }
assert PlannerNeverReports   { always no plannerAgents & Reported }
assert PlannerIsASession     { all a: plannerAgents | some a.peer }

/* The two planes do not overlap, which is what makes `planeOf` `lone` rather
   than a coincidence of the current event lists. Moving an event into both
   lists reddens it. */
assert DisjointPlanes { no campaignPlaneEvents & codePlaneEvents }

/* #185's rule subsumes #177's: a session permitted to work an issue holds a
   claim on it, so `claimBeforeWork` needs no separate statement once
   `permissionByRole` holds. Dropping `i in s.claimedIssues` from `mayAct`'s
   code-plane row reddens it. Q5 is the control that the subsumption is not by
   forbidding work altogether. */
assert PermissionImpliesClaimGates { permissionByRole implies claimBeforeWork }

/* ATTRIBUTION, AND WHAT DERIVING IT COSTS. `holder` reads the claim's owner
   off the checkout, so a live agent is its own task's holder exactly while the
   checkout stays on its branch. `Acquire` is what moves one, and nothing
   forbids moving it under a live agent -- R4c is that trace and A17 is the
   state it leaves. Stated as a property rather than a fact because the fact
   would forbid R4c and call the silence safety. */
assert AttributionIsSound { always all a: Live | a in holder[a.task] }

/* The repair, and THREE events have to be refused, each of which un-names the
   holder a different way. `Acquire` moves the checkout out from under the
   agent -- R4c. `DeleteDir` takes the checkout away with the tree -- A10, and
   `noDeleteUnderLiveAgent` is the gate A11 already measures. `RemoveMember`
   empties `campaignOf`, so there is no campaign directory left to read a
   checkout in and the holder set goes empty with the checkout untouched.
   Each conjunct was found by dropping it and reading the counterexample, and
   deleting any one of the three reddens the check below. */
pred holderStaysAttributed {
  always (Now.event = Acquire implies
            no a: Agent | a in Live and a.host = Where.machine
                          and a in holder[a.task] and a.task.repo = Where.repo)
  always (Now.event = RemoveMember implies
            no a: Agent | a in Live and a.task = Now.issue)
  noDeleteUnderLiveAgent
}
assert AttributionIsSoundIfCheckoutHeld {
  holderStaysAttributed implies (always all a: Live | a in holder[a.task])
}

/* Every delegate was launched by its planner: the launching session holds a
   Planner atom on the delegate's sub-issue. Dropping the planner conjunct from
   `launch` reddens it; P2 in scenarios is the control that delegates still
   launch. */
assert DelegateLaunchedByPlanner {
  always all a: Launched | no a.peer implies
    (some p: plannerAgents | p.peer = a.launcher and p.task = a.task)
}

/* ---------------- reachability floor ---------------- */

pred Cov_LaunchAgent      { eventually (Now.event = Launch and some Target.agent) }
pred Cov_LaunchDelegate   { eventually (Now.event = Launch and no Target.agent.peer) }
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

-- what a planner does not share: the work bit, the REPORT, and being a delegate
check PlannerNeverLocalOnly for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 10 steps expect 0
check PlannerNeverReports   for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 10 steps expect 0
check PlannerIsASession     for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 10 steps expect 0
check DisjointPlanes for 1 Issue, 1 PullRequest, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 1 Repo, 1 Branch, 1 CampaignDir, 1 steps expect 0
check PermissionImpliesClaimGates for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 10 steps expect 0
-- every delegate has a planner behind its launch
check DelegateLaunchedByPlanner       for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 2 Repo, 1 Branch, 1 CampaignDir, 10 steps expect 0

-- the derived attribution is NOT sound on its own: an acquire moves the checkout out from under a live agent
check AttributionIsSound              for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 2 Branch, 1 CampaignDir, 10 steps expect 1
-- and it is once the acquire is refused
check AttributionIsSoundIfCheckoutHeld for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 2 Branch, 1 CampaignDir, 10 steps expect 0

-- every own event fires in some trace
run Cov_LaunchAgent      for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
-- a delegate launch needs the planner atom beside it, so this runs at 2 Agent
run Cov_LaunchDelegate   for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 2 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
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
run Cov_Retire           for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
run Cov_AgentDie         for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
run Cov_GuardedRelease   for 3 Issue, 1 PullRequest, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
