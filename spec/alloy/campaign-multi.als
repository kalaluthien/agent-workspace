/*
 * Several campaign sessions at once.
 *
 * campaign-core.als asks "can this design go wrong?"; campaign-e2e.als asks
 * "can a real campaign do this?". Both assume ONE campaign session. This file
 * drops that assumption and asks what breaks.
 *
 * The owner's intent, modelled: any session opened in the container root is a
 * campaign session. It decides new-versus-follow-up on arrival, and several such
 * sessions may be live at once, on one machine or several, on the same campaign
 * or different ones. No session is privileged. `Session` is therefore a first-
 * class sig and every campaign-level event carries the session that did it, so
 * the actor is observable in every trace.
 *
 * Relation to campaign-e2e.als, stated so the two can be diffed:
 *   - kept: Repo/Container, Machine, Issue/home, Open, Campaign/anchor/members,
 *     Agent/task/st, dirs, the observable-event idiom (`Now`).
 *   - dropped: PR, Merged, pr, complete. Settlement collapses to "the issue is
 *     closed". campaign-core already proved the closed-and-merged half, and none of
 *     the five questions here turns on it. Named again under "Not expressed".
 *   - dropped: `sub`. campaign-core proved index = membership under the sub-issue
 *     scheme in every reachable state, so this model takes that as given and
 *     writes `idx[c] = c.members`.
 *   - added: Session, and with it the survey/file/adopt/read/edit/sync events
 *     that make the anchor issue body a written object rather than a fact.
 *   - added: Topic and `co`, the branch checked out in a campaign's clone of a
 *     repository on a machine, so an acquire can race another session's. Both
 *     branch forms are here: the one R4 was found against and the numbered one
 *     AGENTS.md adopted in answer to it.
 *   - added: Visible and Pushed on an Agent -- what a remote session can check
 *     versus what only a co-located one can.
 *
 * campaign-core.als is spec/'s entry point and carries the orientation to all
 * four models.
 *
 * Thirty-five commands, every one a run. Each finding's witness sits beside the
 * predicate that states it; below is the inventory, not the explanation.
 *
 *
 * WHAT BREAKS
 *
 *   R1   LostBodyUpdate             SAT  a body update is lost outright
 *   R1b  IndexOutlivesRepoList      SAT  and the index outlives the list
 *   R2   DuplicateCampaign          SAT  two anchors over one scope
 *   R3   DeleteUnderWorkingSession  SAT  a directory deleted under a session
 *   R3b  CloseFromAnotherMachine    SAT  a close over a delegate on M1
 *   R4   SameBranchTwice            SAT  two delegates, one branch
 *   R4c  CheckoutSwitchedUnderAgent SAT  an acquire moves a live agent's HEAD
 *   R5   RemoteStandDownLosesWork   SAT  a remote stand-down destroys work
 *
 * Clean: R4b SAT -- c<N> still separates campaigns, so the collision is
 * intra-campaign only. R5c SAT -- a non-launcher on the agent's own machine
 * retires it safely, so co-location is the axis, not ownership (R5b SAT:
 * on-the-remote without a clean tree is reachable).
 *
 *
 * WHAT REPAIRS THEM, AND WHAT IT DOES NOT
 *
 * One shape, applied twice: re-read immediately before you write.
 * Compare-then-write on the anchor body (R1c, UNSAT) and re-surveying at the
 * moment of filing (R2b, UNSAT) are the two, and each has a control showing the
 * green is not the scenario forbidden (R1d, R2c, both SAT).
 *
 * Nothing repaired 3, 4 or 5 inside the model. Each was a contract change, and
 * all three have since been written outside it, so the runs above still read
 * SAT:
 *   - 4, by putting the subtask's issue number in the branch,
 *     c<N>/<issue>-<topic>, which answers it for two SUBTASKS only. R4e is what
 *     it leaves: two sessions delegating the same subtask onto one branch.
 *   - 5, by naming STAND DOWN's pre-check local -- retire only an agent on your
 *     own machine. agent-protocol.als carries that as a check.
 *   - 3, only narrowed, by announcing the close on the anchor issue and reading
 *     the comments back, which a session that never comments still slips past.
 *
 *
 * NOT EXPRESSED
 *
 * Settlement here is "the issue is closed"; the merged-pull-request half stays
 * campaign-core's. "Covers the request" is a static bit, not a judgement over
 * Scope prose. There is no `gh` latency, so each window measured is a minimum.
 *
 * Run one:
 *   alloy exec -f -o /tmp/alloy-multi -t text -c 'R1_LostBodyUpdate' spec/alloy/campaign-multi.als
 * Run all:
 *   alloy exec -f -o /tmp/alloy-multi -t text -c '*' spec/alloy/campaign-multi.als
 */
module campaignMulti

/* ---------------- static structure ---------------- */

sig Repo {}
one sig Container extends Repo {}

sig Machine {}
sig Topic {}                    -- the <topic> half of a c<N>/<topic> branch

/* The standing request a person arrives with. A campaign `covers` it when its
   Scope section would be judged to cover it in opening-campaign step 1. */
one sig Req {}

sig Issue { home: one Repo }
var sig Open in Issue {}

sig Campaign {
  anchor: one Issue,            -- the anchor issue in the container; the campaign ID
  covers: lone Req,             -- does this campaign's Scope cover the request?
  var members: set Issue,       -- ground truth: the subtasks
  var body:    set Repo,        -- the anchor issue body's `## Repos` list
  var dirs:    set Machine,     -- machines holding the git-ignored campaign directory
  var co:      Machine -> Repo -> Topic  -- branch checked out in <campaign>/repos/<repo>
}
var sig Filed in Campaign {}    -- the anchor issue exists on GitHub

/* A campaign session: a Claude session opened in the container root. */
sig Session {
  smach: one Machine,
  var holds:  lone Campaign,    -- the campaign it is working
  var saw:    set Campaign,     -- what its new-versus-follow-up survey returned
  var readme: set Repo,         -- its campaign README's `## Repos` list
  var seen:   set Repo          -- the anchor body's list as this session last read it
}
var sig Surveyed in Session {}

abstract sig AState {}
one sig Unborn, Live, Idle, Gone extends AState {}

sig Agent {
  task:     one Issue,
  amach:    one Machine,
  launcher: one Session,        -- the session that launched it
  atopic:   one Topic,
  var st:   one AState
}
var sig Visible in Agent {}     -- its branch is on the remote: checkable from anywhere
var sig Pushed  in Agent {}     -- nothing it holds exists only on its machine

fact WellFormed {
  all c: Campaign | c.anchor.home = Container
  all disj c1, c2: Campaign | c1.anchor != c2.anchor
  all c: Campaign | c.anchor not in Agent.task
  always all c: Campaign | c.anchor not in c.members
  always all disj c1, c2: Campaign | no c1.members & c2.members
  always all c: Campaign, m: Machine, r: Repo | lone c.co[m][r]
  always Pushed in Visible      -- pushed implies visible; visible does not imply clean
}

fun campaignOf[i: Issue]: lone Campaign { members.i }

/* campaign-core's verdict, imported rather than re-derived: under the sub-issue
   scheme the index equals membership in every reachable state. */
fun idx[c: Campaign]: set Issue { c.members }

/* A session is working in the campaign tree when it holds a campaign whose
   directory exists on its machine. Derived, so no event has to maintain it. */
fun working: set Session { { s: Session | some s.holds and s.smach in s.holds.dirs } }

/* The branch an agent works, in the form the design carried when R4 below was
   found: c<N>/<topic>. Two agents share it when the campaign and the topic
   match -- true by definition of the name, not by proof. */
pred sameBranchByTopic[a1, a2: Agent] {
  campaignOf[a1.task] = campaignOf[a2.task] and a1.atopic = a2.atopic
}

/* The form AGENTS.md adopted in answer to R4: c<N>/<issue>-<topic>. The
   subtask's issue number joins the campaign number, so two agents share a
   branch only when campaign, subtask and topic all match. That it separates two
   subtasks is definitional and is not run; what R4e asks is what it leaves. */
pred sameBranch[a1, a2: Agent] {
  campaignOf[a1.task] = campaignOf[a2.task]
  and a1.task = a2.task
  and a1.atopic = a2.atopic
}

/* Settlement, collapsed: the subtask issue is closed. */
pred settled[i: Issue] { i not in Open }

pred liveUnder[c: Campaign] {
  some a: Agent | a.st = Live and (a.task in c.members or a.amach in c.dirs)
}
/* What one session can actually read: `herdr agent list` on its own machine. */
pred liveUnderLocally[c: Campaign, m: Machine] {
  some a: Agent | a.st = Live and a.amach = m and (a.task in c.members or m in c.dirs)
}
pred closable[c: Campaign]              { (all i: c.members | settled[i]) and not liveUnder[c] }
pred closableLocally[s: Session, c: Campaign] {
  (all i: c.members | settled[i]) and not liveUnderLocally[c, s.smach]
}

/* ---------------- observable events ---------------- */

abstract sig Event {}
one sig Stutter, Survey, FileAnchor, Adopt, ReadBody, EditReadme, Sync,
        AddMember, CloseIssue, CloseAnchor, CreateDir, DeleteDir,
        Acquire, Launch, Push, StandDown, AgentDie extends Event {}

one sig Now {
  var ev:      one Event,
  var actor:   lone Session,
  var evIssue: lone Issue,
  var evAgent: lone Agent,
  var evRepo:  lone Repo
}

pred obs[e: Event, s: set Session, i: set Issue, a: set Agent, r: set Repo] {
  Now.ev = e and Now.actor = s and Now.evIssue = i and Now.evAgent = a and Now.evRepo = r
}

/* ---------------- frames ---------------- */

pred fOpen   { Open' = Open }
pred fMem    { members' = members }
pred fFiled  { Filed' = Filed }
pred fGH     { fOpen and fMem and fFiled }
pred fBody   { body' = body }
pred fReadme { readme' = readme }
pred fSeen   { seen' = seen }
pred fDoc    { fBody and fReadme and fSeen }
pred fSurv   { Surveyed' = Surveyed and saw' = saw }
pred fHolds  { holds' = holds }
pred fDirs   { dirs' = dirs }
pred fCo     { co' = co }
pred fLocal  { fDirs and fCo }
pred fAgent  { st' = st and Pushed' = Pushed and Visible' = Visible }

/* ---------------- events ---------------- */

pred stutter {
  fGH and fDoc and fSurv and fHolds and fLocal and fAgent
  obs[Stutter, none, none, none, none]
}

/* opening-campaign step 1: list the open campaign anchors and read their Scope.
   The result is remembered; nothing keeps it fresh. */
pred survey[s: Session] {
  let X = { c: Campaign | c in Filed and c.anchor in Open and some c.covers } |
    saw' = saw - s->Campaign + s->X
  Surveyed' = Surveyed + s
  fGH and fDoc and fHolds and fLocal and fAgent
  obs[Survey, s, none, none, none]
}

/* opening-campaign step 3: file the anchor, on the strength of the survey. */
pred fileAnchor[s: Session, c: Campaign] {
  s in Surveyed
  no s.saw                      -- the survey found no campaign covering the request
  c not in Filed
  no s.holds
  no c.members and no c.body and no c.dirs
  Filed' = Filed + c
  Open'  = Open + c.anchor
  holds' = holds - s->Campaign + s->c
  fMem and fDoc and fSurv and fLocal and fAgent
  obs[FileAnchor, s, c.anchor, none, none]
}

/* A second session arrives on a campaign that already exists and derives its
   README from the anchor body (opening-campaign step 4, run for an existing
   campaign). This is the read the later overwrite is derived from. */
pred adopt[s: Session, c: Campaign] {
  c in Filed and c.anchor in Open
  no s.holds
  holds'  = holds  - s->Campaign + s->c
  readme' = readme - s->Repo + s->(c.body)
  seen'   = seen   - s->Repo + s->(c.body)
  fGH and fBody and fSurv and fLocal and fAgent
  obs[Adopt, s, none, none, none]
}

/* Re-derive the README from the anchor body. */
pred readBody[s: Session] {
  some s.holds
  readme' = readme - s->Repo + s->(s.holds.body)
  seen'   = seen   - s->Repo + s->(s.holds.body)
  fGH and fBody and fSurv and fHolds and fLocal and fAgent
  obs[ReadBody, s, none, none, none]
}

/* A repository joins the campaign: the session adds it to its own README. */
pred editReadme[s: Session, r: Repo] {
  some s.holds
  r not in s.readme
  readme' = readme + s->r
  fGH and fBody and fSeen and fSurv and fHolds and fLocal and fAgent
  obs[EditReadme, s, none, none, r]
}

/* closing-campaign step 4: overwrite the anchor body with this session's
   README. Unguarded, as written. */
pred sync[s: Session] {
  some s.holds
  body' = body - s.holds->Repo + s.holds->(s.readme)
  seen' = seen - s->Repo + s->(s.readme)
  fGH and fReadme and fSurv and fHolds and fLocal and fAgent
  obs[Sync, s, none, none, none]
}

pred addMember[s: Session, i: Issue] {
  some s.holds
  i not in Campaign.members and i not in Campaign.anchor
  i not in Open
  members' = members + s.holds->i
  Open' = Open + i
  fFiled and fDoc and fSurv and fHolds and fLocal and fAgent
  obs[AddMember, s, i, none, none]
}

pred closeIssue[s: Session, i: Issue] {
  i in Open and i not in Campaign.anchor
  Open' = Open - i
  fMem and fFiled and fDoc and fSurv and fHolds and fLocal and fAgent
  obs[CloseIssue, s, i, none, none]
}

pred closeAnchor[s: Session, c: Campaign] {
  s.holds = c
  c.anchor in Open
  Open' = Open - c.anchor
  fMem and fFiled and fDoc and fSurv and fHolds and fLocal and fAgent
  obs[CloseAnchor, s, c.anchor, none, none]
}

/* Two sessions on one machine resolve <slug>-<YYMMDD>/ to the same path, so
   `dirs` is per campaign per machine, not per session. */
pred createDir[s: Session] {
  some s.holds
  s.smach not in s.holds.dirs
  dirs' = dirs + s.holds->s.smach
  fGH and fDoc and fSurv and fHolds and fCo and fAgent
  obs[CreateDir, s, none, none, none]
}

pred deleteDir[s: Session] {
  some s.holds
  s.smach in s.holds.dirs
  dirs' = dirs - s.holds->s.smach
  co'   = co   - s.holds->s.smach->Repo->Topic
  fGH and fDoc and fSurv and fHolds and fAgent
  obs[DeleteDir, s, none, none, none]
}

/* scripts/acquire-repo: leave <repo> checked out on <branch> in this campaign's
   tree. On a re-run over an existing checkout it switches the branch. */
pred acquire[s: Session, r: Repo, t: Topic] {
  some s.holds
  s.smach in s.holds.dirs
  s.holds.co[s.smach][r] != t
  co' = co - s.holds->s.smach->r->Topic + s.holds->s.smach->r->t
  fGH and fDoc and fSurv and fHolds and fDirs and fAgent
  obs[Acquire, s, none, none, r]
}

pred launch[s: Session, a: Agent] {
  a.st = Unborn
  a.launcher = s
  some s.holds
  a.task in s.holds.members and a.task in Open
  a.amach = s.smach and s.smach in s.holds.dirs
  s.holds.co[s.smach][a.task.home] = a.atopic
  st' = st - a->AState + a->Live
  Pushed' = Pushed and Visible' = Visible
  fGH and fDoc and fSurv and fHolds and fLocal
  obs[Launch, s, a.task, a, none]
}

/* The agent pushes its branch. That makes it visible from any machine; whether
   the tree is also clean is a separate bit only its own machine can read. */
pred push[a: Agent] {
  a.st = Live
  a not in Visible or a not in Pushed
  Visible' = Visible + a
  (Pushed' = Pushed + a or Pushed' = Pushed)
  st' = st
  fGH and fDoc and fSurv and fHolds and fLocal
  obs[Push, none, a.task, a, none]
}

/* STAND DOWN, then retire the pane. Nothing in the protocol restricts this to
   the session that launched the agent. */
pred standDown[s: Session, a: Agent] {
  a.st in Live + Idle
  some s.holds
  a.task in s.holds.members
  st' = st - a->AState + a->Gone
  Pushed' = Pushed and Visible' = Visible
  fGH and fDoc and fSurv and fHolds and fLocal
  obs[StandDown, s, a.task, a, none]
}

pred agentDie[a: Agent] {
  a.st in Live + Idle
  st' = st - a->AState + a->Gone
  Pushed' = Pushed and Visible' = Visible
  fGH and fDoc and fSurv and fHolds and fLocal
  obs[AgentDie, none, a.task, a, none]
}

pred init {
  no Filed and no Open and no Surveyed
  all c: Campaign | no c.members and no c.body and no c.dirs and no c.co
  all s: Session | no s.holds and no s.saw and no s.readme and no s.seen
  all a: Agent | a.st = Unborn
  no Visible and no Pushed
}

pred step {
  stutter
  or (some s: Session | survey[s] or readBody[s] or sync[s] or createDir[s] or deleteDir[s])
  or (some s: Session, c: Campaign | fileAnchor[s,c] or adopt[s,c] or closeAnchor[s,c])
  or (some s: Session, r: Repo | editReadme[s,r])
  or (some s: Session, i: Issue | addMember[s,i] or closeIssue[s,i])
  or (some s: Session, r: Repo, t: Topic | acquire[s,r,t])
  or (some s: Session, a: Agent | launch[s,a] or standDown[s,a])
  or (some a: Agent | push[a] or agentDie[a])
}

fact Trace { init and always step }

/* ---------------- disciplines: candidate repairs ---------------- */

/* Compare-then-write: read the anchor body immediately before overwriting it,
   and refuse if it has moved since this README was derived from it.

   THE RECOMMENDATION, and the one AGENTS.md adopted. R1c -- R1 plus this
   discipline -- is UNSAT at identical bounds, and R1d SAT shows both sessions
   still sync, so the green is not the scenario being forbidden. Step 4 of the
   close already reads the body back after writing, so the extra read costs
   nothing. */
pred syncCAS { always (Now.ev = Sync implies Now.actor.holds.body = Now.actor.seen) }

/* The rejected candidate: write the body only at open and at close, never
   mid-campaign. Modelled as "sync only when every subtask is settled".

   Compare-then-write beats it. R1e is SAT: both sessions reach close and the
   loss happens anyway, and meanwhile a repository added mid-campaign sits in
   one README, invisible to the other session. */
pred syncAtCloseOnly {
  always (Now.ev = Sync implies (all i: Now.actor.holds.members | settled[i]))
}

/* Re-run the new-versus-follow-up survey at the moment of filing.

   The same shape repairs finding 2: R2b is UNSAT, and R2c confirms filing still
   works. It NARROWS the window rather than closing it -- read and create are
   not atomic, and the model cannot say so because it has no clock. AGENTS.md
   states the residue instead of implying it is gone. */
pred surveyAtFile {
  always (Now.ev = FileAnchor implies
            (no c: Campaign | c in Filed and c.anchor in Open and some c.covers))
}

/* What a session on another machine can check before STAND DOWN. */
pred remoteCheckedShutdown { always (Now.ev = StandDown implies Now.evAgent in Visible) }
/* What only a session on the agent's own machine can check. */
pred localCheckedShutdown  { always (Now.ev = StandDown implies Now.evAgent in Pushed) }

/* The close rule as written, plus the honest local reading of it. */
pred closeDiscipline[c: Campaign]      { always (Now.ev = CloseAnchor implies closable[c]) }
pred closeDisciplineLocal[c: Campaign] { always (Now.ev = CloseAnchor implies closableLocally[Now.actor, c]) }

/* =================== 1. two sessions sync the body =================== */

/* R1. Both sessions hold the campaign; both overwrite the anchor body from
   their own README. A repository that reached the body leaves it again and
   never returns, with no event that means "remove a repository". */
/* WITNESS. S1 files and adds R0 to its README; S0 adopts while the body is
   still empty; S1 syncs, so the body reads {R0}; S0 syncs from its own stale
   README, so the body reads empty. R0 never returns. */
pred R1_LostBodyUpdate {
  some c: Campaign, disj s1, s2: Session, r: Repo {
    eventually (Now.ev = FileAnchor and Now.actor = s1 and Now.evIssue = c.anchor)
    eventually (Now.ev = Adopt and Now.actor = s2)
    eventually (Now.ev = Sync and Now.actor = s1)
    eventually (Now.ev = Sync and Now.actor = s2)
    eventually (r in c.body and after (always r not in c.body))
    always Now.ev not in DeleteDir + CloseAnchor
  }
}

/* R1b. The same loss with the campaign's own index watching: the sub-issue
   index still names an open subtask homed in the repository the `## Repos`
   list has just dropped. A session opened later clones from the list and has
   no checkout for work the index says the campaign owns. */
/* WITNESS, and why the loss is worse than it looks. `## Repos` is not
   survivable; the sub-issue index is. A body write cannot touch a sub-issue
   link, so after the loss the index goes on naming an open subtask homed in a
   repository the list has dropped -- and closing the campaign then deletes that
   list's last copy. */
pred R1b_IndexOutlivesRepoList {
  some c: Campaign, disj s1, s2: Session, i: Issue, r: Repo {
    r != Container and i.home = r
    eventually (Now.ev = Sync and Now.actor = s1)
    eventually (Now.ev = Sync and Now.actor = s2)
    -- ordered on purpose: the repository is in the list first, and only then
    -- leaves it for good while the subtask homed there stays open and indexed.
    -- Written unordered, this reads SAT on the ordinary window between filing a
    -- subtask and first syncing the README, which is not the finding.
    eventually (i in idx[c] and r in c.body
                and after (always (i in idx[c] and i in Open and r not in c.body)))
    always Now.ev not in DeleteDir + CloseAnchor
  }
}

/* R1c. The recommendation. Compare-then-write, and the loss is gone. */
pred R1c_CASBlocksLoss { syncCAS and R1_LostBodyUpdate }

/* R1d. Control for R1c: compare-then-write is not vacuous. Both sessions still
   sync, and the body ends holding both their repositories. An UNSAT here would
   mean R1c went green by forbidding the whole scenario. */
pred R1d_CASAdmitsBothSyncs {
  syncCAS
  some c: Campaign, disj s1, s2: Session, disj r1, r2: Repo {
    eventually (Now.ev = FileAnchor and Now.actor = s1 and Now.evIssue = c.anchor)
    eventually (Now.ev = Adopt and Now.actor = s2)
    eventually (Now.ev = Sync and Now.actor = s1)
    eventually (Now.ev = Sync and Now.actor = s2)
    eventually (r1 in c.body and r2 in c.body)
    always Now.ev not in DeleteDir + CloseAnchor
  }
}

/* R1e. The candidate it beats: writing the body only at open and close still
   loses a repository. */
pred R1e_CloseOnlyStillLoses {
  syncAtCloseOnly
  some c: Campaign, disj s1, s2: Session, i: Issue, r: Repo {
    eventually (Now.ev = FileAnchor and Now.actor = s1 and Now.evIssue = c.anchor)
    eventually (Now.ev = AddMember and Now.actor = s1 and Now.evIssue = i)
    eventually (Now.ev = Adopt and Now.actor = s2)
    -- both syncs happen with a real, settled subtask in the campaign, so
    -- `syncAtCloseOnly` is being obeyed rather than satisfied vacuously by a
    -- campaign that has no members at all.
    eventually (Now.ev = Sync and Now.actor = s1 and i in c.members and settled[i])
    eventually (Now.ev = Sync and Now.actor = s2 and i in c.members and settled[i])
    eventually (r in c.body and after (always r not in c.body))
    always Now.ev not in DeleteDir + CloseAnchor
  }
}

/* =================== 2. duplicate campaigns =================== */

/* R2. Two sessions each survey the open anchors, each find nothing covering the
   request, and each file. Two anchors, one scope. */
/* WITNESS. Survey(S0), Survey(S1) -- neither sees a covering campaign --
   FileAnchor(S1), FileAnchor(S0). Two anchors, one scope. */
pred R2_DuplicateCampaign {
  some disj s1, s2: Session, disj c1, c2: Campaign {
    some c1.covers and some c2.covers
    eventually (Now.ev = FileAnchor and Now.actor = s1 and Now.evIssue = c1.anchor)
    eventually (Now.ev = FileAnchor and Now.actor = s2 and Now.evIssue = c2.anchor)
    eventually (c1 + c2 in Filed and c1.anchor in Open and c2.anchor in Open)
  }
}

/* R2b. Control: re-surveying at the moment of filing blocks it. */
pred R2b_SurveyAtFileBlocks { surveyAtFile and R2_DuplicateCampaign }

/* R2c. Control for R2b: with the same discipline one campaign still opens, so
   R2b is not green by forbidding filing altogether. */
pred R2c_SurveyAtFileAdmitsOne {
  surveyAtFile
  some s: Session, c: Campaign {
    some c.covers
    eventually (Now.ev = FileAnchor and Now.actor = s and Now.evIssue = c.anchor)
  }
}

/* =================== 3. a close during another session's work =================== */

/* R3. Same machine, one directory. Session 2 deletes the campaign tree while
   session 1 is working in it with checkouts on disk. No agent is live anywhere,
   so every gate the design has -- the live-agent refusal in closing-campaign
   step 1 -- passes. A live session is invisible to it. */
/* WITNESS. Same slug, same date, one directory. S1 deletes it while S0 holds
   the campaign with checkouts on disk, and NO agent is live anywhere -- so the
   no-live-agent gate is not what was missed. */
pred R3_DeleteUnderWorkingSession {
  some c: Campaign, disj s1, s2: Session {
    s1.smach = s2.smach
    eventually (Now.ev = DeleteDir and Now.actor = s2
                and s1 in working and s1.holds = c
                and some c.co and (no a: Agent | a.st = Live))
  }
}

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
    eventually (Now.ev = CloseAnchor and Now.actor = s2 and Now.evIssue = c.anchor
                and a.st = Live and not closable[c])
  }
}

/* R3c. Control for R3b: the global rule, if it could be read, blocks it. */
pred R3c_GlobalCloseRuleBlocks {
  some c: Campaign, disj s1, s2: Session, a: Agent {
    s1.smach != s2.smach
    a.launcher = s1
    closeDiscipline[c]
    eventually (Now.ev = CloseAnchor and Now.actor = s2 and a.st = Live)
  }
}

/* =================== 4. two sessions, one repository =================== */

/* R4. Two sessions on the same campaign launch delegates into the same
   repository and pick the same topic. c<N> keeps campaigns apart; nothing keeps
   two sessions of one campaign apart. */
/* WITNESS, against c<N>/<topic> -- the branch form this was found on. Two
   subtasks in R0, two sessions, the same <topic>: one branch, two delegates,
   one checkout. R4d is the same with a single subtask. */
pred R4_SameBranchTwice {
  some disj a1, a2: Agent, r: Repo {
    r != Container
    a1.launcher != a2.launcher
    a1.task != a2.task                          -- two different subtasks
    a1.task.home = r and a2.task.home = r
    a1.atopic = a2.atopic
    eventually (a1.st = Live and a2.st = Live
                and some campaignOf[a1.task] and sameBranchByTopic[a1, a2])
  }
}

/* R4e. The adopted form, and what it does not fix. Two sessions that delegate
   the SAME subtask still land on one branch: the issue number separates two
   subtasks, and there is only ever one of it per subtask. AGENTS.md names the
   branch rule as answering the two-subtask collision only, and this is the
   residual it leaves standing. */
/* WHAT THE REPAIR LEAVES. Under c<N>/<issue>-<topic>, the form AGENTS.md
   adopted in answer to R4, two sessions delegating the SAME subtask still share
   one branch. The issue number separates two subtasks, and there is only ever
   one of it per subtask; that the numbered form separates two subtasks is
   definitional and is not run. */
pred R4e_NumberedBranchStillShared {
  some disj a1, a2: Agent {
    a1.launcher != a2.launcher
    eventually (a1.st = Live and a2.st = Live
                and some campaignOf[a1.task] and sameBranch[a1, a2])
  }
}

/* R4d. The sharper form the solver reached first when R4 left the tasks free:
   two sessions delegate the SAME subtask issue. Nothing in the design says a
   subtask has at most one agent. */
pred R4d_SameSubtaskTwice {
  some disj a1, a2: Agent {
    a1.launcher != a2.launcher
    a1.task = a2.task
    eventually (a1.st = Live and a2.st = Live)
  }
}

/* R4b. Positive control for R4: two agents of DIFFERENT campaigns, live in the
   same repository at the same time, with the same <topic> deliberately chosen.
   They do not share a branch. That is what the c<N> prefix buys, and it isolates
   R4's collision as an intra-campaign one. */
pred R4b_CrossCampaignCoexists {
  some disj a1, a2: Agent, r: Repo {
    r != Container
    a1.task.home = r and a2.task.home = r
    a1.atopic = a2.atopic
    eventually (a1.st = Live and a2.st = Live
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
    a.launcher = s1 and a.amach = s1.smach and a.task.home = r
    -- pinned to one step, so the switch is attributable to s2 and not to an
    -- earlier acquire by the launching session itself.
    eventually (Now.ev = Acquire and Now.actor = s2 and Now.evRepo = r
                and a.st = Live and a not in Visible
                and c.co[a.amach][r] = a.atopic
                and after (c.co[a.amach][r] != a.atopic))
  }
}

/* =================== 5. retiring another session's delegate =================== */

/* R5. A session on another machine stands the agent down. The check it can
   actually run -- the branch is on the remote -- passes, and work that exists
   only on the agent's machine is destroyed with the pane. */
/* WITNESS. S0 on M0 stands an M1 agent down. The branch is on the remote, so
   S0's only available check passes; work living only on M1 dies with the pane.
   R5c is the control that co-location, not launch ownership, is the axis: a
   non-launcher on the agent's own machine retires it safely. */
pred R5_RemoteStandDownLosesWork {
  some disj s1, s2: Session, a: Agent {
    a.launcher = s1 and a.amach = s1.smach
    s2.smach != a.amach
    remoteCheckedShutdown
    eventually (Now.ev = StandDown and Now.actor = s2 and Now.evAgent = a
                and a in Visible and a not in Pushed)
  }
}

/* R5b. Control for R5: the gap the finding rests on is reachable at all. An
   agent whose branch is on the remote may still hold work that is not. Without
   this, R5 could be an artefact of a state the model never enters.
   (`localCheckedShutdown` blocking the loss is the guard restated, not a
   result, so it is not run.) */
pred R5b_VisibleNotPushed { some a: Agent | eventually (a in Visible and a not in Pushed) }

/* R5c. Ownership is not the axis. Under the local check, a session that did not
   launch the agent may still retire it safely, provided it shares its machine. */
pred R5c_NonLauncherSameMachineIsFine {
  localCheckedShutdown
  some disj s1, s2: Session, a: Agent {
    a.launcher = s1 and a.amach = s1.smach and s2.smach = a.amach
    eventually (Now.ev = StandDown and Now.actor = s2 and Now.evAgent = a)
  }
}


/* =================== reachability floor ===================
 * Every event fires in some trace. An event no trace can reach would silently
 * remove a whole question from the runs above, and an over-tight frame is the
 * cheapest way to make that happen without any command turning red.
 */
pred Cov_Survey { eventually Now.ev = Survey }
pred Cov_FileAnchor { eventually Now.ev = FileAnchor }
pred Cov_Adopt { eventually Now.ev = Adopt }
pred Cov_ReadBody { eventually Now.ev = ReadBody }
pred Cov_EditReadme { eventually Now.ev = EditReadme }
pred Cov_Sync { eventually Now.ev = Sync }
pred Cov_AddMember { eventually Now.ev = AddMember }
pred Cov_CloseIssue { eventually Now.ev = CloseIssue }
pred Cov_CloseAnchor { eventually Now.ev = CloseAnchor }
pred Cov_CreateDir { eventually Now.ev = CreateDir }
pred Cov_DeleteDir { eventually Now.ev = DeleteDir }
pred Cov_Acquire { eventually Now.ev = Acquire }
pred Cov_Launch { eventually Now.ev = Launch }
pred Cov_Push { eventually Now.ev = Push }
pred Cov_StandDown { eventually Now.ev = StandDown }
pred Cov_AgentDie { eventually Now.ev = AgentDie }

/* ---------------- commands ---------------- */

run R1_LostBodyUpdate            for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 1 Topic, 12 steps
run R1b_IndexOutlivesRepoList    for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 1 Topic, 14 steps
run R1c_CASBlocksLoss            for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 1 Topic, 12 steps
run R1d_CASAdmitsBothSyncs       for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 1 Topic, 14 steps
run R1e_CloseOnlyStillLoses      for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 1 Topic, 12 steps

run R2_DuplicateCampaign         for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 1 Topic, 10 steps
run R2b_SurveyAtFileBlocks       for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 1 Topic, 10 steps
run R2c_SurveyAtFileAdmitsOne    for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 1 Topic, 10 steps

run R3_DeleteUnderWorkingSession for 3 Issue, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 1 Topic, 12 steps
run R3b_CloseFromAnotherMachine  for 3 Issue, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 14 steps
run R3c_GlobalCloseRuleBlocks    for 3 Issue, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 14 steps

run R4_SameBranchTwice           for 4 Issue, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Topic, 14 steps
run R4b_CrossCampaignCoexists    for 4 Issue, 2 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Topic, 16 steps
run R4d_SameSubtaskTwice         for 4 Issue, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Topic, 14 steps
run R4e_NumberedBranchStillShared  for 4 Issue, 1 Campaign, 2 Session, 2 Agent, 1 Machine, 3 Repo, 1 Topic, 14 steps
run R4c_CheckoutSwitchedUnderAgent for 3 Issue, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 2 Topic, 14 steps

run R5_RemoteStandDownLosesWork  for 3 Issue, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 14 steps
run R5b_VisibleNotPushed         for 3 Issue, 1 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 1 Topic, 14 steps
run R5c_NonLauncherSameMachineIsFine for 3 Issue, 1 Campaign, 2 Session, 1 Agent, 1 Machine, 3 Repo, 1 Topic, 14 steps

/* the reachability floor, all sixteen */
run Cov_Survey       for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 2 Topic, 12 steps
run Cov_FileAnchor   for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 2 Topic, 12 steps
run Cov_Adopt        for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 2 Topic, 12 steps
run Cov_ReadBody     for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 2 Topic, 12 steps
run Cov_EditReadme   for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 2 Topic, 12 steps
run Cov_Sync         for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 2 Topic, 12 steps
run Cov_AddMember    for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 2 Topic, 12 steps
run Cov_CloseIssue   for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 2 Topic, 12 steps
run Cov_CloseAnchor  for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 2 Topic, 12 steps
run Cov_CreateDir    for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 2 Topic, 12 steps
run Cov_DeleteDir    for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 2 Topic, 12 steps
run Cov_Acquire      for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 2 Topic, 12 steps
run Cov_Launch       for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 2 Topic, 12 steps
run Cov_Push         for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 2 Topic, 12 steps
run Cov_StandDown    for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 2 Topic, 12 steps
run Cov_AgentDie     for 3 Issue, 2 Campaign, 2 Session, 1 Agent, 2 Machine, 3 Repo, 2 Topic, 12 steps
