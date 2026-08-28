/*
 * A member repository, as one machine sees it and as its remote holds it.
 *
 * ledger.als is spec/'s entry point and carries the orientation to all four
 * layers, the composition idiom, and what is deliberately absent from every one
 * of them.
 *
 *
 * THIS LAYER
 *
 * Everything about a campaign that a machine holds, plus the one fact about a
 * member repository that lives on its remote: the branch that is the subtask's
 * claim. It knows nothing about who is at the keyboard -- session.als adds the
 * actor -- and nothing about a delegate, which is agent.als's.
 *
 *   event          performed by
 *   CreateDir      opening-campaign: mkdir <slug>-<YYMMDD>/ and scaffold it
 *   DeleteDir      closing-campaign step 5: rm -rf the campaign directory
 *   Acquire        scripts/acquire-repo: leave <repo> checked out on <topic>
 *   Claim          gh api repos/<o>/<r>/git/refs -f ref=refs/heads/campaign-<N>/<issue>-<topic>
 *   Release        gh api -X DELETE repos/<o>/<r>/git/refs/heads/campaign-<N>/...
 *   PullContainer  git -C "$CONTAINER" pull --ff-only
 *   PullClone      git -C <campaign>/repos/<repo> pull --ff-only
 *   CommitLocal    git -C "$CONTAINER" commit
 *   Launch         the freshness read taken in the shell that starts the delegate
 *
 * `Launch` is the cross-layer event this file starts. Here it is a marker and a
 * freshness question: WHEN is the clone's distance from origin/main read? The
 * agent-state half -- an agent becoming live on that claim and that checkout --
 * is agent.als's disjunct on the same event atom, and the actor is session.als's.
 *
 * `Claimed` is the create-ref claim and it is a REMOTE fact, which is why it is
 * one set of issues rather than a per-machine one: a claim made on one machine
 * is visible from every other, and that is the whole reason the branch is the
 * claim. Which session created it is session.als's `claims`.
 *
 *
 * VERDICTS
 *
 * Measured 2026-08-28 against this file. X is a counterexample; a check that
 * passes reads UNSAT.
 *
 *   MachineIndependence              pass  a local delete changes no shared fact
 *   S7_TwoMachinesOneDeletes         SAT
 *   S15_NoLocalDirectory             SAT
 *   S16b_ContainerBehindAfterMerge   SAT
 *   S16c_BehindForever               SAT
 *   S16d_CloneFromUnpushedContainer  SAT
 *   S17a_CloneBehindAtLaunch         SAT   the live run's finding
 *   S17b_OldCloneRuleInsufficient    SAT   the superseded rule does not stop it
 *   S17c_PullBeforeLaunchAdmitsLaunch SAT  control: the adopted rule is not vacuous
 *   Cov_*                            SAT   every own event fires in some trace
 *
 * The one green was proved able to fail twice, re-run 2026-08-28: letting
 * `deleteDir` drop every machine's directory rather than this one's reddens
 * MachineIndependence, and so does dropping `ledgerFrame` from ledger.als's
 * fall-through branch -- which is the check that the composition idiom, not a
 * frame written here, is what keeps a lower layer still while an upper layer's
 * event fires.
 *
 * WHAT MOVED. S7 arrives from a model that had agents in it and asked, in one
 * scenario, both "is the other machine's GitHub reading unchanged?" and "is the
 * live agent on the other machine unaffected?". Only the first is stateable
 * here, and it is the half MachineIndependence generalises; the agent half is
 * agent.als's S9 and NoOrphan. The scenario is not weaker for it -- it was two
 * questions in one predicate.
 */
module repos

open ledger

/* ==================== SYSTEM ==================== */

/* ---------------- static structure ---------------- */

sig Machine {}
sig Topic {}                    -- the <topic> half of a campaign-<N>/<issue>-<topic> branch

/* ONE CAMPAIGN'S DIRECTORY ON ONE MACHINE: <slug>-<YYMMDD>/, and the checkouts
   under it. A campaign and a machine name a tree, so the pair is the identity
   and two campaigns on one machine hold separate checkouts of the same
   repository -- which is what S7 and R3 turn on.

   It is a signature rather than a pair of columns on a holder because a var
   field is as wide as its owner plus its columns plus the time dimension, and
   Kodkod cannot represent a five-ary relation once the composed model's
   universe passes about seventy atoms. Keying by an atom instead of by two
   columns buys the arity back and reads better besides. */
sig Tree {
  camp:   one Campaign,
  mach:   one Machine,
  var co: Repo -> Topic         -- branch checked out in <campaign>/repos/<repo>
}
var sig Present in Tree {}      -- the directory exists on that machine

fun treesOf[c: Campaign]: set Tree     { camp.c }
fun treeAt[c: Campaign, m: Machine]: lone Tree { camp.c & mach.m }
fun dirsOf[c: Campaign]: set Machine   { (Present & camp.c).mach }

/* THE CLAIM. The subtask's branch exists on the remote, created by create-ref
   before any executor starts. create-ref refuses an existing ref server-side, at
   any SHA (probed 2026-08-28: HTTP 422 "Reference already exists"), so the claim
   is atomic where a survey-then-file is not. */
var sig Claimed in Issue {}

/* The container cloned into its own campaign tree: one repository, two
   checkouts on a machine. The OUTER checkout is where the campaign session runs
   and where its instruction files are read from; the INNER clone, under
   <campaign>/repos/agent-workspace/, is what a delegate works in and is cut
   from origin/main. */
var sig Behind   in Machine {}  -- the outer checkout is behind origin/main
var sig Unpushed in Machine {}  -- the outer checkout holds commits origin lacks
/* The INNER clone's own distance from origin/main. Separate from `Behind`
   because the two are cleared by different acts: a clone is cut fresh from
   origin/main, which says nothing about the outer checkout it sits inside. Only
   meaningful for a machine that has a campaign directory. */
var sig CloneBehind in Machine {}

/* This layer's observer: the machine an event happens on, and the repository it
   is about. */
one sig Site {
  var mach: lone Machine,
  var repo: lone Repo
}

fact ReposWellFormed {
  -- a tree is identified by its campaign and its machine
  all disj x, y: Tree | x.camp != y.camp or x.mach != y.mach
  always all t: Tree, r: Repo | lone t.co[r]
}

/* ---------------- observable events ---------------- */

one sig CreateDir, DeleteDir, Acquire, Claim, Release,
        PullContainer, PullClone, CommitLocal, Launch extends Event {}

fun reposEvents: set Event {
  CreateDir + DeleteDir + Acquire + Claim + Release
  + PullContainer + PullClone + CommitLocal + Launch
}

/* Behind, Unpushed and CloneBehind are deliberately NOT in this frame. They are
   governed end to end by CheckoutFrame and CloneFrame below, because the act
   that moves them most is a MergePR -- an event this layer does not own. */
pred reposFrame { Present' = Present and co' = co and Claimed' = Claimed }

pred createDir[t: Tree] {
  t not in Present
  Present' = Present + t
  co' = co and Claimed' = Claimed
  Now.ev = CreateDir and no Now.issue and Site.mach = t.mach and no Site.repo
}

/* The design's rule "no campaign is closed while an agent is live under its
   tree" is a discipline, not a guard: nothing here enforces it, and nothing
   here can -- this layer has no agent. agent.als's NoOrphanIfGuarded is that
   rule assumed and checked. */
pred deleteDir[t: Tree] {
  t in Present
  Present' = Present - t
  co'      = co - t->Repo->Topic
  Claimed' = Claimed
  Now.ev = DeleteDir and no Now.issue and Site.mach = t.mach and no Site.repo
}

/* scripts/acquire-repo: leave <repo> checked out on <topic> in this campaign's
   tree. On a re-run over an existing checkout it switches the branch -- which is
   exactly what agent.als's R4c catches it doing under a live delegate.

   WHY IT IS A SEAM. Cloning is one strategy among several that will be wanted,
   so callers ask for a repository at a path on a branch and get a ready
   checkout; how it got there is not their business. Only clone is implemented.
   The seam exists so these can be added later without touching a caller:

     - a shared local mirror, when a repository is too large to re-clone per
       campaign;
     - a git worktree cut from another campaign's checkout of the same
       repository;
     - a shallow or partial clone, when only recent history matters;
     - reusing an existing checkout in place.

   Implementing any of them now would be guessing at which one matters. Leaving
   the seam costs one function boundary, and this predicate is that boundary --
   it says what an acquire DOES to the checkout, not how. */
pred acquire[t: Tree, r: Repo, b: Topic] {
  t in Present
  t.co[r] != b
  co' = co - t->r->Topic + t->r->b
  Present' = Present and Claimed' = Claimed
  Now.ev = Acquire and no Now.issue and Site.mach = t.mach and Site.repo = r
}

/* The base event is deliberately LOOSE -- it does not require the ref to be
   absent -- so that atomicity can be a named discipline below and its absence a
   control, the same shape as compare-then-write in session.als. */
pred claim[i: Issue] {
  i in Campaign.members and i in Open
  Claimed' = Claimed + i
  Present' = Present and co' = co
  Now.ev = Claim and Now.issue = i and no Site.mach and no Site.repo
}

/* Releasing a dangling claim: delete the branch of an executor that never
   pushed. What may be released is guarded above this layer, in agent.als, for
   the same reason `deleteDir` is unguarded here -- the condition is about an
   executor, and this layer has none. */
pred release[i: Issue] {
  i in Claimed
  Claimed' = Claimed - i
  Present' = Present and co' = co
  Now.ev = Release and Now.issue = i and no Site.mach and no Site.repo
}

pred pullContainer[m: Machine] {
  m in Behind
  Behind' = Behind - m and Unpushed' = Unpushed
  reposFrame
  Now.ev = PullContainer and no Now.issue and Site.mach = m and no Site.repo
}

/* `git -C <campaign>/repos/<repo> pull` inside the clone. */
pred pullClone[m: Machine] {
  m in CloneBehind
  Behind' = Behind and Unpushed' = Unpushed
  reposFrame
  Now.ev = PullClone and no Now.issue and Site.mach = m and no Site.repo
}

/* An edit committed in the outer container and not yet pushed. */
pred commitLocal[m: Machine] {
  m not in Unpushed
  Unpushed' = Unpushed + m and Behind' = Behind
  reposFrame
  Now.ev = CommitLocal and no Now.issue and Site.mach = m and no Site.repo
}

/* The moment an executor is started in this machine's clone. Here it moves
   nothing: what this layer asks is WHEN the freshness check happens, not what
   the executor then does. `Now.issue` is left to the layers above, which name
   the subtask -- this one only knows there is a directory to start in. */
pred launch[m: Machine] {
  m in Present.mach
  Now.issue in Campaign.members
  reposFrame
  Now.ev = Launch and Site.mach = m and no Site.repo
}

/* Merging a pull request against the container leaves every outer checkout
   behind origin/main. Nothing else moves either bit -- in particular no event
   here writes the outer checkout from inside the clone, which is hazard 3:
   the model agrees that editing .claude/skills/ in the clone cannot change what
   the running campaign follows, but it agrees *by construction*, because that
   event was never written. That is a restatement, not evidence. */
fact CheckoutFrame {
  always ((Now.ev not in PullContainer + CommitLocal) implies
    (Unpushed' = Unpushed and
     ((Now.ev = MergePR and Now.issue.home = Container)
        implies Behind' = Machine else Behind' = Behind)))
}

/* The clone's bit, moved by three acts and nothing else: a merged container
   pull request leaves every existing clone behind origin/main; cutting the
   clone and pulling it each make one current again. */
fact CloneFrame {
  always ((Now.ev = MergePR and Now.issue.home = Container)
    implies CloneBehind' = CloneBehind + Present.mach
    else ((Now.ev in CreateDir + PullClone)
      implies CloneBehind' = CloneBehind - Site.mach
      else CloneBehind' = CloneBehind))
}

pred reposInit {
  no Claimed
  no Behind and no Unpushed and no CloneBehind
  -- a checkout only exists where a directory does
  all t: Tree | some t.co implies t in Present
}

pred reposStep {
  (Now.ev = Stutter and reposFrame and no Site.mach and no Site.repo)
  or (some t: Tree | createDir[t] or deleteDir[t])
  or (some t: Tree, r: Repo, b: Topic | acquire[t,r,b])
  or (some i: Issue | claim[i] or release[i])
  or (some m: Machine | pullContainer[m] or pullClone[m] or commitLocal[m] or launch[m])
  /* a ledger event: this layer stands still and carries no machine */
  or (Now.ev in ledgerEvents and reposFrame and no Site.mach and no Site.repo)
  /* an event declared in a layer above. It carries no machine: an executor's
     machine is a static field on the executor, and a session's is a static
     field on the session, so nothing above needs to observe one here. */
  or (Now.ev not in Stutter + ledgerEvents + reposEvents
      and reposFrame and no Site.mach and no Site.repo)
}

fact ReposTrace { reposInit and always reposStep }

/* ==================== SCENARIOS ==================== */

/* PASS. Machine independence: deleting a local directory changes no fact
   another machine reads -- not a GitHub fact, not the claim on the remote, not
   another machine's directory. This is the claim that lets the directory be
   optional and lets two machines hold the same campaign under directory names
   that differ only in date: neither is authoritative, so nothing has to agree.

   The `ledgerFrame` conjunct is not proved here so much as inherited: ledger's
   own step frames its state whenever an event it does not own fires. Dropping
   that fall-through reddens this check, which is how the composition idiom
   itself is tested. */
assert MachineIndependence {
  always (Now.ev = DeleteDir implies (
    ledgerFrame
    and Claimed' = Claimed
    and CloneBehind' = CloneBehind
    and (all t: Tree | t.mach != Site.mach implies (t in Present iff t in Present'))))
}

/* Two machines hold the campaign. One deletes its own tree while work continues;
   the GitHub facts are untouched and the subtask still completes. */
/* FOR REAL -- real. Hold the campaign on two machines. Capture
   `scripts/campaign-settlement $ANCHOR > /tmp/before`. Delete the campaign
   directory on the machine with no live agent. Re-run into /tmp/after and diff.
   PASS: identical. Then continue the other machine's work to completion.

   With one machine, two campaign directories for the same anchor stand in and
   test everything this layer distinguishes -- `Machine` here is only "a holder
   of a local directory". What that stand-in does not cover is herdr liveness
   across machines, which is exactly the blind spot agent.als's S9 is about. */
pred S7_TwoMachinesOneDeletes {
  one c: Campaign | some i: c.members {
    #dirsOf[c] = 2
    mergeClosed[c.members]
    some m: Machine | eventually (Now.ev = DeleteDir and Site.mach = m and m in dirsOf[c])
    eventually complete[i]
  }
}

/* The whole campaign runs with no local directory on any machine -- the
   reconstitution claim, exercised rather than asserted. */
/* FOR REAL -- real. Drive an entire two-subtask campaign from a machine that
   never clones anything: create the subtasks, and have a delegate on another
   machine (or the repository's own web editor) push the branches.
   PASS: the listing reaches `closable` read from the machine with no directory.
   This exercises the reconstitution claim rather than asserting it -- the
   campaign plane really does live in GitHub. */
pred S15_NoLocalDirectory {
  one c: Campaign {
    always no dirsOf[c]
    #c.members = 2
    mergeClosed[c.members]
    always Now.ev not in AddMember + RemoveMember
    eventually (all i: c.members | complete[i])
    closeDiscipline[c]
    eventually (closable[c] and campaignClosed[c])
  }
}

/* --- The container as a member of its own campaign --- */

/* agent-workspace is cloned into <campaign>/repos/agent-workspace/, so one
   repository has two checkouts: the OUTER container the campaign session runs
   from, and the INNER clone the delegate works in, which the container ignores.
   That the container may be a member at all is ledger's S16a; what it costs a
   machine is here.

   FOR REAL -- real. One command reads both hazards at once, and it belongs at
   three checkpoints: before launching the delegate, immediately after merging
   its pull request, and before the campaign session next edits anything in the
   container.

     CONTAINER=$(cd "$(dirname "$(git rev-parse --path-format=absolute \
       --git-common-dir)")" && pwd -P)
     git -C "$CONTAINER" fetch origin -q
     git -C "$CONTAINER" rev-list --left-right --count origin/main...HEAD
                                                    # "<behind>  <ahead>"

   - behind > 0 is hazard 1. The delegate's pull request merged and the outer
     checkout has not caught up. Editing from here can silently revert the
     merged work. Fix with `git -C "$CONTAINER" pull --ff-only` and re-read zero
     before editing, which is what AGENTS.md says to do.
   - A clone left behind AT LAUNCH is hazard 2, and the outer checkout is the
     wrong place to read it. S17 below is that hazard on its own.
   - Hazard 3 is safe, but do not read the model as proof. Edits to
     .claude/skills/ inside the clone cannot change the running campaign,
     because the loaded copy is the outer container's. The model agrees -- but
     only because no event was written that writes the outer checkout from
     inside the clone, so it restates the assumption rather than testing it. The
     real check is one command: after editing a skill in the clone, confirm
     `git -C "$CONTAINER" status --porcelain .claude/` is still empty.

   PASS for the whole scenario: the outer checkout reads zero-zero at all three
   checkpoints, the clone reads zero behind at launch, and the delegate's
   subtask reads `complete` in scripts/campaign-settlement. Real-safe -- every
   step is a fetch, a compare, or an ordinary pull. */

/* Hazard 1, and its remedy. A pull request against the container merges; every
   outer container checkout is now behind origin/main, and only a pull clears
   it. Anyone editing from a behind checkout can silently revert the merged
   work. */
pred S16b_ContainerBehindAfterMerge {
  one c: Campaign | some i: c.members {
    i.home = Container
    always Now.ev not in AddMember + RemoveMember
    mergeClosed[c.members]
    eventually (Now.ev = MergePR and Now.issue = i)
    eventually Machine in Behind            -- every outer checkout, not just one
    eventually Now.ev = PullContainer
    eventually (no Behind and complete[i])
  }
}

/* Hazard 1 left alone. Nobody pulls, so the outer checkouts stay behind for the
   rest of the campaign with nothing saying so. */
pred S16c_BehindForever {
  one c: Campaign | some i: c.members {
    i.home = Container
    always Now.ev != PullContainer
    eventually (Now.ev = MergePR and Now.issue = i)
    eventually always Machine in Behind
  }
}

/* Hazard 2. The campaign directory is created -- the clone is cut from
   origin/main -- while the outer container holds unpushed commits. The delegate
   reads an AGENTS.md older than the one the campaign session is following, and
   obeys rules already superseded. */
pred S16d_CloneFromUnpushedContainer {
  one c: Campaign | some m: Machine {
    m not in dirsOf[c]                      -- not yet cloned here
    eventually (Now.ev = CommitLocal and Site.mach = m)
    eventually (m in Unpushed and Now.ev = CreateDir and Site.mach = m)
    eventually (m in dirsOf[c] and m in Unpushed)
  }
}

/* --- The clone that was current when cut and stale when launched --- */

/* The clone is cut from origin/main, then origin/main moves, then the delegate
   starts. Nothing reports it, and the delegate obeys an AGENTS.md this campaign
   session has already superseded.

   FOR REAL -- real. Clone agent-workspace into <campaign>/repos/, merge any
   container pull request, then read the CLONE -- not the outer checkout:

     git -C <campaign>/repos/<repo> fetch origin -q
     git -C <campaign>/repos/<repo> rev-list --left-right --count origin/main...HEAD

   PASS: the pair reads "0  0" in the same shell that then launches the
   delegate, after a `git -C <campaign>/repos/<repo> pull --ff-only` if it did
   not. Real-safe -- a fetch, a compare and an ordinary pull. */

/* The rule as it was written before a live run disproved it: never clone while
   the outer container holds commits origin lacks. */
pred pushBeforeClone { always (Now.ev = CreateDir implies no Unpushed) }

/* The rule AGENTS.md now carries: fetch and compare inside the clone, at
   launch. Stating it and then finding no behind launch restates the guard, so
   what is run below is its control, not the guard. */
pred pullCloneAtLaunch { always (Now.ev = Launch implies Site.mach not in CloneBehind) }

/* The three acts in order: the clone is cut, origin/main then moves under it,
   and the delegate starts in a clone that is behind. Ordered explicitly --
   written as three unordered `eventually`s this also reads SAT on a clone cut
   after the merge, which is not the finding. */
pred cloneThenMergeThenLaunch[c: Campaign, i: Issue, m: Machine] {
  i in c.members and i.home = Container
  eventually (Now.ev = CreateDir and Site.mach = m
    and after eventually (Now.ev = MergePR and Now.issue = i
      and after eventually (Now.ev = Launch and Site.mach = m
                            and m in CloneBehind)))
}

/* It is reachable at all: a delegate launched into a stale clone obeys an
   AGENTS.md the campaign session has already superseded, and nothing reports
   it. */
pred S17a_CloneBehindAtLaunch {
  one c: Campaign | some i: Issue, m: Machine | cloneThenMergeThenLaunch[c, i, m]
}

/* The superseded rule, enforced for the whole trace, does not stop it. This is
   the live run's finding as a model result: the container read clean
   immediately before the clone, and the remote moved between the clone and the
   launch. The rule is not wrong, it is checked in the wrong place. */
pred S17b_OldCloneRuleInsufficient {
  pushBeforeClone
  one c: Campaign | some i: Issue, m: Machine | cloneThenMergeThenLaunch[c, i, m]
}

/* Control for the adopted rule: it is not vacuous. A container pull request
   still merges mid-flight and a delegate still launches, once the clone is
   pulled first. */
pred S17c_PullBeforeLaunchAdmitsLaunch {
  pullCloneAtLaunch
  one c: Campaign | some i: Issue, m: Machine {
    i in c.members and i.home = Container
    eventually (Now.ev = CreateDir and Site.mach = m
      and after eventually (Now.ev = MergePR and Now.issue = i
        and after eventually (Now.ev = PullClone and Site.mach = m
          and after eventually (Now.ev = Launch and Site.mach = m))))
  }
}

/* ---------------- reachability floor ---------------- */

pred Cov_CreateDir     { eventually Now.ev = CreateDir }
pred Cov_DeleteDir     { eventually Now.ev = DeleteDir }
pred Cov_Acquire       { eventually Now.ev = Acquire }
pred Cov_Claim         { eventually Now.ev = Claim }
pred Cov_Release       { eventually Now.ev = Release }
pred Cov_PullContainer { eventually Now.ev = PullContainer }
pred Cov_PullClone     { eventually Now.ev = PullClone }
pred Cov_CommitLocal   { eventually Now.ev = CommitLocal }
pred Cov_Launch        { eventually Now.ev = Launch }

/* ---------------- commands ---------------- */

check MachineIndependence for 4 Issue, 3 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 6 steps

run S7_TwoMachinesOneDeletes    for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Machine, exactly 2 Repo, 1 Topic, 2 Tree, 10 steps
run S15_NoLocalDirectory        for exactly 3 Issue, 2 PR, exactly 1 Campaign, 1 Machine, exactly 3 Repo, 1 Topic, 1 Tree, 12 steps
run S16b_ContainerBehindAfterMerge  for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Machine, exactly 2 Repo, 1 Topic, 2 Tree, 12 steps
run S16c_BehindForever              for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Machine, exactly 2 Repo, 1 Topic, 2 Tree, 10 steps
run S16d_CloneFromUnpushedContainer for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Machine, exactly 2 Repo, 1 Topic, 2 Tree, 10 steps
run S17a_CloneBehindAtLaunch        for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Machine, exactly 2 Repo, 1 Topic, 1 Tree, 12 steps
run S17b_OldCloneRuleInsufficient   for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Machine, exactly 2 Repo, 1 Topic, 1 Tree, 12 steps
run S17c_PullBeforeLaunchAdmitsLaunch for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Machine, exactly 2 Repo, 1 Topic, 1 Tree, 14 steps

run Cov_CreateDir     for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps
run Cov_DeleteDir     for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps
run Cov_Acquire       for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps
run Cov_Claim         for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps
run Cov_Release       for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps
run Cov_PullContainer for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps
run Cov_PullClone     for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps
run Cov_CommitLocal   for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps
run Cov_Launch        for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps
