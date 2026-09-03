/*
 * The witnesses over github/system: the traces that show a story about what
 * GitHub records. github/system.als is spec/'s entry point and carries the
 * orientation.
 */
module github/scenarios

open github/system

/* ---------------- witnesses ---------------- */

/* Settlement is strictly weaker than completion at these bounds, so that
   assertion is an answer rather than a synonym. */
pred SettledWithoutMerge { eventually (some i: Campaign.members | settled[i] and no i.pr) }

/* The plain path. */
pred S1_HappyPath {
  one c: Campaign {
    #c.members = 2
    #(c.members.home) = 2
    always Now.ev not in AddMember + RemoveMember
    mergeClosed[c.members]
    eventually (all i: c.members | complete[i])
    closeDiscipline[c]
    eventually (closable[c] and campaignClosed[c])
  }
}

/* Closed as not planned, no pull request ever, and closable is still
   reached. */
pred S2_SubIssueDropped {
  one c: Campaign {
    #c.members = 2
    always Now.ev not in AddMember + RemoveMember
    some disj i1, i2: c.members {
      mergeClosed[i1]
      eventually complete[i1]
      always no i2.pr
      eventually dropped[i2]
    }
    closeDiscipline[c]
    eventually (closable[c] and campaignClosed[c])
  }
}

/* The campaign re-opens work instead of closing. */
pred S5_FollowUpAfterSettled {
  one c: Campaign {
    #c.members = 1
    mergeClosed[Issue - c.campaignIssue]
    always Now.ev != RemoveMember          -- no emptying the campaign to fake "all settled"
    some i1: c.members, i2: Issue - c.members - c.campaignIssue {
      eventually (complete[i1] and c.campaignIssue in Open
                  and Now.ev = AddMember and Now.issue = i2)
      eventually (i2 in c.members and not settled[i2])
      eventually complete[i2]
    }
    closeDiscipline[c]
    eventually (closable[c] and campaignClosed[c])
  }
}

/* The added sub-issue's home is a repository no existing member lives in. */
pred S6_RepoJoinsMidFlight {
  one c: Campaign {
    #c.members = 1
    #(c.members.home) = 1
    mergeClosed[Issue - c.campaignIssue]
    always Now.ev != RemoveMember
    eventually (Now.ev = AddMember
                and Now.issue not in c.members
                and Now.issue.home not in c.members.home)
    eventually (#c.members = 2 and #(c.members.home) = 2
                and (all i: c.members | complete[i]))
  }
}

/* Nothing guards the campaign issue's close, so a real run must report it. */
pred S8_CloseWithOpenSubIssue {
  one c: Campaign {
    #c.members = 2
    always Now.ev not in AddMember + RemoveMember
    mergeClosed[c.members]
    some disj i1, i2: c.members |
      eventually (Now.ev = CloseIssue and Now.issue = c.campaignIssue
                  and complete[i1] and i2 in Open)
    eventually (campaignClosed[c] and (some i: c.members | i in Open))
  }
}

/* The index prunes with it, which is what the sub-issue link buys over a
   back-reference: a mention cannot be un-said. */
pred S10_SubIssueMovedOut {
  one c: Campaign {
    #c.members = 2
    mergeClosed[c.members]
    always Now.ev != AddMember
    some disj i1, i2: c.members {
      always (Now.ev = RemoveMember implies Now.issue = i2)
      eventually (Now.ev = RemoveMember and Now.issue = i2)
      eventually complete[i1]
      eventually c.members = i1
    }
    always (all d: Campaign | d.members = idx[d])
    closeDiscipline[c]
    eventually (closable[c] and campaignClosed[c])
  }
}

/* A missing "Closes #N": the campaign never becomes closable and nothing
   says why. */
pred S11_MergedButIssueLeftOpen {
  one c: Campaign {
    #c.members = 1
    always Now.ev not in AddMember + RemoveMember
    some i: c.members {
      eventually (some i.pr and i.pr in Merged and i in Open)
      eventually always (i in Open)
      always not complete[i]
    }
    always not closable[c]
  }
}

/* What the campaign-<N>/ branch prefix buys. */
pred S12_TwoCampaignsOneRepo {
  #Campaign = 2
  all c: Campaign | #c.members = 1
  one r: Repo - Container | Campaign.members.home = r
  mergeClosed[Campaign.members]
  always Now.ev not in AddMember + RemoveMember
  all c: Campaign | closeDiscipline[c]
  eventually (all c: Campaign, i: c.members | complete[i])
  eventually (all c: Campaign | campaignClosed[c])
}

/* Reopened after it read complete. UNSAT, and S13a-S13c pin why rather than
   leaving it to the bounds. NOT VERIFIED AGAINST GITHUB -- `gh issue reopen`
   documents no such restriction, so if it holds it is the model, not the
   design, that needs a reopen event. */
pred S13_ReopenAfterMerge {
  one c: Campaign | some i: c.members {
    eventually complete[i]
    eventually (complete[i] and after (i in Open))
  }
}

/* S13a: completion is reachable at these bounds. S13b: a closed issue can
   reopen, via the re-add. S13c: one that ever had a pull request cannot --
   `addMember` guards on `no i.pr` and `WellFormed` never undoes a pr link,
   which is the actual blocker. */
pred S13a_ControlCompletes { some i: Campaign.members | eventually complete[i] }
pred S13b_ReopenAnyClosed  {
  some i: Issue | eventually (i not in Open and Now.ev = AddMember and Now.issue = i
                              and after (i in Open))
}
pred S13c_ReopenWithPR     { some i: Issue | eventually (some i.pr and i not in Open and after (i in Open)) }

/* Nothing in the design guards a closed campaign issue against later sub-issues. */
pred S14_FollowUpAfterClose {
  one c: Campaign {
    #c.members = 1
    mergeClosed[Issue - c.campaignIssue]
    always Now.ev != RemoveMember
    closeDiscipline[c]
    some i2: Issue - c.members - c.campaignIssue {
      eventually (campaignClosed[c] and Now.ev = AddMember and Now.issue = i2)
      eventually (campaignClosed[c] and i2 in c.members and i2 in Open and not settled[i2])
    }
  }
}

/* Under the narrow reading the container cannot be a member of its own
   campaign at all: the model forbade what was about to happen for real. */
pred S16a_ContainerMemberUnderNarrowReading {
  containerIsCampaignIssueOnly
  some c: Campaign, i: c.members | i.home = Container
}

/* The tracker's third kind. It was UNSAT at any bound while
   `containerIssuesAreCampaignIssues` was a fact, and no verdict said so. */
pred S18_PlainContainerIssue {
  some i: Issue | i.home = Container and always (i not in Campaign.campaignIssue + Campaign.members)
}

/* Why the clause is kept rather than deleted: as a predicate it still says
   exactly what it said as a fact. */
pred S18a_PlainContainerIssueUnderClosedWorld {
  containerIssuesAreCampaignIssues and S18_PlainContainerIssue
}

/* ---------------- commands ---------------- */

-- control: settlement is weaker
run SettledWithoutMerge  for 4 Issue, 3 PR, 2 Campaign, 3 Repo, 6 steps expect 1

run S1_HappyPath                for exactly 3 Issue, 2 PR, exactly 1 Campaign, exactly 3 Repo, 12 steps expect 1
run S2_SubIssueDropped           for exactly 3 Issue, 2 PR, exactly 1 Campaign, exactly 3 Repo, 12 steps expect 1
run S5_FollowUpAfterSettled     for exactly 3 Issue, 2 PR, exactly 1 Campaign, exactly 2 Repo, 14 steps expect 1
run S6_RepoJoinsMidFlight       for exactly 3 Issue, 2 PR, exactly 1 Campaign, exactly 3 Repo, 14 steps expect 1
run S8_CloseWithOpenSubIssue     for exactly 3 Issue, 2 PR, exactly 1 Campaign, exactly 3 Repo, 12 steps expect 1
run S10_SubIssueMovedOut         for exactly 3 Issue, 2 PR, exactly 1 Campaign, exactly 3 Repo, 12 steps expect 1
run S11_MergedButIssueLeftOpen  for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Repo, 8 steps expect 1
run S12_TwoCampaignsOneRepo     for exactly 4 Issue, 2 PR, exactly 2 Campaign, exactly 2 Repo, 14 steps expect 1
-- the finding: no reopen after a PR
run S13_ReopenAfterMerge        for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Repo, 10 steps expect 0
run S13a_ControlCompletes       for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Repo, 10 steps expect 1
run S13b_ReopenAnyClosed        for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Repo, 10 steps expect 1
-- the actual blocker
run S13c_ReopenWithPR           for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Repo, 10 steps expect 0
run S14_FollowUpAfterClose      for exactly 3 Issue, 2 PR, exactly 1 Campaign, exactly 2 Repo, 14 steps expect 1
-- the narrow reading forbade it
run S16a_ContainerMemberUnderNarrowReading for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Repo, 6 steps expect 0
-- the tracker's third kind exists
run S18_PlainContainerIssue              for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Repo, 6 steps expect 1
-- control: the clause bites
run S18a_PlainContainerIssueUnderClosedWorld for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Repo, 6 steps expect 0
