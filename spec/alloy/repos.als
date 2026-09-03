/*
 * A member repository, as one machine sees it and as its remote holds it.
 * ledger.als is spec/'s entry point: the layer table and the composition idiom
 * are there.
 */
module repos

open ledger

/* ==================== SYSTEM ==================== */

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

/* A REMOTE fact, so one set over Issue rather than one set per machine: a
   claim made on one machine is visible from every other, which is the whole
   reason the branch is the claim. */
var sig Claimed in Issue {}

/* The OUTER container checkout a campaign session runs from. */
var sig Behind   in Machine {}
var sig Unpushed in Machine {}
/* The INNER clone under <campaign>/repos/agent-workspace/. A separate bit
   because the two are cleared by different acts: a clone is cut fresh from
   origin/main, which says nothing about the outer checkout it sits inside. */
var sig CloneBehind in Machine {}

one sig Site {
  var mach: lone Machine,
  var repo: lone Repo
}

fact ReposWellFormed {
  all disj x, y: Tree | x.camp != y.camp or x.mach != y.mach
  always all t: Tree, r: Repo | lone t.checkout[r]
}

/* ---------------- observable events ---------------- */

one sig CreateDir, DeleteDir, Acquire, Claim, Release,
        PullContainer, PullClone, CommitLocal, Launch extends Event {}

fun reposEvents: set Event {
  CreateDir + DeleteDir + Acquire + Claim + Release
  + PullContainer + PullClone + CommitLocal + Launch
}

/* Behind, Unpushed and CloneBehind are outside this frame on purpose: they are
   governed end to end by CheckoutFrame and CloneFrame, because the act that
   moves them most is a MergePR, an event this layer does not own. */
pred reposFrame { Present' = Present and checkout' = checkout and Claimed' = Claimed }

pred createDir[t: Tree] {
  t not in Present
  Present' = Present + t
  checkout' = checkout and Claimed' = Claimed
  Now.ev = CreateDir and no Now.issue and Site.mach = t.mach and no Site.repo
}

/* Unguarded: this layer has no agent, so "no campaign closes while an agent is
   live under its tree" cannot be stated here. agent.als's NoOrphanIfGuarded is
   that rule assumed and checked. */
pred deleteDir[t: Tree] {
  t in Present
  Present'  = Present - t
  checkout' = checkout - t->Repo->Topic
  Claimed'  = Claimed
  Now.ev = DeleteDir and no Now.issue and Site.mach = t.mach and no Site.repo
}

/* opening-campaign/scripts/acquire-repo.sh. On a re-run over an existing checkout it switches the
   branch, which is what agent.als's R4c catches it doing under a live agent. */
pred acquire[t: Tree, r: Repo, b: Topic] {
  t in Present
  t.checkout[r] != b
  checkout' = checkout - t->r->Topic + t->r->b
  Present' = Present and Claimed' = Claimed
  Now.ev = Acquire and no Now.issue and Site.mach = t.mach and Site.repo = r
}

/* Deliberately LOOSE -- it does not require the ref to be absent -- so that
   create-ref's refusal is a named discipline above (agent.als's `claimAtomic`)
   with its absence runnable as a control. */
pred claim[i: Issue] {
  i in Campaign.members and i in Open
  Claimed' = Claimed + i
  Present' = Present and checkout' = checkout
  Now.ev = Claim and Now.issue = i and no Site.mach and no Site.repo
}

/* What may be released is guarded above, in agent.als, for the reason
   `deleteDir` is unguarded here: the condition is about an executor. */
pred release[i: Issue] {
  i in Claimed
  Claimed' = Claimed - i
  Present' = Present and checkout' = checkout
  Now.ev = Release and Now.issue = i and no Site.mach and no Site.repo
}

pred pullContainer[m: Machine] {
  m in Behind
  Behind' = Behind - m and Unpushed' = Unpushed
  reposFrame
  Now.ev = PullContainer and no Now.issue and Site.mach = m and no Site.repo
}

pred pullClone[m: Machine] {
  m in CloneBehind
  Behind' = Behind and Unpushed' = Unpushed
  reposFrame
  Now.ev = PullClone and no Now.issue and Site.mach = m and no Site.repo
}

pred commitLocal[m: Machine] {
  m not in Unpushed
  Unpushed' = Unpushed + m and Behind' = Behind
  reposFrame
  Now.ev = CommitLocal and no Now.issue and Site.mach = m and no Site.repo
}

/* Here a launch is only a freshness question: WHEN the clone's distance from
   origin/main is read. The agent-state half is agent.als's disjunct on the
   same event atom, and the actor is session.als's. */
pred launch[m: Machine] {
  m in Present.mach
  Now.issue in Campaign.members
  reposFrame
  Now.ev = Launch and Site.mach = m and no Site.repo
}

/* No event writes the outer checkout from inside the clone. The model
   therefore agrees that editing .claude/skills/ in the clone cannot change the
   running campaign -- but it agrees BY CONSTRUCTION, so read it as a
   restatement of the assumption and not as evidence. */
fact CheckoutFrame {
  always ((Now.ev not in PullContainer + CommitLocal) implies
    (Unpushed' = Unpushed and
     ((Now.ev = MergePR and Now.issue.home = Container)
        implies Behind' = Machine else Behind' = Behind)))
}

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
  all t: Tree | some t.checkout implies t in Present
}

pred reposStep {
  (Now.ev = Stutter and reposFrame and no Site.mach and no Site.repo)
  or (some t: Tree | createDir[t] or deleteDir[t])
  or (some t: Tree, r: Repo, b: Topic | acquire[t,r,b])
  or (some i: Issue | claim[i] or release[i])
  or (some m: Machine | pullContainer[m] or pullClone[m] or commitLocal[m] or launch[m])
  or (Now.ev in ledgerEvents and reposFrame and no Site.mach and no Site.repo)
  /* an event declared in a layer above. It carries no machine: an executor's
     and a session's machine are each a static field, so nothing above needs to
     observe one here. */
  or (Now.ev not in Stutter + ledgerEvents + reposEvents
      and reposFrame and no Site.mach and no Site.repo)
}

fact ReposTrace { reposInit and always reposStep }

/* ==================== SCENARIOS ==================== */

/* Deleting a local directory changes no fact another machine reads. This is
   what lets the directory be optional and lets two machines hold one campaign
   under directory names differing only in date.

   The `ledgerFrame` conjunct is inherited rather than proved here, and that
   makes this check the test of the composition idiom itself: dropping the
   fall-through branch of `ledgerStep` reddens it. */
assert MachineIndependence {
  always (Now.ev = DeleteDir implies (
    ledgerFrame
    and Claimed' = Claimed
    and CloneBehind' = CloneBehind
    and (all t: Tree | t.mach != Site.mach implies (t in Present iff t in Present'))))
}

/* Two machines hold the campaign; one deletes its own tree while work
   continues, and the sub-issue still completes. */
pred S7_TwoMachinesOneDeletes {
  one c: Campaign | some i: c.members {
    #dirsOf[c] = 2
    mergeClosed[c.members]
    some m: Machine | eventually (Now.ev = DeleteDir and Site.mach = m and m in dirsOf[c])
    eventually complete[i]
  }
}

/* The reconstitution claim exercised rather than asserted: a whole campaign
   runs with no local directory on any machine. */
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

/* Hazard 1, and its remedy: a merged container pull request leaves every outer
   checkout behind origin/main, and only a pull clears it. */
pred S16b_ContainerBehindAfterMerge {
  one c: Campaign | some i: c.members {
    i.home = Container
    always Now.ev not in AddMember + RemoveMember
    mergeClosed[c.members]
    eventually (Now.ev = MergePR and Now.issue = i)
    eventually Machine in Behind
    eventually Now.ev = PullContainer
    eventually (no Behind and complete[i])
  }
}

/* Hazard 1 left alone: nobody pulls, and nothing says so. */
pred S16c_BehindForever {
  one c: Campaign | some i: c.members {
    i.home = Container
    always Now.ev != PullContainer
    eventually (Now.ev = MergePR and Now.issue = i)
    eventually always Machine in Behind
  }
}

/* Hazard 2: the clone is cut while the outer container holds unpushed commits,
   so the delegate reads instructions the campaign session has superseded. */
pred S16d_CloneFromUnpushedContainer {
  one c: Campaign | some m: Machine {
    m not in dirsOf[c]
    eventually (Now.ev = CommitLocal and Site.mach = m)
    eventually (m in Unpushed and Now.ev = CreateDir and Site.mach = m)
    eventually (m in dirsOf[c] and m in Unpushed)
  }
}

/* --- The clone that was current when cut and stale when launched --- */

/* The superseded rule: never clone while the outer container holds commits
   origin lacks. */
pred pushBeforeClone { always (Now.ev = CreateDir implies no Unpushed) }

/* The adopted rule: fetch and compare inside the clone, at launch. */
pred pullCloneAtLaunch { always (Now.ev = Launch implies Site.mach not in CloneBehind) }

/* Ordered explicitly: written as three unordered `eventually`s this also reads
   SAT on a clone cut after the merge, which is not the finding. */
pred cloneThenMergeThenLaunch[c: Campaign, i: Issue, m: Machine] {
  i in c.members and i.home = Container
  eventually (Now.ev = CreateDir and Site.mach = m
    and after eventually (Now.ev = MergePR and Now.issue = i
      and after eventually (Now.ev = Launch and Site.mach = m
                            and m in CloneBehind)))
}

/* The superseded rule, enforced for the whole trace, does not stop it: the
   container read clean immediately before the clone, and the remote moved
   between the clone and the launch. The rule is checked in the wrong place. */
pred S17b_OldCloneRuleInsufficient {
  pushBeforeClone
  one c: Campaign | some i: Issue, m: Machine | cloneThenMergeThenLaunch[c, i, m]
}

/* Control: the adopted rule is not vacuous. A container pull request still
   merges mid-flight and a delegate still launches, once the clone is pulled. */
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

-- a local delete changes no shared fact
check MachineIndependence for 4 Issue, 3 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 6 steps expect 0

run S7_TwoMachinesOneDeletes    for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Machine, exactly 2 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run S15_NoLocalDirectory        for exactly 3 Issue, 2 PR, exactly 1 Campaign, 1 Machine, exactly 3 Repo, 1 Topic, 1 Tree, 12 steps expect 1
run S16b_ContainerBehindAfterMerge  for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Machine, exactly 2 Repo, 1 Topic, 2 Tree, 12 steps expect 1
run S16c_BehindForever              for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Machine, exactly 2 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run S16d_CloneFromUnpushedContainer for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Machine, exactly 2 Repo, 1 Topic, 2 Tree, 10 steps expect 1
-- the superseded rule does not stop it
run S17b_OldCloneRuleInsufficient   for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Machine, exactly 2 Repo, 1 Topic, 1 Tree, 12 steps expect 1
-- control: the adopted rule is not vacuous
run S17c_PullBeforeLaunchAdmitsLaunch for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Machine, exactly 2 Repo, 1 Topic, 1 Tree, 14 steps expect 1

-- every own event fires in some trace
run Cov_CreateDir     for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps expect 1
run Cov_DeleteDir     for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps expect 1
run Cov_Acquire       for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps expect 1
run Cov_Claim         for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps expect 1
run Cov_Release       for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps expect 1
run Cov_PullContainer for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps expect 1
run Cov_PullClone     for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps expect 1
run Cov_CommitLocal   for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps expect 1
run Cov_Launch        for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps expect 1
