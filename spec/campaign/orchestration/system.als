/*
 * Agents and how a campaign session coordinates them: launch, work, the four
 * messages, review, stand-down and retirement. It opens session/system because
 * every agent has a launcher and every message has a session at one end, and it
 * is the top entity, so this module composed is the whole model.
 *
 *   Agent      one participant working one sub-issue: which role it has, which
 *              sub-issue, which machine, which session launched it, which
 *              branch, and -- when the agent IS a campaign session working its
 *              own claim -- which session that is.
 *   Role       what an agent is for: an Executor works the sub-issue on its
 *              branch; a Planner filed it and distributes it, holding no
 *              claim of its own.
 *   Launched   agents that have been launched, and Live those still running.
 *   LocalOnly  agents holding work that exists only on their host.
 *   PushedToRemote  agents whose branch is on the remote, a different fact.
 *   Reported, Asked, Answered, Waiting   the four messages.
 *   Confirmed  agents a session has itself observed to hold nothing local-only.
 *   StandDownTaken  agents that have been told to stand down.
 *   Retired    agents whose workspace has been destroyed.
 *   Reviewed   a bit on the PULL REQUEST, not on the agent: a review outlives
 *              the agent exactly as the pull request does.
 *   Target     the observer: which agent the current event is about.
 *
 * The three execution modes -- own hands, in-process subagent, herdr delegate
 * -- are ONE `Launch` here: nothing a model can say about reachable states
 * differs between them.
 *
 * ATTRIBUTION IS DERIVED, NOT STORED. `holder` reads which agent a sub-issue's
 * claim belongs to off ONE fact a later session can still see: the checkout in
 * its campaign directory is on the claim's branch. It says nothing about
 * liveness, deliberately -- every caller applies that itself, `AttributionIsSound`
 * by quantifying over `Live` and `holderStaysAttributed` by guarding on it, so
 * a holder that has died is still the holder of the workspace it left. Nothing
 * writes it and nothing can go stale against it, which is what replaced the
 * record whose `session` field this entity used to defer to.
 * `AttributionIsSound` is what that costs, and R4c is its counterexample.
 *
 * NOT MODELLED: whether an agent is any good; that an agent answers about
 * itself only; that STAND DOWN is a request a peer may refuse; and two of the
 * three merge conditions in AGENTS.md -- that the reviewer did not write the
 * commits, because nothing here records who set `Reviewed`, and that the branch
 * contains the current main, because this model has one pull request per issue
 * and no shared branch moving under another.
 */
module orchestration/system

open session/system

/* One participant working one sub-issue: a campaign session working its own
   claim, whose session `peer` names, or a delegate that session launched. */
sig Agent {
  role:     one Role,
  task:     one Issue,
  host:     one Machine,
  launcher: one Session,
  branch:   one Branch,
  /* Set when the agent IS a campaign session working its own claim. A delegate
     is named at launch; a session's own claim is named by nothing anybody else
     chose, which is why only it needs a record. */
  peer:     lone Session
}

/* What an agent is FOR. An Executor works a sub-issue on its branch. A Planner
   is a session's own atom (`some peer`, pinned by PlannerIsASession) on a
   sub-issue it filed and distributes: it never takes `work` or `report`, so of
   the state below it does not share LocalOnly, PushedToRemote and Reported
   (PlannerNeverLocalOnly, PlannerNeverReports), and it shares the rest --
   Asked, Answered and Waiting, three of the four messages with REPORT's own bit
   the one it does not take; Confirmed; the shutdown bits, StandDownTaken among
   them, so the fourth message is counted there and not twice; and
   `branch`. What it executes itself is an Executor atom of the same session. A
   delegate launch is the planner's act, and `launch` says so. A third kind is
   added here the same way, and takes whatever of the state below it turns out
   not to share. */
abstract sig Role {}
one sig Executor extends Role {}
one sig Planner  extends Role {}

var sig Launched in Agent {}
var sig Live     in Agent {}
/* THE one encoding of "only on its host": uncommitted, unpushed, or on a
   branch no remote has. */
var sig LocalOnly    in Agent {}
/* Its branch is on the remote -- checkable from anywhere, and a different fact
   from LocalOnly. The gap between the two is R5b. */
var sig PushedToRemote  in Agent {}
var sig Reported in Agent {}
var sig Asked    in Agent {}
var sig Answered in Agent {}
var sig Waiting  in Agent {}
/* The SESSION has itself observed that this agent holds nothing
   local-only. */
var sig Confirmed in Agent {}
var sig StandDownTaken in Agent {}
var sig Retired  in Agent {}

/* A bit on the PULL REQUEST, not on the agent: the review outlives the
   agent exactly as the pull request does, and a fresh agent briefed from
   the review inherits it. */
var sig Reviewed in PullRequest {}

one sig Target { var agent: lone Agent }

fact AgentWellFormed {
  all c: Campaign | c.campaignIssue not in Agent.task
  all a: Agent | some a.peer implies (a.launcher = a.peer and a.host = a.peer.machine)
  all a: Agent | a.role = Planner implies some a.peer   -- a planner is a session, never a delegate
  always Live in Launched
  always Retired in Launched
  always no Live & Retired
  always PushedToRemote in PushedToRemote'     -- a branch on the remote stays on the remote
}

pred coLocated[s: Session, a: Agent] { s.machine = a.host }

/* WHO HOLDS A SUB-ISSUE'S CLAIM: the WORKSPACE the ref is checked out in, not
   a session. No record, so nothing to go stale, and the answer survives a
   harness restart and a rename -- neither touches a checkout. Empty is a real
   answer: a claimed branch nobody has checked out is a branch with no holder,
   which is what `campaign-claim live` prints as its second group.

   NOT herdr's cwd, which is what a first cut of this read and what #176's body
   said before it was corrected. Measured on this machine 2026-09-04: that join
   found ZERO claims, because herdr reports where a session was STARTED, a base
   executor works in a worktree, and the repository owning that worktree is not
   even the clone the session sits in. So `campaign-claim live` reads checkouts
   instead -- `git worktree list` over the base root, every campaign clone, and
   each session's own repo root -- and this `fun` is that sweep: a holder is an
   agent whose campaign-directory checkout is on its branch. herdr's row is
   still read for two things -- liveness, and its `cwd` as one more root to
   sweep and as the tie between an unnamed session and this campaign -- but
   never for which branch anyone holds. */
fun holder[i: Issue]: set Agent {
  { a: Agent | a.task = i
               and campaignDirAt[campaignOf[i], a.host].checkedOut[i.repo] = a.branch }
}

pred liveUnder[c: Campaign] {
  some a: Agent | a in Live and (a.task in c.memberIssues or a.host in machinesHolding[c])
}
/* What one session can actually read: `herdr agent list` on its own machine. */
/* A live agent whose SESSION's name says it belongs to some other campaign.
   The name is evidence about whose work it is and nothing else is: with the
   record gone, a close reading `herdr agent list` has the name, the cwd, and
   no third thing. A delegate has no session to be named, so it is never this. */
pred namedForAnother[a: Agent, c: Campaign] {
  some a.peer and some a.peer.campaignNamed and a.peer.campaignNamed != c
}

/* What one session can actually read: `herdr agent list` on its own machine.

   TWO DISJUNCTS, AND THEY ARE NOT THE SAME CLAIM. The first is an agent on a
   sub-issue of THIS campaign, which blocks whatever it is called. The second
   is machine-wide -- every agent on a machine holding the campaign -- because a
   session working the campaign directory holds no sub-issue and would
   otherwise be invisible.

   The second is where the name enters. Machine-wide alone made every campaign's
   close gate read the identical set, so closing one campaign asked another's
   sessions to stand down; and a session named for another campaign is the one
   case where the machine says "here" and the evidence says "not this one".
   A name that says NOTHING is not evidence either way, so the cwd decides: that
   agent blocks while it sits under the base tree, which is the direction that
   costs a question rather than somebody's work.

   #187 QUESTION 6 SETTLED IT BY MOVING THE MODEL, not the reader. This used to
   block on an unnamed agent anywhere on the machine while `classify` counted an
   unnamed session only when its cwd was under the base root -- a spec wider
   than its one reader, which is a false statement about the code however
   cautious it sounds. The reader's narrowing is the load-bearing half: with no
   name and no tree, nothing on the machine ties a session to THIS campaign, so
   blocking on it would block on it for every campaign here at once, and closing
   one would ask another's sessions to stand down.

   There was no third piece of evidence to add, which is what decided the
   direction. So the residual case is now IN the model rather than named beside
   it: a session that both renamed to nothing and left the tree does not block,
   and N7 is the witness that says so out loud. A hole the model states is one
   a reader can find. */
/* A live agent whose SESSION is named for THIS campaign. The name is the only
   thing that attributes a session to a campaign: the cwd cannot, since a
   session under the tree is under every campaign's tree at once. */
pred namedForThis[a: Agent, c: Campaign] {
  some a.peer and a.peer.campaignNamed = c
}

pred liveUnderLocally[c: Campaign, m: Machine] {
  some a: Agent | a in Live and a.host = m
    and (a.task in c.memberIssues
         or (m in machinesHolding[c]
             and (namedForThis[a, c]
                  or (no a.peer.campaignNamed and a.peer in UnderBase))))
}

/* github's `closable` is the GitHub half. These two add the half that needs
   an agent: the rule as written, and the honest local reading a session on
   one machine can actually perform. There is no third, narrower reading any
   more -- the close reads `herdr agent list` and nothing keyed to a tree. */
pred closableWithAgents[c: Campaign]          { closable[c] and not liveUnder[c] }
pred closableLocally[s: Session, c: Campaign] { closable[c] and not liveUnderLocally[c, s.machine] }

/* campaign-<N>/<issue>-<topic>: two agents share a branch only when
   campaign, sub-issue and topic all match. That it separates two SUB-ISSUES is
   definitional and is not run; R4e is what it leaves. */
pred sameBranch[a1, a2: Agent] {
  campaignOf[a1.task] = campaignOf[a2.task]
  and a1.task = a2.task
  and a1.branch = a2.branch
}

/* ---------------- observable events ---------------- */

one sig Work, Push, Status, Answer, Report, Blocked, Decide,
        Confirm, ConfirmElsewhere, Review, StandDown, Retire,
        AgentDie extends Event {}

fun orchestrationOwn: set Event {
  Work + Push + Status + Answer + Report + Blocked + Decide
  + Confirm + ConfirmElsewhere + Review + StandDown + Retire
  + AgentDie
}
/* `DeleteDir` is NOT here any more: no bit of this entity has the directory's
   lifetime once attribution is derived, so a delete falls through and frames
   everything. `MergePullRequest` is not here either: session/system.als gives it
   a session and this entity only guards which session that may be, which is a
   discipline over the event rather than a disjunct on it. */
fun orchestrationActed: set Event { orchestrationOwn + Launch + Release }

/* The bits divide by how long they live: a pull request's, and a process's.
   None has a directory's any more. */
pred keepMessages     { Reported' = Reported and Asked' = Asked and Answered' = Answered and Waiting' = Waiting }
pred keepReview   { Reviewed' = Reviewed }
pred keepLife     { Live' = Live and LocalOnly' = LocalOnly and PushedToRemote' = PushedToRemote and Confirmed' = Confirmed }
pred keepShutdown { StandDownTaken' = StandDownTaken and Retired' = Retired }
pred keepLaunched     { Launched' = Launched }
pred agentFrame   { keepLife and keepReview and keepMessages and keepShutdown and keepLaunched }

pred launch[a: Agent] {
  Now.event = Launch
  a not in Launched
  a.launcher = Who.session
  a.host = Where.machine
  Now.issue = a.task
  /* Only a DELEGATE's launch waits on the ref, and the asymmetry is a hole
     measured rather than a shortcut. Every claim is a ref now -- the record
     that used to stand in for one where no commit would land is gone, and a
     repo-less sub-issue cuts its ref on the base -- so the ref is what a
     session working its own claim ought to hold too. That it can reach `work`
     without one is R4h, and `claimBeforeWork` is the discipline that closes
     it. DO NOT strengthen this to require the ref unconditionally: it would
     close R4h here, where nothing runs, and hide the gap the guard exists
     for. */
  no a.peer implies a.task in Claimed
  /* A delegate is the planner's act: the launching session holds a live
     Planner atom on this sub-issue, the one that filed and distributes it. A
     session working its own claim needs none -- the one-executor shape. */
  no a.peer implies (some p: role.Planner | p.peer = Who.session and p.task = a.task and p in Live)
  campaignDirAt[Who.session.worksOn, a.host].checkedOut[a.task.repo] = a.branch
  Launched' = Launched + a
  Live'     = Live + a
  LocalOnly' = LocalOnly and PushedToRemote' = PushedToRemote and Confirmed' = Confirmed
  keepReview and keepMessages and keepShutdown
  Target.agent = a
}

/* Clears an earlier confirmation here rather than at the point it is read.
   The executor's edge: a planner that executes a sub-issue itself is an
   Executor atom of the same session, so no Planner atom is ever LocalOnly. */
pred work[a: Agent] {
  a in Live and a not in Waiting and a.role = Executor
  LocalOnly' = LocalOnly + a
  Confirmed' = Confirmed - a
  Live' = Live and PushedToRemote' = PushedToRemote
  keepReview and keepMessages and keepShutdown and keepLaunched
  Now.event = Work and Now.issue = a.task and Target.agent = a and no Who.session
}

/* Two different facts move, and only the first is readable from another
   machine. It does not set Confirmed -- the session has not looked yet -- and
   it clears `Reviewed`, because A REVIEW IS OF A PULL REQUEST AT A REVISION. */
pred push[a: Agent] {
  a in Live and a in LocalOnly
  LocalOnly'    = LocalOnly - a
  PushedToRemote'  = PushedToRemote + a
  Reviewed' = Reviewed - a.task.pullRequest
  Live' = Live and Confirmed' = Confirmed
  keepMessages and keepShutdown and keepLaunched
  Now.event = Push and Now.issue = a.task and Target.agent = a and no Who.session
}

/* Asking and answering are two events because STATUS queues behind the
   agent's current turn, so a late reply is ordinary rather than a symptom. */
pred status[a: Agent] {
  a in Live
  a.task in Who.session.worksOn.memberIssues
  Asked' = Asked + a
  Answered' = Answered - a
  Reported' = Reported and Waiting' = Waiting
  keepLife and keepReview and keepShutdown and keepLaunched
  Now.event = Status and Now.issue = a.task and Target.agent = a
}

/* A gone agent leaves the question outstanding forever: rule 3. */
pred answer[a: Agent] {
  a in Live and a in Asked
  Answered' = Answered + a
  Asked' = Asked and Reported' = Reported and Waiting' = Waiting
  keepLife and keepReview and keepShutdown and keepLaunched
  Now.event = Answer and Now.issue = a.task and Target.agent = a and no Who.session
}

/* A prompt to verify, never the verification, so this event writes NOTHING
   but the claim itself. A REPORT names a pull request, so it is the
   executor's. */
pred report[a: Agent] {
  a in Live and a.role = Executor
  Reported' = Reported + a
  Asked' = Asked and Answered' = Answered and Waiting' = Waiting
  keepLife and keepReview and keepShutdown and keepLaunched
  Now.event = Report and Now.issue = a.task and Target.agent = a and no Who.session
}

/* Silence is not this message: an agent that stops without sending it
   looks identical to one thinking. */
pred blocked[a: Agent] {
  a in Live and a not in Waiting
  Waiting' = Waiting + a
  Reported' = Reported and Asked' = Asked and Answered' = Answered
  keepLife and keepReview and keepShutdown and keepLaunched
  Now.event = Blocked and Now.issue = a.task and Target.agent = a and no Who.session
}

pred decide[a: Agent] {
  a in Live
  a in Waiting
  a.task in Who.session.worksOn.memberIssues
  Waiting' = Waiting - a
  Reported' = Reported and Asked' = Asked and Answered' = Answered
  keepLife and keepReview and keepShutdown and keepLaunched
  Now.event = Decide and Now.issue = a.task and Target.agent = a
}

/* Stated as an ABSENCE, because "confirm the branch is pushed" has no passing
   form for an agent that correctly produced nothing. It reads a tree on the
   session's own machine and sends the agent nothing, which is why a dead
   agent's pull request still lands. */
pred confirm[a: Agent] {
  coLocated[Who.session, a]
  a.task in Who.session.worksOn.memberIssues
  a not in LocalOnly
  Confirmed' = Confirmed + a
  Live' = Live and LocalOnly' = LocalOnly and PushedToRemote' = PushedToRemote
  keepReview and keepMessages and keepShutdown and keepLaunched
  Now.event = Confirm and Now.issue = a.task and Target.agent = a
}

/* It reads the SESSION's working tree, so there is no `a not in LocalOnly` guard:
   nothing on this machine could fail it. That is the defect, not a shortcut. */
pred confirmElsewhere[a: Agent] {
  not coLocated[Who.session, a]
  a.task in Who.session.worksOn.memberIssues
  Confirmed' = Confirmed + a
  Live' = Live and LocalOnly' = LocalOnly and PushedToRemote' = PushedToRemote
  keepReview and keepMessages and keepShutdown and keepLaunched
  Now.event = ConfirmElsewhere and Now.issue = a.task and Target.agent = a
}

/* KEYED ON THE ISSUE, NOT ON AN AGENT: the review reads GitHub, so keying it
   to an agent made hands-on work unreviewable and so unmergeable. No guard on
   who commissions it -- the property needs independence of JUDGEMENT, not of
   TASKING, and a one-session campaign has nobody else to launch it. The named
   limit: the launcher writes the reviewer's brief. */
pred review[i: Issue] {
  Now.event = Review
  Now.issue = i
  some i.pullRequest and i.pullRequest not in Reviewed
  i in Who.session.worksOn.memberIssues
  Reviewed' = Reviewed + i.pullRequest
  keepLife and keepMessages and keepShutdown and keepLaunched
  no Target.agent
}

/* It does not destroy its own workspace, which is why standing down and
   retiring are two events and the agent is still Live between them. */
pred standDown[a: Agent] {
  a in Live and a not in StandDownTaken
  a.task in Who.session.worksOn.memberIssues
  StandDownTaken' = StandDownTaken + a
  Retired' = Retired
  keepLife and keepReview and keepMessages and keepLaunched
  Now.event = StandDown and Now.issue = a.task and Target.agent = a
}

/* Anything still in LocalOnly at this instant is gone. The second disjunct is not
   a convenience: an agent that already died is retired with no stand-down,
   and that path skips every message, which is why the disciplines guard the
   retire and not only the stand-down. */
pred retire[a: Agent] {
  (a in StandDownTaken or a not in Live) and a in Launched and a not in Retired
  a.task in Who.session.worksOn.memberIssues
  Retired' = Retired + a
  Live'    = Live - a
  LocalOnly' = LocalOnly and PushedToRemote' = PushedToRemote and Confirmed' = Confirmed
  StandDownTaken' = StandDownTaken
  keepReview and keepMessages and keepLaunched
  Now.event = Retire and Now.issue = a.task and Target.agent = a
}

/* Its disk survives, so LocalOnly is untouched: one that died after pushing has
   succeeded. */
pred agentDie[a: Agent] {
  a in Live
  Live' = Live - a
  LocalOnly' = LocalOnly and PushedToRemote' = PushedToRemote and Confirmed' = Confirmed
  keepReview and keepMessages and keepShutdown and keepLaunched
  Now.event = AgentDie and Now.issue = a.task and Target.agent = a and no Who.session
}

/* Both guards are what a session can actually read. Liveness elsewhere is
   not, so R6 is the residue that leaves. */
pred agentRelease {
  Now.event = Release
  no a: Agent | a.task = Now.issue and a in PushedToRemote
  no a: Agent | a.task = Now.issue and a.host = Who.session.machine and a in Live
  agentFrame
  no Target.agent
}

pred orchestrationInit {
  no Launched and no Live and no LocalOnly and no PushedToRemote
  no Reported and no Asked and no Answered
  no Waiting and no Confirmed and no Reviewed and no StandDownTaken and no Retired
}

pred orchestrationStep {
  (Now.event = Stutter and agentFrame and no Target.agent)
  or (some a: Agent |
        launch[a] or work[a] or push[a]
        or status[a] or answer[a] or report[a]
        or blocked[a] or decide[a] or confirm[a] or confirmElsewhere[a]
        or standDown[a] or retire[a] or agentDie[a])
  or (some i: Issue | review[i])
  or agentRelease
  or (Now.event not in Stutter + orchestrationActed and agentFrame and no Target.agent)
}

fact OrchestrationTrace { orchestrationInit and always orchestrationStep }
