/*
 * The executor: launch, work, the four messages, retirement -- and the whole
 * composition, since this is the top layer.
 *
 * ledger.als is spec/'s entry point and carries the orientation to all four
 * layers and the composition idiom. Running this file exercises all four at
 * once; running the other three exercises each on its own.
 *
 *
 * THIS LAYER
 *
 * How a campaign session and the executors it launched talk to each other.
 * Normative. AGENTS.md carries the short form -- four messages and the two-step
 * shutdown; this file is the whole contract, and the parts of it that can be
 * checked are checked below rather than asserted in prose.
 *
 *   event             performed by
 *   Launch (executor) the `claude --session-id ... --name campaign-<N>-<issue>-<topic>`
 *                     that starts an executor on the claim its launcher made
 *   Work              the executor edits its checkout
 *   Push              git push -- the one act that makes work survivable
 *   Status            STATUS, campaign -> executor
 *   Answer            the executor's reply to an outstanding STATUS
 *   Report            REPORT, executor -> campaign, unsolicited
 *   Blocked           BLOCKED, executor -> campaign, unsolicited
 *   Decide            the campaign session answers a BLOCKED
 *   Confirm           the session reads the executor's working tree ITSELF
 *   ConfirmElsewhere  the same check run from the wrong machine -- the defect
 *   StandDown         STAND DOWN, campaign -> executor
 *   Retire            the workspace is destroyed
 *   Release (guard)   what may be released: this layer's half of repos.als's event
 *   AgentDie          the process dies on its own
 *
 * `Agent` here is an EXECUTOR of a subtask, addressed by the name given at
 * launch. Nothing below assumes it is a herdr pane rather than, say, a peer
 * session that claimed the branch itself: `launcher` records which session put
 * it there, and `standDown` and `retire` are guarded by the disciplines below
 * rather than by anything about how the executor is hosted.
 *
 *
 * WHAT THE PROTOCOL IS FOR
 *
 * Three systems already answer questions about an executor, and each answers a
 * different one:
 *
 *   question                              answered by   why not the others
 *   is the work finished?                 GitHub        survives the executor,
 *                                                       the pane and the machine
 *   is the process alive?                 herdr         knows nothing about the
 *                                                       work
 *   what is it doing, and what is it       the executor  nothing else can see
 *   waiting for?                          itself        intent or an unasked
 *                                                       question
 *
 * The protocol carries ONLY the third. A message that repeats a GitHub fact or
 * a herdr fact adds a second copy of something already true elsewhere, and the
 * copy is what goes stale. This is the whole design constraint, and it is why
 * `report` below writes no durable state at all.
 *
 *
 * TRANSPORT
 *
 * The harness's own peer messaging, addressed by the name given at launch
 * (claude --name, the branch with its slash flattened:
 * campaign-<N>-<issue>-<topic>). ListAgents resolves that name; herdr's pane
 * label is not an address.
 *
 * Two properties make it the right transport and both are load-bearing:
 *   - It is not the terminal screen. Reading a pane gives whatever happens to
 *     be rendered, capped by the emulator's buffer; a message is delivered and
 *     queued.
 *   - It carries no state. Every exchange is a fresh question and a fresh
 *     answer, so a campaign session that died and restarted talks to its
 *     executors with no handover, and a second machine's session can do the
 *     same.
 *
 *
 * RETIREMENT, AND WHY THE PROTOCOL EXISTS AT ALL
 *
 * An executor does not close itself. It finishes by pushing its branch and
 * opening or updating a pull request, then goes quiet. The campaign session
 * retires it once the work is durable -- the branch pushed, the pull request
 * open. It deliberately does not wait for the merge: review can take days, and
 * a pane held open across them is the expensive thing. Review feedback gets a
 * fresh session, briefed from the pull request.
 *
 * In a long-lived campaign subtasks finish continuously while the campaign
 * stays open, so retirement cannot wait for the close. The procedure is four
 * steps, and `twoStepShutdown` plus `coLocatedShutdown` below are steps 2 and 3
 * written as disciplines the model can check:
 *
 *   1. STATUS every executor under the campaign tree.
 *   2. For each that says it is finished: confirm in GitHub, and against the
 *      working tree, that nothing it holds exists only on this machine.
 *   3. STAND DOWN the confirmed ones. Leave the rest, and say why.
 *   4. Retire the workspace once the executor has acknowledged.
 *
 * Self-termination is refused for one reason: the only thing that can verify an
 * executor's work is something other than that executor.
 *
 *
 * ONE ENCODING OF "ONLY ON THIS MACHINE"
 *
 * `Local` is it, and it is the whole of it. The predecessors had four -- an
 * issue with no pull request while an agent was live, `Visible`, `Pushed`, and
 * `Local` -- and a widening had to be applied in two files at once because of
 * it. `Visible` is kept because it is a genuinely different fact, readable from
 * a different place: the branch is on the remote. The two are independent and
 * their gap is the finding R5b names -- an executor whose branch is on the
 * remote may still hold work that is not.
 *
 * `Idle` is gone. Its one claim -- "the agent went idle" is not completion --
 * is carried by ReportIsNotEvidence below, which says the same thing about the
 * stronger signal: not even an explicit REPORT moves a GitHub fact.
 *
 *
 * UNMODELLED, STATED FOR THE RECORD
 *
 * Three rules of the contract have no construct here, because each is a fact
 * about the message medium rather than about reachable states:
 *   - The executor answers about itself only. It does not report on siblings,
 *     the campaign, or whether an issue should close.
 *   - No new state. The protocol keeps no file, no log and no registry. Every
 *     exchange stands alone, which is what lets a restarted or second-machine
 *     campaign session speak to the same executors.
 *   - STAND DOWN is a request, not an order. Whoever types into the executor's
 *     pane is its user; the campaign session reaches it as a peer, and a peer
 *     cannot command. An executor with a contradicting instruction from its own
 *     pane is right to refuse. Treat a refusal as information about a conflict,
 *     not as disobedience, and resolve the conflict at the pane.
 *
 * Deliberately absent from the protocol itself:
 *   - No self-termination, for the reason above.
 *   - No heartbeat. Liveness is already a herdr fact; a heartbeat would be a
 *     second, worse copy of it that also stops when the executor is merely busy.
 *   - No task assignment message. The handover brief is a file, because the
 *     launch line has a 1024-byte ceiling and a brief must be readable
 *     afterwards.
 *
 * The three execution modes -- doing the subtask here, an in-process subagent on
 * a worktree, a herdr delegate in a clone -- are one `Launch` here on purpose.
 * The reasons for the choice are in AGENTS.md and no construct below
 * distinguishes them, because nothing a model can say about reachable states
 * differs between them: the branch is the same claim, the completion is the same
 * GitHub fact, and the only differences are turn cost and whether a process
 * boundary is crossed.
 *
 * And one open risk, named rather than solved: retiring at "pull request open"
 * means nobody is watching the review. Until a board exists, the person is the
 * one who notices.
 *
 *
 * VERDICTS
 *
 * Measured 2026-08-28 against this file. X is a counterexample; a check that
 * passes reads UNSAT.
 *
 *   NoLostWork                       pass  a death or a delete never un-completes
 *   NoOrphan                         X     nothing enforces the retirement rule
 *   NoOrphanIfGuarded                pass  it does hold once enforced
 *   UnguardedShutdownIsUnsafe        X     the baseline: work is destroyed
 *   OneStepShutdownSuffices          X     the defect the design records
 *   TwoStepShutdownSuffices          X     two steps run from the wrong machine
 *   TwoStepCoLocatedSuffices         pass  the contract as AGENTS.md states it
 *   SilenceResolutionStaysSafe       pass  rule 3's repair reopens nothing
 *   Sanity                           SAT   the whole retirement procedure runs
 *   ReportIsNotEvidence              SAT   a REPORT changes nothing durable
 *   BlockedAgentDoesNotProceed       SAT   BLOCKED stops the executor
 *   SilentAgentIsRetirableUnderWait  UNSAT wait-for-the-answer strands a pane
 *   SilentAgentStillRetired          SAT   rule 3's repair still retires it
 *   S3_DelegateDiesAfterPushing      SAT
 *   S4_ReportWithoutPush             SAT
 *   S9_OrphanedByLocalDelete         SAT
 *   R3b_CloseFromAnotherMachine      SAT   a close over a delegate on M1
 *   R3c_GlobalCloseRuleBlocks        UNSAT the global rule would block it
 *   R4_SameBranchTwice               SAT   two delegates, one branch
 *   R4b_CrossCampaignCoexists        SAT   control: campaign-<N> still separates
 *   R4c_CheckoutSwitchedUnderAgent   SAT   an acquire moves a live agent's HEAD
 *   R4d_SameSubtaskTwice             SAT
 *   R4e_NumberedBranchStillShared    SAT   what the numbered branch leaves
 *   R4f_ClaimClosesSameSubtask       UNSAT the claim closes it
 *   R4g_ClaimWithoutAtomicityStillShared SAT control: the 422 is load-bearing
 *   R5b_VisibleNotPushed             SAT   the gap R5's finding rests on
 *   R5c_NonLauncherSameMachineIsFine SAT   co-location, not ownership, is the axis
 *   R6_ReleaseUnderRemoteAgent       SAT   a local release under a remote executor
 *   R6b_ReclaimAfterDeath            SAT   a dangling claim is reclaimable
 *   Cov_*                            SAT   every own event fires in some trace
 *
 * Every green was proved able to fail, re-run 2026-08-28 against this model:
 * letting `work` keep an earlier confirmation instead of clearing it reddens
 * TwoStepCoLocatedSuffices and SilenceResolutionStaysSafe; narrowing
 * `coLocatedShutdown` to the stand-down alone reddens TwoStepCoLocatedSuffices;
 * dropping the RemoveMember clause reddens NoOrphanIfGuarded; and dropping
 * `ledgerFrame` from ledger.als's fall-through branch reddens NoLostWork --
 * which is the point of the layering, since nothing written in THIS file holds
 * a GitHub fact still while an executor dies.
 *
 *
 * TWO FINDINGS THE COMPOSITION PRODUCED
 *
 * Both are cases that were in no previous file, because each needs two things
 * the old split kept apart. They are stated here rather than filed away because
 * each changed a construct.
 *
 *   Several sessions x the protocol. `coLocatedShutdown` used to constrain the
 *   stand-down and the retire; with one session that is the whole of it, and
 *   with several it is not. A session on another machine runs the confirmation,
 *   a session on the executor's machine acts on it, and the retire destroys
 *   work: TwoStepCoLocatedSuffices measured X. The discipline now covers the
 *   confirmation too, which is what steps 2 and 3 of the retirement procedure
 *   already meant, and the verdict is back to pass. See `coLocatedShutdown`.
 *
 *   A subtask moved out of a campaign under a live executor. `liveUnder` reads
 *   membership OR co-location, so removing the subtask and deleting the tree
 *   turns the global close rule permissive again. The several-sessions model had
 *   no remove event and could not state it. R3c is scoped to traces without one
 *   and reproduces its UNSAT; the evasion is named beside it.
 *
 * WHAT MOVED, AND WHAT CHANGED WITH IT
 *
 *   R5_RemoteStandDownLosesWork is gone as a separate run: it is
 *   TwoStepShutdownSuffices' counterexample stated twice. Its write-up is beside
 *   that assertion, and its two controls (R5b, R5c) are kept because they pin
 *   the axis.
 *
 *   IdleImpliesComplete is gone as a separate check, merged into
 *   ReportIsNotEvidence -- see ONE ENCODING above.
 *
 *   Every command here carries a Session, because an executor is launched by
 *   one. The predecessors that had no session had no launcher either, and gave
 *   their agents to `init`. The bounds below pay for it in atoms rather than in
 *   steps: a session may already hold a campaign at time zero.
 */
module agent

open session

/* ==================== SYSTEM ==================== */

/* ---------------- static structure ---------------- */

sig Agent {
  task:     one Issue,          -- the member issue it works
  host:     one Machine,        -- the machine whose checkout it runs in
  launcher: one Session,        -- the session that put it there
  topic:    one Topic           -- the <topic> half of its branch
}

var sig Launched in Agent {}    -- an executor exists, or existed, for this claim
var sig Live     in Agent {}    -- it can still act
var sig Local    in Agent {}    -- it holds work that exists ONLY on its host:
                                -- uncommitted, unpushed, or on a branch no
                                -- remote has. THE one encoding of that.
var sig Visible  in Agent {}    -- its branch is on the remote: checkable from
                                -- anywhere, and a different fact from Local
var sig Reported in Agent {}    -- has sent REPORT: a claim, and nothing else
var sig Asked    in Agent {}    -- a STATUS is outstanding
var sig Answered in Agent {}    -- it answered the outstanding STATUS
var sig Waiting  in Agent {}    -- has sent BLOCKED and is waiting on a decision
var sig Confirmed in Agent {}   -- the SESSION has itself observed that this
                                -- executor holds nothing local-only
var sig StoodDown in Agent {}   -- STAND DOWN sent and acknowledged
var sig Retired  in Agent {}    -- the workspace is gone

/* This layer's observer: which executor the event is about. */
one sig Target { var agent: lone Agent }

fact AgentWellFormed {
  all c: Campaign | c.anchor not in Agent.task
  always Live in Launched
  always Retired in Launched
  always no Live & Retired
  always Visible in Visible'     -- a branch on the remote stays on the remote
}

/* A session on the executor's own machine, versus one that is not. */
pred coLocated[s: Session, a: Agent] { s.smach = a.host }

pred liveUnder[c: Campaign] {
  some a: Agent | a in Live and (a.task in c.members or a.host in dirsOf[c])
}
/* What one session can actually read: `herdr agent list` on its own machine. */
pred liveUnderLocally[c: Campaign, m: Machine] {
  some a: Agent | a in Live and a.host = m and (a.task in c.members or m in dirsOf[c])
}
/* ledger's `closable` is the GitHub half -- what scripts/campaign-settlement
   prints, and all it can see. These two add the half that needs an executor. */
pred closableWithAgents[c: Campaign]        { closable[c] and not liveUnder[c] }
pred closableLocally[s: Session, c: Campaign] { closable[c] and not liveUnderLocally[c, s.smach] }

/* The branch an executor works, in the form the design carried when R4 below
   was found: campaign-<N>/<topic>. Two executors share it when the campaign and
   the topic match -- true by definition of the name, not by proof. */
/* BRANCH NAMES CANNOT COLLIDE ACROSS CAMPAIGNS, even though the container
   shares one number sequence between its anchors and its subtasks.
   campaign-<N>/<issue>-<topic> collides only on an equal <N> and <issue> pair.
   An issue has at most one parent, so a subtask maps to exactly one campaign
   number; two subtasks of one campaign have different numbers; and sharing a
   sequence with the anchor HELPS, because it makes <issue> and <N> distinct
   integers rather than allowing them to coincide. The collision case cannot be
   constructed -- which is why what R4 finds below is intra-campaign, and only
   that. */
pred sameBranchByTopic[a1, a2: Agent] {
  campaignOf[a1.task] = campaignOf[a2.task] and a1.topic = a2.topic
}

/* The form AGENTS.md adopted in answer to R4: campaign-<N>/<issue>-<topic>. The
   subtask's issue number joins the campaign number, so two executors share a
   branch only when campaign, subtask and topic all match. That it separates two
   subtasks is definitional and is not run; what R4e asks is what it leaves. */
pred sameBranch[a1, a2: Agent] {
  campaignOf[a1.task] = campaignOf[a2.task]
  and a1.task = a2.task
  and a1.topic = a2.topic
}

/* ---------------- observable events ---------------- */

one sig Work, Push, Status, Answer, Report, Blocked, Decide,
        Confirm, ConfirmElsewhere, StandDown, Retire, AgentDie extends Event {}

fun agentOwn: set Event {
  Work + Push + Status + Answer + Report + Blocked + Decide
  + Confirm + ConfirmElsewhere + StandDown + Retire + AgentDie
}
fun agentActed: set Event { agentOwn + Launch + Release }

pred keepClaims   { Reported' = Reported and Asked' = Asked and Answered' = Answered and Waiting' = Waiting }
pred keepShutdown { StoodDown' = StoodDown and Retired' = Retired }
pred keepWork     { Live' = Live and Local' = Local and Visible' = Visible and Confirmed' = Confirmed }
pred keepBorn     { Launched' = Launched }
pred agentFrame   { keepWork and keepClaims and keepShutdown and keepBorn }

/* The executor's half of a launch. It needs the claim -- the branch exists on
   the remote, created by create-ref before any executor started -- and the
   checkout, on the topic that is its branch. That its launcher is the session
   that made the claim is `claimBeforeLaunch` below, a discipline rather than a
   guard, because a launch that skips claiming is exactly what R4e is about. */
pred launch[a: Agent] {
  Now.ev = Launch
  a not in Launched
  a.launcher = By.actor
  a.host = Site.mach
  Now.issue = a.task
  a.task in Claimed
  treeAt[By.actor.holds, a.host].co[a.task.home] = a.topic
  Launched' = Launched + a
  Live'     = Live + a
  Local' = Local and Visible' = Visible and Confirmed' = Confirmed
  keepClaims and keepShutdown
  Target.agent = a
}

/* The executor produces work that exists only on its own disk. Note what this
   clears: a confirmation the session made earlier is no longer true, so it is
   dropped here rather than at the point it is read. A stale green is worse than
   no green. */
pred work[a: Agent] {
  a in Live and a not in Waiting
  Local' = Local + a
  Confirmed' = Confirmed - a
  Live' = Live and Visible' = Visible
  keepClaims and keepShutdown and keepBorn
  Now.ev = Work and Now.issue = a.task and Target.agent = a and no By.actor
}

/* The one rule that makes a tree deleted under a live executor survivable: it
   pushes as soon as it has one commit, so what a lost workspace costs is
   uncommitted work and nothing more. Pushing puts the branch on the remote and
   clears the local-only work -- two different facts, and only the first is
   readable from another machine. It does not set Confirmed: the session has not
   looked yet, and nothing here lets it believe without looking. */
pred push[a: Agent] {
  a in Live and a in Local
  Local'   = Local - a
  Visible' = Visible + a
  Live' = Live and Confirmed' = Confirmed
  keepClaims and keepShutdown and keepBorn
  Now.ev = Push and Now.issue = a.task and Target.agent = a and no By.actor
}

/* STATUS -- campaign to executor.

   Asks four questions. The executor answers all four, in order, even when the
   answer is "nothing".

     1. What are you doing right now, or are you finished?
     2. Is anything blocking you or waiting on a decision that is not yours?
     3. Does any of your work exist only on this machine -- uncommitted,
        unpushed, or on a branch no remote has?
     4. Can you be shut down safely?

   Question 3 is the one the protocol exists for. A tree deleted under a live
   executor destroys exactly that work and nothing else can see it.

   STATUS queues behind the executor's current turn; it does not interrupt. A
   busy executor answers when its turn ends, which on a long turn is minutes.
   That makes a late reply ordinary rather than a symptom, and it is why asking
   and answering are two events here and why rule 3 exists. */
pred status[a: Agent] {
  a.task in By.actor.holds.members
  Asked' = Asked + a
  Answered' = Answered - a
  Reported' = Reported and Waiting' = Waiting
  keepWork and keepShutdown and keepBorn
  Now.ev = Status and Now.issue = a.task and Target.agent = a
}

/* Only a live executor answers. A gone one leaves the question outstanding
   forever, which is the whole of rule 3. */
pred answer[a: Agent] {
  a in Live and a in Asked
  Answered' = Answered + a
  Asked' = Asked and Reported' = Reported and Waiting' = Waiting
  keepWork and keepShutdown and keepBorn
  Now.ev = Answer and Now.issue = a.task and Target.agent = a and no By.actor
}

/* REPORT -- executor to campaign, unsolicited.

   Sent once, when it has pushed a branch and opened or updated a pull request.
   It names the pull request URL and stops.

   A report is a prompt to verify, never the verification. The campaign session
   reads GitHub before believing it. An executor asserting it is finished is the
   delegate verifying its own work, which is the one thing the design refuses --
   so this event writes NOTHING but the claim itself. Everything a command below
   cares about is untouched by it, and that is the model's statement of rule 1.

   A REPORT names a URL, which makes fabrication cheap to disprove; a false one
   was caught in about two seconds by four independent checks. But the rule
   catches fabrication, not inadequacy: a real pushed branch with a real pull
   request that does not do what was asked passes every check. Verifying that the
   work exists is not reviewing it. */
pred report[a: Agent] {
  a in Live
  Reported' = Reported + a
  Asked' = Asked and Answered' = Answered and Waiting' = Waiting
  keepWork and keepShutdown and keepBorn
  Now.ev = Report and Now.issue = a.task and Target.agent = a and no By.actor
}

/* BLOCKED -- executor to campaign, unsolicited.

   Sent when it needs a decision that is not its to make. It names the decision
   and the options, and then it stops rather than guessing -- which is why `work`
   above refuses to fire while Waiting holds.

   Silence is not this message. An executor that stops without sending it looks
   identical to one that is thinking. */
pred blocked[a: Agent] {
  a in Live and a not in Waiting
  Waiting' = Waiting + a
  Reported' = Reported and Asked' = Asked and Answered' = Answered
  keepWork and keepShutdown and keepBorn
  Now.ev = Blocked and Now.issue = a.task and Target.agent = a and no By.actor
}

pred decide[a: Agent] {
  a in Waiting
  a.task in By.actor.holds.members
  Waiting' = Waiting - a
  Reported' = Reported and Asked' = Asked and Answered' = Answered
  keepWork and keepShutdown and keepBorn
  Now.ev = Decide and Now.issue = a.task and Target.agent = a
}

/* The campaign session reads the executor's working tree ITSELF.

   State the check as an absence: no uncommitted changes, no unpushed commits,
   no branch absent from the remote. "Confirm the branch is pushed and the pull
   request is open" has no passing form for an executor that correctly produced
   nothing durable, and a campaign session following it literally is stuck with
   nothing to verify. What is always checkable is the inverse, and that is the
   `a not in Local` guard here. */
pred confirm[a: Agent] {
  coLocated[By.actor, a]
  a.task in By.actor.holds.members
  a not in Local
  Confirmed' = Confirmed + a
  Live' = Live and Local' = Local and Visible' = Visible
  keepClaims and keepShutdown and keepBorn
  Now.ev = Confirm and Now.issue = a.task and Target.agent = a
}

/* The same check run from another machine. It reads the SESSION's working tree,
   not the executor's, so it comes back clean whatever the executor holds --
   there is no `a not in Local` guard here because there is nothing on this
   machine that could fail it. That is not a modelling shortcut; it is the
   defect, and TwoStepShutdownSuffices below is where it surfaces. */
pred confirmElsewhere[a: Agent] {
  not coLocated[By.actor, a]
  a.task in By.actor.holds.members
  Confirmed' = Confirmed + a
  Live' = Live and Local' = Local and Visible' = Visible
  keepClaims and keepShutdown and keepBorn
  Now.ev = ConfirmElsewhere and Now.issue = a.task and Target.agent = a
}

/* STAND DOWN -- campaign to executor.

   Asks it to finish its current turn and stop. It does not destroy its own
   workspace: it acknowledges and goes quiet, and the campaign session retires it
   afterwards. That is why standing down and retiring are two events, and why the
   executor is still Live between them.

   Nothing guards this predicate beyond holding the campaign. The guards are the
   discipline predicates below, applied per command, so that the unguarded
   protocol and each candidate repair can be measured against the same trace
   space. */
pred standDown[a: Agent] {
  a in Live and a not in StoodDown
  a.task in By.actor.holds.members
  StoodDown' = StoodDown + a
  Retired' = Retired
  keepWork and keepClaims and keepBorn
  Now.ev = StandDown and Now.issue = a.task and Target.agent = a
}

/* The workspace is destroyed. Anything still in Local at this instant is gone
   and GitHub never knew about it.

   The second disjunct is not a convenience: an executor that already died is
   retired without any stand-down, because there is nobody left to ask. That path
   skips every message in the protocol, which is exactly why the disciplines
   below guard the retire and not only the stand-down. */
pred retire[a: Agent] {
  (a in StoodDown or a not in Live) and a in Launched and a not in Retired
  a.task in By.actor.holds.members
  Retired' = Retired + a
  Live'    = Live - a
  Local' = Local and Visible' = Visible and Confirmed' = Confirmed
  StoodDown' = StoodDown and keepClaims and keepBorn
  Now.ev = Retire and Now.issue = a.task and Target.agent = a
}

/* The process dies on its own. Its disk survives, so Local is untouched: an
   executor that died after pushing has still succeeded, and one that died
   holding uncommitted work has not yet lost it. */
pred agentDie[a: Agent] {
  a in Live
  Live' = Live - a
  Local' = Local and Visible' = Visible and Confirmed' = Confirmed
  keepClaims and keepShutdown and keepBorn
  Now.ev = AgentDie and Now.issue = a.task and Target.agent = a and no By.actor
}

/* This layer's half of repos.als's `release`: what may be released. The guard is
   what a session can actually read -- the remote branch holds nothing beyond
   main, and no executor on ITS OWN machine works the task. Liveness on another
   machine is not readable, so a live remote executor with no pushed work can
   still lose its claim under a rule correctly followed: R6 below is that
   residue, stated rather than implied away. */
pred aRelease {
  Now.ev = Release
  no a: Agent | a.task = Now.issue and a in Visible
  no a: Agent | a.task = Now.issue and a.host = By.actor.smach and a in Live
  agentFrame
  no Target.agent
}

pred agentInit {
  no Launched and no Live and no Local and no Visible
  no Reported and no Asked and no Answered
  no Waiting and no Confirmed and no StoodDown and no Retired
}

pred agentStep {
  (Now.ev = Stutter and agentFrame and no Target.agent)
  or (some a: Agent |
        launch[a] or work[a] or push[a] or status[a] or answer[a] or report[a]
        or blocked[a] or decide[a] or confirm[a] or confirmElsewhere[a]
        or standDown[a] or retire[a] or agentDie[a])
  or aRelease
  /* every other event: this layer stands still and is about no executor */
  or (Now.ev not in Stutter + agentActed and agentFrame and no Target.agent)
}

fact AgentTrace { agentInit and always agentStep }

/* ==================== SCENARIOS ==================== */

/* ---------------- the property ---------------- */

/* The one thing the protocol is for. Retiring an executor destroys its
   workspace, so retiring one that still holds work only its own disk has is the
   loss the whole two-step shutdown exists to prevent. */
pred noWorkDestroyed {
  always (Now.ev = Retire implies Target.agent not in Local)
}

/* ---------------- disciplines: the shutdown, three ways ---------------- */

/* THE DEFECT THE DESIGN RECORDS. A single "you're done, quit" sent on the
   strength of a REPORT makes the executor's own account the basis for
   destroying its workspace. */
pred oneStepShutdown {
  always (Now.ev in StandDown + Retire implies Target.agent in Reported)
}

/* Shutdown is two steps, never one: STATUS, then verify, then STAND DOWN.
   Both conjuncts are load-bearing -- the answer is what names work only the
   executor can see, and the confirmation is the session looking for itself. */
pred twoStepShutdown {
  always (Now.ev in StandDown + Retire implies
            (Target.agent in Answered and Target.agent in Confirmed))
}

/* Stand down only an executor on your own machine -- AND confirm it from there
   too. The verification in step 2 is read against a working tree, and a session
   on another machine reads its own.

   THE CONFIRM HALF IS NOT DECORATION, and the several-sessions world is what
   showed it. Written over the stand-down and the retire alone -- which is how
   the one-session model stated it, where it could not fail because there was
   only one session and it could not be in two places -- the contract is X here:
   a remote session runs the confirmation the local one then acts on, and the
   retire destroys work. Steps 2 and 3 of the retirement procedure are one
   session's steps, and this is that sentence made checkable. Narrowing this
   predicate back to `StandDown + Retire` reddens TwoStepCoLocatedSuffices, which
   is the mutation that proves the half is load-bearing. */
pred coLocatedShutdown {
  always (Now.ev in Confirm + ConfirmElsewhere + StandDown + Retire
            implies coLocated[By.actor, Target.agent])
}

/* Rule 3, as a discipline: silence is a liveness question, not a protocol
   answer. An unanswered STATUS is asked once more and then resolved through
   herdr and GitHub -- so an executor that is gone may be stood down on the
   confirmation alone, and only on the confirmation. A quiet executor is not a
   finished one, and waiting forever for a reply that cannot come is the failure
   mode this rule exists to stop. */
pred resolveSilenceExternally {
  always (Now.ev in StandDown + Retire implies
            (Target.agent in Confirmed
             and (Target.agent in Answered or Target.agent not in Live)))
}

/* The rule this one replaces: wait for the answer before standing down.
   SilentAgentIsRetirableUnderWait is the witness that it can wait forever. */
pred waitForAnswer {
  always (Now.ev in StandDown + Retire implies Target.agent in Answered)
}

/* What a session on another machine can check before STAND DOWN. */
pred remoteCheckedShutdown { always (Now.ev = StandDown implies Target.agent in Visible) }
/* What only a session on the executor's own machine can check. */
pred localCheckedShutdown  { always (Now.ev = StandDown implies Target.agent not in Local) }

/* The claim discipline, in two named halves. An executor is launched only onto
   a claim its launcher created; and a claim is created only where no ref exists,
   which is what create-ref's 422 enforces server-side. Together they close R4e
   (R4f UNSAT); the control R4g drops atomicity alone and the collision returns,
   so the refusal -- not the ritual -- is the load-bearing half. A session that
   launches without claiming bypasses the first, which is why the discipline
   lives in the launch procedure and R4e itself stays SAT. */
pred claimBeforeLaunch { always (Now.ev = Launch implies Now.issue in By.actor.claims) }
pred claimAtomic       { always (Now.ev = Claim  implies Now.issue not in Claimed) }

/* The close rule as written, plus the honest local reading of it. */
pred closeDisciplineFull[c: Campaign] {
  always ((Now.ev = CloseIssue and Now.issue = c.anchor) implies closableWithAgents[c])
}
pred closeDisciplineLocal[c: Campaign] {
  always ((Now.ev = CloseIssue and Now.issue = c.anchor) implies closableLocally[By.actor, c])
}

/* ---------------- properties ---------------- */

/* PASS. No lost work: an executor dying and a directory being deleted never
   un-complete a subtask.

   Nothing written in THIS file carries it. Completion is ledger's, and ledger
   frames its own state whenever an event it does not own fires -- so what this
   check tests is the composition idiom, and dropping `ledgerFrame` from ledger's
   fall-through branch is what reddens it. */
assert NoLostWork {
  always all i: Issue |
    (complete[i] and Now.ev in AgentDie + DeleteDir) implies after complete[i]
}

/* X. No orphan: no executor is live on a checkout whose campaign directory is
   gone. Nothing enforces "no campaign closes while an executor is live under its
   tree".

   The counterexample, and it is the reason the rule is stated as a local check
   with its blind spot named: two machines hold campaign #N; an executor is live
   on machine 0; the operator on machine 1 deletes its tree. "No campaign closes
   while an executor is live under its tree" is a local check blind to the other
   machine. Enforcing it, plus refusing to drop a member an executor is working,
   makes NoOrphanIfGuarded pass -- nothing enforces either today. */
pred noOrphanNow {
  all a: Agent | a in Live implies (some c: Campaign | a.task in c.members and a.host in dirsOf[c])
}

assert NoOrphan { always noOrphanNow }

// PASS. Same, assuming the design's stated retirement rule is actually
// enforced.
assert NoOrphanIfGuarded {
  ((always (Now.ev = DeleteDir implies (no a: Agent | a in Live and a.host = Site.mach)))
   and (always (Now.ev = RemoveMember implies (no a: Agent | a in Live and a.task = Now.issue))))
  implies (always noOrphanNow)
}

/* X. Unguarded: work is destroyed. The baseline the disciplines are measured
   against. Counterexample: an executor works, is stood down, is retired. */
assert UnguardedShutdownIsUnsafe { noWorkDestroyed }

/* X. THE ONE-STEP DEFECT. A REPORT is a claim about a pull request; it says
   nothing about a second, uncommitted change made after it. Counterexample:
   the executor reports, then works again, then is stood down on the strength of
   the report and retired with the new work still only on its disk. This is the
   assertion that makes "shutdown is two steps, never one" a checked statement
   rather than an instruction. */
assert OneStepShutdownSuffices { oneStepShutdown implies noWorkDestroyed }

/* X. THE REMOTE HOLE, and it is not a modelling artefact. Two steps are not
   enough when step 2 is run from the wrong machine: an executor launched
   elsewhere passes every check a remote session can make while its uncommitted
   work sits on a disk that session cannot see. Counterexample: confirmElsewhere
   fires, the executor still holds Local, and the retire destroys it. Ask the
   session that launched it, or leave it.

   THIS IS ALSO THE WHOLE OF "a remote stand-down destroys work", which the
   several-sessions model stated separately as a run: a session on another
   machine stands the executor down, the check it can actually run -- the branch
   is on the remote -- passes, and work that exists only on the executor's
   machine dies with the workspace. The two are one finding and one
   counterexample; R5b and R5c below are the controls that pin its axis. */
assert TwoStepShutdownSuffices { twoStepShutdown implies noWorkDestroyed }

/* PASS. The contract as AGENTS.md states it: two steps, on your own machine.
   Confirmed is cleared by any later `work`, which is what makes the green
   survive an executor that keeps working after being confirmed. */
assert TwoStepCoLocatedSuffices {
  (twoStepShutdown and coLocatedShutdown) implies noWorkDestroyed
}

/* PASS. Rule 3's repair does not reopen the hole: dropping the requirement for
   an ANSWER, for an executor that can no longer give one, is safe as long as the
   session's own confirmation is kept and read on the right machine. */
assert SilenceResolutionStaysSafe {
  (resolveSilenceExternally and coLocatedShutdown) implies noWorkDestroyed
}

/* ---------------- witnesses ---------------- */

/* The whole retirement procedure, reachable: the executor works and pushes, the
   session asks STATUS and gets an answer, confirms against the tree, stands it
   down and retires the workspace. SAT means the disciplines above forbid a
   counterexample rather than forbidding the protocol. */
pred Sanity {
  coLocatedShutdown and twoStepShutdown
  and eventually (some a: Agent | a in Retired)
  and eventually Now.ev = Work
  and eventually Now.ev = Push
}

/* Rule 1 as a witness, and the whole of "the agent went idle is not
   completion": the executor claims it is finished while still holding work only
   its machine has, and the claim leaves that fact exactly as it was -- and leaves
   the GitHub fact exactly as it was too, which is the stronger half. A signal
   weaker than an explicit REPORT, such as a pane falling quiet, says even less. */
pred ReportIsNotEvidence {
  some a: Agent | eventually (Now.ev = Report and Target.agent = a
    and a in Local and a in Local'
    and not complete[a.task] and after always not complete[a.task])
}

/* BLOCKED stops the executor rather than letting it guess: it is waiting, and
   no Work event fires while it does. */
pred BlockedAgentDoesNotProceed {
  some a: Agent | eventually (a in Waiting and always (a in Waiting and Now.ev != Work))
}

/* THE FAILURE RULE 3 FORBIDS. Under wait-for-the-answer, an executor asked for
   STATUS that then dies without replying can never be retired at all: the
   premise the discipline waits on is one the world can no longer supply.
   UNSAT is the finding -- there is no such trace, so the workspace stays open
   forever and the session waits for a reply that cannot come. */
pred SilentAgentIsRetirableUnderWait {
  waitForAnswer
  and (some a: Agent |
         eventually (a in Asked and a not in Live and a in Retired)
         and always a not in Answered)
}

/* Rule 3's repair, and the control that it is a repair rather than a
   prohibition: under resolveSilenceExternally the same never-answering executor
   is still retired. */
pred SilentAgentStillRetired {
  resolveSilenceExternally and coLocatedShutdown
  and (some a: Agent | eventually a in Retired and always a not in Answered)
}

/* The delegate dies after pushing. Completion is a GitHub fact, so it survives
   the death and never comes undone. */
/* FOR REAL -- real. Launch a delegate on a subtask. Wait until it has pushed
   and opened a pull request (`gh pr list -R <repo> --head
   campaign-$ANCHOR/<n>-<topic>` returns a row). Kill the pane -- `herdr agent
   list` to find it, then kill the process. Merge the pull request yourself.
   PASS: the row goes `complete` with no executor alive anywhere. Safe on real
   repositories: the branch is already pushed, so nothing local is lost. */
pred S3_DelegateDiesAfterPushing {
  one c: Campaign | one a: Agent {
    a.task in c.members
    always Now.ev not in AddMember + RemoveMember
    mergeClosed[c.members]
    eventually (Now.ev = OpenPR and Now.issue = a.task)
    eventually (Now.ev = AgentDie and some a.task.pr and a.task.pr not in Merged)
    eventually complete[a.task]
    always (complete[a.task] implies always complete[a.task])
  }
}

/* The delegate reports done while nothing is pushed. The campaign session must
   not believe it, and the trace shows why: the claim never becomes a GitHub fact
   on its own. */
/* FOR REAL -- real. Launch a delegate; when it sends REPORT, do not believe it.
   Run `scripts/campaign-settlement $ANCHOR` first.
   PASS: the row is `open` -- the claim was not evidence. Then confirm the
   absence directly, which is the form the protocol requires:

     git -C <campaign>/repos/<repo> status --porcelain           # must be empty
     git -C <campaign>/repos/<repo> log --branches --not --remotes --oneline
                                                                 # must be empty

   Only after both are empty may STAND DOWN be sent. A run where the campaign
   session closed the subtask on the strength of the message is a failure,
   however the work turned out. */
pred S4_ReportWithoutPush {
  one c: Campaign | one a: Agent {
    a.task in c.members
    always Now.ev not in AddMember + RemoveMember
    eventually (Now.ev = Report and Now.issue = a.task)
    eventually (a in Reported and no a.task.pr and a.task in Open)
    eventually always (not complete[a.task])
    always not closable[c]
  }
}

/* The delete lands on the machine the live executor runs on. This is NoOrphan's
   counterexample, requested as a witness so a run can be written that reproduces
   it on purpose. */
/* FOR REAL -- fixture. Launch a delegate, let it commit but NOT push, then
   delete `<campaign>/` from a second session.
   PASS is a demonstration of loss: the commits are unrecoverable and GitHub
   never knew about them. It is why STATUS question 3 exists. Fixture only, and
   never with a real delegate's work in the tree. */
pred S9_OrphanedByLocalDelete {
  one c: Campaign | one a: Agent {
    a.task in c.members
    -- deleted while the executor is live with nothing pushed: this is the only
    -- state where local-only work is actually destroyed
    eventually (Now.ev = DeleteDir and Site.mach = a.host and a in Live
                and a in Local and no a.task.pr)
    eventually (a in Live and a.host not in dirsOf[c])
  }
}

/* =================== a close during another session's work =================== */

/* R3b. The cross-machine form: session 2 closes the anchor from another machine
   while session 1's delegate is live on machine 1. The local gate reads
   closable; the campaign is not. */
/* WITNESS. S0 closes the anchor from M0 while S1's delegate is live on M1; the
   local gate reads closable because it is reading M0. R3c UNSAT below restates
   the close rule globally, so R3b reads as that rule being unreadable from one
   machine, not as the rule failing. */
pred R3b_CloseFromAnotherMachine {
  some c: Campaign, disj s1, s2: Session, a: Agent {
    s1.smach != s2.smach
    a.launcher = s1
    closeDisciplineLocal[c]
    eventually (Now.ev = CloseIssue and By.actor = s2 and Now.issue = c.anchor
                and a in Live and not closableWithAgents[c])
  }
}

/* R3c. Control for R3b: the global rule, if it could be read, blocks it.

   Scoped to traces with no RemoveMember, and the scope is a finding rather than
   a convenience. `liveUnder` reads an executor as under a campaign when its
   subtask is a member OR its machine holds the tree; move the subtask out and
   delete the tree and both go false while the executor is still running, so the
   global rule permits the close after all. The model this came from had no
   remove event and could not state it. Nothing in the design guards it, and it
   is the same shape as the residual risk ledger.als names: a reparent is silent
   and leaves no trace. */
pred R3c_GlobalCloseRuleBlocks {
  some c: Campaign, disj s1, s2: Session, a: Agent {
    s1.smach != s2.smach
    a.launcher = s1
    always Now.ev != RemoveMember
    closeDisciplineFull[c]
    eventually (Now.ev = CloseIssue and Now.issue = c.anchor and By.actor = s2 and a in Live)
  }
}

/* =================== two sessions, one repository =================== */

/* R4. Two sessions on the same campaign launch delegates into the same
   repository and pick the same topic. campaign-<N> keeps campaigns apart;
   nothing keeps two sessions of one campaign apart. */
/* WITNESS, against campaign-<N>/<topic> -- the branch form this was found on.
   Two subtasks in R0, two sessions, the same <topic>: one branch, two delegates,
   one checkout. R4d is the same with a single subtask. */
pred R4_SameBranchTwice {
  some disj a1, a2: Agent, r: Repo {
    r != Container
    a1.launcher != a2.launcher
    a1.task != a2.task                          -- two different subtasks
    a1.task.home = r and a2.task.home = r
    a1.topic = a2.topic
    eventually (a1 in Live and a2 in Live
                and some campaignOf[a1.task] and sameBranchByTopic[a1, a2])
  }
}

/* R4b. Positive control for R4: two executors of DIFFERENT campaigns, live in
   the same repository at the same time, with the same <topic> deliberately
   chosen. They do not share a branch. That is what the campaign-<N> prefix buys,
   and it isolates R4's collision as an intra-campaign one. */
pred R4b_CrossCampaignCoexists {
  some disj a1, a2: Agent, r: Repo {
    r != Container
    a1.task.home = r and a2.task.home = r
    a1.topic = a2.topic
    eventually (a1 in Live and a2 in Live
                and campaignOf[a1.task] != campaignOf[a2.task]
                and not sameBranchByTopic[a1, a2])
  }
}

/* R4c. The acquire race. One machine, one campaign directory, one checkout of
   the repository. Session 2 acquires it on another branch while session 1's
   delegate is live in it with work that is not on the remote. */
/* WITNESS. S0's acquire-repo switches the shared checkout off the branch S1's
   live delegate is working. */
pred R4c_CheckoutSwitchedUnderAgent {
  some c: Campaign, disj s1, s2: Session, a: Agent, r: Repo {
    r != Container
    s1.smach = s2.smach
    a.launcher = s1 and a.host = s1.smach and a.task.home = r
    -- pinned to one step, so the switch is attributable to s2 and not to an
    -- earlier acquire by the launching session itself.
    eventually (Now.ev = Acquire and By.actor = s2 and Site.repo = r
                and a in Live and a not in Visible
                and treeAt[c, a.host].co[r] = a.topic
                and after (treeAt[c, a.host].co[r] != a.topic))
  }
}

/* R4d. The sharper form the solver reached first when R4 left the tasks free:
   two sessions delegate the SAME subtask issue. Nothing in the design says a
   subtask has at most one executor. */
pred R4d_SameSubtaskTwice {
  some disj a1, a2: Agent {
    a1.launcher != a2.launcher
    a1.task = a2.task
    eventually (a1 in Live and a2 in Live)
  }
}

/* R4e. The adopted form, and what it does not fix. Two sessions that delegate
   the SAME subtask still land on one branch: the issue number separates two
   subtasks, and there is only ever one of it per subtask. AGENTS.md names the
   branch rule as answering the two-subtask collision only, and this is the
   residual it leaves standing. */
pred R4e_NumberedBranchStillShared {
  some disj a1, a2: Agent {
    a1.launcher != a2.launcher
    eventually (a1 in Live and a2 in Live
                and some campaignOf[a1.task] and sameBranch[a1, a2])
  }
}

/* R4f. The claim discipline closes R4e. Launch only a claim you created, and
   create-ref refuses an existing ref: the second session's claim fails before a
   second executor exists, so two live executors on one subtask from two
   launchers become unreachable. UNSAT at R4e's own bounds. */
pred R4f_ClaimClosesSameSubtask {
  claimBeforeLaunch and claimAtomic
  R4e_NumberedBranchStillShared
}

/* R4g. CONTROL: the ritual without the refusal. Both sessions claim -- nothing
   refuses the second create -- and both launch onto claims they hold. SAT: the
   collision returns, so the load-bearing half is the server's 422, not the
   procedure. */
pred R4g_ClaimWithoutAtomicityStillShared {
  claimBeforeLaunch
  some disj s1, s2: Session, i: Issue |
    eventually (i in s1.claims and i in s2.claims)
  R4e_NumberedBranchStillShared
}

/* =================== retiring another session's delegate =================== */

/* R5b. Control for TwoStepShutdownSuffices: the gap that finding rests on is
   reachable at all. An executor whose branch is on the remote may still hold
   work that is not. Without this, the remote hole could be an artefact of a
   state the model never enters. */
pred R5b_VisibleNotPushed { some a: Agent | eventually (a in Visible and a in Local) }

/* R5c. Ownership is not the axis. Under the local check, a session that did not
   launch the executor may still retire it safely, provided it shares its
   machine. */
pred R5c_NonLauncherSameMachineIsFine {
  localCheckedShutdown
  some disj s1, s2: Session, a: Agent {
    a.launcher = s1 and a.host = s1.smach and s2.smach = a.host
    eventually (Now.ev = StandDown and By.actor = s2 and Target.agent = a)
  }
}

/* R6. What release cannot read. The guard on release is local -- nothing on the
   remote branch, no LIVE executor on this machine -- because liveness elsewhere
   is not readable. A live executor on another machine that has not pushed loses
   its claim under a rule correctly followed. Same shape as the remote hole, same
   mitigation: push as soon as one commit exists. */
pred R6_ReleaseUnderRemoteAgent {
  some s: Session, a: Agent {
    a.host != s.smach
    eventually (a in Live and a not in Visible
                and Now.ev = Release and By.actor = s and Now.issue = a.task)
  }
}

/* R6b. Recovery: a dead delegate's dangling claim is released and the subtask
   claimed again by a survivor. The claim does not outlive its usefulness. */
pred R6b_ReclaimAfterDeath {
  some disj s1, s2: Session, a: Agent {
    a.launcher = s1
    eventually (a in Launched and a not in Live and a not in Visible
                and eventually (Now.ev = Release
                and eventually (Now.ev = Claim and By.actor = s2 and Now.issue = a.task)))
  }
}

/* ---------------- reachability floor ---------------- */

pred Cov_LaunchAgent      { eventually (Now.ev = Launch and some Target.agent) }
pred Cov_Work             { eventually Now.ev = Work }
pred Cov_Push             { eventually Now.ev = Push }
pred Cov_Status           { eventually Now.ev = Status }
pred Cov_Answer           { eventually Now.ev = Answer }
pred Cov_Report           { eventually Now.ev = Report }
pred Cov_Blocked          { eventually Now.ev = Blocked }
pred Cov_Decide           { eventually Now.ev = Decide }
pred Cov_Confirm          { eventually Now.ev = Confirm }
pred Cov_ConfirmElsewhere { eventually Now.ev = ConfirmElsewhere }
pred Cov_StandDown        { eventually Now.ev = StandDown }
pred Cov_Retire           { eventually Now.ev = Retire }
pred Cov_AgentDie         { eventually Now.ev = AgentDie }
pred Cov_GuardedRelease   { eventually Now.ev = Release }

/* ---------------- commands ---------------- */

check NoLostWork        for 3 Issue, 2 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps
check NoOrphan          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps
check NoOrphanIfGuarded for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps

check UnguardedShutdownIsUnsafe  for 2 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps
check OneStepShutdownSuffices    for 2 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps
check TwoStepShutdownSuffices    for 2 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps
check TwoStepCoLocatedSuffices   for 2 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps
check SilenceResolutionStaysSafe for 2 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps

run Sanity                          for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps
run ReportIsNotEvidence             for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 10 steps
run BlockedAgentDoesNotProceed      for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 10 steps
run SilentAgentIsRetirableUnderWait for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps
run SilentAgentStillRetired         for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps

run S3_DelegateDiesAfterPushing for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps
run S4_ReportWithoutPush        for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps
run S9_OrphanedByLocalDelete    for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps

run R3b_CloseFromAnotherMachine  for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps
run R3c_GlobalCloseRuleBlocks    for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps

run R4_SameBranchTwice           for 4 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps
run R4b_CrossCampaignCoexists    for 4 Issue, 1 PR, 2 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 14 steps
run R4c_CheckoutSwitchedUnderAgent for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 2 Topic, 1 Tree, 12 steps
run R4d_SameSubtaskTwice         for 4 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps
run R4e_NumberedBranchStillShared for 4 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps
run R4f_ClaimClosesSameSubtask    for 4 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps
run R4g_ClaimWithoutAtomicityStillShared for 4 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps

run R5b_VisibleNotPushed         for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps
run R5c_NonLauncherSameMachineIsFine for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps
run R6_ReleaseUnderRemoteAgent   for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps
run R6b_ReclaimAfterDeath        for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 14 steps

run Cov_LaunchAgent      for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_Work             for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_Push             for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_Status           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_Answer           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_Report           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_Blocked          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_Decide           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_Confirm          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_ConfirmElsewhere for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_StandDown        for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_Retire           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_AgentDie         for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run Cov_GuardedRelease   for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
