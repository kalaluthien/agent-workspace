/*
 * The reachability floor for directory/system's own events.
 * github/system.als is spec/'s entry point.
 */
module directory/checks

open directory/scenarios

/* ---------------- reachability floor ---------------- */

pred Cov_CreateDir     { eventually Now.ev = CreateDir }
pred Cov_DeleteDir     { eventually Now.ev = DeleteDir }
pred Cov_Acquire       { eventually Now.ev = Acquire }

/* ---------------- commands ---------------- */

-- every own event fires in some trace
run Cov_CreateDir     for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps expect 1
run Cov_DeleteDir     for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps expect 1
run Cov_Acquire       for 3 Issue, 2 PR, 2 Campaign, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 8 steps expect 1
