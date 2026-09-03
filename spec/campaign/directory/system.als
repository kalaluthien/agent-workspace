/*
 * One campaign's directory on a machine, and the repository checkouts inside
 * it. It opens github/system because a directory holds a campaign's work and a
 * checkout is of a repository, and both of those are the entity below.
 *
 *   Machine       a machine a campaign can run on.
 *   Branch        a git branch a checkout can be on.
 *   CampaignDir   one campaign's directory on one machine: which campaign,
 *                 which machine, and which branch each repository is on.
 *   OnDisk        the campaign directories that currently exist.
 *   Where         the observer: which machine and which repository the current
 *                 event touched.
 *
 * A campaign directory holds no fact another machine reads, which is what lets
 * it be optional and lets two machines hold one campaign under directory names
 * differing only in date.
 *
 * CampaignDir is keyed by an atom rather than carried as two columns on a
 * holder. Keep it that way: Kodkod cannot represent the five-column varying
 * relation those columns would make once the composed universe passes about
 * seventy atoms.
 */
module directory/system

open github/system

sig Machine {}
sig Branch {}

/* One campaign's directory on one machine. Keyed by an atom rather than
   carried as two columns on a holder: Kodkod cannot represent the five-ary var
   relation those columns would make once the composed universe passes about
   seventy atoms. */
sig CampaignDir {
  campaign:         one Campaign,
  machine:         one Machine,
  var checkedOut: Repo -> Branch
}
var sig OnDisk in CampaignDir {}

fun campaignDirsOf[c: Campaign]: set CampaignDir             { campaign.c }
fun campaignDirAt[c: Campaign, m: Machine]: lone CampaignDir { campaign.c & machine.m }
fun machinesHolding[c: Campaign]: set Machine           { (OnDisk & campaign.c).machine }

one sig Where {
  var machine: lone Machine,
  var repo: lone Repo
}

fact DirectoryWellFormed {
  all disj x, y: CampaignDir | x.campaign != y.campaign or x.machine != y.machine
  always all t: CampaignDir, r: Repo | lone t.checkedOut[r]
}

/* ---------------- observable events ---------------- */

one sig CreateDir, DeleteDir, Acquire extends Event {}

fun directoryEvents: set Event { CreateDir + DeleteDir + Acquire }

pred directoryFrame { OnDisk' = OnDisk and checkedOut' = checkedOut }

pred createDir[t: CampaignDir] {
  t not in OnDisk
  OnDisk' = OnDisk + t
  checkedOut' = checkedOut
  Now.event = CreateDir and no Now.issue and Where.machine = t.machine and no Where.repo
}

/* Unguarded: this entity has no role, so "no campaign closes while a role is
   live under its tree" cannot be stated here. orchestration/checks.als's
   NoOrphanIfGuarded is that rule assumed and checked. */
pred deleteDir[t: CampaignDir] {
  t in OnDisk
  OnDisk'  = OnDisk - t
  checkedOut' = checkedOut - t->Repo->Branch
  Now.event = DeleteDir and no Now.issue and Where.machine = t.machine and no Where.repo
}

/* opening-campaign/scripts/acquire-repo.sh. On a re-run over an existing checkout it switches the
   branch, which is what orchestration/scenarios.als's R4c catches it doing under a live role. */
pred acquire[t: CampaignDir, r: Repo, b: Branch] {
  t in OnDisk
  t.checkedOut[r] != b
  checkedOut' = checkedOut - t->r->Branch + t->r->b
  OnDisk' = OnDisk
  Now.event = Acquire and no Now.issue and Where.machine = t.machine and Where.repo = r
}

pred directoryInit {
  all t: CampaignDir | some t.checkedOut implies t in OnDisk
}

pred directoryStep {
  (Now.event = Stutter and directoryFrame and no Where.machine and no Where.repo)
  or (some t: CampaignDir | createDir[t] or deleteDir[t])
  or (some t: CampaignDir, r: Repo, b: Branch | acquire[t,r,b])
  or (Now.event in githubEvents and directoryFrame and no Where.machine and no Where.repo)
  /* An event declared in an entity above. `Where` is left to that entity: the
     one directly above sets `Where.machine` on its own events, and constrains it
     to none on everything higher, so the observer is pinned exactly once. */
  or (Now.event not in Stutter + githubEvents + directoryEvents and directoryFrame)
}

fact DirectoryTrace { directoryInit and always directoryStep }
