/*
 * The witnesses over synchronization/system: a base pull request landing under
 * an outer checkout and under a clone. github/system.als is spec/'s entry
 * point.
 */
module synchronization/scenarios

open synchronization/system

/* ---------------- witnesses ---------------- */

/* --- The base as a member of its own campaign --- */

/* Hazard 1, and its remedy: a merged base pull request leaves every outer
   checkout behind origin/main, and only a pull clears it. */
pred S16b_BaseBehindAfterMerge {
  one c: Campaign | some i: c.memberIssues {
    i.repo = Base
    always Now.event not in AddMember + RemoveMember
    mergeClosed[c.memberIssues]
    eventually (Now.event = MergePullRequest and Now.issue = i)
    eventually Machine in BaseBehind
    eventually Now.event = PullBase
    eventually (no BaseBehind and complete[i])
  }
}

/* Hazard 1 left alone: nobody pulls, and nothing says so. */
pred S16c_BehindForever {
  one c: Campaign | some i: c.memberIssues {
    i.repo = Base
    always Now.event != PullBase
    eventually (Now.event = MergePullRequest and Now.issue = i)
    eventually always Machine in BaseBehind
  }
}

/* Hazard 2: the clone is cut while the outer base holds unpushed commits,
   so the delegate reads instructions the campaign session has superseded. */
pred S16d_CloneFromUnpushedBase {
  one c: Campaign | some m: Machine {
    m not in machinesHolding[c]
    eventually (Now.event = CommitLocal and Where.machine = m)
    eventually (m in BaseUnpushed and Now.event = CreateDir and Where.machine = m)
    eventually (m in machinesHolding[c] and m in BaseUnpushed)
  }
}

/* --- The clone that was current when cut and stale when launched --- */

/* The superseded rule: never clone while the outer base holds commits
   origin lacks. */
pred pushBeforeClone { always (Now.event = CreateDir implies no BaseUnpushed) }

/* The adopted rule: fetch and compare inside the clone, at launch. */
pred pullCloneAtLaunch { always (Now.event = Launch implies Where.machine not in CloneBehind) }

/* Ordered explicitly: written as three unordered `eventually`s this also reads
   SAT on a clone cut after the merge, which is not the finding. */
pred cloneThenMergeThenLaunch[c: Campaign, i: Issue, m: Machine] {
  i in c.memberIssues and i.repo = Base
  eventually (Now.event = CreateDir and Where.machine = m
    and after eventually (Now.event = MergePullRequest and Now.issue = i
      and after eventually (Now.event = Launch and Where.machine = m
                            and m in CloneBehind)))
}

/* The superseded rule, enforced for the whole trace, does not stop it: the
   base read clean immediately before the clone, and the remote moved
   between the clone and the launch. The rule is checked in the wrong place. */
pred S17b_OldCloneRuleInsufficient {
  pushBeforeClone
  one c: Campaign | some i: Issue, m: Machine | cloneThenMergeThenLaunch[c, i, m]
}

/* Control: the adopted rule is not vacuous. A base pull request still
   merges mid-flight and a delegate still launches, once the clone is pulled. */
pred S17c_PullBeforeLaunchAdmitsLaunch {
  pullCloneAtLaunch
  one c: Campaign | some i: Issue, m: Machine {
    i in c.memberIssues and i.repo = Base
    eventually (Now.event = CreateDir and Where.machine = m
      and after eventually (Now.event = MergePullRequest and Now.issue = i
        and after eventually (Now.event = PullClone and Where.machine = m
          and after eventually (Now.event = Launch and Where.machine = m))))
  }
}

/* ---------------- commands ---------------- */

run S16b_BaseBehindAfterMerge  for exactly 2 Issue, 1 PullRequest, exactly 1 Campaign, exactly 2 Machine, exactly 2 Repo, 1 Branch, 2 CampaignDir, 12 steps expect 1
run S16c_BehindForever              for exactly 2 Issue, 1 PullRequest, exactly 1 Campaign, exactly 2 Machine, exactly 2 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
run S16d_CloneFromUnpushedBase for exactly 2 Issue, 1 PullRequest, exactly 1 Campaign, exactly 2 Machine, exactly 2 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
-- the superseded rule does not stop it
run S17b_OldCloneRuleInsufficient   for exactly 2 Issue, 1 PullRequest, exactly 1 Campaign, exactly 1 Machine, exactly 2 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
-- control: the adopted rule is not vacuous
run S17c_PullBeforeLaunchAdmitsLaunch for exactly 2 Issue, 1 PullRequest, exactly 1 Campaign, exactly 1 Machine, exactly 2 Repo, 1 Branch, 1 CampaignDir, 14 steps expect 1
