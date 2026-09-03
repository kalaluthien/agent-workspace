/*
 * What must hold of checkout/system, and the floor for its own events.
 * github/system.als is spec/'s entry point.
 */
module checkout/checks

open checkout/scenarios

/* ---------------- properties ---------------- */

/* Deleting a local directory changes no fact another machine reads. This is
   what lets the directory be optional and lets two machines hold one campaign
   under directory names differing only in date.

   The `githubFrame` conjunct is inherited rather than proved here, and that
   makes this check the test of the composition idiom itself: dropping the
   fall-through branch of `githubStep` reddens it. */
assert MachineIndependence {
  always (Now.ev = DeleteDir implies (
    githubFrame
    and Claimed' = Claimed
    and CloneBehind' = CloneBehind
    and (all t: Tree | t.mach != Site.mach implies (t in Present iff t in Present'))))
}

/* ---------------- reachability floor ---------------- */

pred Cov_PullContainer { eventually Now.ev = PullContainer }
pred Cov_PullClone     { eventually Now.ev = PullClone }
pred Cov_CommitLocal   { eventually Now.ev = CommitLocal }
pred Cov_Launch        { eventually Now.ev = Launch }

/* ---------------- commands ---------------- */

-- a local delete changes no shared fact
check MachineIndependence for 4 Issue, 3 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 6 steps expect 0

-- every own event fires in some trace
run Cov_PullContainer for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps expect 1
run Cov_PullClone     for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps expect 1
run Cov_CommitLocal   for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps expect 1
run Cov_Launch        for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps expect 1
