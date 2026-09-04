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
 *   Plane      which half of the work an event writes: the campaign plane (the
 *              issues, the index, the claims, the directories) or the code
 *              plane (the commits and what carries them). `Role` itself is
 *              session/system.als's, because it is a property of a session.
 *   Launched   agents that have been launched, and Live those still running.
 *   LocalOnly  agents holding work that exists only on their host.
 *   PushedToRemote  agents whose branch is on the remote, a different fact.
 *   Addressable     agents a campaign session can send a message to.
 *   Reported, Asked, Answered, Waiting   the four messages.
 *   Confirmed  agents a session has itself observed to hold nothing local-only.
 *   StandDownTaken          agents that have been told to stand down.
 *   StoodDownCommentPosted  agents whose stand-down is on the campaign issue.
 *   Retired    agents whose workspace has been destroyed.
 *   Reviewed   a bit on the PULL REQUEST, not on the agent: a review outlives
 *              the agent exactly as the pull request does.
 *   Target     the observer: which agent the current event is about.
 *
 * The three execution modes -- own hands, in-process subagent, herdr delegate
 * -- are ONE `Launch` here: nothing a model can say about reachable states
 * differs between them.
 *
 * NOT MODELLED: whether an agent is any good; that an agent answers about
 * itself only; that STAND DOWN is a request a peer may refuse; which session a
 * claim's RECORD names -- `claimedIssues` is attributed to the acting session,
 * so at a delegate launch the planner's session holds the claim here, where
 * AGENTS.md's "a planner holds no claim of its own" speaks of the record's
 * `session` field, which no atom carries; and two of the
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

/* `Role` is session/system.als's now: it is what a SESSION is for, read from
   its name, and an agent inherits it. An Executor works a sub-issue on its
   branch. A Planner is a session's own atom (`some peer`, pinned by
   PlannerIsASession) on a sub-issue it filed and distributes: it never takes
   `work` or `report`, so of the state below it does not share LocalOnly,
   PushedToRemote and Reported (PlannerNeverLocalOnly, PlannerNeverReports), and
   it shares the rest -- Asked, Answered and Waiting, three of the four messages
   with REPORT's own bit the one it does not take; Confirmed; the shutdown bits,
   StandDownTaken among them, so the fourth message is counted there and not
   twice; Addressable; and `branch`. A delegate launch is the planner's act, and
   `launch` says so. A third kind is added in session/system.als the same way,
   and takes whatever of the state below it turns out not to share.

   WHAT #185 RETIRED: a planner working a sub-issue by its own hands used to be
   "an Executor atom of the same session". AgentInheritsSessionRole below forbids
   that, so a planner session reaches `work` along no edge at all, and its code
   modes are a delegate or a separate executor session. */

/* Which half of the work an event writes. The two are disjoint and do not
   cover: an event on NEITHER plane is one no role rule speaks to.

   THIS entity, not session/system.als where `Role` lives, because the code
   plane names `Work` and `Push`, which are declared here and which an entity
   below may not reach up to.

   `MergePullRequest` is on neither plane deliberately: AGENTS.md's three merge
   conditions hold it and none of them names a role, so putting it on the code
   plane would make a planner unable to land a reviewed pull request and putting
   it on the campaign plane would let one land any. `Review`, `Launch`, the four
   messages, `Retire` and the survey events are on neither because they are not
   writes to either half. */
abstract sig Plane {}
one sig CampaignPlane, CodePlane extends Plane {}

fun campaignPlaneEvents: set Event {
  FileCampaignIssue + AddMember + RemoveMember + CloseIssue + WriteBody
  + Claim + Release + CreateDir + DeleteDir
}
fun codePlaneEvents: set Event { Work + Push + CommitLocal + OpenPullRequest }

/* `lone` holds because the two sets above are disjoint; DisjointPlanes in
   checks.als is what says so rather than this comment. */
fun planeOf[e: Event]: lone Plane {
  { p: Plane | (p = CampaignPlane and e in campaignPlaneEvents)
            or (p = CodePlane      and e in codePlaneEvents) }
}

/* `Session` also has a `role` field now, so the RELATIONAL spelling `role.Planner`
   no longer says which entity's -- it resolves to Agent + Session and every
   reader of it wants agents. This names that set once; the dotted `a.role` form
   is unambiguous and is left alone. */
fun plannerAgents: set Agent { (Agent <: role).Planner }

var sig Launched in Agent {}
var sig Live     in Agent {}
/* THE one encoding of "only on its host": uncommitted, unpushed, or on a
   branch no remote has. */
var sig LocalOnly    in Agent {}
/* Its branch is on the remote -- checkable from anywhere, and a different fact
   from LocalOnly. The gap between the two is R5b. */
var sig PushedToRemote  in Agent {}
var sig Reported in Agent {}
/* A campaign session can reach it. A DIRECTORY FACT: it dies with the tree,
   and it is keyed to no reader, so any later session inherits every address in
   it. */
var sig Addressable in Agent {}
var sig Asked    in Agent {}
var sig Answered in Agent {}
var sig Waiting  in Agent {}
/* The SESSION has itself observed that this agent holds nothing
   local-only. */
var sig Confirmed in Agent {}
var sig StandDownTaken in Agent {}
/* The agent has posted `STOOD DOWN <name> <session-id>` on the campaign
   issue: the agreement made durable where a close gate can read it. Set only
   by the agent itself, after it stood down, and never for one still LocalOnly
   -- the comment says its work is on GitHub. */
var sig StoodDownCommentPosted    in Agent {}
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
  /* AgentInheritsSessionRole. An agent that IS a session has that session's
     role; a delegate has no session and its role is free. This is what makes
     "a planner never touches code" a fact of the model rather than a
     discipline: `work` and `report` require `a.role = Executor`, so a session
     whose role is Planner has no atom that can take either. Q2c measures which
     of the two forbids it. */
  all a: Agent | some a.peer implies a.role = a.peer.role
  always Live in Launched
  always Retired in Launched
  always no Live & Retired
  always PushedToRemote in PushedToRemote'     -- a branch on the remote stays on the remote
}

pred coLocated[s: Session, a: Agent] { s.machine = a.host }

pred liveUnder[c: Campaign] {
  some a: Agent | a in Live and (a.task in c.memberIssues or a.host in machinesHolding[c])
}
/* What one session can actually read: `herdr agent list` on its own machine. */
pred liveUnderLocally[c: Campaign, m: Machine] {
  some a: Agent | a in Live and a.host = m and (a.task in c.memberIssues or m in machinesHolding[c])
}
/* Whether any campaign session can reach this agent at all. Separate from
   liveness on purpose: "I can see it in a list" and "I can send it a message"
   are different questions, and this is the second. */
pred addressable[a: Agent] { a in Addressable }

/* What a close gate can read AND ATTRIBUTE, a strictly smaller set than what
   it can see. Liveness is readable for BOTH kinds of agent without any
   record -- a session working its own claim holds a pane and is listed too --
   but a pane gives a name and a campaign session's cwd is the base root,
   so only the record ties the name to a claim. The split's subject is
   attribution, and A17 is the residual gap measured. */
pred liveAndAddressable[c: Campaign, m: Machine] {
  some a: Agent | a in Live and a.host = m
    and (a.task in c.memberIssues or m in machinesHolding[c])
    and (no a.peer or addressable[a])
}
/* github's `closable` is the GitHub half. These three add the half that needs
   an agent. */
pred closableWithAgents[c: Campaign]          { closable[c] and not liveUnder[c] }
pred closableLocally[s: Session, c: Campaign] { closable[c] and not liveUnderLocally[c, s.machine] }
pred closableAsRead[s: Session, c: Campaign]  { closable[c] and not liveAndAddressable[c, s.machine] }

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
        Confirm, ConfirmElsewhere, Review, StandDown, StoodDownPosted, Retire,
        AgentDie extends Event {}

fun orchestrationOwn: set Event {
  Work + Push + Status + Answer + Report + Blocked + Decide
  + Confirm + ConfirmElsewhere + Review + StandDown + StoodDownPosted + Retire
  + AgentDie
}
/* `DeleteDir` is here because this entity has a bit with the directory's
   lifetime. `MergePullRequest` is NOT: session/system.als gives it a session and this
   entity only guards which session that may be, which is a discipline over the event
   rather than a disjunct on it, so the merge falls through and frames
   everything. */
fun orchestrationActed: set Event { orchestrationOwn + Launch + Release + DeleteDir }

/* The bits divide by how long they live: a directory fact, a pull request's,
   and a process's. */
pred keepMessages     { Reported' = Reported and Asked' = Asked and Answered' = Answered and Waiting' = Waiting }
pred keepAddress  { Addressable' = Addressable }
pred keepReview   { Reviewed' = Reviewed }
pred keepLife     { Live' = Live and LocalOnly' = LocalOnly and PushedToRemote' = PushedToRemote and Confirmed' = Confirmed }
pred keepShutdown { StandDownTaken' = StandDownTaken and StoodDownCommentPosted' = StoodDownCommentPosted and Retired' = Retired }
pred keepLaunched     { Launched' = Launched }
pred agentFrame   { keepLife and keepReview and keepMessages and keepAddress and keepShutdown and keepLaunched }

/* `Addressable` is set unconditionally: a delegate is addressable from its
   `--name`, a session from the record it wrote at the claim, which precedes
   every launch. A1 is the gap that closes. */
pred launch[a: Agent] {
  Now.event = Launch
  a not in Launched
  a.launcher = Who.session
  a.host = Where.machine
  Now.issue = a.task
  /* Only a delegate's launch waits on a branch existing. A session working
     with its own hands starts on work that may land no commit at all, where
     the claim is a record and no ref. DO NOT strengthen this to require the
     ref unconditionally: it would model a create-ref that does not happen, and
     the record is what must hold on this edge -- `claimBeforeWork` says so. */
  no a.peer implies a.task in Claimed
  /* A delegate is the planner's act: the launching session holds a live
     Planner atom on this sub-issue, the one that filed and distributes it. A
     session working its own claim needs none -- the one-executor shape. */
  no a.peer implies (some p: plannerAgents | p.peer = Who.session and p.task = a.task and p in Live)
  campaignDirAt[Who.session.worksOn, a.host].checkedOut[a.task.repo] = a.branch
  Launched' = Launched + a
  Live'     = Live + a
  Addressable' = Addressable + a
  LocalOnly' = LocalOnly and PushedToRemote' = PushedToRemote and Confirmed' = Confirmed
  keepReview and keepMessages and keepShutdown
  Target.agent = a
}

/* `Addressable` is the one bit here that does not outlive the tree, and only
   for a session working its own claim: stripping a delegate too would make it
   permanently unreachable when a directory its `--name` never depended on is
   deleted. Scoped to the deleted tree's own campaign and machine. */
pred agentDeleteDir {
  Now.event = DeleteDir
  Addressable' = Addressable
    - { a: Agent | some a.peer
                   and a.host = Where.machine
                   and campaignOf[a.task] in (OnDisk - OnDisk').campaign }
  keepLife and keepReview and keepMessages and keepShutdown and keepLaunched
  no Target.agent
}

/* Clears an earlier confirmation here rather than at the point it is read.
   The executor's edge: no Planner atom is ever LocalOnly, and after #185 no
   Planner SESSION reaches this edge either -- AgentInheritsSessionRole leaves it
   no Executor atom to take it with. */
pred work[a: Agent] {
  a in Live and a not in Waiting and a.role = Executor
  LocalOnly' = LocalOnly + a
  Confirmed' = Confirmed - a
  Live' = Live and PushedToRemote' = PushedToRemote
  keepReview and keepMessages and keepAddress and keepShutdown and keepLaunched
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
  keepMessages and keepAddress and keepShutdown and keepLaunched
  Now.event = Push and Now.issue = a.task and Target.agent = a and no Who.session
}

/* Asking and answering are two events because STATUS queues behind the
   agent's current turn, so a late reply is ordinary rather than a symptom. */
pred status[a: Agent] {
  addressable[a]
  a.task in Who.session.worksOn.memberIssues
  Asked' = Asked + a
  Answered' = Answered - a
  Reported' = Reported and Waiting' = Waiting
  keepLife and keepReview and keepAddress and keepShutdown and keepLaunched
  Now.event = Status and Now.issue = a.task and Target.agent = a
}

/* A gone agent leaves the question outstanding forever: rule 3. */
pred answer[a: Agent] {
  a in Live and a in Asked
  Answered' = Answered + a
  Asked' = Asked and Reported' = Reported and Waiting' = Waiting
  keepLife and keepReview and keepAddress and keepShutdown and keepLaunched
  Now.event = Answer and Now.issue = a.task and Target.agent = a and no Who.session
}

/* A prompt to verify, never the verification, so this event writes NOTHING
   but the claim itself. A REPORT names a pull request, so it is the
   executor's. */
pred report[a: Agent] {
  a in Live and a.role = Executor
  Reported' = Reported + a
  Asked' = Asked and Answered' = Answered and Waiting' = Waiting
  keepLife and keepReview and keepAddress and keepShutdown and keepLaunched
  Now.event = Report and Now.issue = a.task and Target.agent = a and no Who.session
}

/* Silence is not this message: an agent that stops without sending it
   looks identical to one thinking. */
pred blocked[a: Agent] {
  a in Live and a not in Waiting
  Waiting' = Waiting + a
  Reported' = Reported and Asked' = Asked and Answered' = Answered
  keepLife and keepReview and keepAddress and keepShutdown and keepLaunched
  Now.event = Blocked and Now.issue = a.task and Target.agent = a and no Who.session
}

pred decide[a: Agent] {
  addressable[a]
  a in Waiting
  a.task in Who.session.worksOn.memberIssues
  Waiting' = Waiting - a
  Reported' = Reported and Asked' = Asked and Answered' = Answered
  keepLife and keepReview and keepAddress and keepShutdown and keepLaunched
  Now.event = Decide and Now.issue = a.task and Target.agent = a
}

/* Stated as an ABSENCE, because "confirm the branch is pushed" has no passing
   form for an agent that correctly produced nothing. NO `addressable` guard,
   deliberately: it reads a tree on the session's own machine and sends the
   agent nothing. A14/A15 are what gating it would cost. */
pred confirm[a: Agent] {
  coLocated[Who.session, a]
  a.task in Who.session.worksOn.memberIssues
  a not in LocalOnly
  Confirmed' = Confirmed + a
  Live' = Live and LocalOnly' = LocalOnly and PushedToRemote' = PushedToRemote
  keepReview and keepMessages and keepAddress and keepShutdown and keepLaunched
  Now.event = Confirm and Now.issue = a.task and Target.agent = a
}

/* It reads the SESSION's working tree, so there is no `a not in LocalOnly` guard:
   nothing on this machine could fail it. That is the defect, not a shortcut. */
pred confirmElsewhere[a: Agent] {
  not coLocated[Who.session, a]
  a.task in Who.session.worksOn.memberIssues
  Confirmed' = Confirmed + a
  Live' = Live and LocalOnly' = LocalOnly and PushedToRemote' = PushedToRemote
  keepReview and keepMessages and keepAddress and keepShutdown and keepLaunched
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
  keepLife and keepMessages and keepAddress and keepShutdown and keepLaunched
  no Target.agent
}

/* It does not destroy its own workspace, which is why standing down and
   retiring are two events and the agent is still Live between them. */
pred standDown[a: Agent] {
  addressable[a]
  a in Live and a not in StandDownTaken
  a.task in Who.session.worksOn.memberIssues
  StandDownTaken' = StandDownTaken + a
  StoodDownCommentPosted' = StoodDownCommentPosted and Retired' = Retired
  keepLife and keepReview and keepMessages and keepAddress and keepLaunched
  Now.event = StandDown and Now.issue = a.task and Target.agent = a
}

/* The agent's own record of the stand-down, on the campaign issue. It
   is the agent's own word (no Who.session), it comes after the stand-down, and
   it is never posted over local-only work -- which is what makes the comment
   evidence a close may read where a pane is not. */
pred stoodDownPosted[a: Agent] {
  a in StandDownTaken and a not in StoodDownCommentPosted and a not in LocalOnly
  StoodDownCommentPosted'     = StoodDownCommentPosted + a
  StandDownTaken' = StandDownTaken and Retired' = Retired
  keepLife and keepReview and keepMessages and keepAddress and keepLaunched
  Now.event = StoodDownPosted and Now.issue = a.task and Target.agent = a and no Who.session
}

/* Anything still in LocalOnly at this instant is gone. The second disjunct is not
   a convenience: an agent that already died is retired with no stand-down,
   and that path skips every message, which is why the disciplines guard the
   retire and not only the stand-down. No `addressable` guard either. */
pred retire[a: Agent] {
  (a in StandDownTaken or a not in Live) and a in Launched and a not in Retired
  a.task in Who.session.worksOn.memberIssues
  Retired' = Retired + a
  Live'    = Live - a
  LocalOnly' = LocalOnly and PushedToRemote' = PushedToRemote and Confirmed' = Confirmed
  StandDownTaken' = StandDownTaken and StoodDownCommentPosted' = StoodDownCommentPosted
  keepReview and keepMessages and keepAddress and keepLaunched
  Now.event = Retire and Now.issue = a.task and Target.agent = a
}

/* Its disk survives, so LocalOnly is untouched: one that died after pushing has
   succeeded. */
pred agentDie[a: Agent] {
  a in Live
  Live' = Live - a
  LocalOnly' = LocalOnly and PushedToRemote' = PushedToRemote and Confirmed' = Confirmed
  keepReview and keepMessages and keepAddress and keepShutdown and keepLaunched
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
  no Reported and no Addressable and no Asked and no Answered
  no Waiting and no Confirmed and no Reviewed and no StandDownTaken and no StoodDownCommentPosted and no Retired
}

pred orchestrationStep {
  (Now.event = Stutter and agentFrame and no Target.agent)
  or (some a: Agent |
        launch[a] or work[a] or push[a]
        or status[a] or answer[a] or report[a]
        or blocked[a] or decide[a] or confirm[a] or confirmElsewhere[a]
        or standDown[a] or stoodDownPosted[a] or retire[a] or agentDie[a])
  or (some i: Issue | review[i])
  or agentRelease
  or agentDeleteDir
  or (Now.event not in Stutter + orchestrationActed and agentFrame and no Target.agent)
}

fact OrchestrationTrace { orchestrationInit and always orchestrationStep }
