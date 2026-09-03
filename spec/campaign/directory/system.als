/*
 * One campaign's directory on one machine, and the member checkouts inside it.
 * github/system.als is spec/'s entry point: the entity table and the
 * composition idiom are there.
 *
 * The directory is a cache, not a plane of its own: it holds no fact another
 * machine reads, which is what lets it be optional and lets two machines hold
 * one campaign under directory names differing only in date. `Site` -- the
 * observer for which machine and which repository an event touched -- is
 * declared here, and the entity above sets it on its own events.
 */
module directory/system

open github/system

sig Machine {}
sig Topic {}

/* One campaign's directory on one machine. Keyed by an atom rather than
   carried as two columns on a holder: Kodkod cannot represent the five-ary var
   relation those columns would make once the composed universe passes about
   seventy atoms. */
sig Tree {
  camp:         one Campaign,
  mach:         one Machine,
  var checkout: Repo -> Topic
}
var sig Present in Tree {}

fun treesOf[c: Campaign]: set Tree             { camp.c }
fun treeAt[c: Campaign, m: Machine]: lone Tree { camp.c & mach.m }
fun dirsOf[c: Campaign]: set Machine           { (Present & camp.c).mach }

one sig Site {
  var mach: lone Machine,
  var repo: lone Repo
}

fact DirectoryWellFormed {
  all disj x, y: Tree | x.camp != y.camp or x.mach != y.mach
  always all t: Tree, r: Repo | lone t.checkout[r]
}

/* ---------------- observable events ---------------- */

one sig CreateDir, DeleteDir, Acquire extends Event {}

fun directoryEvents: set Event { CreateDir + DeleteDir + Acquire }

pred directoryFrame { Present' = Present and checkout' = checkout }

pred createDir[t: Tree] {
  t not in Present
  Present' = Present + t
  checkout' = checkout
  Now.ev = CreateDir and no Now.issue and Site.mach = t.mach and no Site.repo
}

/* Unguarded: this entity has no role, so "no campaign closes while a role is
   live under its tree" cannot be stated here. role/checks.als's
   NoOrphanIfGuarded is that rule assumed and checked. */
pred deleteDir[t: Tree] {
  t in Present
  Present'  = Present - t
  checkout' = checkout - t->Repo->Topic
  Now.ev = DeleteDir and no Now.issue and Site.mach = t.mach and no Site.repo
}

/* opening-campaign/scripts/acquire-repo.sh. On a re-run over an existing checkout it switches the
   branch, which is what role/scenarios.als's R4c catches it doing under a live role. */
pred acquire[t: Tree, r: Repo, b: Topic] {
  t in Present
  t.checkout[r] != b
  checkout' = checkout - t->r->Topic + t->r->b
  Present' = Present
  Now.ev = Acquire and no Now.issue and Site.mach = t.mach and Site.repo = r
}

pred directoryInit {
  all t: Tree | some t.checkout implies t in Present
}

pred directoryStep {
  (Now.ev = Stutter and directoryFrame and no Site.mach and no Site.repo)
  or (some t: Tree | createDir[t] or deleteDir[t])
  or (some t: Tree, r: Repo, b: Topic | acquire[t,r,b])
  or (Now.ev in githubEvents and directoryFrame and no Site.mach and no Site.repo)
  /* An event declared in an entity above. `Site` is left to that entity: the
     one directly above sets `Site.mach` on its own events, and constrains it
     to none on everything higher, so the observer is pinned exactly once. */
  or (Now.ev not in Stutter + githubEvents + directoryEvents and directoryFrame)
}

fact DirectoryTrace { directoryInit and always directoryStep }
