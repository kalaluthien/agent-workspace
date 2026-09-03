/*
 * The disciplines a campaign session might follow, and the witnesses that
 * measure each. github/system.als is spec/'s entry point.
 */
module session/scenarios

open session/system

/* ---------------- disciplines: candidate repairs ---------------- */

/* Compare-then-write, THE guard the design adopted. Emptying it -- the
   discipline present but comparing nothing -- brings the loss back, so R1c's
   green is the comparison and not the shape of the scenario. */
pred syncCAS { always (Now.ev = WriteBody implies By.actor.holds.body = By.actor.bodyAsRead) }

/* The rejected candidate, modelled as "sync only when every sub-issue is
   settled". R1e is what it costs. */
pred syncAtCloseOnly {
  always (Now.ev = WriteBody implies (all i: By.actor.holds.members | settled[i]))
}

/* A rule about WHEN, where compare-then-write is a rule about HOW, so the two
   are not alternatives: R1j measures that, R1k is what it beats
   `syncAtCloseOnly` by. */
pred syncAtTwoMoments {
  always (Now.ev = WriteBody implies
            (some By.actor.readme - By.actor.holds.body        -- a scope change
             or (all i: By.actor.holds.members | settled[i]))) -- or the close
}

/* R1p is why the membership rule is not enough by itself. */
pred boundOnly {
  always (Now.ev = Adopt implies Binding.bound[By.actor.holds'] = By.actor.smach)
  always (Now.ev in WriteBody + CreateDir + DeleteDir implies
            Binding.bound[By.actor.holds] = By.actor.smach)
  always ((Now.ev = CloseIssue and Now.issue in Campaign.campaignIssue) implies
            Binding.bound[campaignIssueOf[Now.issue]] = By.actor.smach)
  /* The claim and the launch: `campaign-claim take` reads the binding before
     it cuts a ref, so the claim is mechanically gated; the launch is gated by
     AGENTS.md § The binding as a rule, stated here so the model and the prose
     name the same set. */
  always (Now.ev in Claim + Launch implies
            Binding.bound[By.actor.holds] = By.actor.smach)
}

/* NARROWS the window rather than closing it: read and create are not atomic,
   and this model has no clock. */
pred surveyAtFile {
  always (Now.ev = FileCampaignIssue implies
            (no c: Campaign | c in Filed and c.campaignIssue in Open and c in Req.covers))
}

/* So a repository leaving the list is the write that lost it, and not a
   campaign being torn down. */
pred noCloseNoDelete {
  always (Now.ev != DeleteDir
          and (Now.ev = CloseIssue implies Now.issue not in Campaign.campaignIssue))
}

/* =================== 1. two sessions sync the body =================== */

/* R1. S1 files and adds R0 to its README; S0 adopts while the body is still
   empty; S1 syncs, so the body reads {R0}; S0 syncs from its own stale README,
   so the body reads empty. R0 never returns, and no event means "remove a
   repository". */
pred R1_LostBodyUpdate {
  some c: Campaign, disj s1, s2: Session, r: Repo {
    eventually (Now.ev = FileCampaignIssue and By.actor = s1 and Now.issue = c.campaignIssue)
    eventually (Now.ev = Adopt and By.actor = s2)
    eventually (Now.ev = WriteBody and By.actor = s1)
    eventually (Now.ev = WriteBody and By.actor = s2)
    eventually (r in c.body and after (always r not in c.body))
    noCloseNoDelete
  }
}

/* R1b. A body write cannot touch a sub-issue link, so the index goes on
   naming an open sub-issue homed in a repository the list has dropped -- and
   closing the campaign deletes that list's last copy. Ordered on purpose:
   unordered it reads SAT on the ordinary window between filing and syncing. */
pred R1b_IndexOutlivesRepoList {
  some c: Campaign, disj s1, s2: Session, i: Issue, r: Repo {
    r != Container and i.home = r
    eventually (Now.ev = WriteBody and By.actor = s1)
    eventually (Now.ev = WriteBody and By.actor = s2)
    eventually (i in idx[c] and r in c.body
                and after (always (i in idx[c] and i in Open and r not in c.body)))
    noCloseNoDelete
  }
}

/* R1c. The recommendation, and the loss is gone. */
pred R1c_CASBlocksLoss { syncCAS and R1_LostBodyUpdate }

/* R1d. UNSAT here would mean R1c went green by forbidding the scenario. */
pred R1d_CASAdmitsBothSyncs {
  syncCAS
  some c: Campaign, disj s1, s2: Session, disj r1, r2: Repo {
    eventually (Now.ev = FileCampaignIssue and By.actor = s1 and Now.issue = c.campaignIssue)
    eventually (Now.ev = Adopt and By.actor = s2)
    eventually (Now.ev = WriteBody and By.actor = s1)
    eventually (Now.ev = WriteBody and By.actor = s2)
    eventually (r1 in c.body and r2 in c.body)
    noCloseNoDelete
  }
}

/* R1e. Both syncs happen with a real settled sub-issue in the campaign, so
   `syncAtCloseOnly` is obeyed rather than satisfied vacuously. */
pred R1e_CloseOnlyStillLoses {
  syncAtCloseOnly
  some c: Campaign, disj s1, s2: Session, i: Issue, r: Repo {
    eventually (Now.ev = FileCampaignIssue and By.actor = s1 and Now.issue = c.campaignIssue)
    eventually (Now.ev = AddMember and By.actor = s1 and Now.issue = i)
    eventually (Now.ev = Adopt and By.actor = s2)
    eventually (Now.ev = WriteBody and By.actor = s1 and i in c.members and settled[i])
    eventually (Now.ev = WriteBody and By.actor = s2 and i in c.members and settled[i])
    eventually (r in c.body and after (always r not in c.body))
    noCloseNoDelete
  }
}

/* R1h. The binding is a rule sessions follow, not a lock GitHub enforces:
   `gh issue edit` refuses nothing. */
pred R1h_UnboundMachineStillLoses {
  some c: Campaign, disj s1, s2: Session, r: Repo {
    s1.smach != s2.smach
    always Binding.bound[c] = s1.smach
    always Binding.bound[c] != s2.smach
    eventually (Now.ev = WriteBody and By.actor = s1)
    eventually (Now.ev = WriteBody and By.actor = s2)
    eventually (r in c.body and after (always r not in c.body))
    noCloseNoDelete
  }
}

/* R1p. Two sessions on the one bound machine are both members, so `boundOnly`
   alone leaves R1's two syncs legal: the membership rule never serialized the
   body. */
pred R1p_BoundAloneStillLoses { boundOnly and R1_LostBodyUpdate }

/* R1j. A WHEN rule says nothing about comparing before you write. */
pred R1j_TwoMomentStillLoses { syncAtTwoMoments and R1_LostBodyUpdate }

/* R1k. The difference from `syncAtCloseOnly` in one trace: under it, this
   mid-campaign sync cannot happen at all. */
pred R1k_TwoMomentAdmitsScopeSync {
  syncAtTwoMoments
  some c: Campaign, s: Session, i: Issue, r: Repo {
    eventually (Now.ev = EditReadme and By.actor = s and r not in c.body)
    eventually (Now.ev = WriteBody and By.actor = s
                and i in c.members and not settled[i] and r in c.body')
    noCloseNoDelete
  }
}

/* =================== 2. duplicate campaigns =================== */

/* R2. Two campaign issues, one scope. */
pred R2_DuplicateCampaign {
  some disj s1, s2: Session, disj c1, c2: Campaign {
    c1 in Req.covers and c2 in Req.covers
    eventually (Now.ev = FileCampaignIssue and By.actor = s1 and Now.issue = c1.campaignIssue)
    eventually (Now.ev = FileCampaignIssue and By.actor = s2 and Now.issue = c2.campaignIssue)
    eventually (c1 + c2 in Filed and c1.campaignIssue in Open and c2.campaignIssue in Open)
  }
}

pred R2b_SurveyAtFileBlocks { surveyAtFile and R2_DuplicateCampaign }

/* Control: with the same discipline one campaign still opens. */
pred R2c_SurveyAtFileAdmitsOne {
  surveyAtFile
  some s: Session, c: Campaign {
    c in Req.covers
    eventually (Now.ev = FileCampaignIssue and By.actor = s and Now.issue = c.campaignIssue)
  }
}

/* =================== 3. a close during another session's work =================== */

/* R3. The finding needs no delegate at all, which is why it is stated in the
   entity that has none: every live-role gate the design has passes vacuously
   here and the loss happens anyway, because a live SESSION is invisible to
   that gate. Nothing in this layer repairs it -- whether a peer is working the
   tree is carried by `runtime/claims/`, so the repair is role/scenarios.als's A10-A12. */
pred R3_DeleteUnderWorkingSession {
  some c: Campaign, disj s1, s2: Session {
    s1.smach = s2.smach
    eventually (Now.ev = DeleteDir and By.actor = s2
                and s1 in working and s1.holds = c
                and some (treesOf[c]).checkout)
  }
}

/* =================== 4. a campaign with no member repository =================== */

/* R4. `- none` is encoded as `always no c.body`. Note what the predicate does
   NOT say: the container IS in `c.members`, as the home of the sub-issue, since
   a repo-less campaign files on the container tracker -- "no member
   repository" is a claim about the list, not about where an issue is homed.

   Checked WITH the disciplines rather than instead of them, and the claim is
   required: the branch is the claim before it is a workspace. */
pred R4_RepolessCampaign {
  syncCAS and surveyAtFile
  some s: Session, c: Campaign, i: Issue {
    closeDiscipline[c]
    always no c.body
    i.home = Container            -- the only tracker there is
    eventually (Now.ev = FileCampaignIssue and By.actor = s and Now.issue = c.campaignIssue)
    eventually (Now.ev = AddMember and By.actor = s and Now.issue = i)
    eventually (Now.ev = Claim and By.actor = s and Now.issue = i)
    eventually (Now.ev = CloseIssue and Now.issue = i and no i.pr)
    eventually (Now.ev = CloseIssue and Now.issue = c.campaignIssue)
    eventually (campaignClosed[c] and i in c.members and dropped[i])
  }
}

/* ---------------- commands ---------------- */

-- the loss
run R1_LostBodyUpdate            for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 1
-- and it is worse than it looks
run R1b_IndexOutlivesRepoList    for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 14 steps expect 1
-- compare-then-write works: THE guard
run R1c_CASBlocksLoss            for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 0
-- control: it is not vacuous
run R1d_CASAdmitsBothSyncs       for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 14 steps expect 1
-- the candidate it beats
run R1e_CloseOnlyStillLoses      for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 1
-- BOUND is a rule, not a lock
run R1h_UnboundMachineStillLoses for 3 Issue, 1 PR, 2 Campaign, 2 Session, 2 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 1
-- the membership rule never serialized the body
run R1p_BoundAloneStillLoses     for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 1
-- two moments is a WHEN rule, not a HOW
run R1j_TwoMomentStillLoses      for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 1
-- control, and the close-only difference
run R1k_TwoMomentAdmitsScopeSync for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 12 steps expect 1

-- two campaign issues, one scope
run R2_DuplicateCampaign         for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1
-- the same shape repairs it
run R2b_SurveyAtFileBlocks       for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 0
-- control
run R2c_SurveyAtFileAdmitsOne    for 3 Issue, 1 PR, 2 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 2 Tree, 10 steps expect 1

-- a live session is invisible to the gate; the repair is role/scenarios.als's A10-A12
run R3_DeleteUnderWorkingSession for 3 Issue, 1 PR, 1 Campaign, 2 Session, 1 Machine, 3 Repo, 1 Topic, 1 Tree, 12 steps expect 1

-- `- none` opens, claims and closes
run R4_RepolessCampaign          for 2 Issue, 1 PR, 1 Campaign, 1 Session, 1 Machine, 1 Repo, 1 Topic, 1 Tree, 12 steps expect 1
