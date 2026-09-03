/*
 * The campaign's record on GitHub -- and the entry point to spec/.
 *
 * ORIENTATION
 *
 * Four layers, each opening the one below, so the composed model is the top
 * file and there is no fifth integration file:
 *
 *   ledger.als    issues, the sub-issue index, settlement, the campaign issue body
 *   repos.als     a member repository from one machine and on its remote
 *   session.als   a campaign session: one role, bound to one machine
 *   agent.als     the executor: launch, the four messages, retirement
 *
 * WHAT CHECKS WHAT
 *
 * Every command states its own verdict, in the `expect` clause the solver
 * enforces: `expect 0` where the solver says UNSAT -- a check with no
 * counterexample, a run with no instance -- and `expect 1` where it says SAT.
 * `alloy exec -f -t text -c '*'` on any of these four files exits non-zero and
 * names each command that came out other than its clause says. No comment
 * restates a verdict, and one that did would be a second reader of what the
 * solver already decided.
 *
 * A command someone DELETES misses no expectation, having none left to miss,
 * and nothing generated from these files can see that either. So the command
 * list is stated a second time, in commands.lock.json beside them, which is
 * committed and compared rather than regenerated:
 *
 *   scripts/alloy-check.py spec/alloy/ledger.als -o /tmp/alloy-ledger
 *   scripts/alloy-check.py --commands spec/alloy            -- and --write to update
 *   scripts/alloy-check.py --digest /tmp/alloy-ledger/S1_HappyPath-solution-0.txt
 *
 * HOW THE LAYERS COMPOSE
 *
 * Facts conjoin on `open`, so each layer's `step` is written as
 *
 *   stutter, or one of this layer's own events, or
 *   (the event is none of this layer's and this layer's state is framed)
 *
 * and a lower layer therefore frames its own state automatically whenever an
 * upper layer's event fires. No upper layer ever writes a frame for a lower
 * layer's variables.
 *
 * A cross-layer event is ONE `Event` atom, declared in the lowest layer that
 * knows the fact, with a disjunct in each layer above that adds to it: the
 * lower layer owns the fact and the primitive, the upper layer owns the actor
 * and the guard. The primitive stays loose so the refinement above it is
 * satisfiable together with it. Observer fields follow the same rule -- `Now`
 * here, `Site` in repos, `By` in session, `Target` in agent -- so no layer
 * declares a field over a signature it does not own.
 */
module ledger

/* ==================== SYSTEM ==================== */

sig Repo {}
one sig Container extends Repo {}

sig PR {}

sig Issue {
  home:   one Repo,
  var pr: lone PR
}

sig Campaign {
  campaignIssue:      one Issue,       -- the campaign issue; its number is the campaign ID
  var members: set Issue,       -- ground truth
  var sub:     set Issue,       -- the index: GitHub's native sub-issue link
  var body:    set Repo         -- the campaign issue body's `## Repos` list
}

var sig Open   in Issue {}
var sig Merged in PR {}
var sig Filed  in Campaign {}

fact WellFormed {
  all c: Campaign | c.campaignIssue.home = Container
  all disj c1, c2: Campaign | c1.campaignIssue != c2.campaignIssue
  always all p: PR | lone pr.p
  always all i: Issue | some i.pr implies i.pr' = i.pr    -- a PR link is never undone
  always all c: Campaign | c.campaignIssue not in c.members
  always all disj c1, c2: Campaign | no c1.members & c2.members
  always all p: PR | p in Merged implies some pr.p
}

/* Read from GitHub, so it survives the executor's death and the machine's
   reboot. */
pred complete[i: Issue] { i not in Open and some i.pr and i.pr in Merged }

/* Completion alone has no way to say "dropped", which is what
   TerminationUnderFairness's counterexample is. */
pred dropped[i: Issue] { i not in Open and not complete[i] }
pred settled[i: Issue] { complete[i] or dropped[i] }

/* The GitHub half. The other -- no agent live under the tree -- is
   agent.als's. */
pred closable[c: Campaign]       { all i: c.members | settled[i] }
pred campaignClosed[c: Campaign] { c.campaignIssue not in Open }

/* S8 is what happens without it. */
pred closeDiscipline[c: Campaign] {
  always ((Now.ev = CloseIssue and Now.issue = c.campaignIssue) implies closable[c])
}

/* A trace that closes first and merges later satisfies `settled` the whole
   way and is not the path anyone runs, so scenarios meaning "merged" say so. */
pred mergeClosed[s: set Issue] {
  always (all i: s | (Now.ev = CloseIssue and Now.issue = i)
                     implies (some i.pr and i.pr in Merged))
}

/* Not a fact: the container's tracker holds THREE kinds of issue, and a
   global fact admitting the third says nothing. S18/S18a are why. */
pred containerIssuesAreCampaignIssues {
  all i: Issue | i.home = Container implies (i in Campaign.campaignIssue or eventually i in Campaign.members)
}

/* The narrower reading, kept runnable beside it. */
pred containerIsCampaignIssueOnly { always all i: Issue | i.home = Container implies i in Campaign.campaignIssue }

fun campaignOf[i: Issue]: lone Campaign { members.i }
fun campaignIssueOf[i: Issue]: lone Campaign { campaignIssue.i }
fun idx[c: Campaign]: set Issue { c.sub }

/* ---------------- observable events ---------------- */

abstract sig Event {}
one sig Stutter, FileCampaignIssue, AddMember, RemoveMember,
        OpenPR, MergePR, CloseIssue, WriteBody extends Event {}

one sig Now {
  var ev:    one Event,
  var issue: lone Issue
}

fun ledgerEvents: set Event {
  FileCampaignIssue + AddMember + RemoveMember + OpenPR + MergePR + CloseIssue + WriteBody
}

pred ledgerFrame {
  Open' = Open and Merged' = Merged and pr' = pr
  and members' = members and sub' = sub and body' = body and Filed' = Filed
}

pred fileCampaignIssue[c: Campaign] {
  c not in Filed
  no c.members and no c.sub and no c.body
  Filed' = Filed + c
  Open'  = Open + c.campaignIssue
  members' = members and sub' = sub and body' = body
  Merged' = Merged and pr' = pr
  Now.ev = FileCampaignIssue and Now.issue = c.campaignIssue
}

/* The issue and its index entry are one write. Deliberately no actor, machine
   or binding precondition: filing a sub-issue is a record, not a claim, so any
   session on any machine may do it (AGENTS.md § The binding). The binding
   gates writeBody, BOUND, the claim and the launch, which live in session.als
   and the claim script, not here. */
pred addMember[c: Campaign, i: Issue] {
  c in Filed
  i not in Campaign.members and i not in Campaign.campaignIssue
  i not in Open and no i.pr
  members' = members + c->i
  sub'     = sub + c->i
  Open'    = Open + i
  Merged' = Merged and pr' = pr and body' = body and Filed' = Filed
  Now.ev = AddMember and Now.issue = i
}

/* The index prunes with the membership. */
pred removeMember[c: Campaign, i: Issue] {
  i in c.members
  members' = members - c->i
  sub'     = sub - c->i
  Open' = Open and Merged' = Merged and pr' = pr and body' = body and Filed' = Filed
  Now.ev = RemoveMember and Now.issue = i
}

pred openPR[i: Issue] {
  i in Campaign.members and i in Open and no i.pr
  some p: PR - Issue.pr | pr' = pr + i->p
  Open' = Open and Merged' = Merged
  members' = members and sub' = sub and body' = body and Filed' = Filed
  Now.ev = OpenPR and Now.issue = i
}

pred mergePR[i: Issue] {
  some i.pr and i.pr not in Merged
  Merged' = Merged + i.pr
  Open' = Open and pr' = pr
  members' = members and sub' = sub and body' = body and Filed' = Filed
  Now.ev = MergePR and Now.issue = i
}

/* Nothing forbids closing an issue whose pull request never merged. */
pred closeIssue[i: Issue] {
  i in Open
  Open' = Open - i
  Merged' = Merged and pr' = pr
  members' = members and sub' = sub and body' = body and Filed' = Filed
  Now.ev = CloseIssue and Now.issue = i
}

/* Deliberately loose. What the list is overwritten WITH is session.als's
   `sync`, satisfiable together with this precisely because this does not pin
   the value. */
pred writeBody[c: Campaign] {
  c in Filed
  body' - c->Repo = body - c->Repo
  Open' = Open and Merged' = Merged and pr' = pr
  members' = members and sub' = sub and Filed' = Filed
  Now.ev = WriteBody and no Now.issue
}

pred stutter {
  ledgerFrame
  Now.ev = Stutter and no Now.issue
}

/* Admits a campaign already in flight, an unfiled one, or any mixture:
   session.als has to be able to file a campaign issue, and the scenarios have to be
   able to start with one already filed. */
pred init {
  no Merged
  no pr
  all c: Campaign - Filed | no c.members and no c.sub and no c.body
  Open = Filed.campaignIssue + Campaign.members
  all c: Campaign | c.sub = c.members
}

pred ledgerStep {
  stutter
  or (some c: Campaign | fileCampaignIssue[c] or writeBody[c])
  or (some c: Campaign, i: Issue | addMember[c,i] or removeMember[c,i])
  or (some i: Issue | openPR[i] or mergePR[i] or closeIssue[i])
  or (Now.ev not in Stutter + ledgerEvents and ledgerFrame)
}

fact Trace { init and always ledgerStep }

/* ==================== SCENARIOS ==================== */

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

-- every own event fires in some trace
run Cov_FileCampaignIssue   for 4 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps expect 1
run Cov_AddMember    for 4 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps expect 1
run Cov_RemoveMember for 4 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps expect 1
run Cov_OpenPR       for 4 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps expect 1
run Cov_MergePR      for 4 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps expect 1
run Cov_CloseIssue   for 4 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps expect 1
run Cov_WriteBody    for 4 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps expect 1
