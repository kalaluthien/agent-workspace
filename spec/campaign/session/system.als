/*
 * A campaign session -- what makes a session one, and what it may do.
 * github/system.als is spec/'s entry point.
 *
 * A SESSION is one harness session: the `claude` process a herdr pane runs,
 * the thing `campaign-<N>-<role>-<n>` names. It sits BELOW the role because a
 * role is a session working its own claim, or a delegate a session launched --
 * so the dependency runs role -> session and cannot be nested the other way.
 *
 * ONE ROLE: a session is in a campaign exactly when the campaign is BOUND to
 * its machine. What this entity does NOT know is whether anything is running,
 * so every finding below is one a campaign session reaches with no delegate
 * anywhere.
 *
 * "Covers the request" is a static bit, not a judgement over Scope prose.
 * There is no `gh` latency, so each window measured is a minimum. Migration
 * has no event, because nothing here can observe its premise.
 */
module session/system

open checkout/system

/* `covers` hangs off a `one sig` because Campaign is github/system's signature and a
   layer above it may not add a field to it. */
one sig Req { covers: set Campaign }

sig Session {
  smach:          one Machine,
  var holds:      lone Campaign,
  var surveyResult: set Campaign,  -- what its new-versus-follow-up survey returned
  var readme:     set Repo,        -- its campaign README's `## Repos` list
  var bodyAsRead: set Repo,        -- the campaign issue body's list as it last read it
  var claims:     set Issue        -- sub-issue branches it created on the remote
}
var sig Surveyed in Session {}

/* The campaign issue's latest `BOUND <machine>` comment. A GitHub fact, so the
   layering rule would put it in github/system.als -- but its value is a Machine and
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
   is somebody's act, and naming whose is what lets role/scenarios.als's
   `mergedOnCurrentReview` hold the merger to a current review. */
fun sessionActed: set Event {
  sessionOwn + FileCampaignIssue + AddMember + CloseIssue + WriteBody + MergePR
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
  let X = { c: Campaign | c in Filed and c.campaignIssue in Open and c in Req.covers } |
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
  c in Filed and c.campaignIssue in Open
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
pred sFileCampaignIssue[s: Session] {
  Now.ev = FileCampaignIssue
  s in Surveyed
  no s.surveyResult             -- the survey found no campaign covering the request
  no s.holds
  holds' = holds - s->Campaign + s->campaignIssueOf[Now.issue]
  bound' = bound - Binding->campaignIssueOf[Now.issue]->Machine
           + Binding->campaignIssueOf[Now.issue]->s.smach
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
  Now.issue in Campaign.campaignIssue implies s.holds = campaignIssueOf[Now.issue]
  sessionFrame
  By.actor = s
}

/* Where github's `writeBody` says whose README the list changed to.
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

/* `runtime/` goes with the directory; role/system.als's `aDeleteDir` is that
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
   all is github/system.als's `Claimed`. */
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
   What may be released is role/scenarios.als's guard. */
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
        or sFileCampaignIssue[s] or sAddMember[s] or sCloseIssue[s]
        or sCreateDir[s] or sDeleteDir[s] or sAcquire[s]
        or sClaim[s] or sRelease[s] or sLaunch[s] or sMergePR[s])
  or (some s: Session, c: Campaign | adopt[s,c])
  or (some s: Session, r: Repo | editReadme[s,r])
  or (Now.ev in unattended and sessionFrame and no By.actor)
  /* an event declared in a layer above: it names its own actor, or none */
  or (Now.ev not in Stutter + sessionActed + unattended and sessionFrame)
}

fact SessionTrace { sessionInit and always sessionStep }
