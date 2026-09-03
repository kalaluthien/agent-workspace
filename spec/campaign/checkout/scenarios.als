/*
 * The witnesses over checkout/system: a container pull request landing under
 * an outer checkout and under a clone. github/system.als is spec/'s entry
 * point.
 */
module checkout/scenarios

open checkout/system

/* ---------------- witnesses ---------------- */

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

/* ---------------- commands ---------------- */

run S16b_ContainerBehindAfterMerge  for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Machine, exactly 2 Repo, 1 Topic, 2 Tree, 12 steps expect 1
run S16c_BehindForever              for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Machine, exactly 2 Repo, 1 Topic, 2 Tree, 10 steps expect 1
run S16d_CloneFromUnpushedContainer for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Machine, exactly 2 Repo, 1 Topic, 2 Tree, 10 steps expect 1
-- the superseded rule does not stop it
run S17b_OldCloneRuleInsufficient   for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Machine, exactly 2 Repo, 1 Topic, 1 Tree, 12 steps expect 1
-- control: the adopted rule is not vacuous
run S17c_PullBeforeLaunchAdmitsLaunch for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Machine, exactly 2 Repo, 1 Topic, 1 Tree, 14 steps expect 1
