/*
 * A campaign session -- what makes a session one, and what it may do.
 * ledger.als is spec/'s entry point.
 *
 * ONE ROLE: a session is in a campaign exactly when the campaign is BOUND to
 * its machine. What this layer does NOT know is whether anything is running,
 * so every finding below is one a campaign session reaches with no delegate
 * anywhere.
 *
 * "Covers the request" is a static bit, not a judgement over Scope prose.
 * There is no `gh` latency, so each window measured is a minimum. Migration
 * has no event, because nothing here can observe its premise.
 */
module session

open repos

/* ==================== SYSTEM ==================== */

/* `covers` hangs off a `one sig` because Campaign is ledger's signature and a
   layer above it may not add a field to it. */
one sig Req { covers: set Campaign }

sig Session {
  smach:          one Machine,
  var holds:      lone Campaign,
  var surveyResult: set Campaign,  -- what its new-versus-follow-up survey returned
  var readme:     set Repo,        -- its campaign README's `## Repos` list
  var bodyAsRead: set Repo,        -- the anchor body's list as it last read it
  var claims:     set Issue        -- sub-issue branches it created on the remote
}
var sig Surveyed in Session {}

/* The anchor's latest `BOUND <machine>` comment. A GitHub fact, so the
   layering rule would put it in ledger.als -- but its value is a Machine and
   its source is the filing session's own `smach`, and this is the lowest layer
   that has either. The placement follows from that, not from the binding being
   local. */
one sig Binding {
  var bound: Campaign -> Machine
}

fact BindingWellFormed {
  always all c: Campaign | lone Binding.bound[c]
}

one sig By { var actor: lone Session }

/* Derived, so no event has to maintain it. */
fun working: set Session { { s: Session | some s.holds and s.smach in dirsOf[s.holds] } }

/* ---------------- observable events ---------------- */

one sig Survey, Adopt, ReadBody, EditReadme extends Event {}

fun sessionOwn: set Event { Survey + Adopt + ReadBody + EditReadme }

/* `MergePR` is here rather than in `unattended` because landing a pull request
   is somebody's act, and naming whose is what lets agent.als's
   `mergedOnCurrentReview` hold the merger to a current review. */
fun sessionActed: set Event {
  sessionOwn + FileAnchor + AddMember + CloseIssue + WriteBody + MergePR
  + CreateDir + DeleteDir + Acquire + Claim + Release + Launch
}

/* `RemoveMember` is here because moving a sub-issue out has no sanctioned flow:
   it is a hand-run `gh issue edit --remove-parent`. */
fun unattended: set Event {
  OpenPR + RemoveMember + PullContainer + PullClone + CommitLocal
}

pred sessionFrame {
  holds' = holds and surveyResult' = surveyResult and readme' = readme
  and bodyAsRead' = bodyAsRead
  and claims' = claims and Surveyed' = Surveyed
  and bound' = bound
}

/* The result is remembered; nothing keeps it fresh. */
pred survey[s: Session] {
  let X = { c: Campaign | c in Filed and c.anchor in Open and c in Req.covers } |
    surveyResult' = surveyResult - s->Campaign + s->X
  Surveyed' = Surveyed + s
  holds' = holds and readme' = readme and bodyAsRead' = bodyAsRead and claims' = claims
  bound' = bound
  Now.ev = Survey and no Now.issue and By.actor = s
}

/* Nothing is taken: under one role, arriving is just starting to work.
   Unguarded here, so the unrepaired scenarios stay measurable against the same
   trace space; `boundOnly` is the membership rule applied per command. */
pred adopt[s: Session, c: Campaign] {
  c in Filed and c.anchor in Open
  no s.holds
  holds'      = holds  - s->Campaign + s->c
  readme'     = readme - s->Repo + s->(c.body)
  bodyAsRead' = bodyAsRead - s->Repo + s->(c.body)
  surveyResult' = surveyResult and Surveyed' = Surveyed and claims' = claims
  bound' = bound
  Now.ev = Adopt and no Now.issue and By.actor = s
}

pred readBody[s: Session] {
  some s.holds
  readme'     = readme - s->Repo + s->(s.holds.body)
  bodyAsRead' = bodyAsRead - s->Repo + s->(s.holds.body)
  holds' = holds and surveyResult' = surveyResult and Surveyed' = Surveyed and claims' = claims
  bound' = bound
  Now.ev = ReadBody and no Now.issue and By.actor = s
}

pred editReadme[s: Session, r: Repo] {
  some s.holds
  r not in s.readme
  readme' = readme + s->r
  holds' = holds and surveyResult' = surveyResult and bodyAsRead' = bodyAsRead
  and Surveyed' = Surveyed and claims' = claims
  bound' = bound
  Now.ev = EditReadme and no Now.issue and By.actor = s
}

/* --- refinements: the actor and the guard on a lower layer's event --- */

/* The binding is posted in the same step, because everything after it is a
   write or a launch and both are gated on it. */
pred sFileAnchor[s: Session] {
  Now.ev = FileAnchor
  s in Surveyed
  no s.surveyResult             -- the survey found no campaign covering the request
  no s.holds
  holds' = holds - s->Campaign + s->anchorOf[Now.issue]
  bound' = bound - Binding->anchorOf[Now.issue]->Machine
           + Binding->anchorOf[Now.issue]->s.smach
  surveyResult' = surveyResult and readme' = readme and bodyAsRead' = bodyAsRead
  and Surveyed' = Surveyed and claims' = claims
  By.actor = s
}

pred sAddMember[s: Session] {
  Now.ev = AddMember
  some s.holds
  s.holds->Now.issue in members'
  sessionFrame
  By.actor = s
}

/* Any other issue is an ordinary sub-issue close and needs no such tie. */
pred sCloseIssue[s: Session] {
  Now.ev = CloseIssue
  Now.issue in Campaign.anchor implies s.holds = anchorOf[Now.issue]
  sessionFrame
  By.actor = s
}

/* Where ledger's `writeBody` says whose README the list changed to.
   Unguarded as written; `syncCAS` is the repair. */
pred sync[s: Session] {
  Now.ev = WriteBody
  some s.holds
  body' = body - s.holds->Repo + s.holds->(s.readme)
  bodyAsRead' = bodyAsRead - s->Repo + s->(s.readme)
  holds' = holds and surveyResult' = surveyResult and readme' = readme
  and Surveyed' = Surveyed and claims' = claims
  bound' = bound
  By.actor = s
}

/* Two sessions on one machine resolve <slug>-<YYMMDD>/ to the same path, so
   the directory is per campaign per machine, not per session. */
pred sCreateDir[s: Session] {
  Now.ev = CreateDir
  some s.holds
  Site.mach = s.smach
  some treeAt[s.holds, s.smach] and treeAt[s.holds, s.smach] in Present'
  bound' = bound
  holds' = holds and surveyResult' = surveyResult and readme' = readme
  and bodyAsRead' = bodyAsRead
  and claims' = claims and Surveyed' = Surveyed
  By.actor = s
}

/* `runtime/` goes with the directory; agent.als's `aDeleteDir` is that
   lifetime on the record's own bit. */
pred sDeleteDir[s: Session] {
  Now.ev = DeleteDir
  some s.holds
  Site.mach = s.smach
  some treeAt[s.holds, s.smach] and treeAt[s.holds, s.smach] not in Present'
  bound' = bound
  holds' = holds and surveyResult' = surveyResult and readme' = readme
  and bodyAsRead' = bodyAsRead
  and claims' = claims and Surveyed' = Surveyed
  By.actor = s
}

pred sAcquire[s: Session] {
  Now.ev = Acquire
  some s.holds
  Site.mach = s.smach
  -- the checkout that moved is in this session's campaign tree
  checkout' - treesOf[s.holds]->Repo->Topic = checkout - treesOf[s.holds]->Repo->Topic
  sessionFrame
  By.actor = s
}

/* Which session created it is what `claims` records; that the ref exists at
   all is repos.als's `Claimed`. */
pred sClaim[s: Session] {
  Now.ev = Claim
  some s.holds
  Now.issue in s.holds.members
  claims' = claims + s->Now.issue
  holds' = holds and surveyResult' = surveyResult and readme' = readme
  and bodyAsRead' = bodyAsRead and Surveyed' = Surveyed
  bound' = bound
  By.actor = s
}

/* Dropped by whoever reads the branch as dangling, not only by its maker.
   What may be released is agent.als's guard. */
pred sRelease[s: Session] {
  Now.ev = Release
  claims' = claims - Session->Now.issue
  holds' = holds and surveyResult' = surveyResult and readme' = readme
  and bodyAsRead' = bodyAsRead and Surveyed' = Surveyed
  bound' = bound
  By.actor = s
}

/* Loose: this layer says only that a session did it. */
pred sMergePR[s: Session] {
  Now.ev = MergePR
  sessionFrame
  By.actor = s
}

pred sLaunch[s: Session] {
  Now.ev = Launch
  some s.holds
  Site.mach = s.smach
  s.smach in dirsOf[s.holds]
  Now.issue in s.holds.members and Now.issue in Open
  sessionFrame
  By.actor = s
}

/* A session may already hold a campaign at time zero; the scenarios ABOUT
   arriving require the arrival events explicitly. `bound` is deliberately
   unconstrained: a campaign in flight was bound by a session this trace never
   contains. */
pred sessionInit {
  no Surveyed
  all s: Session {
    s.holds in Filed
    no s.surveyResult and no s.claims
    s.readme = s.holds.body and s.bodyAsRead = s.holds.body
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

/* Compare-then-write, THE guard the design adopted. Emptying it -- the
   discipline present but comparing nothing -- brings the loss back, so R1c's
   green is the comparison and not the shape of the scenario. */
pred syncCAS { always (Now.ev = WriteBody implies By.actor.holds.body = By.actor.bodyAsRead) }

/* The rejected candidate, modelled as "sync only when every sub-issue is
   settled". R1e is what it costs. */
pred syncAtCloseOnly {
  always (Now.ev = WriteBody implies (all i: By.actor.holds.members | settled[i]))
}

/* A rule about WHEN, where compare-then-write is a rule about HOW, so the two
   are not alternatives: R1j measures that, R1k is what it beats
   `syncAtCloseOnly` by. */
pred syncAtTwoMoments {
  always (Now.ev = WriteBody implies
            (some By.actor.readme - By.actor.holds.body        -- a scope change
             or (all i: By.actor.holds.members | settled[i]))) -- or the close
}

/* R1p is why the membership rule is not enough by itself. */
pred boundOnly {
  always (Now.ev = Adopt implies Binding.bound[By.actor.holds'] = By.actor.smach)
  always (Now.ev in WriteBody + CreateDir + DeleteDir implies
            Binding.bound[By.actor.holds] = By.actor.smach)
  always ((Now.ev = CloseIssue and Now.issue in Campaign.anchor) implies
            Binding.bound[anchorOf[Now.issue]] = By.actor.smach)
}

/* NARROWS the window rather than closing it: read and create are not atomic,
   and this model has no clock. */
pred surveyAtFile {
  always (Now.ev = FileAnchor implies
            (no c: Campaign | c in Filed and c.anchor in Open and c in Req.covers))
}

/* So a repository leaving the list is the write that lost it, and not a
   campaign being torn down. */
pred noCloseNoDelete {
  always (Now.ev != DeleteDir
          and (Now.ev = CloseIssue implies Now.issue not in Campaign.anchor))
}

/* =================== 1. two sessions sync the body =================== */

/* R1. S1 files and adds R0 to its README; S0 adopts while the body is still
   empty; S1 syncs, so the body reads {R0}; S0 syncs from its own stale README,
   so the body reads empty. R0 never returns, and no event means "remove a
   repository". */
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

/* R1b. A body write cannot touch a sub-issue link, so the index goes on
   naming an open sub-issue homed in a repository the list has dropped -- and
   closing the campaign deletes that list's last copy. Ordered on purpose:
   unordered it reads SAT on the ordinary window between filing and syncing. */
pred R1b_IndexOutlivesRepoList {
  some c: Campaign, disj s1, s2: Session, i: Issue, r: Repo {
    r != Container and i.home = r
    eventually (Now.ev = WriteBody and By.actor = s1)
    eventually (Now.ev = WriteBody and By.actor = s2)
    eventually (i in idx[c] and r in c.body
                and after (always (i in idx[c] and i in Open and r not in c.body)))
    noCloseNoDelete
  }
}

/* R1c. The recommendation, and the loss is gone. */
pred R1c_CASBlocksLoss { syncCAS and R1_LostBodyUpdate }

/* R1d. UNSAT here would mean R1c went green by forbidding the scenario. */
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

/* R1e. Both syncs happen with a real settled sub-issue in the campaign, so
   `syncAtCloseOnly` is obeyed rather than satisfied vacuously. */
pred R1e_CloseOnlyStillLoses {
  syncAtCloseOnly
  some c: Campaign, disj s1, s2: Session, i: Issue, r: Repo {
    eventually (Now.ev = FileAnchor and By.actor = s1 and Now.issue = c.anchor)
    eventually (Now.ev = AddMember and By.actor = s1 and Now.issue = i)
    eventually (Now.ev = Adopt and By.actor = s2)
    eventually (Now.ev = WriteBody and By.actor = s1 and i in c.members and settled[i])
    eventually (Now.ev = WriteBody and By.actor = s2 and i in c.members and settled[i])
    eventually (r in c.body and after (always r not in c.body))
    noCloseNoDelete
  }
}

/* R1h. The binding is a rule sessions follow, not a lock GitHub enforces:
   `gh issue edit` refuses nothing. */
pred R1h_UnboundMachineStillLoses {
  some c: Campaign, disj s1, s2: Session, r: Repo {
    s1.smach != s2.smach
    always Binding.bound[c] = s1.smach
    always Binding.bound[c] != s2.smach
    eventually (Now.ev = WriteBody and By.actor = s1)
    eventually (Now.ev = WriteBody and By.actor = s2)
    eventually (r in c.body and after (always r not in c.body))
    noCloseNoDelete
  }
}

/* R1p. Two sessions on the one bound machine are both members, so `boundOnly`
   alone leaves R1's two syncs legal: the membership rule never serialized the
   body. */
pred R1p_BoundAloneStillLoses { boundOnly and R1_LostBodyUpdate }

/* R1j. A WHEN rule says nothing about comparing before you write. */
pred R1j_TwoMomentStillLoses { syncAtTwoMoments and R1_LostBodyUpdate }

/* R1k. The difference from `syncAtCloseOnly` in one trace: under it, this
   mid-campaign sync cannot happen at all. */
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

/* R2. Two anchors, one scope. */
pred R2_DuplicateCampaign {
  some disj s1, s2: Session, disj c1, c2: Campaign {
    c1 in Req.covers and c2 in Req.covers
    eventually (Now.ev = FileAnchor and By.actor = s1 and Now.issue = c1.anchor)
    eventually (Now.ev = FileAnchor and By.actor = s2 and Now.issue = c2.anchor)
    eventually (c1 + c2 in Filed and c1.anchor in Open and c2.anchor in Open)
  }
}

pred R2b_SurveyAtFileBlocks { surveyAtFile and R2_DuplicateCampaign }

/* Control: with the same discipline one campaign still opens. */
pred R2c_SurveyAtFileAdmitsOne {
  surveyAtFile
  some s: Session, c: Campaign {
    c in Req.covers
    eventually (Now.ev = FileAnchor and By.actor = s and Now.issue = c.anchor)
  }
}

/* =================== 3. a close during another session's work =================== */

/* R3. The finding needs no delegate at all, which is why it is stated in the
   layer that has none: every live-agent gate the design has passes vacuously
   here and the loss happens anyway, because a live SESSION is invisible to
   that gate. Nothing in this layer repairs it -- whether a peer is working the
   tree is carried by `runtime/claims/`, so the repair is agent.als's A10-A12. */
pred R3_DeleteUnderWorkingSession {
  some c: Campaign, disj s1, s2: Session {
    s1.smach = s2.smach
    eventually (Now.ev = DeleteDir and By.actor = s2
                and s1 in working and s1.holds = c
                and some (treesOf[c]).checkout)
  }
}

/* =================== 4. a campaign with no member repository =================== */

/* R4. `- none` is encoded as `always no c.body`. Note what the predicate does
   NOT say: the container IS in `c.members`, as the home of the sub-issue, since
   a repo-less campaign files on the container tracker -- "no member
   repository" is a claim about the list, not about where an issue is homed.

   Checked WITH the disciplines rather than instead of them, and the claim is
   required: the branch is the claim before it is a workspace. */
pred R4_RepolessCampaign {
  syncCAS and surveyAtFile
  some s: Session, c: Campaign, i: Issue {
    closeDiscipline[c]
    always no c.body
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
 * green. `Cov_Bound` pins `FileAnchor` rather than reading `some
 * Binding.bound`, which `init` alone satisfies at step 0.
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

-- the loss
run R1_LostBodyUpdate            for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 1
-- and it is worse than it looks
run R1b_IndexOutlivesRepoList    for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 14 steps expect 1
-- compare-then-write works: THE guard
run R1c_CASBlocksLoss            for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 0
-- control: it is not vacuous
run R1d_CASAdmitsBothSyncs       for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 14 steps expect 1
-- the candidate it beats
run R1e_CloseOnlyStillLoses      for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 1
-- BOUND is a rule, not a lock
run R1h_UnboundMachineStillLoses for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 1
-- the membership rule never serialized the body
run R1p_BoundAloneStillLoses     for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 1
-- two moments is a WHEN rule, not a HOW
run R1j_TwoMomentStillLoses      for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 1
-- control, and the close-only difference
run R1k_TwoMomentAdmitsScopeSync for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 1

-- two anchors, one scope
run R2_DuplicateCampaign         for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
-- the same shape repairs it
run R2b_SurveyAtFileBlocks       for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 0
-- control
run R2c_SurveyAtFileAdmitsOne    for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1

-- a live session is invisible to the gate; the repair is agent.als's A10-A12
run R3_DeleteUnderWorkingSession for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps expect 1

-- `- none` opens, claims and closes
run R4_RepolessCampaign          for 2 Issue, 1 PR, 1 Campaign, 1 Session, 1 Machine, 1 Repo, 1 Topic, 1 Tree, 12 steps expect 1

-- every own event and every refinement this layer adds fires in some trace
run Cov_Survey            for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_Adopt             for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_ReadBody          for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_EditReadme        for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_Sync              for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_CloseAnchor       for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_FiledBySession    for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_MemberBySession   for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_DirBySession      for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_DeleteBySession   for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_AcquireBySession  for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_ClaimBySession    for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_ReleaseBySession  for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_LaunchBySession   for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_MergeBySession    for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_Bound             for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
