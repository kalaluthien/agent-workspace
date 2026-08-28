/*
 * Campaign lifecycle -- variant D (proposed).
 *
 * Index mechanism: GitHub's native sub-issue link. The anchor issue is the
 * parent; every member issue is a sub-issue of it.
 *
 * Modelled consequences: the link is one first-class relation the platform
 * maintains in both directions, so the parent's sub-issue list is exact by
 * construction, it is created with the child, and it can be pruned.
 *
 * Probed live 2026-08-28 on this machine, so the atomic-creation assumption is
 * not a guess: the GraphQL schema exposes addSubIssue / removeSubIssue, and
 * gh 2.96.0 has `gh issue create --parent <number|url>` plus
 * `gh issue edit --add-sub-issue / --remove-sub-issue`. The link is therefore
 * made by the same command that creates the member issue.
 *
 * STILL UNVERIFIED: whether a sub-issue may live in a different repository
 * from its parent for this owner. If it may not, D is unusable and C is the
 * fallback.
 */
module campaignD

/* ---------------- static structure ---------------- */

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
  var dirs:    set Machine      -- machines currently holding the git-ignored local directory
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
  all i: Issue | i.home = Container implies i in Campaign.anchor
  always all p: PR | lone pr.p
  always all i: Issue | some i.pr implies i.pr' = i.pr    -- a PR link is never undone
  always all c: Campaign | c.anchor not in c.members
  always all disj c1, c2: Campaign | no c1.members & c2.members
  always all p: PR | p in Merged implies some pr.p
}

var sig Open   in Issue {}      -- issues currently open on GitHub
var sig Merged in PR {}         -- pull requests currently merged

fun campaignOf[i: Issue]: lone Campaign { members.i }

/* Completion is a GitHub fact and mentions no agent. */
pred complete[i: Issue] { i not in Open and some i.pr and i.pr in Merged }

/* ---------------- the index, variant D ---------------- */

sig CampaignD in Campaign { var sub: set Issue }
fact { CampaignD = Campaign }

fun idx[c: Campaign]: set Issue { c.sub }

pred idxFrame { sub' = sub }

/* One relation, maintained by the platform in both directions. */
pred addIdx[c: Campaign, i: Issue] { sub' = sub + c->i }
pred remIdx[c: Campaign, i: Issue] { sub' = sub - c->i }
pred initIdx { all c: Campaign | c.sub = c.members }

pred variantStep { some none }

/* ---------------- observable events ---------------- */

abstract sig Event {}
one sig Stutter, OpenPR, MergePR, CloseIssue, AddMember, RemoveMember,
        AgentDie, DeleteDir, CreateDir, Mention extends Event {}

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
  i.home != Container and i not in Open and no i.pr
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
  initIdx
}

pred step {
  stutter
  or (some i: Issue | openPR[i] or mergePR[i] or closeIssue[i])
  or (some c: Campaign, i: Issue | addMember[c,i] or removeMember[c,i])
  or (some a: Agent | agentDie[a])
  or (some c: Campaign, m: Machine | deleteDir[c,m] or createDir[c,m])
  or variantStep
}

fact Trace { init and always step }

/* ---------------- properties ---------------- */

// 1. No lost work: agent death and directory deletion never un-complete a subtask.
assert NoLostWork {
  always all i: Issue |
    (complete[i] and Now.ev in AgentDie + DeleteDir) implies after complete[i]
}

// 2a. No false completion, with completion read as the design defines it.
assert NoFalseCompletion { always all i: Issue | complete[i] implies i.pr in Merged }

// 2b. The cheaper reading -- "the issue is closed" -- is not completion.
assert ClosedImpliesComplete {
  always all c: Campaign, i: c.members | i not in Open implies complete[i]
}

// 2c. The cheapest reading -- "the agent went idle" -- is not completion.
assert IdleImpliesComplete { always all a: Agent | a.st = Idle implies complete[a.task] }

// 3a. Index totality: no member is missing from the index.
assert IndexCoversMembers { always all c: Campaign | c.members in idx[c] }

// 3b. Index exactness: the index holds nothing but members.
assert IndexExact { always all c: Campaign | c.members = idx[c] }

// 3c. Exactness when no member is ever removed -- isolates noise from staleness.
assert IndexExactStableMembership {
  (always Now.ev != RemoveMember) implies (always all c: Campaign | c.members = idx[c])
}

// 4. Machine independence: deleting a local directory changes no fact another machine reads.
assert MachineIndependence {
  always (Now.ev = DeleteDir implies
    (githubFrame and all c: Campaign, m: Machine - Now.evMachine | (m in c.dirs iff m in c.dirs')))
}

// 5. Reconstitution: from the anchor alone, member repos and open subtasks are recoverable.
assert Reconstitution {
  always all c: Campaign |
    c.members.home = idx[c].home and (c.members & Open) = (idx[c] & Open)
}

// 6. No orphan: no agent is live on a checkout whose campaign directory is gone.
pred noOrphanNow { all a: Agent | a.st = Live implies (some c: Campaign | a.task in c.members and a.host in c.dirs) }

assert NoOrphan { always noOrphanNow }

// 6b. Same, assuming the design's stated retirement rule is actually enforced.
assert NoOrphanIfGuarded {
  ((always (Now.ev = DeleteDir implies (no a: Agent | a.st = Live and a.host = Now.evMachine)))
   and (always (Now.ev = RemoveMember implies (no a: Agent | a.st = Live and a.task = Now.evIssue))))
  implies (always noOrphanNow)
}

// 7a. Termination, as designed: nothing forces progress.
assert Termination {
  (eventually always Now.ev != AddMember) implies
    (eventually all c: Campaign, i: c.members | complete[i])
}

pred progressPossible { some c: Campaign, i: c.members | not complete[i] }

/* Weak fairness: whenever some progress event is enabled on a member issue,
   one eventually fires. It says nothing when nothing is enabled. */
pred progressEnabled {
  some i: Campaign.members |
    (i in Open and no i.pr)                 -- an agent could open a PR
    or (some i.pr and i.pr not in Merged)   -- the PR could be merged
    or i in Open                            -- the issue could be closed
}
pred weakFairness { always (progressEnabled implies eventually Now.ev in OpenPR + MergePR + CloseIssue) }

// 7b. Termination under weak fairness on the progress events.
assert TerminationUnderFairness {
  ((eventually always Now.ev != AddMember)
   and weakFairness)
  implies (eventually all c: Campaign, i: c.members | complete[i])
}

// 7c. Termination under fairness AND a close-discipline: an issue is closed only by a merged PR.
assert TerminationDisciplined {
  ((eventually always Now.ev != AddMember)
   and (always (Now.ev = CloseIssue implies (some Now.evIssue.pr and Now.evIssue.pr in Merged)))
   and (always Now.ev != RemoveMember)
   and weakFairness)
  implies (eventually all c: Campaign, i: c.members | complete[i])
}

run Sanity { eventually (some Merged and some i: Issue | complete[i]) }
                             for 4 Issue, 3 PR, 2 Campaign, 2 Machine, 2 Agent, 3 Repo, 6 steps
check NoLostWork             for 4 Issue, 3 PR, 2 Campaign, 2 Machine, 2 Agent, 3 Repo, 6 steps
check NoFalseCompletion      for 4 Issue, 3 PR, 2 Campaign, 2 Machine, 2 Agent, 3 Repo, 6 steps
check ClosedImpliesComplete  for 4 Issue, 3 PR, 2 Campaign, 2 Machine, 2 Agent, 3 Repo, 6 steps
check IdleImpliesComplete    for 4 Issue, 3 PR, 2 Campaign, 2 Machine, 2 Agent, 3 Repo, 6 steps
check IndexCoversMembers     for 4 Issue, 3 PR, 2 Campaign, 2 Machine, 2 Agent, 3 Repo, 6 steps
check IndexExact             for 4 Issue, 3 PR, 2 Campaign, 2 Machine, 2 Agent, 3 Repo, 6 steps
check IndexExactStableMembership for 4 Issue, 3 PR, 2 Campaign, 2 Machine, 2 Agent, 3 Repo, 6 steps
check MachineIndependence    for 4 Issue, 3 PR, 2 Campaign, 2 Machine, 2 Agent, 3 Repo, 6 steps
check Reconstitution         for 4 Issue, 3 PR, 2 Campaign, 2 Machine, 2 Agent, 3 Repo, 6 steps
check NoOrphan               for 4 Issue, 3 PR, 2 Campaign, 2 Machine, 2 Agent, 3 Repo, 6 steps
check NoOrphanIfGuarded      for 4 Issue, 3 PR, 2 Campaign, 2 Machine, 2 Agent, 3 Repo, 6 steps
check Termination            for 3 Issue, 2 PR, 1 Campaign, 1 Machine, 1 Agent, 2 Repo, 10 steps
check TerminationUnderFairness for 3 Issue, 2 PR, 1 Campaign, 1 Machine, 1 Agent, 2 Repo, 10 steps
check TerminationDisciplined   for 3 Issue, 2 PR, 1 Campaign, 1 Machine, 1 Agent, 2 Repo, 10 steps
