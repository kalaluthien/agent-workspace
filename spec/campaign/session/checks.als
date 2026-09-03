/*
 * The reachability floor for session/system: its own events, and every
 * refinement it adds to a lower entity's event. github/system.als is spec/'s
 * entry point.
 */
module session/checks

open session/scenarios

/* ---------------- reachability floor ----------------
 * The four events this layer introduces, and every refinement it adds to a
 * lower layer's event. A refinement that cannot be satisfied would make its
 * event unreachable from here upward while the lower layer's own floor stayed
 * green. `Cov_Bound` pins `FileCampaignIssue` rather than reading `some
 * Binding.bound`, which `init` alone satisfies at step 0.
 */
pred Cov_Survey            { eventually Now.ev = Survey }
pred Cov_Adopt             { eventually Now.ev = Adopt }
pred Cov_ReadBody          { eventually Now.ev = ReadBody }
pred Cov_EditReadme        { eventually Now.ev = EditReadme }
pred Cov_Sync              { eventually (Now.ev = WriteBody and some By.actor) }
pred Cov_CloseCampaignIssue       { eventually (Now.ev = CloseIssue and Now.issue in Campaign.campaignIssue) }
pred Cov_FiledBySession    { eventually (Now.ev = FileCampaignIssue and some By.actor) }
pred Cov_MemberBySession   { eventually (Now.ev = AddMember and some By.actor) }
pred Cov_DirBySession      { eventually (Now.ev = CreateDir and some By.actor) }
pred Cov_DeleteBySession   { eventually (Now.ev = DeleteDir and some By.actor) }
pred Cov_AcquireBySession  { eventually (Now.ev = Acquire and some By.actor) }
pred Cov_ClaimBySession    { eventually (Now.ev = Claim and some By.actor) }
pred Cov_ReleaseBySession  { eventually (Now.ev = Release and some By.actor) }
pred Cov_LaunchBySession   { eventually (Now.ev = Launch and some By.actor) }
pred Cov_MergeBySession    { eventually (Now.ev = MergePR and some By.actor) }
pred Cov_Bound             { eventually (Now.ev = FileCampaignIssue and some Binding.bound') }

/* ---------------- commands ---------------- */

-- every own event and every refinement this layer adds fires in some trace
run Cov_Survey            for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_Adopt             for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_ReadBody          for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_EditReadme        for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_Sync              for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_CloseCampaignIssue       for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_FiledBySession    for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_MemberBySession   for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_DirBySession      for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_DeleteBySession   for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_AcquireBySession  for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_ClaimBySession    for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_ReleaseBySession  for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_LaunchBySession   for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_MergeBySession    for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
run Cov_Bound             for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 2 Topic, 4 Tree, 12 steps expect 1
