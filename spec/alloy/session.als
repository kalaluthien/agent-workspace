/*
 * A campaign session -- what makes a session one, and what it may do.
 *
 * ledger.als is spec/'s entry point and carries the orientation to all four
 * layers and the composition idiom.
 *
 *
 * THIS LAYER
 *
 * Any session opened in the container root is a candidate, and whether it is in
 * a campaign is READ rather than assumed, from one fact: `bound`, the anchor's
 * latest `BOUND <machine>` comment. ONE ROLE (#59): a session is a campaign
 * session exactly when the campaign is bound to its machine, and is not in the
 * campaign otherwise. Nothing assigns roles beyond that -- no holder, no
 * executor session; a session claims subtasks and works them, and the claim it
 * takes it records itself, `runtime/claims/<issue>` (agent.als's `Addressed`).
 * `Session` is a first-class sig and every event a session performs carries the
 * session that did it, so the actor is observable in every trace.
 *
 * This layer implements the two skills:
 *
 *   event                     performed by
 *   Survey                    opening-campaign step 1: list the open anchors,
 *                             `gh issue list --label campaign --state open`
 *   FileAnchor (actor)        opening-campaign step 3, which also posts BOUND
 *   Adopt                     opening-campaign step 4 on a campaign that exists:
 *                             a session starts working a campaign bound here
 *   ReadBody                  `gh issue view <N> --json body`
 *   EditReadme                a repository joins: the session's own README
 *   WriteBody as Sync         closing-campaign step 4: overwrite the anchor body
 *   MergePR (actor)           `gh pr merge` -- somebody's act, held to a current
 *                             review by agent.als's `mergedOnCurrentReview`
 *   CreateDir / DeleteDir     the scaffold and the delete, with the actor
 *   Acquire / Claim / Release the campaign session running the tools
 *   Launch (actor)            the session that starts an executor
 *
 * What it does NOT know: whether anything is running. `Agent` is agent.als's,
 * so every finding below is one a campaign session can reach with no delegate
 * anywhere -- which is the point of R3.
 *
 * `RemoveMember` is deliberately unattended here. Moving a subtask out of a
 * campaign has no sanctioned flow; it is a hand-run `gh issue edit
 * --remove-parent`, and ledger.als's header names it as a residual risk.
 *
 *
 * WHAT BREAKS
 *
 *   R1   LostBodyUpdate             SAT  a body update is lost outright
 *   R1b  IndexOutlivesRepoList      SAT  and the index outlives the list
 *   R2   DuplicateCampaign          SAT  two anchors over one scope
 *   R3   DeleteUnderWorkingSession  SAT  a directory deleted under a session
 *
 * R4 is not a breakage. It is the case the design had never been walked
 * through: a campaign with no member repository, opened, claimed and closed
 * with every discipline on.
 *
 *
 * WHAT REPAIRS THEM, AND WHAT IT DOES NOT
 *
 * One shape, applied twice: re-read immediately before you write.
 * Compare-then-write on the anchor body (R1c, UNSAT) and re-surveying at the
 * moment of filing (R2b, UNSAT) are the two, and each has a control showing the
 * green is not the scenario being forbidden (R1d, R2c, both SAT).
 *
 * Compare-then-write is THE everyday guard on the body since #59, and R1p is
 * the measurement its promotion rests on: `boundOnly` -- one campaign, one
 * machine, the whole membership rule now that the holder is retired -- admits
 * two member sessions on the one bound machine, so it never serialized the body
 * by itself and the loss returns under it (R1p, SAT). The holder discipline
 * that did serialize it, `holderOnly`, is retired with its record; its final
 * measurements are under WHAT #59 RETIRED below.
 *
 * Nothing in this layer repairs R3, and no discipline here claims to any more:
 * whether another session is working the tree is a fact about a peer, and the
 * file that carries it is `runtime/claims/`, each claim written by its own
 * claiming session. That record is about an executor, so it is agent.als's
 * `Addressed`, and the repair is checkable there rather than assumed here --
 * A11 is UNSAT with the record read at the delete, A12 is its control, and A1
 * measures the record's completeness from the close gate's side.
 *
 *
 * WHY CONCURRENCY IS CHEAP RATHER THAN CORRECT
 *
 * This layer was first written to the intent that several sessions may hold one
 * campaign at once, on one machine or several. That intent was retired: the
 * campaign is pinned to one machine by a comment on its anchor, so no lock is
 * ever judged stale across a network. What stays concurrent is concurrent
 * within the bound machine -- including the anchor body, now that no single
 * session owns it -- and two things serialize it: the branch claim for
 * subtasks, and compare-then-write for the body.
 *
 * Two findings are narrowed rather than closed, and AGENTS.md says so rather
 * than implying otherwise. Filing is still not atomic, so two sessions can
 * still produce two anchors for one scope -- the one window a binding cannot
 * narrow, because a campaign that does not exist yet is bound to nobody. And a
 * machine working against its BOUND still overwrites the body (R1h, SAT);
 * compare-then-write is the guard that does not care which machine it is
 * obeyed on, which is the other half of why it is the everyday guard.
 *
 * A lock would need a place to live, and every candidate is either a second
 * copy of a GitHub fact or a file the campaign directory takes with it when it
 * goes. The binding is the first of those on purpose -- it IS a GitHub fact,
 * appended as a comment so writing one races nothing -- and the claim records
 * are the second on purpose, because their lifetime is exactly the directory's.
 *
 *
 * NOT EXPRESSED
 *
 * "Covers the request" is a static bit, not a judgement over Scope prose. There
 * is no `gh` latency, so each window measured is a minimum. Migration -- a
 * person's new BOUND comment -- has no event, because nothing here can observe
 * its premise; `init` admits any binding instead.
 *
 *
 * VERDICTS
 *
 * Measured 2026-08-29 against this file.
 *
 *   R1_LostBodyUpdate                SAT   the loss
 *   R1b_IndexOutlivesRepoList        SAT   and it is worse than it looks
 *   R1c_CASBlocksLoss                UNSAT compare-then-write works: THE guard
 *   R1d_CASAdmitsBothSyncs           SAT   control: it is not vacuous
 *   R1e_CloseOnlyStillLoses          SAT   the candidate it beats
 *   R1h_UnboundMachineStillLoses     SAT   residue 1: BOUND is a rule, not a lock
 *   R1p_BoundAloneStillLoses         SAT   residue 2: the membership rule never
 *                                          serialized the body; #59's promotion
 *   R1j_TwoMomentStillLoses          SAT   two moments is a WHEN rule, not a HOW
 *   R1k_TwoMomentAdmitsScopeSync     SAT   control, and the close-only difference
 *   R2_DuplicateCampaign             SAT   two anchors, one scope
 *   R2b_SurveyAtFileBlocks           UNSAT the same shape repairs it
 *   R2c_SurveyAtFileAdmitsOne        SAT   control
 *   R3_DeleteUnderWorkingSession     SAT   a live session is invisible to the gate,
 *                                          and the repair is agent.als's A10-A12
 *   R4_RepolessCampaign              SAT   `- none` opens, claims and closes
 *   Cov_*                            SAT   every own event and every refinement
 *                                          this layer adds fires in some trace
 *
 * Every UNSAT is proved a finding rather than an artefact by its own control:
 * R1d for R1c, R2c for R2b. R1c, promoted to the everyday guard by #59, was
 * additionally proved able to fail by a named mutation, run 2026-08-29 against
 * this model and undone afterwards:
 *
 *   R1c   emptying `syncCAS` -- the discipline present but comparing nothing --
 *         brings the loss back (SAT), so the green is the comparison itself and
 *         not the shape of the scenario.
 *
 *
 * WHAT #59 RETIRED, AND ITS FINAL MEASUREMENTS
 *
 * One campaign, one machine, ONE HOLDER was the stronger repair for R1, and it
 * is retired with `runtime/holder`: the holder role cost more than it bought
 * (issue #59 carries the evidence from campaign #1). Kept here is what it
 * measured, all verified on the pre-#59 model, 2026-08-28/29:
 *
 *   R1f_HolderOnlyBlocksLoss    UNSAT  one holder also blocked the loss, and
 *                                      independently of compare-then-write --
 *                                      R1c and R1f each contained only its own
 *                                      discipline and each was UNSAT alone,
 *                                      which is what made the holder removable:
 *                                      the property survives on R1c.
 *                                      Its mutation: narrowing `isHolder` to
 *                                      its BOUND half brought the loss back.
 *   R1g_HolderOnlyAdmitsSync    SAT    its control.
 *   R1m_NoDirectoryCannotLose   UNSAT  the optional-directory branch, measured
 *                                      retired: a session with no directory had
 *                                      no `runtime/holder` and could not write.
 *                                      Nothing re-derives it -- no record gates
 *                                      the body write now, and R1c is
 *                                      directory-independent, so the branch has
 *                                      nothing left to cost.
 *   R1n_NoDirectoryTakesThenCloses SAT its control: a directory-less campaign
 *                                      closed by being taken -- scaffolded --
 *                                      first. Dissolved: there is no take. A
 *                                      session still scaffolds before claiming,
 *                                      because the directory is the claim
 *                                      records' home, but nothing in this layer
 *                                      gates the close on it; the close gates
 *                                      that do read the directory are
 *                                      agent.als's.
 *   R3d_HolderOnlyStillDeletesUnderExecutor
 *                               SAT    THE FINDING #37 PRODUCED: the holder
 *                                      discipline never closed R3 -- the holder
 *                                      deleted the tree under its own executor
 *                                      with every rule obeyed. Dissolved into
 *                                      R3 itself: no discipline here claims to
 *                                      close R3, and the repair -- the record
 *                                      the deleting session can read -- was
 *                                      always agent.als's A10-A12, which
 *                                      survive keyed on `runtime/claims/`.
 *   R3g_RecycledHolderBlocksTakeover
 *                               SAT    a recycled PID read live, so a dead
 *                                      holder's record could strand the whole
 *                                      campaign: the rule erred towards never
 *                                      taking over. With no holder there is no
 *                                      takeover to refuse. The recycled-PID
 *                                      residue survives, narrowed to the claim
 *                                      records: a stale `runtime/claims/<issue>`
 *                                      reads live and keeps that ONE claim
 *                                      standing -- release refused, close gate
 *                                      refusing -- instead of the campaign held
 *                                      by nobody. It is not constructible here
 *                                      for the reason R3g was init-only: no
 *                                      event writes a stale record, and
 *                                      agent.als's `init` starts with none.
 *
 * WHAT THE FIRST DRAFT OF THIS FILE GOT WRONG
 *
 * Three things, all found by review and all kept visible here because each is a
 * standing hazard rather than a typo.
 *
 *   `isHolder` was the guard everywhere, and it needed `runtime/holder`, which
 *   an OPTIONAL DIRECTORY never has -- so the model forbade closing a campaign
 *   that `closing-campaign` step 0 documented closing, campaign #1 among them.
 *   The second draft added `mayWrite`, a reading that fell back to the binding
 *   alone where there was no directory, and named its price as R1m. The third
 *   draft, #52, retired that branch: the price was larger than R1m measured,
 *   because the executor record of agent.als had the same home as the holder
 *   record, and on the branch neither existed -- campaign #1's first CLAIMED
 *   arrived with nowhere to be written, and A1's gap was open again on exactly
 *   the path #46 had made first-class. The scaffold rule survived the holder's
 *   retirement (#59) with a shorter reason: the directory is the claim records'
 *   home, so a session scaffolds before it claims, and the directory stays
 *   optional on a machine the campaign is not bound to.
 *
 *   `Cov_Bound` was `eventually some Binding.bound`, satisfiable at step 0 by
 *   `init` alone: it certified nothing about the event that writes the binding.
 *   It pins `FileAnchor` now.
 *
 *   `noDeleteUnderWorkingPeer` was stated here and keyed on a working PEER --
 *   a fact nothing on the machine records, which is why it belonged one layer
 *   up. See R3.
 */
module session

open repos

/* ==================== SYSTEM ==================== */

/* ---------------- static structure ---------------- */

/* The standing request a person arrives with, and the campaigns whose Scope
   section would be judged to cover it in opening-campaign step 1. `covers` sits
   on Req rather than on Campaign because Campaign is ledger's signature and a
   layer above it may not add a field to it. */
one sig Req { covers: set Campaign }

/* A campaign session: a Claude session opened in the container root. */
sig Session {
  smach:      one Machine,
  var holds:  lone Campaign,    -- the campaign it is working
  var saw:    set Campaign,     -- what its new-versus-follow-up survey returned
  var readme: set Repo,         -- its campaign README's `## Repos` list
  var seen:   set Repo,         -- the anchor body's list as this session last read it
  var claims: set Issue         -- subtask branches this session created on the remote
}
var sig Surveyed in Session {}

/* ONE CAMPAIGN, ONE MACHINE -- the one reading membership is read from, as one
   relation. #59 retired the second: `runtime/holder` is gone, and with it the
   holder role. A session is in a campaign exactly when the campaign is BOUND to
   its machine, and every session there is the same kind of session.

   `bound` is the anchor's latest `BOUND <machine>` comment. It is a GitHub fact,
   and the layering rule -- the lower layer owns the fact -- would put it in
   ledger.als, which is where every other GitHub fact lives. It cannot go there:
   its value is a Machine, and Machine is repos.als's. It cannot go in repos.als
   either without distorting that layer's observer, because the act that writes
   it is `FileAnchor`, a ledger event, and repos.als's step says a ledger event
   carries `no Site.mach` -- so repos would have to widen `Site` to state a fact
   it never reads. The value is supplied by the filing session's own `smach`, and
   this is the lowest layer that has one. So it sits here, and this paragraph is
   why: the placement is a consequence of `Machine` and `Session` being declared
   above the fact's home, not a claim that the binding is local.

   It hangs off a `one sig` for the reason `Req` does: Campaign is ledger's
   signature and a layer above it may not add a field to it.

   The per-claim record that replaced the holder, `runtime/claims/<issue>`, is
   not a relation here: its subject is an executor of one subtask, so it is
   agent.als's `Addressed`, written by the claiming session at the claim and
   dying with the directory there exactly as the holder record used to die. */
one sig Binding {
  var bound: Campaign -> Machine
}

fact BindingWellFormed {
  always all c: Campaign | lone Binding.bound[c]
}

/* This layer's observer: who did it. */
one sig By { var actor: lone Session }

/* A session is working in the campaign tree when it holds a campaign whose
   directory exists on its machine. Derived, so no event has to maintain it. */
fun working: set Session { { s: Session | some s.holds and s.smach in dirsOf[s.holds] } }

/* ---------------- observable events ---------------- */

one sig Survey, Adopt, ReadBody, EditReadme extends Event {}

/* The four this layer introduces. */
fun sessionOwn: set Event { Survey + Adopt + ReadBody + EditReadme }

/* Every event a session performs: its own four, plus the lower-layer events it
   refines by naming the actor and adding the guard.

   `MergePR` is here rather than in `unattended`, and that is #37 item 8's whole
   structural change: landing a subtask's pull request is somebody's act, and
   naming whose is what lets `mergedOnCurrentReview` in agent.als hold the
   merger to a current review of the work. */
fun sessionActed: set Event {
  sessionOwn + FileAnchor + AddMember + CloseIssue + WriteBody + MergePR
  + CreateDir + DeleteDir + Acquire + Claim + Release + Launch
}

/* Things that happen to a campaign rather than by a session. */
fun unattended: set Event {
  OpenPR + RemoveMember + PullContainer + PullClone + CommitLocal
}

pred sessionFrame {
  holds' = holds and saw' = saw and readme' = readme and seen' = seen
  and claims' = claims and Surveyed' = Surveyed
  and bound' = bound
}

/* opening-campaign step 1: list the open campaign anchors and read their Scope.
   The result is remembered; nothing keeps it fresh. */
pred survey[s: Session] {
  let X = { c: Campaign | c in Filed and c.anchor in Open and c in Req.covers } |
    saw' = saw - s->Campaign + s->X
  Surveyed' = Surveyed + s
  holds' = holds and readme' = readme and seen' = seen and claims' = claims
  bound' = bound
  Now.ev = Survey and no Now.issue and By.actor = s
}

/* A session arrives on a campaign that already exists and derives its README
   from the anchor body (opening-campaign step 4, run for an existing campaign).
   This is the read the later overwrite is derived from.

   Nothing is taken: under one role there is no holder record to write and no
   live holder to defer to, so arriving is just starting to work. Unguarded
   here: `boundOnly` below is the membership rule, applied per command, so the
   unrepaired scenarios stay measurable against the same trace space. */
pred adopt[s: Session, c: Campaign] {
  c in Filed and c.anchor in Open
  no s.holds
  holds'  = holds  - s->Campaign + s->c
  readme' = readme - s->Repo + s->(c.body)
  seen'   = seen   - s->Repo + s->(c.body)
  saw' = saw and Surveyed' = Surveyed and claims' = claims
  bound' = bound
  Now.ev = Adopt and no Now.issue and By.actor = s
}

/* Re-derive the README from the anchor body. */
pred readBody[s: Session] {
  some s.holds
  readme' = readme - s->Repo + s->(s.holds.body)
  seen'   = seen   - s->Repo + s->(s.holds.body)
  holds' = holds and saw' = saw and Surveyed' = Surveyed and claims' = claims
  bound' = bound
  Now.ev = ReadBody and no Now.issue and By.actor = s
}

/* A repository joins the campaign: the session adds it to its own README. */
pred editReadme[s: Session, r: Repo] {
  some s.holds
  r not in s.readme
  readme' = readme + s->r
  holds' = holds and saw' = saw and seen' = seen and Surveyed' = Surveyed and claims' = claims
  bound' = bound
  Now.ev = EditReadme and no Now.issue and By.actor = s
}

/* --- refinements: the actor and the guard on a lower layer's event --- */

/* opening-campaign step 3: file the anchor, on the strength of the survey -- and
   post `BOUND <machine>` in the same step, which is one of only two occasions a
   session posts one at all. It is the same step because everything after it is a
   write or a launch, and both are gated on the binding. The other occasion is a
   person's word, a migration; nothing here can observe its premise, so no event
   models it and `init` admits any binding instead. */
pred sFileAnchor[s: Session] {
  Now.ev = FileAnchor
  s in Surveyed
  no s.saw                      -- the survey found no campaign covering the request
  no s.holds
  holds' = holds - s->Campaign + s->anchorOf[Now.issue]
  bound' = bound - Binding->anchorOf[Now.issue]->Machine
           + Binding->anchorOf[Now.issue]->s.smach
  saw' = saw and readme' = readme and seen' = seen
  and Surveyed' = Surveyed and claims' = claims
  By.actor = s
}

/* A subtask is filed on the campaign this session holds. */
pred sAddMember[s: Session] {
  Now.ev = AddMember
  some s.holds
  s.holds->Now.issue in members'
  sessionFrame
  By.actor = s
}

/* Only the session holding a campaign closes its anchor. Any other issue is an
   ordinary subtask close and needs no such tie. */
pred sCloseIssue[s: Session] {
  Now.ev = CloseIssue
  Now.issue in Campaign.anchor implies s.holds = anchorOf[Now.issue]
  sessionFrame
  By.actor = s
}

/* SYNC -- closing-campaign step 4: overwrite the anchor body with this session's
   README. Unguarded, as written; `syncCAS` below is the repair. This is the
   refinement of ledger's `writeBody`, which says only that one campaign's list
   changed: here is where it says whose README it changed to. */
pred sync[s: Session] {
  Now.ev = WriteBody
  some s.holds
  body' = body - s.holds->Repo + s.holds->(s.readme)
  seen' = seen - s->Repo + s->(s.readme)
  holds' = holds and saw' = saw and readme' = readme
  and Surveyed' = Surveyed and claims' = claims
  bound' = bound
  By.actor = s
}

/* Two sessions on one machine resolve <slug>-<YYMMDD>/ to the same path, so the
   directory is per campaign per machine, not per session. */
pred sCreateDir[s: Session] {
  Now.ev = CreateDir
  some s.holds
  Site.mach = s.smach
  some treeAt[s.holds, s.smach] and treeAt[s.holds, s.smach] in Present'
  /* The directory is the claim records' home -- `runtime/claims/<issue>` has
     nowhere else to live -- which is what the scaffold is for now that no
     holder record rides along. */
  bound' = bound
  holds' = holds and saw' = saw and readme' = readme and seen' = seen
  and claims' = claims and Surveyed' = Surveyed
  By.actor = s
}

pred sDeleteDir[s: Session] {
  Now.ev = DeleteDir
  some s.holds
  Site.mach = s.smach
  some treeAt[s.holds, s.smach] and treeAt[s.holds, s.smach] not in Present'
  /* `runtime/` goes with the directory, claim records included; agent.als's
     `aDeleteDir` is that lifetime on the record's own bit. */
  bound' = bound
  holds' = holds and saw' = saw and readme' = readme and seen' = seen
  and claims' = claims and Surveyed' = Surveyed
  By.actor = s
}

pred sAcquire[s: Session] {
  Now.ev = Acquire
  some s.holds
  Site.mach = s.smach
  -- the checkout that moved is in this session's campaign tree
  co' - treesOf[s.holds]->Repo->Topic = co - treesOf[s.holds]->Repo->Topic
  sessionFrame
  By.actor = s
}

/* The launcher creates the subtask's branch on the remote BEFORE any executor
   exists. Which session created it is what `claims` records; that the ref exists
   at all is repos.als's `Claimed`. */
pred sClaim[s: Session] {
  Now.ev = Claim
  some s.holds
  Now.issue in s.holds.members
  claims' = claims + s->Now.issue
  holds' = holds and saw' = saw and readme' = readme
  and seen' = seen and Surveyed' = Surveyed
  bound' = bound
  By.actor = s
}

/* The claim is dropped by whoever reads the branch as dangling, not only by the
   session that made it. What may be released is agent.als's guard. */
pred sRelease[s: Session] {
  Now.ev = Release
  claims' = claims - Session->Now.issue
  holds' = holds and saw' = saw and readme' = readme
  and seen' = seen and Surveyed' = Surveyed
  bound' = bound
  By.actor = s
}

/* MERGE -- landing a subtask's pull request, with the actor named.

   Loose here on purpose: this layer says only that a session did it, and
   agent.als's `mergedOnCurrentReview` says on what terms. The split is the same
   one `sync` and `syncCAS` make, and it is what lets the unreviewed-merge
   collision stay reachable as a control. */
pred sMergePR[s: Session] {
  Now.ev = MergePR
  sessionFrame
  By.actor = s
}

/* The session's half of a launch: it launches into its own campaign's tree, on
   its own machine, onto one of that campaign's open subtasks. */
pred sLaunch[s: Session] {
  Now.ev = Launch
  some s.holds
  Site.mach = s.smach
  s.smach in dirsOf[s.holds]
  Now.issue in s.holds.members and Now.issue in Open
  sessionFrame
  By.actor = s
}

/* A session may already hold a campaign at time zero, in the state an `adopt`
   leaves it in -- ledger.als's `init` admits a campaign already in flight for
   the same reason, and the scenarios that are ABOUT arriving (R1, R2) require
   the arrival events explicitly, so nothing they measure is skipped. */
/* `bound` is deliberately unconstrained at time zero: a campaign already in
   flight was bound by a session this trace never contains, and may have been
   migrated by a person, which no event here models. */
pred sessionInit {
  no Surveyed
  all s: Session {
    s.holds in Filed
    no s.saw and no s.claims
    s.readme = s.holds.body and s.seen = s.holds.body
  }
}

pred sessionStep {
  (Now.ev = Stutter and sessionFrame and no By.actor)
  or (some s: Session | survey[s] or readBody[s] or sync[s]
        or sFileAnchor[s] or sAddMember[s] or sCloseIssue[s]
        or sCreateDir[s] or sDeleteDir[s] or sAcquire[s]
        or sClaim[s] or sRelease[s] or sLaunch[s] or sMergePR[s])
  or (some s: Session, c: Campaign | adopt[s,c])
  or (some s: Session, r: Repo | editReadme[s,r])
  or (Now.ev in unattended and sessionFrame and no By.actor)
  /* an event declared in a layer above: it names its own actor, or none */
  or (Now.ev not in Stutter + sessionActed + unattended and sessionFrame)
}

fact SessionTrace { sessionInit and always sessionStep }

/* ==================== SCENARIOS ==================== */

/* ---------------- disciplines: candidate repairs ---------------- */

/* Compare-then-write: read the anchor body immediately before overwriting it,
   and refuse if it has moved since this README was derived from it.

   THE RECOMMENDATION, and the one AGENTS.md adopted. R1c -- R1 plus this
   discipline -- is UNSAT at identical bounds, and R1d SAT shows both sessions
   still sync, so the green is not the scenario being forbidden. Step 4 of the
   close already reads the body back after writing, so the extra read costs
   nothing. */
pred syncCAS { always (Now.ev = WriteBody implies By.actor.holds.body = By.actor.seen) }

/* The rejected candidate: write the body only at open and at close, never
   mid-campaign. Modelled as "sync only when every subtask is settled".

   Compare-then-write beats it. R1e is SAT: both sessions reach close and the
   loss happens anyway, and meanwhile a repository added mid-campaign sits in
   one README, invisible to the other session. */
pred syncAtCloseOnly {
  always (Now.ev = WriteBody implies (all i: By.actor.holds.members | settled[i]))
}

/* The two-moment rule, and the third candidate for the same slot as the two
   above: the anchor body is written at exactly two moments, a scope change and
   the close. Filing a subtask is neither -- the sub-issue index already carries
   it, and a hand copy of a listing costs one lost-update window per write.

   It is a rule about WHEN, where compare-then-write is a rule about HOW, so the
   two are not alternatives and R1j measures that: the two-moment rule alone does
   not stop the loss. What it does beat is `syncAtCloseOnly`, and R1k is that
   difference made visible -- a repository joining mid-campaign syncs at once
   here and is held back until the close there. */
pred syncAtTwoMoments {
  always (Now.ev = WriteBody implies
            (some By.actor.readme - By.actor.holds.body        -- a scope change
             or (all i: By.actor.holds.members | settled[i]))) -- or the close
}

/* ONE CAMPAIGN, ONE MACHINE as a discipline: the one-role membership rule of
   AGENTS.md § Who is a campaign session turned into a guard. A session acts on
   a campaign only when the campaign is BOUND to its machine -- arriving,
   scaffolding, writing the body, deleting the directory, closing the anchor.
   No act is any one session's: what serializes the body is compare-then-write
   (`syncCAS`), and what serializes subtasks is the branch claim. R1p below is
   why the membership rule alone is not enough. */
pred boundOnly {
  always (Now.ev = Adopt implies Binding.bound[By.actor.holds'] = By.actor.smach)
  always (Now.ev in WriteBody + CreateDir + DeleteDir implies
            Binding.bound[By.actor.holds] = By.actor.smach)
  always ((Now.ev = CloseIssue and Now.issue in Campaign.anchor) implies
            Binding.bound[anchorOf[Now.issue]] = By.actor.smach)
}

/* THE HALF THIS LAYER CANNOT SUPPLY. Being in the campaign says nothing about
   who else is working the tree, and R3 below is that gap measured. A first
   draft stated the missing half here, as "refuse the delete while another
   session on this machine is working the campaign" -- and it was the wrong home
   for it: the key was a working PEER, which is a fact nothing on the machine
   records. The record that does carry it is `<campaign>/runtime/claims/`,
   written by each claiming session for its own claim, and `Agent` is
   agent.als's, so the repair is `noDeleteUnderReadableExecutor` there. R3
   states the gap; A10-A12 close it. */

/* Re-run the new-versus-follow-up survey at the moment of filing.

   The same shape repairs R2: R2b is UNSAT, and R2c confirms filing still works.
   It NARROWS the window rather than closing it -- read and create are not
   atomic, and the model cannot say so because it has no clock. AGENTS.md states
   the residue instead of implying it is gone. */
pred surveyAtFile {
  always (Now.ev = FileAnchor implies
            (no c: Campaign | c in Filed and c.anchor in Open and c in Req.covers))
}

/* The close rule, this layer's half: the anchor is closed only from a state
   where every subtask is settled. The other half -- and no agent is live under
   the tree -- is agent.als's, which is the only layer with an agent in it. */
pred closeDisciplineHere[c: Campaign] {
  always ((Now.ev = CloseIssue and Now.issue = c.anchor) implies closable[c])
}

/* Nothing closes and nothing is deleted: the frame the body-loss scenarios are
   read against, so a repository leaving the list is the write that lost it and
   not a campaign being torn down. */
pred noCloseNoDelete {
  always (Now.ev != DeleteDir
          and (Now.ev = CloseIssue implies Now.issue not in Campaign.anchor))
}

/* =================== 1. two sessions sync the body =================== */

/* R1. Both sessions hold the campaign; both overwrite the anchor body from
   their own README. A repository that reached the body leaves it again and
   never returns, with no event that means "remove a repository". */
/* WITNESS. S1 files and adds R0 to its README; S0 adopts while the body is
   still empty; S1 syncs, so the body reads {R0}; S0 syncs from its own stale
   README, so the body reads empty. R0 never returns. */
pred R1_LostBodyUpdate {
  some c: Campaign, disj s1, s2: Session, r: Repo {
    eventually (Now.ev = FileAnchor and By.actor = s1 and Now.issue = c.anchor)
    eventually (Now.ev = Adopt and By.actor = s2)
    eventually (Now.ev = WriteBody and By.actor = s1)
    eventually (Now.ev = WriteBody and By.actor = s2)
    eventually (r in c.body and after (always r not in c.body))
    noCloseNoDelete
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
    eventually (Now.ev = WriteBody and By.actor = s1)
    eventually (Now.ev = WriteBody and By.actor = s2)
    -- ordered on purpose: the repository is in the list first, and only then
    -- leaves it for good while the subtask homed there stays open and indexed.
    -- Written unordered, this reads SAT on the ordinary window between filing a
    -- subtask and first syncing the README, which is not the finding.
    eventually (i in idx[c] and r in c.body
                and after (always (i in idx[c] and i in Open and r not in c.body)))
    noCloseNoDelete
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
    eventually (Now.ev = FileAnchor and By.actor = s1 and Now.issue = c.anchor)
    eventually (Now.ev = Adopt and By.actor = s2)
    eventually (Now.ev = WriteBody and By.actor = s1)
    eventually (Now.ev = WriteBody and By.actor = s2)
    eventually (r1 in c.body and r2 in c.body)
    noCloseNoDelete
  }
}

/* R1e. The candidate it beats: writing the body only at open and close still
   loses a repository. */
pred R1e_CloseOnlyStillLoses {
  syncAtCloseOnly
  some c: Campaign, disj s1, s2: Session, i: Issue, r: Repo {
    eventually (Now.ev = FileAnchor and By.actor = s1 and Now.issue = c.anchor)
    eventually (Now.ev = AddMember and By.actor = s1 and Now.issue = i)
    eventually (Now.ev = Adopt and By.actor = s2)
    -- both syncs happen with a real, settled subtask in the campaign, so
    -- `syncAtCloseOnly` is being obeyed rather than satisfied vacuously by a
    -- campaign that has no members at all.
    eventually (Now.ev = WriteBody and By.actor = s1 and i in c.members and settled[i])
    eventually (Now.ev = WriteBody and By.actor = s2 and i in c.members and settled[i])
    eventually (r in c.body and after (always r not in c.body))
    noCloseNoDelete
  }
}

/* R1h. THE RESIDUE, and AGENTS.md names it rather than implying it is gone: one
   campaign, one machine is a rule sessions follow, not a lock GitHub enforces. A
   session on a machine the campaign is not BOUND to can still overwrite the body
   -- `gh issue edit` refuses nothing -- and the loss returns exactly as R1 had
   it, while the bound machine's session obeyed the rule throughout. SAT is the
   point, and it is one of the two reasons compare-then-write is the everyday
   guard. */
pred R1h_UnboundMachineStillLoses {
  some c: Campaign, disj s1, s2: Session, r: Repo {
    s1.smach != s2.smach
    always Binding.bound[c] = s1.smach    -- the campaign is bound to s1's machine
    always Binding.bound[c] != s2.smach   -- s2's machine is not the bound one
    eventually (Now.ev = WriteBody and By.actor = s1)
    eventually (Now.ev = WriteBody and By.actor = s2)
    eventually (r in c.body and after (always r not in c.body))
    noCloseNoDelete
  }
}

/* R1p. THE OTHER REASON, and the measurement #59's promotion of
   compare-then-write rests on. With the holder retired, the binding is the
   whole membership rule -- and two sessions on the one bound machine are both
   members, so `boundOnly` alone leaves R1's two syncs legal and the loss
   returns. SAT: one campaign, one machine never serialized the body by itself;
   the holder did, and with the holder gone, compare-then-write (R1c, UNSAT at
   these bounds) is what carries the property. The retired discipline's own
   final measurements are in the header. */
pred R1p_BoundAloneStillLoses { boundOnly and R1_LostBodyUpdate }

/* R1j. The two-moment rule measured against the loss it is not for: SAT. Writing
   the body at a scope change and at the close says nothing about comparing
   before you write, so both sessions still sync and a repository still leaves
   the list for good. The two disciplines are orthogonal, and stating that here
   is what stops the next reader from adopting one as the other. */
pred R1j_TwoMomentStillLoses { syncAtTwoMoments and R1_LostBodyUpdate }

/* R1k. Control for R1j, and the difference from `syncAtCloseOnly` in one trace:
   a repository joins mid-campaign and is synced while a subtask of the campaign
   is still open. Under `syncAtCloseOnly` that write cannot happen at all, which
   is R1e's hidden cost -- the addition sits in one README, invisible to every
   other session, until a close that then loses it. */
pred R1k_TwoMomentAdmitsScopeSync {
  syncAtTwoMoments
  some c: Campaign, s: Session, i: Issue, r: Repo {
    eventually (Now.ev = EditReadme and By.actor = s and r not in c.body)
    eventually (Now.ev = WriteBody and By.actor = s
                and i in c.members and not settled[i] and r in c.body')
    noCloseNoDelete
  }
}

/* =================== 2. duplicate campaigns =================== */

/* R2. Two sessions each survey the open anchors, each find nothing covering the
   request, and each file. Two anchors, one scope. */
/* WITNESS. Survey(S0), Survey(S1) -- neither sees a covering campaign --
   FileAnchor(S1), FileAnchor(S0). Two anchors, one scope. */
pred R2_DuplicateCampaign {
  some disj s1, s2: Session, disj c1, c2: Campaign {
    c1 in Req.covers and c2 in Req.covers
    eventually (Now.ev = FileAnchor and By.actor = s1 and Now.issue = c1.anchor)
    eventually (Now.ev = FileAnchor and By.actor = s2 and Now.issue = c2.anchor)
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
    c in Req.covers
    eventually (Now.ev = FileAnchor and By.actor = s and Now.issue = c.anchor)
  }
}

/* =================== 3. a close during another session's work =================== */

/* R3. Same machine, one directory. Session 2 deletes the campaign tree while
   session 1 is working in it with checkouts on disk.

   The finding needs no delegate at all, which is why it is stated in the layer
   that has none: this model cannot express a live agent, so every gate the
   design has -- the live-agent refusal in closing-campaign step 1 -- passes
   vacuously here, and the loss happens anyway. A live SESSION is invisible to
   that gate. */
/* WITNESS. Same slug, same date, one directory. S1 deletes it while S0 holds
   the campaign with checkouts on disk. */
pred R3_DeleteUnderWorkingSession {
  some c: Campaign, disj s1, s2: Session {
    s1.smach = s2.smach
    eventually (Now.ev = DeleteDir and By.actor = s2
                and s1 in working and s1.holds = c
                and some (treesOf[c]).co)
  }
}

/* R3d and R3g stood here and are retired with the holder; their final
   measurements are in the header. What R3d measured -- the holder discipline
   does not close R3 -- has nothing left to measure: no discipline in this layer
   claims to close R3 now, and the repair was always one layer up, in the record
   the deleting session can read. That repair survives the rename: A10-A12 in
   agent.als, keyed on `runtime/claims/` instead of `runtime/executors/`. */

/* =================== 4. a campaign with no member repository =================== */

/* R4. `## Repos` reads `- none`. What says the campaign has no member
   repository is `always no c.body` and nothing else: `c.body` IS the `## Repos`
   list, so an empty one for the whole trace is the list reading `- none`. Note
   what the predicate does not say -- the container is in `c.members` here, as
   the home of the subtask, because a repo-less campaign files on the container
   tracker; "no member repository" is a claim about the list, not about which
   repository an issue is homed on. Such subtasks are worked by the session's
   own hands or by an in-process subagent in the campaign directory, the
   delegate-in-a-clone mode wanting a checkout this campaign never has.

   WITNESS, and it is the campaign's whole life in one trace: Survey,
   FileAnchor, AddMember on a container-homed issue, Claim on the container's
   own campaign-<N>/<issue>-<topic> ref, CloseIssue on that subtask with no pull
   request behind it, CloseIssue on the anchor.

   Two things it is checked WITH rather than instead of. The disciplines stay
   on -- compare-then-write, re-survey-at-file, and the close discipline all
   hold in the trace -- so what is witnessed is a repo-less campaign the design
   admits, not one that got past the design by having a gate switched off. And
   the claim is required, on the container: the branch is the claim before it is
   a workspace, and dropping that conjunct would witness a campaign whose
   subtasks nothing serializes.

   The subtask closes with no merged pull request, which is what
   scripts/campaign-settlement prints as `dropped [completed, no merged pull
   request]`. `settled` covers it, so `closable` holds and the anchor closes on
   it -- the designed reading, checked here for the case that has no pull
   request to offer.

   This run is why ledger.als's container clause is no longer a clause of
   WellFormed: as a global fact it made a container-homed subtask unfilable, and
   R4 was UNSAT against it. It survives there as
   `containerIssuesAreCampaignIssues`, conjoined by the scenario that is about
   it (S18/S18a), where it constrains what it meant to constrain and nothing
   else. */
pred R4_RepolessCampaign {
  syncCAS and surveyAtFile
  some s: Session, c: Campaign, i: Issue {
    closeDisciplineHere[c]
    always no c.body              -- `- none`: the list never names a repository
    i.home = Container            -- the only tracker there is
    eventually (Now.ev = FileAnchor and By.actor = s and Now.issue = c.anchor)
    eventually (Now.ev = AddMember and By.actor = s and Now.issue = i)
    eventually (Now.ev = Claim and By.actor = s and Now.issue = i)
    eventually (Now.ev = CloseIssue and Now.issue = i and no i.pr)
    eventually (Now.ev = CloseIssue and Now.issue = c.anchor)
    eventually (campaignClosed[c] and i in c.members and dropped[i])
  }
}
/* ---------------- reachability floor ----------------
 * The four events this layer introduces, and every refinement it adds to a
 * lower layer's event. A refinement that cannot be satisfied would make its
 * event unreachable from here upward while the lower layer's own floor stayed
 * green, which is exactly the failure a floor exists to catch.
 */
pred Cov_Survey            { eventually Now.ev = Survey }
pred Cov_Adopt             { eventually Now.ev = Adopt }
pred Cov_ReadBody          { eventually Now.ev = ReadBody }
pred Cov_EditReadme        { eventually Now.ev = EditReadme }
pred Cov_Sync              { eventually (Now.ev = WriteBody and some By.actor) }
pred Cov_CloseAnchor       { eventually (Now.ev = CloseIssue and Now.issue in Campaign.anchor) }
pred Cov_FiledBySession    { eventually (Now.ev = FileAnchor and some By.actor) }
pred Cov_MemberBySession   { eventually (Now.ev = AddMember and some By.actor) }
pred Cov_DirBySession      { eventually (Now.ev = CreateDir and some By.actor) }
pred Cov_DeleteBySession   { eventually (Now.ev = DeleteDir and some By.actor) }
pred Cov_AcquireBySession  { eventually (Now.ev = Acquire and some By.actor) }
pred Cov_ClaimBySession    { eventually (Now.ev = Claim and some By.actor) }
pred Cov_ReleaseBySession  { eventually (Now.ev = Release and some By.actor) }
pred Cov_LaunchBySession   { eventually (Now.ev = Launch and some By.actor) }
pred Cov_MergeBySession    { eventually (Now.ev = MergePR and some By.actor) }
pred Cov_Bound             { eventually (Now.ev = FileAnchor and some Binding.bound') }

/* ---------------- commands ---------------- */

run R1_LostBodyUpdate            for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps
run R1b_IndexOutlivesRepoList    for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 14 steps
run R1c_CASBlocksLoss            for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps
run R1d_CASAdmitsBothSyncs       for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 14 steps
run R1e_CloseOnlyStillLoses      for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps
run R1h_UnboundMachineStillLoses for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps
run R1p_BoundAloneStillLoses     for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps
run R1j_TwoMomentStillLoses      for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps
run R1k_TwoMomentAdmitsScopeSync for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps

run R2_DuplicateCampaign         for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run R2b_SurveyAtFileBlocks       for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run R2c_SurveyAtFileAdmitsOne    for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps

run R3_DeleteUnderWorkingSession for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps

run R4_RepolessCampaign          for 2 Issue, 1 PR, 1 Campaign, 1 Session, 1 Machine, 1 Repo, 1 Topic, 1 Tree, 12 steps

run Cov_Survey            for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps
run Cov_Adopt             for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps
run Cov_ReadBody          for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps
run Cov_EditReadme        for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps
run Cov_Sync              for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps
run Cov_CloseAnchor       for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps
run Cov_FiledBySession    for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps
run Cov_MemberBySession   for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps
run Cov_DirBySession      for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps
run Cov_DeleteBySession   for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps
run Cov_AcquireBySession  for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps
run Cov_ClaimBySession    for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps
run Cov_ReleaseBySession  for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps
run Cov_LaunchBySession   for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps
run Cov_MergeBySession    for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps
run Cov_Bound             for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps
