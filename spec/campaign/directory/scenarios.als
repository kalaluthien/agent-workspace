/*
 * The witnesses over directory/system: what a campaign directory's presence
 * and absence buy. github/system.als is spec/'s entry point.
 */
module directory/scenarios

open directory/system

/* ---------------- witnesses ---------------- */

/* Two machines hold the campaign; one deletes its own tree while work
   continues, and the sub-issue still completes. */
pred S7_TwoMachinesOneDeletes {
  one c: Campaign | some i: c.memberIssues {
    #machinesHolding[c] = 2
    mergeClosed[c.memberIssues]
    some m: Machine | eventually (Now.event = DeleteDir and Where.machine = m and m in machinesHolding[c])
    eventually complete[i]
  }
}

/* The reconstitution claim exercised rather than asserted: a whole campaign
   runs with no local directory on any machine. */
pred S15_NoLocalDirectory {
  one c: Campaign {
    always no machinesHolding[c]
    #c.memberIssues = 2
    mergeClosed[c.memberIssues]
    always Now.event not in AddMember + RemoveMember
    eventually (all i: c.memberIssues | complete[i])
    closeDiscipline[c]
    eventually (closable[c] and campaignClosed[c])
  }
}

/* ---------------- commands ---------------- */

run S7_TwoMachinesOneDeletes    for exactly 2 Issue, 1 PullRequest, exactly 1 Campaign, exactly 2 Machine, exactly 2 Repo, 1 Branch, 2 CampaignDir, 10 steps expect 1
run S15_NoLocalDirectory        for exactly 3 Issue, 2 PullRequest, exactly 1 Campaign, 1 Machine, exactly 3 Repo, 1 Branch, 1 CampaignDir, 12 steps expect 1
