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
  var checkedOut: Repo -> Branch,
  /* THE CLONES HERE THAT CARRY THE CAMPAIGN'S PRINCIPLES. #176 replaced
     `--append-system-prompt-file` and its canary with a `CLAUDE.local.md` in
     the delegate's own clone -- a file on disk in its cwd, so there is nothing
     to prove arrived. #187 question 5 is that no command anywhere wrote one, so
     the mechanism existed only as prose and a delegate launched by the book got
     nothing. Modelled as a set of repositories rather than a file, because what
     a launch needs is that the clone it launches into carries them; WHICH bytes
     is `acquire-repo.sh`'s. */
  var principled:  set Repo
}
var sig OnDisk in CampaignDir {}

fun campaignDirsOf[c: Campaign]: set CampaignDir             { campaign.c }
/* THE ONE WAY TO REACH A CAMPAIGN'S DIRECTORY, and every reading about a
   campaign goes through it -- orchestration/system.als's `holder` included.
   Stated because the base is a member of its own campaigns: a campaign
   directory holds a CLONE of the base, so a script run from
   `<campaign>/repos/campaign-base/` sits in a second checkout of the same
   repository, and resolving "which base am I" from that checkout's own git
   answers with the clone -- a base whose set of campaign directories is empty,
   which reads as a clean sweep of nothing rather than as a failure. NOT
   MODELLED, and it cannot be here: no atom carries a path, so this is prose
   with a reader in `scripts/campaign-claim.py`'s `base_root`, which walks its
   own ancestors for a campaign directory before it asks git. */
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

pred directoryFrame { OnDisk' = OnDisk and checkedOut' = checkedOut and principled' = principled }

pred createDir[t: CampaignDir] {
  t not in OnDisk
  OnDisk' = OnDisk + t
  checkedOut' = checkedOut
  principled' = principled     -- a fresh directory has no clone yet to principle
  Now.event = CreateDir and no Now.issue and Where.machine = t.machine and no Where.repo
}

/* Unguarded: this entity has no role, so "no campaign closes while a role is
   live under its tree" cannot be stated here. orchestration/checks.als's
   NoOrphanIfGuarded is that rule assumed and checked. */
pred deleteDir[t: CampaignDir] {
  t in OnDisk
  OnDisk'  = OnDisk - t
  checkedOut' = checkedOut - t->Repo->Branch
  principled' = principled - t->Repo    -- the clones go with the directory
  Now.event = DeleteDir and no Now.issue and Where.machine = t.machine and no Where.repo
}

/* opening-campaign/scripts/acquire-repo.sh. On a re-run over an existing checkout it switches the
   branch, which is what orchestration/scenarios.als's R4c catches it doing under a live role.
   Not modelled, stated: an acquired checkout carries the repository's own git hooks when the
   repository ships an installer (scripts/install-hooks.sh), and the machine-wide no-main-commits
   guard alone otherwise, and acquire-repo.sh verifies the guard is chained on both paths. For a
   repository shipping this base's installer, one writer owns the slot -- the installer, which
   adopts the guard's shim and refuses anything else -- because two writers left every delegate
   clone with no hook of the repository's own, and a commit there was never auto-pushed. */
pred acquire[t: CampaignDir, r: Repo, b: Branch] {
  t in OnDisk
  t.checkedOut[r] != b
  checkedOut' = checkedOut - t->r->Branch + t->r->b
  /* ACQUIRE IS WHAT PRINCIPLES A CLONE, and saying so is the whole of the
     mechanism: `acquire-repo.sh` writes the campaign's `AGENTS.md` into the
     checkout as `CLAUDE.local.md` on every checkout it leaves. Written into
     the event because there is no other moment -- the clone comes into
     existence here -- where `checkedOut` is a fact a later event may change.
     Without this `principled` had no producer at all: every directory event
     left it free, so R12c's witness rested on a set nothing wrote. */
  principled' = principled + t->r
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
