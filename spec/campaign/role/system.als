/*
 * The role: launch, work, the four messages, retirement -- and the whole
 * composition, since this is the top entity. github/system.als is spec/'s
 * entry point.
 *
 * A ROLE holds one sub-issue on one host. It is either a campaign session
 * working its own claim -- `peer` names that session -- or a delegate a
 * session launched, which is why it sits above session/ and not beside it.
 * `scripts/campaign-name-session.py` already reserves the slot: a session is
 * named `campaign-<N>-<role>-<n>`.
 *
 * `Executor` IS THE ONLY KIND TODAY, and `Role` is abstract, so `Role =
 * Executor` holds by construction and no command means anything different for
 * the split existing. What a second kind would inherit is everything declared
 * over `Role` here: that it was launched and is or is not live (`Launched`,
 * `Live`, `RoleDie`), where its work is (`Local`, `Visible`), whether a
 * campaign session can reach it (`Addressed`), the four messages (`Reported`,
 * `Asked`, `Answered`, `Waiting`), and the shutdown (`Confirmed`,
 * `StoodDown`, `Stood`, `Retired`). None of those is about executing; each is
 * about being a thing a campaign session launches, addresses and retires.
 * WHERE THE LINE FALLS IS THE SECOND KIND'S DECISION: whatever it turns out
 * not to share moves down into `Executor` when it arrives, and until then the
 * split is a claim about naming rather than about behaviour.
 *
 * The three execution modes -- own hands, in-process subagent, herdr delegate
 * -- are ONE `Launch` here: nothing a model can say about reachable states
 * differs between them.
 *
 * UNMODELLED: adequacy; that the role answers about itself only; that STAND
 * DOWN is a request a peer may refuse; and two of AGENTS.md's three merge
 * conditions -- the NON-AUTHOR one, because nothing here records who set
 * `Reviewed`, and CONTAINS-CURRENT-MAIN, because this model has one pull
 * request per issue and no shared branch moving under another (#95).
 */
module role/system

open session/system

abstract sig Role {
  task:     one Issue,
  host:     one Machine,
  launcher: one Session,
  topic:    one Topic,
  /* Set when the executor IS a campaign session working its own claim. A
     delegate is `--name`d at launch; a session's own claim is named by nothing
     anybody else chose, which is why only it needs a record. */
  peer:     lone Session
}

/* The one kind there is. A second would extend `Role` beside it, and take
   whatever of the state above it does not turn out to share. */
sig Executor extends Role {}

var sig Launched in Role {}
var sig Live     in Role {}
/* THE one encoding of "only on its host": uncommitted, unpushed, or on a
   branch no remote has. */
var sig Local    in Role {}
/* Its branch is on the remote -- checkable from anywhere, and a different fact
   from Local. The gap between the two is R5b. */
var sig Visible  in Role {}
var sig Reported in Role {}
/* A campaign session can reach it. A DIRECTORY FACT: it dies with the tree,
   and it is keyed to no reader, so any later session inherits every address in
   it. */
var sig Addressed in Role {}
var sig Asked    in Role {}
var sig Answered in Role {}
var sig Waiting  in Role {}
/* The SESSION has itself observed that this executor holds nothing
   local-only. */
var sig Confirmed in Role {}
var sig StoodDown in Role {}
/* The executor has posted `STOOD DOWN <name> <session-id>` on the campaign
   issue: the agreement made durable where a close gate can read it. Set only
   by the executor itself, after it stood down, and never for one still Local
   -- the comment says its work is on GitHub. */
var sig Stood    in Role {}
var sig Retired  in Role {}

/* A bit on the PULL REQUEST, not on the executor: the review outlives the
   executor exactly as the pull request does, and a fresh executor briefed from
   the review inherits it. */
var sig Reviewed in PR {}

one sig Target { var role: lone Role }

fact RoleWellFormed {
  all c: Campaign | c.campaignIssue not in Role.task
  all a: Role | some a.peer implies (a.launcher = a.peer and a.host = a.peer.smach)
  always Live in Launched
  always Retired in Launched
  always no Live & Retired
  always Visible in Visible'     -- a branch on the remote stays on the remote
}

pred coLocated[s: Session, a: Role] { s.smach = a.host }

pred liveUnder[c: Campaign] {
  some a: Role | a in Live and (a.task in c.members or a.host in dirsOf[c])
}
/* What one session can actually read: `herdr agent list` on its own machine. */
pred liveUnderLocally[c: Campaign, m: Machine] {
  some a: Role | a in Live and a.host = m and (a.task in c.members or m in dirsOf[c])
}
/* Whether any campaign session can reach this executor at all. Separate from
   liveness on purpose: "I can see it in a list" and "I can send it a message"
   are different questions, and this is the second. */
pred reachable[a: Role] { a in Addressed }

/* What a close gate can read AND ATTRIBUTE, a strictly smaller set than what
   it can see. Liveness is readable for BOTH kinds of executor without any
   record -- a session working its own claim holds a pane and is listed too --
   but a pane gives a name and a campaign session's cwd is the container root,
   so only the record ties the name to a claim. The split's subject is
   attribution, and A17 is the residual gap measured. */
pred liveAndReadable[c: Campaign, m: Machine] {
  some a: Role | a in Live and a.host = m
    and (a.task in c.members or m in dirsOf[c])
    and (no a.peer or reachable[a])
}
/* github's `closable` is the GitHub half. These three add the half that needs
   an executor. */
pred closableWithAgents[c: Campaign]          { closable[c] and not liveUnder[c] }
pred closableLocally[s: Session, c: Campaign] { closable[c] and not liveUnderLocally[c, s.smach] }
pred closableAsRead[s: Session, c: Campaign]  { closable[c] and not liveAndReadable[c, s.smach] }

/* campaign-<N>/<issue>-<topic>: two executors share a branch only when
   campaign, sub-issue and topic all match. That it separates two SUB-ISSUES is
   definitional and is not run; R4e is what it leaves. */
pred sameBranch[a1, a2: Role] {
  campaignOf[a1.task] = campaignOf[a2.task]
  and a1.task = a2.task
  and a1.topic = a2.topic
}

/* ---------------- observable events ---------------- */

one sig Work, Push, Status, Answer, Report, Blocked, Decide,
        Confirm, ConfirmElsewhere, Review, StandDown, StoodDownPosted, Retire,
        RoleDie extends Event {}

fun roleOwn: set Event {
  Work + Push + Status + Answer + Report + Blocked + Decide
  + Confirm + ConfirmElsewhere + Review + StandDown + StoodDownPosted + Retire
  + RoleDie
}
/* `DeleteDir` is here because this layer has a bit with the directory's
   lifetime. `MergePR` is NOT: session/system.als gives it an actor and this layer
   only guards who that actor may be, which is a discipline over the event
   rather than a disjunct on it, so the merge falls through and frames
   everything. */
fun roleActed: set Event { roleOwn + Launch + Release + DeleteDir }

/* The bits divide by how long they live: a directory fact, a pull request's,
   and a process's. */
pred keepMsgs     { Reported' = Reported and Asked' = Asked and Answered' = Answered and Waiting' = Waiting }
pred keepAddress  { Addressed' = Addressed }
pred keepReview   { Reviewed' = Reviewed }
pred keepLife     { Live' = Live and Local' = Local and Visible' = Visible and Confirmed' = Confirmed }
pred keepShutdown { StoodDown' = StoodDown and Stood' = Stood and Retired' = Retired }
pred keepBorn     { Launched' = Launched }
pred roleFrame   { keepLife and keepReview and keepMsgs and keepAddress and keepShutdown and keepBorn }

/* `Addressed` is set unconditionally: a delegate is addressable from its
   `--name`, a session from the record it wrote at the claim, which precedes
   every launch. A1 is the gap that closes. */
pred launch[a: Role] {
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
  Target.role = a
}

/* `Addressed` is the one bit here that does not outlive the tree, and only
   for a session working its own claim: stripping a delegate too would make it
   permanently unreachable when a directory its `--name` never depended on is
   deleted. Scoped to the deleted tree's own campaign and machine. */
pred aDeleteDir {
  Now.ev = DeleteDir
  Addressed' = Addressed
    - { a: Role | some a.peer
                   and a.host = Site.mach
                   and campaignOf[a.task] in (Present - Present').camp }
  keepLife and keepReview and keepMsgs and keepShutdown and keepBorn
  no Target.role
}

/* Clears an earlier confirmation here rather than at the point it is read. */
pred work[a: Role] {
  a in Live and a not in Waiting
  Local' = Local + a
  Confirmed' = Confirmed - a
  Live' = Live and Visible' = Visible
  keepReview and keepMsgs and keepAddress and keepShutdown and keepBorn
  Now.ev = Work and Now.issue = a.task and Target.role = a and no By.actor
}

/* Two different facts move, and only the first is readable from another
   machine. It does not set Confirmed -- the session has not looked yet -- and
   it clears `Reviewed`, because A REVIEW IS OF A PULL REQUEST AT A REVISION. */
pred push[a: Role] {
  a in Live and a in Local
  Local'    = Local - a
  Visible'  = Visible + a
  Reviewed' = Reviewed - a.task.pr
  Live' = Live and Confirmed' = Confirmed
  keepMsgs and keepAddress and keepShutdown and keepBorn
  Now.ev = Push and Now.issue = a.task and Target.role = a and no By.actor
}

/* Asking and answering are two events because STATUS queues behind the
   executor's current turn, so a late reply is ordinary rather than a symptom. */
pred status[a: Role] {
  reachable[a]
  a.task in By.actor.holds.members
  Asked' = Asked + a
  Answered' = Answered - a
  Reported' = Reported and Waiting' = Waiting
  keepLife and keepReview and keepAddress and keepShutdown and keepBorn
  Now.ev = Status and Now.issue = a.task and Target.role = a
}

/* A gone executor leaves the question outstanding forever: rule 3. */
pred answer[a: Role] {
  a in Live and a in Asked
  Answered' = Answered + a
  Asked' = Asked and Reported' = Reported and Waiting' = Waiting
  keepLife and keepReview and keepAddress and keepShutdown and keepBorn
  Now.ev = Answer and Now.issue = a.task and Target.role = a and no By.actor
}

/* A prompt to verify, never the verification, so this event writes NOTHING
   but the claim itself. */
pred report[a: Role] {
  a in Live
  Reported' = Reported + a
  Asked' = Asked and Answered' = Answered and Waiting' = Waiting
  keepLife and keepReview and keepAddress and keepShutdown and keepBorn
  Now.ev = Report and Now.issue = a.task and Target.role = a and no By.actor
}

/* Silence is not this message: an executor that stops without sending it
   looks identical to one thinking. */
pred blocked[a: Role] {
  a in Live and a not in Waiting
  Waiting' = Waiting + a
  Reported' = Reported and Asked' = Asked and Answered' = Answered
  keepLife and keepReview and keepAddress and keepShutdown and keepBorn
  Now.ev = Blocked and Now.issue = a.task and Target.role = a and no By.actor
}

pred decide[a: Role] {
  reachable[a]
  a in Waiting
  a.task in By.actor.holds.members
  Waiting' = Waiting - a
  Reported' = Reported and Asked' = Asked and Answered' = Answered
  keepLife and keepReview and keepAddress and keepShutdown and keepBorn
  Now.ev = Decide and Now.issue = a.task and Target.role = a
}

/* Stated as an ABSENCE, because "confirm the branch is pushed" has no passing
   form for an executor that correctly produced nothing. NO `reachable` guard,
   deliberately: it reads a tree on the session's own machine and sends the
   executor nothing. A14/A15 are what gating it would cost. */
pred confirm[a: Role] {
  coLocated[By.actor, a]
  a.task in By.actor.holds.members
  a not in Local
  Confirmed' = Confirmed + a
  Live' = Live and Local' = Local and Visible' = Visible
  keepReview and keepMsgs and keepAddress and keepShutdown and keepBorn
  Now.ev = Confirm and Now.issue = a.task and Target.role = a
}

/* It reads the SESSION's working tree, so there is no `a not in Local` guard:
   nothing on this machine could fail it. That is the defect, not a shortcut. */
pred confirmElsewhere[a: Role] {
  not coLocated[By.actor, a]
  a.task in By.actor.holds.members
  Confirmed' = Confirmed + a
  Live' = Live and Local' = Local and Visible' = Visible
  keepReview and keepMsgs and keepAddress and keepShutdown and keepBorn
  Now.ev = ConfirmElsewhere and Now.issue = a.task and Target.role = a
}

/* KEYED ON THE ISSUE, NOT ON A ROLE: the review reads GitHub, so keying it
   to an Role made hands-on work unreviewable and so unmergeable. No guard on
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
  no Target.role
}

/* It does not destroy its own workspace, which is why standing down and
   retiring are two events and the executor is still Live between them. */
pred standDown[a: Role] {
  reachable[a]
  a in Live and a not in StoodDown
  a.task in By.actor.holds.members
  StoodDown' = StoodDown + a
  Stood' = Stood and Retired' = Retired
  keepLife and keepReview and keepMsgs and keepAddress and keepBorn
  Now.ev = StandDown and Now.issue = a.task and Target.role = a
}

/* The executor's own record of the stand-down, on the campaign issue. It
   is the executor's word (no By.actor), it comes after the stand-down, and
   it is never posted over local-only work -- which is what makes the comment
   evidence a close may read where a pane is not. */
pred stoodDownPosted[a: Role] {
  a in StoodDown and a not in Stood and a not in Local
  Stood'     = Stood + a
  StoodDown' = StoodDown and Retired' = Retired
  keepLife and keepReview and keepMsgs and keepAddress and keepBorn
  Now.ev = StoodDownPosted and Now.issue = a.task and Target.role = a and no By.actor
}

/* Anything still in Local at this instant is gone. The second disjunct is not
   a convenience: an executor that already died is retired with no stand-down,
   and that path skips every message, which is why the disciplines guard the
   retire and not only the stand-down. No `reachable` guard either. */
pred retire[a: Role] {
  (a in StoodDown or a not in Live) and a in Launched and a not in Retired
  a.task in By.actor.holds.members
  Retired' = Retired + a
  Live'    = Live - a
  Local' = Local and Visible' = Visible and Confirmed' = Confirmed
  StoodDown' = StoodDown and Stood' = Stood
  keepReview and keepMsgs and keepAddress and keepBorn
  Now.ev = Retire and Now.issue = a.task and Target.role = a
}

/* Its disk survives, so Local is untouched: one that died after pushing has
   succeeded. */
pred roleDie[a: Role] {
  a in Live
  Live' = Live - a
  Local' = Local and Visible' = Visible and Confirmed' = Confirmed
  keepReview and keepMsgs and keepAddress and keepShutdown and keepBorn
  Now.ev = RoleDie and Now.issue = a.task and Target.role = a and no By.actor
}

/* Both guards are what a session can actually read. Liveness elsewhere is
   not, so R6 is the residue that leaves. */
pred aRelease {
  Now.ev = Release
  no a: Role | a.task = Now.issue and a in Visible
  no a: Role | a.task = Now.issue and a.host = By.actor.smach and a in Live
  roleFrame
  no Target.role
}

pred roleInit {
  no Launched and no Live and no Local and no Visible
  no Reported and no Addressed and no Asked and no Answered
  no Waiting and no Confirmed and no Reviewed and no StoodDown and no Stood and no Retired
}

pred roleStep {
  (Now.ev = Stutter and roleFrame and no Target.role)
  or (some a: Role |
        launch[a] or work[a] or push[a]
        or status[a] or answer[a] or report[a]
        or blocked[a] or decide[a] or confirm[a] or confirmElsewhere[a]
        or standDown[a] or stoodDownPosted[a] or retire[a] or roleDie[a])
  or (some i: Issue | review[i])
  or aRelease
  or aDeleteDir
  or (Now.ev not in Stutter + roleActed and roleFrame and no Target.role)
}

fact RoleTrace { roleInit and always roleStep }
