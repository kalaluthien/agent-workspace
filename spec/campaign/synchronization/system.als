/*
 * How far behind origin a machine's two base checkouts are: the OUTER one
 * a campaign session runs from, and the INNER clone under
 * `<campaign>/repos/campaign-base/` a delegate is launched in. It opens
 * directory/system because a clone lives in a campaign directory and a launch
 * happens in one.
 *
 *   BaseBehind    machines whose outer checkout is behind origin/main.
 *   BaseUnpushed  machines whose outer checkout holds commits origin lacks.
 *   CloneBehind        machines whose inner clone is behind origin/main.
 *
 * The outer checkout and the inner clone are two bits and not one because they
 * are cleared by different acts: a clone is cut fresh from origin/main, which
 * says nothing about the outer checkout it sits inside.
 *
 * This entity declares no signature of its own. It adds three subsets of the
 * entity below's Machine, four events, and the two facts that govern all three
 * subsets end to end.
 */
module synchronization/system

open directory/system

/* The OUTER base checkout a campaign session runs from. */
var sig BaseBehind   in Machine {}
var sig BaseUnpushed in Machine {}
/* The INNER clone under <campaign>/repos/campaign-base/. A separate bit
   because the two are cleared by different acts: a clone is cut fresh from
   origin/main, which says nothing about the outer checkout it sits inside. */
var sig CloneBehind in Machine {}

/* ---------------- observable events ---------------- */

one sig PullBase, PullClone, CommitLocal, Launch extends Event {}

fun synchronizationEvents: set Event {
  PullBase + PullClone + CommitLocal + Launch
}

/* This entity writes no frame predicate. BaseBehind, BaseUnpushed
   and CloneBehind are governed end to end by BaseCheckoutFrame and
   CloneCheckoutFrame below, because the act that moves them most is a
   MergePullRequest, an event this entity does not own -- so there is nothing
   left for a step branch to frame, and the branches carry only the observer
   constraint. */

pred pullBase[m: Machine] {
  m in BaseBehind
  BaseBehind' = BaseBehind - m and BaseUnpushed' = BaseUnpushed
  Now.event = PullBase and no Now.issue and Where.machine = m and no Where.repo
}

pred pullClone[m: Machine] {
  m in CloneBehind
  BaseBehind' = BaseBehind and BaseUnpushed' = BaseUnpushed
  Now.event = PullClone and no Now.issue and Where.machine = m and no Where.repo
}

/* `Now.issue` is left free here: a commit by an agent names its task, and
   orchestration/system.als's `agentCommitLocal` pins it, which is what lets a
   discipline over a commit be stated at all; a commit by nobody's agent -- a
   person at a terminal -- names none. */
pred commitLocal[m: Machine] {
  m not in BaseUnpushed
  BaseUnpushed' = BaseUnpushed + m and BaseBehind' = BaseBehind
  Now.event = CommitLocal and Where.machine = m and no Where.repo
}

/* Here a launch is only a freshness question: WHEN the clone's distance from
   origin/main is read. The role-state half is orchestration/system.als's disjunct on
   the same event atom, and the session is session/system.als's. */
pred launch[m: Machine] {
  m in OnDisk.machine
  Now.issue in Campaign.memberIssues
  Now.event = Launch and Where.machine = m and no Where.repo
}

/* No event writes the outer checkout from inside the clone. The model
   therefore agrees that editing .claude/skills/ in the clone cannot change the
   running campaign -- but it agrees BY CONSTRUCTION, so read it as a
   restatement of the assumption and not as evidence. */
fact BaseCheckoutFrame {
  always ((Now.event not in PullBase + CommitLocal) implies
    (BaseUnpushed' = BaseUnpushed and
     ((Now.event = MergePullRequest and Now.issue.repo = Base)
        implies BaseBehind' = Machine else BaseBehind' = BaseBehind)))
}

fact CloneCheckoutFrame {
  always ((Now.event = MergePullRequest and Now.issue.repo = Base)
    implies CloneBehind' = CloneBehind + OnDisk.machine
    else ((Now.event in CreateDir + PullClone)
      implies CloneBehind' = CloneBehind - Where.machine
      else CloneBehind' = CloneBehind))
}

pred synchronizationInit {
  no BaseBehind and no BaseUnpushed and no CloneBehind
}

pred synchronizationStep {
  (Now.event = Stutter and no Where.machine and no Where.repo)
  or (some m: Machine | pullBase[m] or pullClone[m] or commitLocal[m] or launch[m])
  /* An event of an entity below: those set `Where` themselves where they touch
     a machine, and this entity has no state a branch could frame. */
  or (Now.event in githubEvents + directoryEvents)
  /* An event declared in an entity above. This is the last entity that can see
     `Where`'s owner and every event below it, so it is where the observer is
     pinned to none for everything higher. */
  or (Now.event not in Stutter + githubEvents + directoryEvents + synchronizationEvents
      and no Where.machine and no Where.repo)
}

fact SynchronizationTrace { synchronizationInit and always synchronizationStep }
