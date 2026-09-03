/*
 * What must hold of github/system, and the floor that says its events are
 * reachable at all. github/system.als is spec/'s entry point.
 */
module github/checks

open github/scenarios

/* ---------------- properties ---------------- */

// X. The cheaper reading -- "the issue is closed" -- is not completion.
assert ClosedImpliesComplete {
  always all c: Campaign, i: c.members | i not in Open implies complete[i]
}

/* Neither missing a member nor holding a stale one. Dropping `addMember`'s
   sub-issue write reddens it, and so does any index that is a second write. */
assert IndexExact { always all c: Campaign | c.members = idx[c] }

/* From the campaign issue alone, member repositories and open sub-issues are
   recoverable. */
assert Reconstitution {
  always all c: Campaign |
    c.members.home = idx[c].home and (c.members & Open) = (idx[c] & Open)
}

/* Weak fairness: whenever some progress event is enabled on a member issue,
   one eventually fires. It says nothing when nothing is enabled. */
pred progressEnabled {
  some i: Campaign.members |
    (i in Open and no i.pr)
    or (some i.pr and i.pr not in Merged)
    or i in Open
}
pred weakFairness { always (progressEnabled implies eventually Now.ev in OpenPR + MergePR + CloseIssue) }

/* `init` also admits the empty world a campaign issue is filed from, where the
   conclusion is vacuously true at time zero. */
pred hasWork { some Campaign.members }

/* This counterexample changed the design: a member closed without a merged
   pull request never reads complete, so the campaign never becomes closable. */
assert TerminationUnderFairness {
  (hasWork
   and (eventually always Now.ev != AddMember)
   and weakFairness)
  implies (eventually all c: Campaign, i: c.members | complete[i])
}

// PASS. Under fairness AND an issue closed only by a merged pull request.
assert TerminationDisciplined {
  (hasWork
   and (eventually always Now.ev != AddMember)
   and (always (Now.ev = CloseIssue implies (some Now.issue.pr and Now.issue.pr in Merged)))
   and (always Now.ev != RemoveMember)
   and weakFairness)
  implies (eventually all c: Campaign, i: c.members | complete[i])
}

/* The repair: read settlement both ways and the same traces terminate.
   Dropping `weakFairness` reddens it. */
assert TerminationUnderSettlement {
  (hasWork
   and (eventually always Now.ev != AddMember)
   and weakFairness)
  implies (eventually all c: Campaign, i: c.members | settled[i])
}

/* ---------------- reachability floor ----------------
 * An event no trace can reach silently removes a whole question from the
 * commands above, and an over-tight frame is the cheapest way to cause it
 * without any command turning red.
 */
pred Cov_FileCampaignIssue   { eventually Now.ev = FileCampaignIssue }
pred Cov_AddMember    { eventually Now.ev = AddMember }
pred Cov_RemoveMember { eventually Now.ev = RemoveMember }
pred Cov_OpenPR       { eventually Now.ev = OpenPR }
pred Cov_MergePR      { eventually Now.ev = MergePR }
pred Cov_CloseIssue   { eventually Now.ev = CloseIssue }
pred Cov_WriteBody    { eventually Now.ev = WriteBody }
pred Cov_Claim        { eventually Now.ev = Claim }
pred Cov_Release      { eventually Now.ev = Release }

/* ---------------- commands ---------------- */

-- closed is not completed
check ClosedImpliesComplete      for 4 Issue, 3 PR, 2 Campaign, 3 Repo, 6 steps expect 1
-- the index is exactly the membership
check IndexExact                 for 4 Issue, 3 PR, 2 Campaign, 3 Repo, 6 steps expect 0
-- the campaign issue alone recovers the campaign
check Reconstitution             for 4 Issue, 3 PR, 2 Campaign, 3 Repo, 6 steps expect 0
-- closed-and-merged cannot say "dropped"
check TerminationUnderFairness     for 3 Issue, 2 PR, 1 Campaign, 2 Repo, 10 steps expect 1
check TerminationDisciplined       for 3 Issue, 2 PR, 1 Campaign, 2 Repo, 10 steps expect 0
-- the reading AGENTS.md adopted
check TerminationUnderSettlement   for 3 Issue, 2 PR, 1 Campaign, 2 Repo, 10 steps expect 0

-- every own event fires in some trace
run Cov_FileCampaignIssue   for 4 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps expect 1
run Cov_AddMember    for 4 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps expect 1
run Cov_RemoveMember for 4 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps expect 1
run Cov_OpenPR       for 4 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps expect 1
run Cov_MergePR      for 4 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps expect 1
run Cov_CloseIssue   for 4 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps expect 1
run Cov_WriteBody    for 4 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps expect 1
run Cov_Claim         for 3 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps expect 1
run Cov_Release       for 3 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps expect 1
