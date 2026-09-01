/*
 * A member repository, as one machine sees it and its remote holds it --
 * everything a machine holds about a campaign, plus the one remote fact: the
 * branch that is the subtask's claim. Knows nothing of who is at the keyboard
 * (session.als) or a delegate (agent.als); ledger.als is spec/'s entry point.
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
 * `Launch` is the cross-layer event this file starts (WHEN the clone's
 * distance is read; agent.als adds the agent-state half, session.als the
 * actor). `Claimed` is a REMOTE fact -- one set of issues, not per-machine.
 *
 * VERDICTS
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
 */
module repos

open ledger

sig Machine {}
sig Topic {}                    -- the <topic> half of a campaign-<N>/<issue>-<topic> branch

-- <slug>-<YYMMDD>/: keyed by an atom, not a pair of columns -- Kodkod cannot represent the five-ary relation past ~70 atoms
sig Tree {
  camp:   one Campaign,
  mach:   one Machine,
  var co: Repo -> Topic         -- branch checked out in <campaign>/repos/<repo>
}
var sig Present in Tree {}      -- the directory exists on that machine

fun treesOf[c: Campaign]: set Tree     { camp.c }
fun treeAt[c: Campaign, m: Machine]: lone Tree { camp.c & mach.m }
fun dirsOf[c: Campaign]: set Machine   { (Present & camp.c).mach }

-- THE CLAIM: created by create-ref, which refuses an existing ref server-side, so the claim is atomic where a survey-then-file is not
var sig Claimed in Issue {}

var sig Behind   in Machine {}  -- the OUTER checkout (session runs here) is behind origin/main
var sig Unpushed in Machine {}  -- the outer checkout holds commits origin lacks
var sig CloneBehind in Machine {} -- the INNER clone's own distance (a delegate runs here), cleared by a fresh cut

one sig Site {                  -- this layer's observer: which machine, which repository
  var mach: lone Machine,
  var repo: lone Repo
}

fact ReposWellFormed {
  -- a tree is identified by its campaign and its machine
  all disj x, y: Tree | x.camp != y.camp or x.mach != y.mach
  always all t: Tree, r: Repo | lone t.co[r]
}

one sig CreateDir, DeleteDir, Acquire, Claim, Release,
        PullContainer, PullClone, CommitLocal, Launch extends Event {}

fun reposEvents: set Event {
  CreateDir + DeleteDir + Acquire + Claim + Release
  + PullContainer + PullClone + CommitLocal + Launch
}

-- Behind, Unpushed, CloneBehind are NOT in this frame: CheckoutFrame and CloneFrame govern them, moved mainly by MergePR, an event this layer does not own
pred reposFrame { Present' = Present and co' = co and Claimed' = Claimed }

pred createDir[t: Tree] {
  t not in Present
  Present' = Present + t
  co' = co and Claimed' = Claimed
  Now.ev = CreateDir and no Now.issue and Site.mach = t.mach and no Site.repo
}

pred deleteDir[t: Tree] {  -- a discipline, not a guard: this layer has no agent to check it against
  t in Present
  Present' = Present - t
  co'      = co - t->Repo->Topic
  Claimed' = Claimed
  Now.ev = DeleteDir and no Now.issue and Site.mach = t.mach and no Site.repo
}

-- only clone is implemented; this predicate is the seam -- what acquire DOES to the checkout, not how
pred acquire[t: Tree, r: Repo, b: Topic] {
  t in Present
  t.co[r] != b
  co' = co - t->r->Topic + t->r->b
  Present' = Present and Claimed' = Claimed
  Now.ev = Acquire and no Now.issue and Site.mach = t.mach and Site.repo = r
}

pred claim[i: Issue] {  -- deliberately LOOSE: atomicity is a named discipline below, not required here
  i in Campaign.members and i in Open
  Claimed' = Claimed + i
  Present' = Present and co' = co
  Now.ev = Claim and Now.issue = i and no Site.mach and no Site.repo
}

pred release[i: Issue] {  -- delete the branch of an executor that never pushed; guarded in agent.als
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

pred launch[m: Machine] {  -- moves nothing; this layer only asks WHEN the freshness check happens
  m in Present.mach
  Now.issue in Campaign.members
  reposFrame
  Now.ev = Launch and Site.mach = m and no Site.repo
}

-- no event here writes the outer checkout from inside the clone -- hazard 3 below is safe by construction, not proof
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
  -- a checkout only exists where a directory does
  all t: Tree | some t.co implies t in Present
}

pred reposStep {
  (Now.ev = Stutter and reposFrame and no Site.mach and no Site.repo)
  or (some t: Tree | createDir[t] or deleteDir[t])
  or (some t: Tree, r: Repo, b: Topic | acquire[t,r,b])
  or (some i: Issue | claim[i] or release[i])
  or (some m: Machine | pullContainer[m] or pullClone[m] or commitLocal[m] or launch[m])
  -- the last two arms are events this layer does not own -- ledger's, or a layer above's -- standing still and carrying no machine
  or (Now.ev in ledgerEvents and reposFrame and no Site.mach and no Site.repo)
  or (Now.ev not in Stutter + ledgerEvents + reposEvents
      and reposFrame and no Site.mach and no Site.repo)
}

fact ReposTrace { reposInit and always reposStep }

-- PASS: deleting a local directory changes no fact another machine reads, so the directory is optional (ledgerFrame tests the composition idiom itself)
assert MachineIndependence {
  always (Now.ev = DeleteDir implies (
    ledgerFrame
    and Claimed' = Claimed
    and CloneBehind' = CloneBehind
    and (all t: Tree | t.mach != Site.mach implies (t in Present iff t in Present'))))
}

-- one of two machines deletes its own tree while work continues and completes; herdr liveness across machines is agent.als's S9
pred S7_TwoMachinesOneDeletes {
  one c: Campaign | some i: c.members {
    #dirsOf[c] = 2
    mergeClosed[c.members]
    some m: Machine | eventually (Now.ev = DeleteDir and Site.mach = m and m in dirsOf[c])
    eventually complete[i]
  }
}

-- the reconstitution claim, exercised: the campaign plane lives in GitHub, not a directory
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

-- THE CONTAINER AS ITS OWN CAMPAIGN'S MEMBER, three hazards: (1) an outer checkout left behind after a merge; (2) a clone gone stale before launch (S17 below); (3) an edit inside the clone that cannot reach the running campaign
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

pred S16c_BehindForever {
  one c: Campaign | some i: c.members {
    i.home = Container
    always Now.ev != PullContainer
    eventually (Now.ev = MergePR and Now.issue = i)
    eventually always Machine in Behind
  }
}

pred S16d_CloneFromUnpushedContainer {
  one c: Campaign | some m: Machine {
    m not in dirsOf[c]                      -- not yet cloned here
    eventually (Now.ev = CommitLocal and Site.mach = m)
    eventually (m in Unpushed and Now.ev = CreateDir and Site.mach = m)
    eventually (m in dirsOf[c] and m in Unpushed)
  }
}

-- THE CLONE STALE AT LAUNCH: cut, origin moves, then launch reads it, unreported. Old rule: never clone while the outer container holds commits origin lacks
pred pushBeforeClone { always (Now.ev = CreateDir implies no Unpushed) }

-- adopted rule: fetch and compare inside the clone, at launch
pred pullCloneAtLaunch { always (Now.ev = Launch implies Site.mach not in CloneBehind) }

-- cut, merge, launch, in explicit order -- unordered `eventually`s would also admit a clone cut after the merge
pred cloneThenMergeThenLaunch[c: Campaign, i: Issue, m: Machine] {
  i in c.members and i.home = Container
  eventually (Now.ev = CreateDir and Site.mach = m
    and after eventually (Now.ev = MergePR and Now.issue = i
      and after eventually (Now.ev = Launch and Site.mach = m
                            and m in CloneBehind)))
}

-- reachable at all: a delegate can launch into a stale clone, unreported
pred S17a_CloneBehindAtLaunch {
  one c: Campaign | some i: Issue, m: Machine | cloneThenMergeThenLaunch[c, i, m]
}

-- the old rule, enforced for the whole trace, does not stop it: checked in the wrong place, not wrong
pred S17b_OldCloneRuleInsufficient {
  pushBeforeClone
  one c: Campaign | some i: Issue, m: Machine | cloneThenMergeThenLaunch[c, i, m]
}

-- control: the adopted rule is not vacuous
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
