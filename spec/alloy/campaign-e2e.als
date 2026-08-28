/*
 * End-to-end scenarios over the adopted campaign model (variant D).
 *
 * campaign-{A,B,C,D}.als ask "can this design go wrong?" and answer with
 * counterexamples. This file asks the opposite question: "can a real campaign
 * actually do this?" Every command below is a `run`, so a SAT result hands back
 * a concrete trace -- the script a real campaign must be able to follow. An
 * UNSAT result is a finding about the design, not a broken scenario.
 *
 * Relation to campaign-D.als, stated so the two can be diffed:
 *   - kept verbatim: the signatures, the events, `init`, `step`, `complete`.
 *   - dropped: `Mention` and `variantStep`, which D never reaches (they exist
 *     only so the four variants share one `step`), and the `CampaignD` subset
 *     wrapper, folded into `Campaign` since there is one variant here.
 *   - added: `Report`, the delegate's unsolicited "I am done" claim. D has no
 *     way to reach Idle except by opening a pull request, so D cannot state
 *     scenario 4 at all. `Report` touches no GitHub relation, which is exactly
 *     the protocol's point: a claim is not evidence.
 *   - added: the settlement vocabulary a close decision actually reads --
 *     `dropped`, `settled`, `closable`, `campaignClosed`.
 *   - added: `CloneBehind`, `PullClone` and `Launch`, for scenario 17. The
 *     clone's distance from origin/main is not the outer checkout's, and the
 *     hazard is read at launch rather than before the clone.
 *
 * No assertions here. The checks live in campaign-D.als and are not repeated.
 *
 * Run one:
 *   alloy exec -f -o /tmp/alloy-e2e -t text -c 'S1_HappyPath' spec/alloy/campaign-e2e.als
 * Run all:
 *   alloy exec -f -o /tmp/alloy-e2e -t text -c '*' spec/alloy/campaign-e2e.als
 */
module campaignE2E

/* ---------------- static structure (D, verbatim) ---------------- */

sig Repo {}
one sig Container extends Repo {}

sig Machine {}
sig PR {}

sig Issue {
  home: one Repo,
  var pr: lone PR          -- the pull request that would close this issue
}

sig Campaign {
  anchor:      one Issue,       -- the anchor issue in the container repo; the campaign ID
  var members: set Issue,       -- ground truth: the subtasks that belong to the campaign
  var dirs:    set Machine,     -- machines currently holding the git-ignored local directory
  var sub:     set Issue        -- the index: GitHub's native sub-issue link
}

abstract sig AState {}
one sig Live, Idle, Gone extends AState {}

sig Agent {
  task:   one Issue,            -- the member issue it works
  host:   one Machine,          -- the machine whose checkout it runs in
  var st: one AState
}

fact WellFormed {
  all c: Campaign | c.anchor.home = Container
  all disj c1, c2: Campaign | c1.anchor != c2.anchor
  -- D says `i.home = Container implies i in Campaign.anchor`, which forbids the
  -- container being a member of its own campaign outright. Widened here to admit
  -- scenario 16; `containerIsAnchorOnly` below keeps D's reading runnable.
  all i: Issue | i.home = Container implies i in Campaign.anchor + Campaign.members
  always all p: PR | lone pr.p
  always all i: Issue | some i.pr implies i.pr' = i.pr    -- a PR link is never undone
  always all c: Campaign | c.anchor not in c.members
  always all disj c1, c2: Campaign | no c1.members & c2.members
  always all p: PR | p in Merged implies some pr.p
}

var sig Open   in Issue {}      -- issues currently open on GitHub
var sig Merged in PR {}         -- pull requests currently merged

/* The container cloned into its own campaign tree: one repository, two
   checkouts on a machine. The OUTER checkout is where the campaign session runs
   and where its instruction files are read from; the INNER clone, under
   <campaign>/repos/agent-workspace/, is what a delegate works in and is cut
   from origin/main. Two bits per machine say everything the hazards need. */
var sig Behind   in Machine {}  -- the outer checkout is behind origin/main
var sig Unpushed in Machine {}  -- the outer checkout holds commits origin lacks
/* The INNER clone's own distance from origin/main. Separate from `Behind`
   because the two are cleared by different acts: a clone is cut fresh from
   origin/main, which says nothing about the outer checkout it sits inside. Only
   meaningful for a machine that has a campaign directory. */
var sig CloneBehind in Machine {}

/* D's original reading, kept runnable so the widening above stays visible. */
pred containerIsAnchorOnly { always all i: Issue | i.home = Container implies i in Campaign.anchor }

fun campaignOf[i: Issue]: lone Campaign { members.i }

/* Completion is a GitHub fact and mentions no agent. */
pred complete[i: Issue] { i not in Open and some i.pr and i.pr in Merged }

/* ---------------- the index (D) ---------------- */

fun idx[c: Campaign]: set Issue { c.sub }

pred idxFrame { sub' = sub }
pred addIdx[c: Campaign, i: Issue] { sub' = sub + c->i }
pred remIdx[c: Campaign, i: Issue] { sub' = sub - c->i }
pred initIdx { all c: Campaign | c.sub = c.members }

/* ---------------- settlement, as a close decision reads it ---------------- */

/* Closed as "not planned": the issue is closed and no merged PR stands behind
   it. This is how a subtask gets dropped, and campaign-D's 7b counterexample is
   precisely that closed-and-merged alone cannot say it. */
pred dropped[i: Issue]  { i not in Open and not complete[i] }
pred settled[i: Issue]  { complete[i] or dropped[i] }

pred noLiveAgent[c: Campaign] {
  no a: Agent | a.st = Live and (a.task in c.members or a.host in c.dirs)
}
pred closable[c: Campaign] { (all i: c.members | settled[i]) and noLiveAgent[c] }
pred campaignClosed[c: Campaign] { c.anchor not in Open }

/* The design's close rule, as a trace constraint: the anchor is closed only
   from a closable state. Scenario 8 is what happens without it. */
pred closeDiscipline[c: Campaign] {
  always ((Now.ev = CloseIssue and Now.evIssue = c.anchor) implies closable[c])
}

/* Realism: on GitHub a subtask issue is closed by its merged pull request. A
   trace that closes first and merges later satisfies `settled` the whole way
   and is not the path anyone runs, so the scenarios that mean "merged" say so. */
pred mergeClosed[s: set Issue] {
  always (all i: s | (Now.ev = CloseIssue and Now.evIssue = i)
                     implies (some i.pr and i.pr in Merged))
}

/* ---------------- observable events ---------------- */

abstract sig Event {}
one sig Stutter, OpenPR, MergePR, CloseIssue, AddMember, RemoveMember,
        AgentDie, DeleteDir, CreateDir, Report, PullContainer, CommitLocal,
        PullClone, Launch extends Event {}

one sig Now {
  var ev:        one Event,
  var evIssue:   lone Issue,
  var evMachine: lone Machine
}

pred githubFrame { Open' = Open and Merged' = Merged and pr' = pr and members' = members and idxFrame }

pred openPR[i: Issue] {
  i in Campaign.members and i in Open and no i.pr
  some p: PR - Issue.pr | pr' = pr + i->p
  all a: Agent | (a.task = i and a.st = Live) implies a.st' = Idle else a.st' = a.st
  Open' = Open and Merged' = Merged and members' = members and dirs' = dirs and idxFrame
  Now.ev = OpenPR and Now.evIssue = i and no Now.evMachine
}

pred mergePR[i: Issue] {
  some i.pr and i.pr not in Merged
  Merged' = Merged + i.pr
  Open' = Open and pr' = pr and members' = members and dirs' = dirs and idxFrame and st' = st
  Now.ev = MergePR and Now.evIssue = i and no Now.evMachine
}

/* Nothing in the design forbids closing an issue whose PR never merged. */
pred closeIssue[i: Issue] {
  i in Open
  Open' = Open - i
  Merged' = Merged and pr' = pr and members' = members and dirs' = dirs and idxFrame and st' = st
  Now.ev = CloseIssue and Now.evIssue = i and no Now.evMachine
}

pred addMember[c: Campaign, i: Issue] {
  i not in Campaign.members and i not in Campaign.anchor
  i not in Open and no i.pr
  members' = members + c->i
  Open' = Open + i
  addIdx[c, i]
  Merged' = Merged and pr' = pr and dirs' = dirs and st' = st
  Now.ev = AddMember and Now.evIssue = i and no Now.evMachine
}

pred removeMember[c: Campaign, i: Issue] {
  i in c.members
  members' = members - c->i
  remIdx[c, i]
  Open' = Open and Merged' = Merged and pr' = pr and dirs' = dirs and st' = st
  Now.ev = RemoveMember and Now.evIssue = i and no Now.evMachine
}

pred agentDie[a: Agent] {
  a.st != Gone
  a.st' = Gone
  all b: Agent - a | b.st' = b.st
  githubFrame and dirs' = dirs
  Now.ev = AgentDie and Now.evIssue = a.task and no Now.evMachine
}

/* REPORT: the delegate says it is finished. It writes nothing to GitHub, which
   is the whole reason the campaign session may not believe it. */
pred agentReport[a: Agent] {
  a.st = Live
  a.st' = Idle
  all b: Agent - a | b.st' = b.st
  githubFrame and dirs' = dirs
  Now.ev = Report and Now.evIssue = a.task and no Now.evMachine
}

/* The design's rule "no campaign is closed while an agent is live under its
   tree" is a discipline, not a guard: nothing here enforces it. */
pred deleteDir[c: Campaign, m: Machine] {
  m in c.dirs
  dirs' = dirs - c->m
  githubFrame and st' = st
  Now.ev = DeleteDir and no Now.evIssue and Now.evMachine = m
}

pred createDir[c: Campaign, m: Machine] {
  m not in c.dirs
  dirs' = dirs + c->m
  githubFrame and st' = st
  Now.ev = CreateDir and no Now.evIssue and Now.evMachine = m
}

pred pullContainer[m: Machine] {
  m in Behind
  Behind' = Behind - m and Unpushed' = Unpushed
  githubFrame and dirs' = dirs and st' = st
  Now.ev = PullContainer and no Now.evIssue and Now.evMachine = m
}

/* `git -C <campaign>/repos/<repo> pull` inside the clone. */
pred pullClone[m: Machine] {
  m in CloneBehind
  Behind' = Behind and Unpushed' = Unpushed
  githubFrame and dirs' = dirs and st' = st
  Now.ev = PullClone and no Now.evIssue and Now.evMachine = m
}

/* The moment a delegate is started in this machine's clone. An observable
   marker only -- it moves no agent, because what scenario 17 asks about is when
   the freshness check happens, not what the delegate then does. The agent-state
   half of a launch is campaign-multi's. */
pred launchDelegate[m: Machine] {
  m in Campaign.dirs
  Behind' = Behind and Unpushed' = Unpushed
  githubFrame and dirs' = dirs and st' = st
  Now.ev = Launch and no Now.evIssue and Now.evMachine = m
}

/* An edit committed in the outer container and not yet pushed. */
pred commitLocal[m: Machine] {
  m not in Unpushed
  Unpushed' = Unpushed + m and Behind' = Behind
  githubFrame and dirs' = dirs and st' = st
  Now.ev = CommitLocal and no Now.evIssue and Now.evMachine = m
}

pred stutter {
  githubFrame and dirs' = dirs and st' = st
  Now.ev = Stutter and no Now.evIssue and no Now.evMachine
}

pred init {
  Open = Campaign.anchor + Campaign.members
  no Merged
  no pr
  some Campaign.members
  all a: Agent | a.st = Live
  all a: Agent | some c: Campaign | a.task in c.members and a.host in c.dirs
  no Behind and no Unpushed and no CloneBehind
  initIdx
}

pred step {
  stutter
  or (some i: Issue | openPR[i] or mergePR[i] or closeIssue[i])
  or (some c: Campaign, i: Issue | addMember[c,i] or removeMember[c,i])
  or (some a: Agent | agentDie[a] or agentReport[a])
  or (some c: Campaign, m: Machine | deleteDir[c,m] or createDir[c,m])
  or (some m: Machine | pullContainer[m] or commitLocal[m]
                       or pullClone[m] or launchDelegate[m])
}

/* Merging a pull request against the container leaves every outer checkout
   behind origin/main. Nothing else moves either bit -- in particular no event
   here writes the outer checkout from inside the clone, which is hazard 3:
   the model agrees that editing .claude/skills/ in the clone cannot change what
   the running campaign follows, but it agrees *by construction*, because that
   event was never written. That is a restatement, not evidence. */
fact CheckoutFrame {
  always ((Now.ev not in PullContainer + CommitLocal) implies
    (Unpushed' = Unpushed and
     ((Now.ev = MergePR and Now.evIssue.home = Container)
        implies Behind' = Machine else Behind' = Behind)))
}

/* The clone's bit, moved by three acts and nothing else: a merged container
   pull request leaves every existing clone behind origin/main; cutting the
   clone and pulling it each make one current again. */
fact CloneFrame {
  always ((Now.ev = MergePR and Now.evIssue.home = Container)
    implies CloneBehind' = CloneBehind + Campaign.dirs
    else ((Now.ev in CreateDir + PullClone)
      implies CloneBehind' = CloneBehind - Now.evMachine
      else CloneBehind' = CloneBehind))
}

fact Trace { init and always step }

/* ================= scenarios =================
 * Each is a witness request. Read the trace as a script.
 */

/* 1. The plain path: two repositories, two subtasks, both settled by merge,
      then the campaign closes. */
pred S1_HappyPath {
  one c: Campaign {
    #c.members = 2
    #(c.members.home) = 2                       -- two distinct member repositories
    always Now.ev not in AddMember + RemoveMember
    mergeClosed[c.members]
    eventually (all i: c.members | complete[i])
    closeDiscipline[c]
    eventually (closable[c] and campaignClosed[c])
  }
}

/* 2. One subtask dropped -- closed as not planned, no pull request ever -- and
      the campaign still reaches closable. */
pred S2_SubtaskDropped {
  one c: Campaign {
    #c.members = 2
    always Now.ev not in AddMember + RemoveMember
    some disj i1, i2: c.members {
      mergeClosed[i1]
      eventually complete[i1]
      always no i2.pr                           -- not planned: never had a PR
      eventually dropped[i2]
    }
    closeDiscipline[c]
    eventually (closable[c] and campaignClosed[c])
  }
}

/* 3. The delegate dies after pushing. Completion is a GitHub fact, so it
      survives the death and never comes undone. */
pred S3_DelegateDiesAfterPushing {
  one c: Campaign | one a: Agent {
    a.task in c.members
    always Now.ev not in AddMember + RemoveMember
    mergeClosed[c.members]
    eventually (Now.ev = OpenPR and Now.evIssue = a.task)
    eventually (Now.ev = AgentDie and some a.task.pr and a.task.pr not in Merged)
    eventually complete[a.task]
    always (complete[a.task] implies always complete[a.task])
  }
}

/* 4. The delegate reports done while nothing is pushed. The campaign session
      must not believe it, and the trace shows why: the claim never becomes a
      GitHub fact on its own. */
pred S4_ReportWithoutPush {
  one c: Campaign | one a: Agent {
    a.task in c.members
    always Now.ev not in AddMember + RemoveMember
    eventually (Now.ev = Report and Now.evIssue = a.task)
    eventually (a.st = Idle and no a.task.pr and a.task in Open)
    eventually always (not complete[a.task])
    always not closable[c]
  }
}

/* 5. A follow-up subtask arrives after everything else settled, so the campaign
      re-opens work instead of closing. */
pred S5_FollowUpAfterSettled {
  one c: Campaign {
    #c.members = 1
    mergeClosed[Issue - c.anchor]
    always Now.ev != RemoveMember          -- no emptying the campaign to fake "all settled"
    some i1: c.members, i2: Issue - c.members - c.anchor {
      -- the first subtask is complete and the campaign has not closed; then the
      -- follow-up lands and the campaign has open work again
      eventually (complete[i1] and c.anchor in Open
                  and Now.ev = AddMember and Now.evIssue = i2)
      eventually (i2 in c.members and not settled[i2])
      eventually complete[i2]
    }
    closeDiscipline[c]
    eventually (closable[c] and campaignClosed[c])
  }
}

/* 6. A repository joins the campaign mid-flight: the added subtask's home is a
      repository no existing member lives in. */
pred S6_RepoJoinsMidFlight {
  one c: Campaign {
    #c.members = 1
    #(c.members.home) = 1
    mergeClosed[Issue - c.anchor]
    always Now.ev != RemoveMember
    eventually (Now.ev = AddMember
                and Now.evIssue not in c.members
                and Now.evIssue.home not in c.members.home)
    eventually (#c.members = 2 and #(c.members.home) = 2
                and (all i: c.members | complete[i]))
  }
}

/* 7. Two machines hold the campaign. One deletes its own tree while the other
      is still working; the working machine and the GitHub facts are untouched. */
pred S7_TwoMachinesOneDeletes {
  one c: Campaign | one a: Agent {
    a.task in c.members
    #c.dirs = 2
    mergeClosed[c.members]
    some m: Machine - a.host {
      m in c.dirs
      eventually (Now.ev = DeleteDir and Now.evMachine = m and a.st = Live)
    }
    always (a.st = Live implies a.host in c.dirs)
    eventually complete[a.task]
  }
}

/* 8. The campaign is closed with a subtask still open. The model allows it --
      nothing guards the anchor's close -- so a real run must report it. */
pred S8_CloseWithOpenSubtask {
  one c: Campaign {
    #c.members = 2
    always Now.ev not in AddMember + RemoveMember
    mergeClosed[c.members]
    some disj i1, i2: c.members |
      eventually (Now.ev = CloseIssue and Now.evIssue = c.anchor
                  and complete[i1] and i2 in Open)
    eventually (campaignClosed[c] and (some i: c.members | i in Open))
  }
}

/* --- scenarios beyond the brief's eight, all reachable in this model --- */

/* 9. Scenario 7's dangerous twin: the delete lands on the machine the live
      agent runs on. This is campaign-D's assertion-6 counterexample, requested
      as a witness so a run can be written that reproduces it on purpose. */
pred S9_OrphanedByLocalDelete {
  one c: Campaign | one a: Agent {
    a.task in c.members
    -- deleted while the agent is live with nothing pushed: this is the only
    -- state where local-only work is actually destroyed
    eventually (Now.ev = DeleteDir and Now.evMachine = a.host and a.st = Live
                and no a.task.pr)
    eventually (a.st = Live and a.host not in c.dirs)
  }
}

/* 10. A subtask is moved out of the campaign. The sub-issue index prunes with
       it, so the index equals membership before and after. */
pred S10_SubtaskMovedOut {
  one c: Campaign {
    #c.members = 2
    mergeClosed[c.members]
    always Now.ev != AddMember
    some disj i1, i2: c.members {
      always (Now.ev = RemoveMember implies Now.evIssue = i2)   -- exactly one moves out
      eventually (Now.ev = RemoveMember and Now.evIssue = i2)
      eventually complete[i1]
      eventually c.members = i1
    }
    always (all d: Campaign | d.members = idx[d])               -- the index prunes with it
    closeDiscipline[c]
    eventually (closable[c] and campaignClosed[c])
  }
}

/* 11. The pull request merged but nobody closed the issue -- a missing
       "Closes #N". The subtask never reads complete and the campaign never
       becomes closable, with nothing on screen to say so. */
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

/* 12. Two campaigns work the same repository at once. Both settle; neither
       touches the other's members. This is what the c<N>/ branch rule buys. */
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

/* 13. Review feedback on a merged subtask: the issue is reopened after it read
       complete. UNSAT, and the controls below pin why -- not a bound artifact.
       Reopening a closed issue is reachable (13b, via remove-then-re-add), but
       only for an issue that never had a pull request: `addMember` guards on
       `no i.pr`, and `WellFormed` never undoes a pr link. So any issue that
       ever had a PR is closed forever (13c, UNSAT). */
pred S13_ReopenAfterMerge {
  one c: Campaign | some i: c.members {
    eventually complete[i]
    eventually (complete[i] and after (i in Open))
  }
}

/* Controls for the UNSAT above. An UNSAT is a finding only if the same bounds
   admit the pieces separately. 13a: completion is reachable here (SAT).
   13b: a closed issue can reopen (SAT). 13c: one that ever had a pull request
   cannot (UNSAT) -- that is the actual blocker. */
pred S13a_ControlCompletes { some i: Campaign.members | eventually complete[i] }
pred S13b_ReopenAnyClosed  { some i: Issue | eventually (i not in Open and after (i in Open)) }
pred S13c_ReopenWithPR     { some i: Issue | eventually (some i.pr and i not in Open and after (i in Open)) }

/* 14. A follow-up subtask arrives after the anchor was already closed. Nothing
       in the design guards the anchor's close against later sub-issues. */
pred S14_FollowUpAfterClose {
  one c: Campaign {
    #c.members = 1
    mergeClosed[Issue - c.anchor]
    always Now.ev != RemoveMember
    closeDiscipline[c]                     -- the anchor closed legitimately
    some i2: Issue - c.members - c.anchor {
      eventually (campaignClosed[c] and Now.ev = AddMember and Now.evIssue = i2)
      eventually (campaignClosed[c] and i2 in c.members and i2 in Open and not settled[i2])
    }
  }
}

/* 15. The whole campaign runs with no local directory on any machine -- the
       reconstitution claim, exercised rather than asserted. */
pred S15_NoLocalDirectory {
  one c: Campaign {
    always no c.dirs
    #c.members = 2
    mergeClosed[c.members]
    always Now.ev not in AddMember + RemoveMember
    eventually (all i: c.members | complete[i])
    closeDiscipline[c]
    eventually (closable[c] and campaignClosed[c])
  }
}

/* --- 16. The container as a member of its own campaign --- */

/* 16a. Under D's reading, this scenario cannot exist at all: a container-homed
        issue must BE the anchor. Expected UNSAT, and that is the finding --
        the model forbade what is about to happen for real. */
pred S16a_ContainerMemberUnderD {
  containerIsAnchorOnly
  some c: Campaign, i: c.members | i.home = Container
}

/* 16b. Hazard 1, and its remedy. A pull request against the container merges;
        every outer container checkout is now behind origin/main, and only a
        pull clears it. Anyone editing from a behind checkout can silently
        revert the merged work. */
pred S16b_ContainerBehindAfterMerge {
  one c: Campaign | some i: c.members {
    i.home = Container
    always Now.ev not in AddMember + RemoveMember
    mergeClosed[c.members]
    eventually (Now.ev = MergePR and Now.evIssue = i)
    eventually Machine in Behind            -- every outer checkout, not just one
    eventually Now.ev = PullContainer
    eventually (no Behind and complete[i])
  }
}

/* 16c. Hazard 1 left alone. Nobody pulls, so the outer checkouts stay behind
        for the rest of the campaign with nothing saying so. */
pred S16c_BehindForever {
  one c: Campaign | some i: c.members {
    i.home = Container
    always Now.ev != PullContainer
    eventually (Now.ev = MergePR and Now.evIssue = i)
    eventually always Machine in Behind
  }
}

/* 16d. Hazard 2. The campaign directory is created -- the clone is cut from
        origin/main -- while the outer container holds unpushed commits. The
        delegate reads an AGENTS.md older than the one the campaign session is
        following, and obeys rules already superseded. */
pred S16d_CloneFromUnpushedContainer {
  one c: Campaign | some m: Machine {
    m not in c.dirs                         -- not yet cloned here
    eventually (Now.ev = CommitLocal and Now.evMachine = m)
    eventually (m in Unpushed and Now.ev = CreateDir and Now.evMachine = m)
    eventually (m in c.dirs and m in Unpushed)
  }
}

/* --- 17. The clone that was current when cut and stale when launched --- */

/* The rule as it was written before a live run disproved it: never clone while
   the outer container holds commits origin lacks. */
pred pushBeforeClone { always (Now.ev = CreateDir implies no Unpushed) }

/* The rule AGENTS.md now carries: fetch and compare inside the clone, at
   launch. Stating it and then finding no behind launch restates the guard, so
   what is run below is its control, not the guard. */
pred pullCloneAtLaunch { always (Now.ev = Launch implies Now.evMachine not in CloneBehind) }

/* The three acts in order: the clone is cut, origin/main then moves under it,
   and the delegate starts in a clone that is behind. Ordered explicitly --
   written as three unordered `eventually`s this also reads SAT on a clone cut
   after the merge, which is not the finding. */
pred cloneThenMergeThenLaunch[c: Campaign, i: Issue, m: Machine] {
  i in c.members and i.home = Container
  eventually (Now.ev = CreateDir and Now.evMachine = m
    and after eventually (Now.ev = MergePR and Now.evIssue = i
      and after eventually (Now.ev = Launch and Now.evMachine = m
                            and m in CloneBehind)))
}

/* 17a. It is reachable at all: a delegate launched into a stale clone obeys an
        AGENTS.md the campaign session has already superseded, and nothing
        reports it. */
pred S17a_CloneBehindAtLaunch {
  one c: Campaign | some i: Issue, m: Machine | cloneThenMergeThenLaunch[c, i, m]
}

/* 17b. The superseded rule, enforced for the whole trace, does not stop it.
        This is the live run's finding as a model result: the container read
        clean immediately before the clone, and the remote moved between the
        clone and the launch. The rule is not wrong, it is checked in the wrong
        place. */
pred S17b_OldCloneRuleInsufficient {
  pushBeforeClone
  one c: Campaign | some i: Issue, m: Machine | cloneThenMergeThenLaunch[c, i, m]
}

/* 17c. Control for the adopted rule: it is not vacuous. A container pull
        request still merges mid-flight and a delegate still launches, once the
        clone is pulled first. */
pred S17c_PullBeforeLaunchAdmitsLaunch {
  pullCloneAtLaunch
  one c: Campaign | some i: Issue, m: Machine {
    i in c.members and i.home = Container
    eventually (Now.ev = CreateDir and Now.evMachine = m
      and after eventually (Now.ev = MergePR and Now.evIssue = i
        and after eventually (Now.ev = PullClone and Now.evMachine = m
          and after eventually (Now.ev = Launch and Now.evMachine = m))))
  }
}

/* ---------------- commands ---------------- */

run S1_HappyPath                for exactly 3 Issue, 2 PR, exactly 1 Campaign, 1 Machine, 0 Agent, exactly 3 Repo, 12 steps
run S2_SubtaskDropped           for exactly 3 Issue, 2 PR, exactly 1 Campaign, 1 Machine, 0 Agent, exactly 3 Repo, 12 steps
run S3_DelegateDiesAfterPushing for exactly 2 Issue, 1 PR, exactly 1 Campaign, 1 Machine, exactly 1 Agent, exactly 2 Repo, 10 steps
run S4_ReportWithoutPush        for exactly 2 Issue, 1 PR, exactly 1 Campaign, 1 Machine, exactly 1 Agent, exactly 2 Repo, 10 steps
run S5_FollowUpAfterSettled     for exactly 3 Issue, 2 PR, exactly 1 Campaign, 1 Machine, 0 Agent, exactly 2 Repo, 14 steps
run S6_RepoJoinsMidFlight       for exactly 3 Issue, 2 PR, exactly 1 Campaign, 1 Machine, 0 Agent, exactly 3 Repo, 14 steps
run S7_TwoMachinesOneDeletes    for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Machine, exactly 1 Agent, exactly 2 Repo, 10 steps
run S8_CloseWithOpenSubtask     for exactly 3 Issue, 2 PR, exactly 1 Campaign, 1 Machine, 0 Agent, exactly 3 Repo, 12 steps
run S9_OrphanedByLocalDelete    for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Machine, exactly 1 Agent, exactly 2 Repo, 8 steps
run S10_SubtaskMovedOut         for exactly 3 Issue, 2 PR, exactly 1 Campaign, 1 Machine, 0 Agent, exactly 3 Repo, 12 steps
run S11_MergedButIssueLeftOpen  for exactly 2 Issue, 1 PR, exactly 1 Campaign, 1 Machine, 0 Agent, exactly 2 Repo, 8 steps
run S12_TwoCampaignsOneRepo     for exactly 4 Issue, 2 PR, exactly 2 Campaign, 1 Machine, 0 Agent, exactly 2 Repo, 14 steps
run S13_ReopenAfterMerge        for exactly 2 Issue, 1 PR, exactly 1 Campaign, 1 Machine, 0 Agent, exactly 2 Repo, 10 steps
run S13a_ControlCompletes       for exactly 2 Issue, 1 PR, exactly 1 Campaign, 1 Machine, 0 Agent, exactly 2 Repo, 10 steps
run S13b_ReopenAnyClosed        for exactly 2 Issue, 1 PR, exactly 1 Campaign, 1 Machine, 0 Agent, exactly 2 Repo, 10 steps
run S13c_ReopenWithPR           for exactly 2 Issue, 1 PR, exactly 1 Campaign, 1 Machine, 0 Agent, exactly 2 Repo, 10 steps
run S14_FollowUpAfterClose      for exactly 3 Issue, 2 PR, exactly 1 Campaign, 1 Machine, 0 Agent, exactly 2 Repo, 14 steps
run S15_NoLocalDirectory        for exactly 3 Issue, 2 PR, exactly 1 Campaign, 1 Machine, 0 Agent, exactly 3 Repo, 12 steps
run S16a_ContainerMemberUnderD      for exactly 2 Issue, 1 PR, exactly 1 Campaign, 1 Machine, 0 Agent, exactly 2 Repo, 6 steps
run S16b_ContainerBehindAfterMerge  for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Machine, 0 Agent, exactly 2 Repo, 12 steps
run S16c_BehindForever              for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Machine, 0 Agent, exactly 2 Repo, 10 steps
run S16d_CloneFromUnpushedContainer for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Machine, 0 Agent, exactly 2 Repo, 10 steps
run S17a_CloneBehindAtLaunch        for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Machine, 0 Agent, exactly 2 Repo, 12 steps
run S17b_OldCloneRuleInsufficient   for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Machine, 0 Agent, exactly 2 Repo, 12 steps
run S17c_PullBeforeLaunchAdmitsLaunch for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Machine, 0 Agent, exactly 2 Repo, 14 steps
