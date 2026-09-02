/*
 * The executor: launch, work, the four messages, retirement -- and the whole
 * composition, since this is the top layer. ledger.als is spec/'s entry point.
 *
 * The three execution modes -- own hands, in-process subagent, herdr delegate
 * -- are ONE `Launch` here: nothing a model can say about reachable states
 * differs between them.
 *
 * UNMODELLED: adequacy; that the executor answers about itself only; that
 * STAND DOWN is a request a peer may refuse; and two of AGENTS.md's three
 * merge conditions -- the NON-AUTHOR one, because nothing here records who set
 * `Reviewed`, and CONTAINS-CURRENT-MAIN, because this model has one pull
 * request per issue and no shared branch moving under another (#95).
 */
module agent

open session

/* ==================== SYSTEM ==================== */

sig Agent {
  task:     one Issue,
  host:     one Machine,
  launcher: one Session,
  topic:    one Topic,
  /* Set when the executor IS a campaign session working its own claim. A
     delegate is `--name`d at launch; a session's own claim is named by nothing
     anybody else chose, which is why only it needs a record. */
  peer:     lone Session
}

var sig Launched in Agent {}
var sig Live     in Agent {}
/* THE one encoding of "only on its host": uncommitted, unpushed, or on a
   branch no remote has. */
var sig Local    in Agent {}
/* Its branch is on the remote -- checkable from anywhere, and a different fact
   from Local. The gap between the two is R5b. */
var sig Visible  in Agent {}
var sig Reported in Agent {}
/* A campaign session can reach it. A DIRECTORY FACT: it dies with the tree,
   and it is keyed to no reader, so any later session inherits every address in
   it. */
var sig Addressed in Agent {}
var sig Asked    in Agent {}
var sig Answered in Agent {}
var sig Waiting  in Agent {}
/* The SESSION has itself observed that this executor holds nothing
   local-only. */
var sig Confirmed in Agent {}
var sig StoodDown in Agent {}
var sig Retired  in Agent {}

/* A bit on the PULL REQUEST, not on the executor: the review outlives the
   executor exactly as the pull request does, and a fresh executor briefed from
   the review inherits it. */
var sig Reviewed in PR {}

one sig Target { var agent: lone Agent }

fact AgentWellFormed {
  all c: Campaign | c.anchor not in Agent.task
  all a: Agent | some a.peer implies (a.launcher = a.peer and a.host = a.peer.smach)
  always Live in Launched
  always Retired in Launched
  always no Live & Retired
  always Visible in Visible'     -- a branch on the remote stays on the remote
}

pred coLocated[s: Session, a: Agent] { s.smach = a.host }

pred liveUnder[c: Campaign] {
  some a: Agent | a in Live and (a.task in c.members or a.host in dirsOf[c])
}
/* What one session can actually read: `herdr agent list` on its own machine. */
pred liveUnderLocally[c: Campaign, m: Machine] {
  some a: Agent | a in Live and a.host = m and (a.task in c.members or m in dirsOf[c])
}
/* Whether any campaign session can reach this executor at all. Separate from
   liveness on purpose: "I can see it in a list" and "I can send it a message"
   are different questions, and this is the second. */
pred reachable[a: Agent] { a in Addressed }

/* What a close gate can read AND ATTRIBUTE, a strictly smaller set than what
   it can see. Liveness is readable for BOTH kinds of executor without any
   record -- a session working its own claim holds a pane and is listed too --
   but a pane gives a name and a campaign session's cwd is the container root,
   so only the record ties the name to a claim. The split's subject is
   attribution, and A17 is the residual gap measured. */
pred liveAndReadable[c: Campaign, m: Machine] {
  some a: Agent | a in Live and a.host = m
    and (a.task in c.members or m in dirsOf[c])
    and (no a.peer or reachable[a])
}
/* ledger's `closable` is the GitHub half. These three add the half that needs
   an executor. */
pred closableWithAgents[c: Campaign]          { closable[c] and not liveUnder[c] }
pred closableLocally[s: Session, c: Campaign] { closable[c] and not liveUnderLocally[c, s.smach] }
pred closableAsRead[s: Session, c: Campaign]  { closable[c] and not liveAndReadable[c, s.smach] }

/* campaign-<N>/<issue>-<topic>: two executors share a branch only when
   campaign, subtask and topic all match. That it separates two SUBTASKS is
   definitional and is not run; R4e is what it leaves. */
pred sameBranch[a1, a2: Agent] {
  campaignOf[a1.task] = campaignOf[a2.task]
  and a1.task = a2.task
  and a1.topic = a2.topic
}

/* ---------------- observable events ---------------- */

one sig Work, Push, Status, Answer, Report, Blocked, Decide,
        Confirm, ConfirmElsewhere, Review, StandDown, Retire, AgentDie extends Event {}

fun agentOwn: set Event {
  Work + Push + Status + Answer + Report + Blocked + Decide
  + Confirm + ConfirmElsewhere + Review + StandDown + Retire + AgentDie
}
/* `DeleteDir` is here because this layer has a bit with the directory's
   lifetime. `MergePR` is NOT: session.als gives it an actor and this layer
   only guards who that actor may be, which is a discipline over the event
   rather than a disjunct on it, so the merge falls through and frames
   everything. */
fun agentActed: set Event { agentOwn + Launch + Release + DeleteDir }

/* The bits divide by how long they live: a directory fact, a pull request's,
   and a process's. */
pred keepMsgs     { Reported' = Reported and Asked' = Asked and Answered' = Answered and Waiting' = Waiting }
pred keepAddress  { Addressed' = Addressed }
pred keepReview   { Reviewed' = Reviewed }
pred keepLife     { Live' = Live and Local' = Local and Visible' = Visible and Confirmed' = Confirmed }
pred keepShutdown { StoodDown' = StoodDown and Retired' = Retired }
pred keepBorn     { Launched' = Launched }
pred agentFrame   { keepLife and keepReview and keepMsgs and keepAddress and keepShutdown and keepBorn }

/* `Addressed` is set unconditionally: a delegate is addressable from its
   `--name`, a session from the record it wrote at the claim, which precedes
   every launch. A1 is the gap that closes. */
pred launch[a: Agent] {
  Now.ev = Launch
  a not in Launched
  a.launcher = By.actor
  a.host = Site.mach
  Now.issue = a.task
  /* A REF is what a delegate's launch waits on, and only a delegate's. A
     session working with its own hands starts on work that may land no commit
     at all, where `take --local` writes the record and cuts nothing -- so
     requiring a ref here would model a create-ref that does not happen, and it
     did: it made R4h unsatisfiable and the model claimed a hole closed that
     this campaign then fell into. What must hold on this edge is the RECORD,
     and that is `claimBeforeWork`, not a conjunct here. */
  no a.peer implies a.task in Claimed
  treeAt[By.actor.holds, a.host].checkout[a.task.home] = a.topic
  Launched' = Launched + a
  Live'     = Live + a
  Addressed' = Addressed + a
  Local' = Local and Visible' = Visible and Confirmed' = Confirmed
  keepReview and keepMsgs and keepShutdown
  Target.agent = a
}

/* `Addressed` is the one bit here that does not outlive the tree, and only
   for a session working its own claim: stripping a delegate too would make it
   permanently unreachable when a directory its `--name` never depended on is
   deleted. Scoped to the deleted tree's own campaign and machine. */
pred aDeleteDir {
  Now.ev = DeleteDir
  Addressed' = Addressed
    - { a: Agent | some a.peer
                   and a.host = Site.mach
                   and campaignOf[a.task] in (Present - Present').camp }
  keepLife and keepReview and keepMsgs and keepShutdown and keepBorn
  no Target.agent
}

/* Clears an earlier confirmation here rather than at the point it is read. */
pred work[a: Agent] {
  a in Live and a not in Waiting
  Local' = Local + a
  Confirmed' = Confirmed - a
  Live' = Live and Visible' = Visible
  keepReview and keepMsgs and keepAddress and keepShutdown and keepBorn
  Now.ev = Work and Now.issue = a.task and Target.agent = a and no By.actor
}

/* Two different facts move, and only the first is readable from another
   machine. It does not set Confirmed -- the session has not looked yet -- and
   it clears `Reviewed`, because A REVIEW IS OF A PULL REQUEST AT A REVISION. */
pred push[a: Agent] {
  a in Live and a in Local
  Local'    = Local - a
  Visible'  = Visible + a
  Reviewed' = Reviewed - a.task.pr
  Live' = Live and Confirmed' = Confirmed
  keepMsgs and keepAddress and keepShutdown and keepBorn
  Now.ev = Push and Now.issue = a.task and Target.agent = a and no By.actor
}

/* Asking and answering are two events because STATUS queues behind the
   executor's current turn, so a late reply is ordinary rather than a symptom. */
pred status[a: Agent] {
  reachable[a]
  a.task in By.actor.holds.members
  Asked' = Asked + a
  Answered' = Answered - a
  Reported' = Reported and Waiting' = Waiting
  keepLife and keepReview and keepAddress and keepShutdown and keepBorn
  Now.ev = Status and Now.issue = a.task and Target.agent = a
}

/* A gone executor leaves the question outstanding forever: rule 3. */
pred answer[a: Agent] {
  a in Live and a in Asked
  Answered' = Answered + a
  Asked' = Asked and Reported' = Reported and Waiting' = Waiting
  keepLife and keepReview and keepAddress and keepShutdown and keepBorn
  Now.ev = Answer and Now.issue = a.task and Target.agent = a and no By.actor
}

/* A prompt to verify, never the verification, so this event writes NOTHING
   but the claim itself. */
pred report[a: Agent] {
  a in Live
  Reported' = Reported + a
  Asked' = Asked and Answered' = Answered and Waiting' = Waiting
  keepLife and keepReview and keepAddress and keepShutdown and keepBorn
  Now.ev = Report and Now.issue = a.task and Target.agent = a and no By.actor
}

/* Silence is not this message: an executor that stops without sending it
   looks identical to one thinking. */
pred blocked[a: Agent] {
  a in Live and a not in Waiting
  Waiting' = Waiting + a
  Reported' = Reported and Asked' = Asked and Answered' = Answered
  keepLife and keepReview and keepAddress and keepShutdown and keepBorn
  Now.ev = Blocked and Now.issue = a.task and Target.agent = a and no By.actor
}

pred decide[a: Agent] {
  reachable[a]
  a in Waiting
  a.task in By.actor.holds.members
  Waiting' = Waiting - a
  Reported' = Reported and Asked' = Asked and Answered' = Answered
  keepLife and keepReview and keepAddress and keepShutdown and keepBorn
  Now.ev = Decide and Now.issue = a.task and Target.agent = a
}

/* Stated as an ABSENCE, because "confirm the branch is pushed" has no passing
   form for an executor that correctly produced nothing. NO `reachable` guard,
   deliberately: it reads a tree on the session's own machine and sends the
   executor nothing. A14/A15 are what gating it would cost. */
pred confirm[a: Agent] {
  coLocated[By.actor, a]
  a.task in By.actor.holds.members
  a not in Local
  Confirmed' = Confirmed + a
  Live' = Live and Local' = Local and Visible' = Visible
  keepReview and keepMsgs and keepAddress and keepShutdown and keepBorn
  Now.ev = Confirm and Now.issue = a.task and Target.agent = a
}

/* It reads the SESSION's working tree, so there is no `a not in Local` guard:
   nothing on this machine could fail it. That is the defect, not a shortcut. */
pred confirmElsewhere[a: Agent] {
  not coLocated[By.actor, a]
  a.task in By.actor.holds.members
  Confirmed' = Confirmed + a
  Live' = Live and Local' = Local and Visible' = Visible
  keepReview and keepMsgs and keepAddress and keepShutdown and keepBorn
  Now.ev = ConfirmElsewhere and Now.issue = a.task and Target.agent = a
}

/* KEYED ON THE ISSUE, NOT ON AN AGENT: the review reads GitHub, so keying it
   to an Agent made hands-on work unreviewable and so unmergeable. No guard on
   who commissions it -- the property needs independence of JUDGEMENT, not of
   TASKING, and a one-session campaign has nobody else to launch it. The named
   limit: the launcher writes the reviewer's brief. */
pred review[i: Issue] {
  Now.ev = Review
  Now.issue = i
  some i.pr and i.pr not in Reviewed
  i in By.actor.holds.members
  Reviewed' = Reviewed + i.pr
  keepLife and keepMsgs and keepAddress and keepShutdown and keepBorn
  no Target.agent
}

/* It does not destroy its own workspace, which is why standing down and
   retiring are two events and the executor is still Live between them. */
pred standDown[a: Agent] {
  reachable[a]
  a in Live and a not in StoodDown
  a.task in By.actor.holds.members
  StoodDown' = StoodDown + a
  Retired' = Retired
  keepLife and keepReview and keepMsgs and keepAddress and keepBorn
  Now.ev = StandDown and Now.issue = a.task and Target.agent = a
}

/* Anything still in Local at this instant is gone. The second disjunct is not
   a convenience: an executor that already died is retired with no stand-down,
   and that path skips every message, which is why the disciplines guard the
   retire and not only the stand-down. No `reachable` guard either. */
pred retire[a: Agent] {
  (a in StoodDown or a not in Live) and a in Launched and a not in Retired
  a.task in By.actor.holds.members
  Retired' = Retired + a
  Live'    = Live - a
  Local' = Local and Visible' = Visible and Confirmed' = Confirmed
  StoodDown' = StoodDown
  keepReview and keepMsgs and keepAddress and keepBorn
  Now.ev = Retire and Now.issue = a.task and Target.agent = a
}

/* Its disk survives, so Local is untouched: one that died after pushing has
   succeeded. */
pred agentDie[a: Agent] {
  a in Live
  Live' = Live - a
  Local' = Local and Visible' = Visible and Confirmed' = Confirmed
  keepReview and keepMsgs and keepAddress and keepShutdown and keepBorn
  Now.ev = AgentDie and Now.issue = a.task and Target.agent = a and no By.actor
}

/* Both guards are what a session can actually read. Liveness elsewhere is
   not, so R6 is the residue that leaves. */
pred aRelease {
  Now.ev = Release
  no a: Agent | a.task = Now.issue and a in Visible
  no a: Agent | a.task = Now.issue and a.host = By.actor.smach and a in Live
  agentFrame
  no Target.agent
}

pred agentInit {
  no Launched and no Live and no Local and no Visible
  no Reported and no Addressed and no Asked and no Answered
  no Waiting and no Confirmed and no Reviewed and no StoodDown and no Retired
}

pred agentStep {
  (Now.ev = Stutter and agentFrame and no Target.agent)
  or (some a: Agent |
        launch[a] or work[a] or push[a]
        or status[a] or answer[a] or report[a]
        or blocked[a] or decide[a] or confirm[a] or confirmElsewhere[a]
        or standDown[a] or retire[a] or agentDie[a])
  or (some i: Issue | review[i])
  or aRelease
  or aDeleteDir
  or (Now.ev not in Stutter + agentActed and agentFrame and no Target.agent)
}

fact AgentTrace { agentInit and always agentStep }

/* ==================== SCENARIOS ==================== */

/* ---------------- the property ---------------- */

/* The one thing the protocol is for. */
pred noWorkDestroyed {
  always (Now.ev = Retire implies Target.agent not in Local)
}

/* ---------------- disciplines: the shutdown, three ways ---------------- */

/* The executor's own account as the basis for destroying its workspace. */
pred oneStepShutdown {
  always (Now.ev in StandDown + Retire implies Target.agent in Reported)
}

/* Both conjuncts are load-bearing: the answer names work only the executor
   can see, the confirmation is the session looking for itself. */
pred twoStepShutdown {
  always (Now.ev in StandDown + Retire implies
            (Target.agent in Answered and Target.agent in Confirmed))
}

/* Narrowing this to `StandDown + Retire` reddens TwoStepCoLocatedSuffices: a
   remote session can then run the confirmation a local one acts on. */
pred coLocatedShutdown {
  always (Now.ev in Confirm + ConfirmElsewhere + StandDown + Retire
            implies coLocated[By.actor, Target.agent])
}

/* Rule 3: an executor that is gone may be stood down on the confirmation
   alone, and only on it. */
pred resolveSilenceExternally {
  always (Now.ev in StandDown + Retire implies
            (Target.agent in Confirmed
             and (Target.agent in Answered or Target.agent not in Live)))
}

/* The rule it replaces: wait for the answer. */
pred waitForAnswer {
  always (Now.ev in StandDown + Retire implies Target.agent in Answered)
}

/* What only a session on the executor's own machine can check. */
pred localCheckedShutdown { always (Now.ev = StandDown implies Target.agent not in Local) }

/* R4g drops `claimAtomic` alone and the collision returns, so create-ref's
   server-side refusal -- not the ritual -- is the load-bearing half. */
pred claimBeforeLaunch { always (Now.ev = Launch implies Now.issue in By.actor.claims) }
pred claimAtomic       { always (Now.ev = Claim  implies Now.issue not in Claimed) }

/* The gate on LAUNCH covers the executor a session starts and says nothing
   about the executor a session IS: `work` carries no `By.actor`, so a session
   working its own claim reaches the same subtask along an edge
   `claimBeforeLaunch` never touches. R4h is that hole and R4i is its repair --
   scripts/check-campaign-claim.py, a PreToolUse guard refusing a changing call
   from a session holding no claim. Keyed on `a.peer` because a delegate has no
   session to hold one; its launcher was gated already. */
pred claimBeforeWork {
  always (Now.ev = Work and some Target.agent.peer
            implies Now.issue in Target.agent.peer.claims)
}

/* The rule as written, the honest local reading, and the reading a session
   can actually perform. */
pred closeDisciplineFull[c: Campaign] {
  always ((Now.ev = CloseIssue and Now.issue = c.anchor) implies closableWithAgents[c])
}
pred closeDisciplineLocal[c: Campaign] {
  always ((Now.ev = CloseIssue and Now.issue = c.anchor) implies closableLocally[By.actor, c])
}
pred closeDisciplineAsRead[c: Campaign] {
  always ((Now.ev = CloseIssue and Now.issue = c.anchor) implies closableAsRead[By.actor, c])
}

/* Where session.als's R3 is answered: keyed on the record, which is the thing
   a deleting session can actually read. */
pred noDeleteUnderReadableExecutor {
  always (Now.ev = DeleteDir implies
            no a: Agent | a in Live and a.host = Site.mach and reachable[a]
                          and campaignOf[a.task] in (Present - Present').camp)
}

/* Empty for a subtask a session did with its own hands, which is what makes
   `mergedOnCurrentReview`'s second conjunct vacuous there -- see A18/A18b. */
fun executorsOf[i: Issue]: set Agent { task.i }

/* A MERGE REQUIRES A CURRENT REVIEW, and the author may then merge as anyone
   else may: an identity rule would make the one-session landing unreachable
   and call it safety. CURRENT is encoded as `Reviewed` cleared by `push`,
   which pins the revision THE REVIEW WAS READ AT rather than the merged
   commit, so a squash merge of a reviewed head stays reviewed. The second
   conjunct is UNIVERSAL, not existential, and vacuous with no Agent. */
pred mergedOnCurrentReview {
  always (Now.ev = MergePR implies
            (Now.issue.pr in Reviewed
             and (all a: executorsOf[Now.issue] |
                    a in Confirmed and coLocated[By.actor, a])))
}

/* ---------------- properties ---------------- */

/* Nothing written in THIS file carries it, so it tests the composition idiom:
   dropping `ledgerFrame` from ledger's fall-through branch reddens it. */
assert NoLostWork {
  always all i: Issue |
    (complete[i] and Now.ev in AgentDie + DeleteDir) implies after complete[i]
}

/* The counterexample: two machines hold the campaign, the executor is live on
   one, the tree is deleted from the other. The rule is a local check blind to
   the other machine. */
pred noOrphanNow {
  all a: Agent | a in Live implies (some c: Campaign | a.task in c.members and a.host in dirsOf[c])
}

assert NoOrphan { always noOrphanNow }

// Dropping the RemoveMember clause reddens it.
assert NoOrphanIfGuarded {
  ((always (Now.ev = DeleteDir implies (no a: Agent | a in Live and a.host = Site.mach)))
   and (always (Now.ev = RemoveMember implies (no a: Agent | a in Live and a.task = Now.issue))))
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

/* ---------------- witnesses ---------------- */

/* SAT means the disciplines forbid a counterexample rather than the protocol. */
pred Sanity {
  coLocatedShutdown and twoStepShutdown
  and eventually (some a: Agent | a in Retired)
  and eventually Now.ev = Work
  and eventually Now.ev = Push
}

/* The claim leaves the local fact and the GitHub fact exactly as they were. A
   signal weaker than an explicit REPORT says even less. */
pred ReportIsNotEvidence {
  some a: Agent | eventually (Now.ev = Report and Target.agent = a
    and a in Local and a in Local'
    and not complete[a.task] and after always not complete[a.task])
}

pred BlockedAgentDoesNotProceed {
  some a: Agent | eventually (a in Waiting and always (a in Waiting and Now.ev != Work))
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
    a.task in c.members
    always Now.ev not in AddMember + RemoveMember
    mergeClosed[c.members]
    eventually (Now.ev = OpenPR and Now.issue = a.task)
    eventually (Now.ev = AgentDie and some a.task.pr and a.task.pr not in Merged)
    eventually complete[a.task]
    always (complete[a.task] implies always complete[a.task])
  }
}

/* The claim never becomes a GitHub fact on its own. */
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

/* Live with nothing pushed is the only state where local-only work is
   actually destroyed. */
pred S9_OrphanedByLocalDelete {
  one c: Campaign | one a: Agent {
    a.task in c.members
    eventually (Now.ev = DeleteDir and Site.mach = a.host and a in Live
                and a in Local and no a.task.pr)
    eventually (a in Live and a.host not in dirsOf[c])
  }
}

/* =================== a close during another session's work =================== */

/* R3b. The local gate reads closable; the campaign is not. */
pred R3b_CloseFromAnotherMachine {
  some c: Campaign, disj s1, s2: Session, a: Agent {
    s1.smach != s2.smach
    a.launcher = s1
    closeDisciplineLocal[c]
    eventually (Now.ev = CloseIssue and By.actor = s2 and Now.issue = c.anchor
                and a in Live and not closableWithAgents[c])
  }
}

/* R3c. The global rule, if it could be read, blocks it. The RemoveMember
   scope is a finding, not a convenience: `liveUnder` reads membership OR
   co-location, so moving the subtask out and deleting the tree turns the rule
   permissive while the executor still runs, and nothing guards that. */
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

/* R4c. Pinned to one step, so the switch is attributable to s2 and not to an
   earlier acquire by the launching session itself. */
pred R4c_CheckoutSwitchedUnderAgent {
  some c: Campaign, disj s1, s2: Session, a: Agent, r: Repo {
    r != Container
    s1.smach = s2.smach
    a.launcher = s1 and a.host = s1.smach and a.task.home = r
    eventually (Now.ev = Acquire and By.actor = s2 and Site.repo = r
                and a in Live and a not in Visible
                and treeAt[c, a.host].checkout[r] = a.topic
                and after (treeAt[c, a.host].checkout[r] != a.topic))
  }
}

/* R4e. The issue number separates two subtasks and there is only ever one of
   it per subtask, so two sessions on the SAME subtask still share a branch. */
pred R4e_NumberedBranchStillShared {
  some disj a1, a2: Agent {
    a1.launcher != a2.launcher
    eventually (a1 in Live and a2 in Live
                and some campaignOf[a1.task] and sameBranch[a1, a2])
  }
}

/* R4f. The second session's claim fails before a second executor exists. */
pred R4f_ClaimClosesSameSubtask {
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
   its own subtask and no claim of it ever exists, so every peer reading the
   records sees an open sub-issue indistinguishable from one nobody started. */
pred R4h_OwnHandsWorkWithoutClaim {
  some s: Session, a: Agent {
    a.peer = s
    eventually (Now.ev = Work and Target.agent = a)
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
  some s: Session, a: Agent {
    a.peer = s
    eventually (Now.ev = Claim and By.actor = s and Now.issue = a.task
                and eventually (Now.ev = Work and Target.agent = a))
  }
}

/* =================== retiring another session's delegate =================== */

/* R5b. The gap TwoStepShutdownSuffices rests on is reachable at all. */
pred R5b_VisibleNotPushed { some a: Agent | eventually (a in Visible and a in Local) }

/* R5c. Ownership is not the axis; co-location is. */
pred R5c_NonLauncherSameMachineIsFine {
  localCheckedShutdown
  some disj s1, s2: Session, a: Agent {
    a.launcher = s1 and a.host = s1.smach and s2.smach = a.host
    eventually (Now.ev = StandDown and By.actor = s2 and Target.agent = a)
  }
}

/* R6. A live executor on another machine that has not pushed loses its claim
   under a rule correctly followed. */
pred R6_ReleaseUnderRemoteAgent {
  some s: Session, a: Agent {
    a.host != s.smach
    eventually (a in Live and a not in Visible
                and Now.ev = Release and By.actor = s and Now.issue = a.task)
  }
}

/* R6b. A dangling claim does not outlive its usefulness. */
pred R6b_ReclaimAfterDeath {
  some disj s1, s2: Session, a: Agent {
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
  some c: Campaign, disj s1, s2: Session, a: Agent {
    a.peer = s2 and a.task in c.members
    always a not in Addressed                   -- a claim with no record
    closeDisciplineAsRead[c]                    -- s1 obeys the gate it can read
    eventually (a in Live and a.task in Claimed
                and Now.ev = CloseIssue and Now.issue = c.anchor and By.actor = s1
                and liveUnderLocally[c, s1.smach])
  }
}

/* A3. Control for A1: UNSAT here would mean A1 went green by forbidding the
   executor's life altogether. */
pred A3_RecordedExecutorRunsTheWholeProtocol {
  coLocatedShutdown and twoStepShutdown
  some c: Campaign, disj s1, s2: Session, a: Agent {
    a.peer = s2 and a.task in c.members
    s1.smach = s2.smach
    eventually (Now.ev = Status and By.actor = s1 and Target.agent = a)
    eventually a in Retired
  }
}

/* A13. Without it, a fresh executor briefed from a bad review lands new
   commits under the old review's bit. */
pred A13_PushAfterReviewUnReviews {
  some a: Agent |
    eventually (Now.ev = Review and Now.issue = a.task
                and after eventually (Now.ev = Push and Target.agent = a
                                      and after (a.task.pr not in Reviewed)))
}

/* =================== who merges, and who reviews =================== */

/* A4. BUILT SO THAT ONLY ONE THING IS WRONG: the executor is confirmed and a
   REPORT preceded the merge, so A5 turns on the review conjunct alone.
   `always s2.holds = c` keeps the merger a campaign session. */
pred A4_ExecutorMergesItsOwnPR {
  some c: Campaign, s2: Session, a: Agent {
    a.peer = s2 and a.task in c.members
    always s2.holds = c
    eventually (Now.ev = Report and Target.agent = a)
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
  some a: Agent {
    some a.peer                        -- a delegate's address is its --name
    eventually (reachable[a] and Now.ev = DeleteDir and Site.mach = a.host
                and after not reachable[a])
  }
}

/* A10. session.als's R3 with the missing half supplied: the record names the
   working session and nothing reads it. */
pred A10_DeleteUnderRecordedExecutor {
  some c: Campaign, a: Agent {
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
  some a: Agent |
    eventually (reachable[a] and eventually (a not in Live and Now.ev = DeleteDir
                                             and Site.mach = a.host))
}

/* A6. The other chair. A confirmation checks that the work EXISTS, never that
   it is right, so with A4 this pair says the rule's subject is the review. */
pred A6_UnreviewedMerge {
  some c: Campaign, s: Session, a: Agent {
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
  some c: Campaign, disj s1, s2: Session, a: Agent {
    a.peer = s2 and a.task in c.members
    s1.smach = s2.smach and always s1.holds = c
    eventually (Now.ev = Report and Target.agent = a)
    eventually (Now.ev = Confirm and By.actor = s1 and Target.agent = a)
    eventually (Now.ev = Review and By.actor = s1 and Now.issue = a.task)
    eventually (Now.ev = MergePR and By.actor = s1 and Now.issue = a.task)
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
pred Cov_Review           { eventually Now.ev = Review }
pred Cov_StandDown        { eventually Now.ev = StandDown }
pred Cov_Retire           { eventually Now.ev = Retire }
pred Cov_AgentDie         { eventually Now.ev = AgentDie }
pred Cov_GuardedRelease   { eventually Now.ev = Release }

/* A14. An executor whose record died is still retirable, on the confirmation
   alone. Restoring the `reachable` guard on `confirm` turns this UNSAT. */
pred A14_UnaddressedExecutorIsRetirable {
  resolveSilenceExternally and coLocatedShutdown
  some a: Agent {
    some a.peer
    eventually (a not in Addressed and Now.ev = Confirm and Target.agent = a)
    eventually (a not in Addressed and Now.ev = Retire and Target.agent = a)
  }
}

/* A14b. And it cannot be stood down: `standDown` carries a message and
   nothing re-creates an address after the delete. So A14's ending is a
   stand-down taken while the record stood, or `retire`'s second disjunct. */
pred A14b_UnaddressedExecutorCannotBeStoodDown {
  A14_UnaddressedExecutorIsRetirable
  some a: Agent {
    some a.peer
    eventually (a not in Addressed and Now.ev = StandDown and Target.agent = a)
  }
}

/* A15. And its pull request still lands. Gating `confirm` on `reachable` made
   a record-less executor's work permanently unmergeable, which `gh pr merge`
   does not do. */
pred A15_UnaddressedExecutorPRLands {
  mergedOnCurrentReview
  some a: Agent {
    some a.peer
    eventually (a not in Addressed and Now.ev = Confirm and Target.agent = a)
    eventually (Now.ev = MergePR and Now.issue = a.task)
  }
}

/* A16. THE ONE-SESSION LANDING, admitted. Run at exactly one Session so the
   absence of a second merger is the scope and not an accident. */
pred A16_AuthorLandsOwnReviewedWork {
  mergedOnCurrentReview
  some s: Session, a: Agent {
    a.peer = s
    eventually (Now.ev = Push and Target.agent = a)
    eventually (Now.ev = Review and By.actor = s and Now.issue = a.task)
    eventually (Now.ev = Confirm and By.actor = s and Target.agent = a)
    eventually (Now.ev = MergePR and By.actor = s and Now.issue = a.task)
  }
}

/* A16b. The author gets no special door. Letting `push` keep `Reviewed` turns
   this SAT, so the currency half of the rule is `push`'s clearing line. */
pred A16b_AuthorCannotMergeOnStaleReview {
  mergedOnCurrentReview
  some s: Session, a: Agent {
    a.peer = s
    eventually (Now.ev = Review and Now.issue = a.task
                and after eventually (Now.ev = Push and Target.agent = a
                                      and after ((always Now.ev != Review)
                                                 and eventually (Now.ev = MergePR
                                                                 and Now.issue = a.task))))
  }
}

/* A18. Hands-on work is no Agent at all. It matters because the confirm
   conjunct ranges over `executorsOf[Now.issue]`, empty here, so it is
   VACUOUSLY true and the review half holds the rule up alone -- which A16,
   having an Agent, cannot see. */
pred A18_AgentLessLandingIsAdmitted {
  mergedOnCurrentReview
  no Agent
  some s: Session, i: Issue {
    eventually (Now.ev = Review  and By.actor = s and Now.issue = i)
    eventually (Now.ev = MergePR and By.actor = s and Now.issue = i)
  }
}

/* A18b. The direction a vacuous conjunct could have swallowed: weaken the
   review half as the confirm half is vacated here and hands-on work lands
   unreviewed with every rule obeyed. */
pred A18b_AgentLessUnreviewedMergeIsBlocked {
  mergedOnCurrentReview
  no Agent
  always Now.ev != Review
  some i: Issue | eventually (Now.ev = MergePR and Now.issue = i)
}

/* A17. Seen live, no longer attributable: the pane proves the executor ALIVE
   and cannot say WHOSE CLAIM it is. */
pred A17_PaneSeesWhatTheRecordLost {
  some c: Campaign, a: Agent {
    some a.peer
    a.task in c.members
    eventually (a in Live and liveUnderLocally[c, a.host]
                and not liveAndReadable[c, a.host])
  }
}

/* ---------------- commands ---------------- */

-- a death or a delete never un-completes
check NoLostWork        for 3 Issue, 2 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps expect 0
-- nothing enforces the retirement rule
check NoOrphan          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps expect 1
-- it does hold once enforced
check NoOrphanIfGuarded for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps expect 0

-- the defect the design records
check OneStepShutdownSuffices    for 2 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps expect 1
-- two steps run from the wrong machine
check TwoStepShutdownSuffices    for 2 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps expect 1
-- the contract as AGENTS.md states it
check TwoStepCoLocatedSuffices   for 2 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps expect 0
-- rule 3's repair reopens nothing
check SilenceResolutionStaysSafe for 2 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 2 Machine, 2 Repo, 1 Topic, 2 Tree, 10 steps expect 0

-- the whole retirement procedure runs
run Sanity                          for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps expect 1
-- a REPORT changes nothing durable
run ReportIsNotEvidence             for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 10 steps expect 1
-- BLOCKED stops the executor
run BlockedAgentDoesNotProceed      for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 10 steps expect 1
-- wait-for-the-answer strands a pane
run SilentAgentIsRetirableUnderWait for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps expect 0
-- rule 3's repair still retires it
run SilentAgentStillRetired         for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps expect 1

run S3_DelegateDiesAfterPushing for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps expect 1
run S4_ReportWithoutPush        for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps expect 1
run S9_OrphanedByLocalDelete    for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Session, exactly 1 Agent, exactly 1 Machine, exactly 2 Repo, exactly 1 Topic, 1 Tree, 12 steps expect 1

-- a close over a delegate on M1
run R3b_CloseFromAnotherMachine  for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 1
-- the global rule would block it
run R3c_GlobalCloseRuleBlocks    for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 0

-- an acquire moves a live agent's HEAD
run R4c_CheckoutSwitchedUnderAgent for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 2 Topic, 1 Tree, 12 steps expect 1
-- what the numbered branch leaves
run R4e_NumberedBranchStillShared for 4 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps expect 1
-- the claim closes it
run R4f_ClaimClosesSameSubtask    for 4 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps expect 0
-- control: the 422 is load-bearing
run R4g_ClaimWithoutAtomicityStillShared for 4 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps expect 1
-- the own-hands hole, the guard that closes it, and the control
run R4h_OwnHandsWorkWithoutClaim for 3 Issue, 1 PR, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 1
run R4i_GuardClosesOwnHandsGap   for 3 Issue, 1 PR, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 0
run R4j_GuardAdmitsClaimedWork   for 3 Issue, 1 PR, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 1

-- the gap TwoStepShutdownSuffices rests on
run R5b_VisibleNotPushed         for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 1
-- co-location, not ownership, is the axis
run R5c_NonLauncherSameMachineIsFine for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps expect 1
-- a local release under a remote executor
run R6_ReleaseUnderRemoteAgent   for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 1
-- a dangling claim is reclaimable
run R6b_ReclaimAfterDeath        for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 14 steps expect 1

/* A1 and A3 run at two agents, where the gap they measure was widest. A9-A12
   need a Tree to delete; A14-A15 need one to delete mid-trace. A16, A16b, A18
   and A18b run at exactly ONE Session, because the absence of a second merger
   is their subject. */
-- closed BY CONSTRUCTION: the claimant writes its own record, so no live claim is unattributable
run A1_UnrecordedExecutorAtTheClose          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 0
-- control: the whole run still happens
run A3_RecordedExecutorRunsTheWholeProtocol  for 3 Issue, 1 PR, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps expect 1

-- the live collision: a self-merge with NO review
run A4_ExecutorMergesItsOwnPR                for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps expect 1
-- still caught, by what was missing
run A5_ReviewRuleBlocksTheCollision          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps expect 0
-- the same merge from the other chair
run A6_UnreviewedMerge                       for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 1
-- nobody merges unread
run A7_ReviewRuleBlocksUnreviewed            for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 0
-- control: two-session landing runs
run A8_ReviewRuleAdmitsTheLanding            for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps expect 1

-- the record has the tree's lifetime
run A9_RecordDiesWithTheDirectory            for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 1
-- session.als's R3, reached from here
run A10_DeleteUnderRecordedExecutor          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 1
-- and closed by reading the record
run A11_ReadableGateBlocksTheDelete          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 0
-- control
run A12_ReadableGateAdmitsTheDelete          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 1
-- a push retires a review
run A13_PushAfterReviewUnReviews             for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps expect 1
-- a record dead with its directory still ends in a lawful retire
run A14_UnaddressedExecutorIsRetirable       for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps expect 1
-- and never a stand-down: that one carries a message, so it stays gated
run A14b_UnaddressedExecutorCannotBeStoodDown for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps expect 0
-- and its pull request still lands
run A15_UnaddressedExecutorPRLands           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 16 steps expect 1
-- the one-session landing
run A16_AuthorLandsOwnReviewedWork           for 3 Issue, 1 PR, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps expect 1
-- and a push retires that permission
run A16b_AuthorCannotMergeOnStaleReview      for 3 Issue, 1 PR, 1 Campaign, 1 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 14 steps expect 0
-- attribution, not liveness, is the split's subject
run A17_PaneSeesWhatTheRecordLost            for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 1
-- hands-on work, reviewed and merged by one session, at `0 Agent`
run A18_AgentLessLandingIsAdmitted           for 3 Issue, 1 PR, 1 Campaign, 1 Session, 0 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 1
-- and unreviewed it does not land. The pair matters because the confirm conjunct is VACUOUS at `0 Agent`, so the review half holds the rule up alone
run A18b_AgentLessUnreviewedMergeIsBlocked   for 3 Issue, 1 PR, 1 Campaign, 1 Session, 0 Agent, 1 Machine, 2 Repo, 1 Topic, 1 Tree, 12 steps expect 0

-- every own event fires in some trace
run Cov_LaunchAgent      for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_Work             for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_Push             for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_Status           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_Answer           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_Report           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_Blocked          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_Decide           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_Confirm          for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_ConfirmElsewhere for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_Review           for 3 Issue, 2 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 1
run Cov_StandDown        for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_Retire           for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_AgentDie         for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run Cov_GuardedRelease   for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
