/*
 * The container's two checkouts on a machine, and how far behind each is: the
 * OUTER one a campaign session runs from, and the INNER clone under
 * `<campaign>/repos/agent-workspace/` a delegate is launched in.
 * github/system.als is spec/'s entry point.
 *
 * They are two bits because they are cleared by different acts: a clone is cut
 * fresh from origin/main, which says nothing about the outer checkout it sits
 * inside. It opens directory/system because a clone lives in a campaign
 * directory and a launch happens in one.
 */
module checkout/system

open directory/system

/* The OUTER container checkout a campaign session runs from. */
var sig Behind   in Machine {}
var sig Unpushed in Machine {}
/* The INNER clone under <campaign>/repos/agent-workspace/. A separate bit
   because the two are cleared by different acts: a clone is cut fresh from
   origin/main, which says nothing about the outer checkout it sits inside. */
var sig CloneBehind in Machine {}

/* ---------------- observable events ---------------- */

one sig PullContainer, PullClone, CommitLocal, Launch extends Event {}

fun checkoutEvents: set Event {
  PullContainer + PullClone + CommitLocal + Launch
}

/* This entity writes no frame predicate. Behind, Unpushed and CloneBehind are
   governed end to end by CheckoutFrame and CloneFrame below, because the act
   that moves them most is a MergePR, an event this entity does not own -- so
   there is nothing left for a step branch to frame, and the branches carry
   only the observer constraint. */

pred pullContainer[m: Machine] {
  m in Behind
  Behind' = Behind - m and Unpushed' = Unpushed
  Now.ev = PullContainer and no Now.issue and Site.mach = m and no Site.repo
}

pred pullClone[m: Machine] {
  m in CloneBehind
  Behind' = Behind and Unpushed' = Unpushed
  Now.ev = PullClone and no Now.issue and Site.mach = m and no Site.repo
}

pred commitLocal[m: Machine] {
  m not in Unpushed
  Unpushed' = Unpushed + m and Behind' = Behind
  Now.ev = CommitLocal and no Now.issue and Site.mach = m and no Site.repo
}

/* Here a launch is only a freshness question: WHEN the clone's distance from
   origin/main is read. The role-state half is role/system.als's disjunct on
   the same event atom, and the actor is session/system.als's. */
pred launch[m: Machine] {
  m in Present.mach
  Now.issue in Campaign.members
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

pred checkoutInit {
  no Behind and no Unpushed and no CloneBehind
}

pred checkoutStep {
  (Now.ev = Stutter and no Site.mach and no Site.repo)
  or (some m: Machine | pullContainer[m] or pullClone[m] or commitLocal[m] or launch[m])
  /* An event of an entity below: those set `Site` themselves where they touch
     a machine, and this entity has no state a branch could frame. */
  or (Now.ev in githubEvents + directoryEvents)
  /* An event declared in an entity above. This is the last entity that can see
     `Site`'s owner and every event below it, so it is where the observer is
     pinned to none for everything higher. */
  or (Now.ev not in Stutter + githubEvents + directoryEvents + checkoutEvents
      and no Site.mach and no Site.repo)
}

fact CheckoutTrace { checkoutInit and always checkoutStep }
