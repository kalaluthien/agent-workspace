/*
 * A campaign session -- and several of them at once.
 *
 * ledger.als is spec/'s entry point and carries the orientation to all four
 * layers and the composition idiom.
 *
 *
 * THIS LAYER
 *
 * The owner's intent, modelled: any session opened in the container root is a
 * campaign session. It decides new-versus-follow-up on arrival, and several such
 * sessions may be live at once, on one machine or several, on the same campaign
 * or different ones. No session is privileged. `Session` is a first-class sig
 * and every event a session performs carries the session that did it, so the
 * actor is observable in every trace.
 *
 * This layer implements the two skills:
 *
 *   event                     performed by
 *   Survey                    opening-campaign step 1: list the open anchors,
 *                             `gh issue list --label campaign --state open`
 *   FileAnchor (actor)        opening-campaign step 3
 *   Adopt                     opening-campaign step 4 on a campaign that exists
 *   ReadBody                  `gh issue view <N> --json body`
 *   EditReadme                a repository joins: the session's own README
 *   WriteBody as Sync         closing-campaign step 4: overwrite the anchor body
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
 *
 * WHAT REPAIRS THEM, AND WHAT IT DOES NOT
 *
 * One shape, applied twice: re-read immediately before you write.
 * Compare-then-write on the anchor body (R1c, UNSAT) and re-surveying at the
 * moment of filing (R2b, UNSAT) are the two, and each has a control showing the
 * green is not the scenario being forbidden (R1d, R2c, both SAT).
 *
 * Nothing repaired R3 inside the model. It was narrowed outside it, by
 * announcing the close on the anchor issue and reading the comments back, which
 * a session that never comments still slips past.
 *
 *
 * WHY CONCURRENCY IS CHEAP RATHER THAN CORRECT
 *
 * Several sessions holding one campaign is the owner's intent, and it was not
 * what the design said: the phrase "the campaign session" appeared five times
 * without ever being defined, and one rule -- that it is the anchor body's only
 * writer -- contradicted the intent outright. This layer is what settled it.
 *
 * Two findings are narrowed rather than closed, and AGENTS.md says so rather
 * than implying otherwise. Filing is still not atomic, so two sessions can still
 * produce two anchors for one scope. And a local gate cannot see a delegate
 * alive on another machine, so a campaign can still be closed out from under
 * one; what makes that survivable is not a lock but that a delegate pushes as
 * soon as it has a commit, which is why that rule sits where it does.
 *
 * A lock would need a place to live, and every candidate is either a second copy
 * of a GitHub fact or a file the campaign directory takes with it when it goes.
 * So the answer is cheap and honest rather than correct.
 *
 *
 * NOT EXPRESSED
 *
 * "Covers the request" is a static bit, not a judgement over Scope prose. There
 * is no `gh` latency, so each window measured is a minimum.
 *
 *
 * VERDICTS
 *
 * Measured 2026-08-28 against this file.
 *
 *   R1_LostBodyUpdate                SAT   the loss
 *   R1b_IndexOutlivesRepoList        SAT   and it is worse than it looks
 *   R1c_CASBlocksLoss                UNSAT the recommendation works
 *   R1d_CASAdmitsBothSyncs           SAT   control: it is not vacuous
 *   R1e_CloseOnlyStillLoses          SAT   the candidate it beats
 *   R2_DuplicateCampaign             SAT   two anchors, one scope
 *   R2b_SurveyAtFileBlocks           UNSAT the same shape repairs it
 *   R2c_SurveyAtFileAdmitsOne        SAT   control
 *   R3_DeleteUnderWorkingSession     SAT   a live session is invisible to the gate
 *   Cov_*                            SAT   every own event and every refinement
 *                                          this layer adds fires in some trace
 *
 * The two UNSATs are proved to be findings rather than artefacts by their own
 * controls, R1d and R2c, which is the same shape the old model used and the
 * reason both pairs are kept.
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
   refines by naming the actor and adding the guard. */
fun sessionActed: set Event {
  sessionOwn + FileAnchor + AddMember + CloseIssue + WriteBody
  + CreateDir + DeleteDir + Acquire + Claim + Release + Launch
}

/* Things that happen to a campaign rather than by a session. */
fun unattended: set Event {
  OpenPR + MergePR + RemoveMember + PullContainer + PullClone + CommitLocal
}

pred sessionFrame {
  holds' = holds and saw' = saw and readme' = readme and seen' = seen
  and claims' = claims and Surveyed' = Surveyed
}

/* opening-campaign step 1: list the open campaign anchors and read their Scope.
   The result is remembered; nothing keeps it fresh. */
pred survey[s: Session] {
  let X = { c: Campaign | c in Filed and c.anchor in Open and c in Req.covers } |
    saw' = saw - s->Campaign + s->X
  Surveyed' = Surveyed + s
  holds' = holds and readme' = readme and seen' = seen and claims' = claims
  Now.ev = Survey and no Now.issue and By.actor = s
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
  saw' = saw and Surveyed' = Surveyed and claims' = claims
  Now.ev = Adopt and no Now.issue and By.actor = s
}

/* Re-derive the README from the anchor body. */
pred readBody[s: Session] {
  some s.holds
  readme' = readme - s->Repo + s->(s.holds.body)
  seen'   = seen   - s->Repo + s->(s.holds.body)
  holds' = holds and saw' = saw and Surveyed' = Surveyed and claims' = claims
  Now.ev = ReadBody and no Now.issue and By.actor = s
}

/* A repository joins the campaign: the session adds it to its own README. */
pred editReadme[s: Session, r: Repo] {
  some s.holds
  r not in s.readme
  readme' = readme + s->r
  holds' = holds and saw' = saw and seen' = seen and Surveyed' = Surveyed and claims' = claims
  Now.ev = EditReadme and no Now.issue and By.actor = s
}

/* --- refinements: the actor and the guard on a lower layer's event --- */

/* opening-campaign step 3: file the anchor, on the strength of the survey. */
pred sFileAnchor[s: Session] {
  Now.ev = FileAnchor
  s in Surveyed
  no s.saw                      -- the survey found no campaign covering the request
  no s.holds
  holds' = holds - s->Campaign + s->anchorOf[Now.issue]
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
  By.actor = s
}

/* Two sessions on one machine resolve <slug>-<YYMMDD>/ to the same path, so the
   directory is per campaign per machine, not per session. */
pred sCreateDir[s: Session] {
  Now.ev = CreateDir
  some s.holds
  Site.mach = s.smach
  some treeAt[s.holds, s.smach] and treeAt[s.holds, s.smach] in Present'
  sessionFrame
  By.actor = s
}

pred sDeleteDir[s: Session] {
  Now.ev = DeleteDir
  some s.holds
  Site.mach = s.smach
  some treeAt[s.holds, s.smach] and treeAt[s.holds, s.smach] not in Present'
  sessionFrame
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
  By.actor = s
}

/* The claim is dropped by whoever reads the branch as dangling, not only by the
   session that made it. What may be released is agent.als's guard. */
pred sRelease[s: Session] {
  Now.ev = Release
  claims' = claims - Session->Now.issue
  holds' = holds and saw' = saw and readme' = readme
  and seen' = seen and Surveyed' = Surveyed
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
        or sClaim[s] or sRelease[s] or sLaunch[s])
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

/* ---------------- commands ---------------- */

run R1_LostBodyUpdate            for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps
run R1b_IndexOutlivesRepoList    for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 14 steps
run R1c_CASBlocksLoss            for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps
run R1d_CASAdmitsBothSyncs       for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 14 steps
run R1e_CloseOnlyStillLoses      for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps

run R2_DuplicateCampaign         for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run R2b_SurveyAtFileBlocks       for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps
run R2c_SurveyAtFileAdmitsOne    for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps

run R3_DeleteUnderWorkingSession for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps

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
