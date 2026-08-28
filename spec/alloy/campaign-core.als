/*
 * Campaign lifecycle: the adopted model, and the entry point to spec/.
 *
 *
 * ORIENTATION
 *
 * spec/ is Alloy and nothing else. Four models, one question each, and no prose
 * beside them: what a model checks is stated in its own comments, next to the
 * construct that checks it. A spec written beside a model drifts from it; a
 * spec written in the model file cannot.
 *
 *   campaign-core.als    can the design go wrong?            15 checks, 2 runs
 *   campaign-e2e.als     can a real campaign do this?        25 runs
 *   campaign-multi.als   what breaks with several sessions?  35 runs
 *   agent-protocol.als   how a session and its agents talk    5 checks, 5 runs
 *
 *   alloy exec -f -o /tmp/alloy-core -t text -c '*' spec/alloy/campaign-core.als
 *
 * The first three share a signature-and-event skeleton -- about a third of this
 * file reappears in campaign-e2e. That is deliberate: each file is read on its
 * own, and each header states what it kept, dropped and added from the one
 * before, so the two can be diffed.
 *
 *
 * STATUS
 *
 * First design, 2026-08-28. Campaign #1 is exercising it as it is written -- a
 * smoke test, a protocol test and an e2e drill have each contradicted a rule
 * here, and each correction is folded into the model rather than kept as an
 * erratum.
 *
 *
 * IDENTITY
 *
 * A campaign is opened by filing one anchor issue in agent-workspace, and that
 * issue number is the campaign's ID. What each name is for, since AGENTS.md
 * states the forms and not the reasons:
 *
 *   ID            #N, the anchor issue number. Short to type, already unique,
 *                 already resolvable from any machine and from a phone.
 *   Slug          a meaningful kebab-case phrase, chosen when the campaign
 *                 opens.
 *   Directory     <slug>-<YYMMDD>/ at the container root, and optional. The
 *                 date disambiguates a slug reused months later and sorts
 *                 usefully in a listing.
 *   Branch        c<N>/<issue>-<topic>. The campaign number stops two campaigns
 *                 working one repository from colliding on the remote, and it
 *                 tells a reviewer which campaign a branch came from; the
 *                 subtask's issue number separates subtasks within a campaign,
 *                 which only matters once several sessions hold it at once.
 *   Display name  the anchor issue's title, in the person's own words.
 *
 * The directory name is a local convenience; the ID is the identity. Assertion
 * 4 below is that claim checked.
 *
 *
 * THIS FILE
 *
 * The properties of the design and of the rules in AGENTS.md, checked against
 * the index the design chose.
 *
 * Issues live on the repository whose code changes -- that is where a reviewer
 * expects them, and it is what a pull request can close. A campaign spans
 * repositories, so its issues are scattered by construction, and the whole
 * index question below is what to do about that.
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
 * made by the same command that creates the member issue. The one open
 * question -- whether a sub-issue may live in another repository, and a private
 * one, under a public parent -- was probed the same day and holds.
 *
 *
 * VERDICTS
 *
 * X is a counterexample; a check that passes reads UNSAT. Each row is restated
 * beside its own assertion below; this is the inventory, not the explanation.
 *
 *   1   NoLostWork                     pass
 *   2a  NoFalseCompletion              pass  (a tautology; 2b and 2c carry it)
 *   2b  ClosedImpliesComplete          X
 *   2c  IdleImpliesComplete            X
 *   3a  IndexCoversMembers             pass
 *   3b  IndexExact                     pass
 *   3c  IndexExactStableMembership     pass
 *   4   MachineIndependence            pass
 *   5   Reconstitution                 pass
 *   6   NoOrphan                       X
 *   6b  NoOrphanIfGuarded              pass
 *   7a  Termination                    X
 *   7b  TerminationUnderFairness       X
 *   7c  TerminationDisciplined         pass
 *   7d  TerminationUnderSettlement     pass
 *
 * Every pass was proved able to fail by mutation, re-run 2026-08-28 against
 * this model: reopening the task in `agentDie` reddens 1; dropping
 * `addMember`'s sub-issue write reddens 3a and 5; letting `deleteDir` drop
 * members reddens 4; removing a guard clause reddens 6b and 7c; dropping
 * `weakFairness` reddens 7d.
 *
 *
 * THE THREE ALTERNATIVES THAT LOST
 *
 * Four index schemes were modelled side by side before one was chosen. The
 * losers are deleted rather than kept as full models, since each was a ~90%
 * copy of the winner differing only in its index. What each was, and what
 * killed it:
 *
 *   A -- a `Campaign: <owner/repo>#N` line in the member issue body, read back
 *   from the anchor's cross-reference timeline. The timeline is append-only and
 *   records any issue that names the anchor, so a subtask moved out stays
 *   indexed forever and the anchor reconstitutes a growing superset: 3b, 3c and
 *   5 all red.
 *
 *   B -- a checklist of member issues in the anchor body. The index entry is a
 *   second write to a different object and may simply not happen, which loses
 *   the issue with nothing anywhere to contradict it. The only scheme where 3a
 *   was red, and the only silent total loss of the four.
 *
 *   C -- a `campaign-<N>` label on every member issue. Correct on totality and
 *   on staleness, but the label object must be created per repository before an
 *   issue there can carry it, and removing a subtask leaves the label behind as
 *   a stale mark: 3b red.
 *
 * The `Campaign:` body line survives as prose for a human reading the raw
 * issue. Nothing queries it.
 *
 *
 * DELIBERATELY ABSENT
 *
 *   No ticket system. Campaigns are triggered by a person, and GitHub issues
 *   carry the subtasks. A board over campaigns will be built later, as a
 *   campaign run in this container.
 *
 *   No campaign-level git. See the three planes in AGENTS.md.
 *
 *   No status file, no lock file, no local database. Every one of them would be
 *   a second copy of a GitHub fact, and the copy is what goes stale.
 *
 *   No virtual environment until something needs one. `.venv` appears the first
 *   time a campaign script is run, not at scaffold time.
 *
 *
 * UNMODELLED, STATED FOR THE RECORD
 *
 * No construct here exercises any of these. Modelling them was weighed and is
 * not worth it -- each is a fact about text, a platform's timing, or another
 * tool's internals rather than a property of the lifecycle.
 *
 * Text well-formedness, `gh` latency and search-index consistency, herdr's
 * liveness derivation, issues in repositories the reader's token cannot see,
 * the delegation mechanics (--append-system-prompt-file, the canary, the
 * 1024-byte launch line, all of which live in campaign-e2e.als's header), and
 * whether a merged pull request does what was asked.
 *
 * Four residual risks of the self-hosted arrangement, none of them modelled:
 *
 *   The `campaign` label is the only thing that marks an anchor, and nothing
 *   enforces it. An anchor filed without it is invisible to every later survey,
 *   so the next session opens a second campaign over the same scope and nothing
 *   reports it. Two cheap readers narrow this -- opening-campaign reads the
 *   label back after filing, and `parent == null` finds an anchor the label
 *   missed -- but a session that runs neither still files the duplicate.
 *
 *   A campaign may be filed under another campaign. GitHub allows it and
 *   sub_issues is not recursive, so the outer settlement shows the nested
 *   anchor as one ordinary row and never sees its members: the outer campaign
 *   reads closable while the inner one is still running.
 *   scripts/campaign-settlement reports a subtask that has sub-issues of its
 *   own; nothing prevents the shape.
 *
 *   A reparent is silent and leaves no trace. `gh issue edit <other>
 *   --add-sub-issue <n>` moves a subtask out of its campaign's index with no
 *   warning, and the old parent's listing simply gets shorter. The sanctioned
 *   flow only ever passes --parent at create, so this needs a hand-run command
 *   with a mistyped number -- but there is no undo signal if one happens.
 *
 *   A bare issue number says nothing about its kind. #4 and #1 are an anchor
 *   and a subtask by nothing a reader can see. Prose that names a number should
 *   name the kind with it, and a tool should resolve it rather than assume.
 *
 *
 * OPEN RISKS
 *
 * Two machines can open the same campaign into directories whose date suffixes
 * differ. Nothing breaks -- assertion 4 is exactly that -- but a person reading
 * two listings sees two names for one thing.
 */
module campaignCore

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
  /* THE WIDENING. This clause said `implies i in Campaign.anchor`, which
     requires every container-homed issue to be SOME campaign's anchor. Read
     precisely, that forbids an ordinary container subtask while still
     permitting the odd case of one campaign's anchor being another campaign's
     member -- so a coarse probe reads SAT and hides it. The probe that isolates
     the real claim is "a container-homed member that is nobody's anchor", and
     on the original model it is UNSAT. With a single campaign, which is the
     actual situation, the clause rules the case out entirely. `addMember`'s
     `i.home != Container` was the same rule restated, and it blocked the
     container joining mid-flight.

     Nothing in the three planes forbade the case -- the container plane is a
     repository like any other -- so this was the model contradicting the
     design, not the design being narrow. Worth stating because the modelled
     version originally ruled it out, which made it possible to read the whole
     scheme as forbidding it.

     Both were widened on 2026-08-28: the clause to `Campaign.anchor +
     Campaign.members`, and the redundant addMember guard dropped. Measured
     before and after, at this model's own bounds:

       probe                                                before  after
       a container-homed member that is nobody's anchor      UNSAT   SAT
       a container-homed issue added mid-flight              UNSAT   SAT

     So the widened world is genuinely reachable, and "no verdict changed" is a
     real result rather than a search that never got there. All fifteen verdicts
     measured then -- the fourteen checks and the Sanity run -- are identical
     before and after, and the greens were re-proved able to fail in the widened
     model. 7d was added later and has only ever been checked here. */
  all i: Issue | i.home = Container implies i in Campaign.anchor + Campaign.members
  always all p: PR | lone pr.p
  always all i: Issue | some i.pr implies i.pr' = i.pr    -- a PR link is never undone
  always all c: Campaign | c.anchor not in c.members
  always all disj c1, c2: Campaign | no c1.members & c2.members
  always all p: PR | p in Merged implies some pr.p
}

var sig Open   in Issue {}      -- issues currently open on GitHub
var sig Merged in PR {}         -- pull requests currently merged

/* Completion is a GitHub fact and mentions no agent.

   The old workspace asked a delegate to print `DONE <name>` and grepped for it.
   That conflates completion with liveness and is fragile in both: a pane can
   show the word and have finished nothing, and a delegate can finish and have
   its line scrolled away. Splitting them is the point -- completion is read
   from GitHub, survives the delegate's death, the pane's death and the
   machine's reboot, and reads the same from a phone; liveness is a herdr fact
   and appears nowhere in this model. Assertions 2b and 2c are the two cheaper
   readings, refuted. */
pred complete[i: Issue] { i not in Open and some i.pr and i.pr in Merged }

/* Settlement, the reading AGENTS.md adopted after 7b below: a subtask is
   settled when its issue is closed, either as completed or as dropped -- closed
   as not planned, with no merged pull request behind it. Completion alone has no
   way to say "dropped", which is what 7b's counterexample is. */
pred dropped[i: Issue] { i not in Open and not complete[i] }
pred settled[i: Issue] { complete[i] or dropped[i] }

/* ---------------- the index ---------------- */

/* One relation, maintained by the platform in both directions: it is written by
   the same command that creates the member issue, and it prunes.

   WHAT THE PLATFORM ACTUALLY DOES. agent-workspace is a member of its own
   campaigns, so its tracker holds anchors and subtasks side by side, drawn from
   one number sequence, and every reader of issues could conflate them. The
   following was probed against GitHub on 2026-08-28, on throwaway issues since
   deleted -- not read out of documentation. It is what this relation's
   modelling rests on, which is why it is recorded here rather than anywhere
   else.

     does closing a parent close its sub-issues?    no; the children stay open
     does closing every sub-issue close the parent? no
     does a closed sub-issue stay in sub_issues?    yes, with state: closed
     may a sub-issue itself be a parent?            yes, to any depth
     is sub_issues recursive?                       no -- direct children only
     may an issue have two parents?                 no; a second
                                                    --add-sub-issue MOVES it
     may an issue be its own parent?                no; the API refuses it
     does an unlabelled anchor appear under
       --label campaign?                            no

   Two readers come out clean because of it, and neither is modelled here:

   Closing cannot reach another campaign. Every enumeration in
   closing-campaign is scoped to issues/<N>/sub_issues, the only issue it closes
   is <N> itself, and GitHub does not cascade a close in either direction. A
   campaign closed here leaves a neighbouring campaign's subtasks untouched even
   though they sit in the same tracker.

   The settlement stays correct. Each row's repository comes from the
   sub-issue's own repository_url, which resolves to the anchor's repository in
   the self-hosted case and to a different one otherwise; nothing in
   scripts/campaign-settlement assumes the two differ. */
fun idx[c: Campaign]: set Issue { c.sub }

pred idxFrame { sub' = sub }

/* ---------------- observable events ---------------- */

abstract sig Event {}
one sig Stutter, OpenPR, MergePR, CloseIssue, AddMember, RemoveMember,
        AgentDie, DeleteDir, CreateDir extends Event {}

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
  i not in Open and no i.pr                    -- the anchor guard above already covers it
  members' = members + c->i
  Open' = Open + i
  sub' = sub + c->i
  Merged' = Merged and pr' = pr and dirs' = dirs and st' = st
  Now.ev = AddMember and Now.evIssue = i and no Now.evMachine
}

pred removeMember[c: Campaign, i: Issue] {
  i in c.members
  members' = members - c->i
  sub' = sub - c->i
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
  all c: Campaign | c.sub = c.members
}

pred step {
  stutter
  or (some i: Issue | openPR[i] or mergePR[i] or closeIssue[i])
  or (some c: Campaign, i: Issue | addMember[c,i] or removeMember[c,i])
  or (some a: Agent | agentDie[a])
  or (some c: Campaign, m: Machine | deleteDir[c,m] or createDir[c,m])
}

fact Trace { init and always step }

/* ---------------- properties ---------------- */

// 1. PASS. No lost work: agent death and directory deletion never un-complete
// a subtask.
assert NoLostWork {
  always all i: Issue |
    (complete[i] and Now.ev in AgentDie + DeleteDir) implies after complete[i]
}

// 2a. PASS, and a tautology: `complete` is DEFINED as closed-and-merged, so
// the content is in 2b and 2c rather than here.
assert NoFalseCompletion { always all i: Issue | complete[i] implies i.pr in Merged }

// 2b. X. The cheaper reading -- "the issue is closed" -- is not completion.
assert ClosedImpliesComplete {
  always all c: Campaign, i: c.members | i not in Open implies complete[i]
}

// 2c. X. The cheapest reading -- "the agent went idle" -- is not completion.
assert IdleImpliesComplete { always all a: Agent | a.st = Idle implies complete[a.task] }

// 3a. PASS. Index totality: no member is missing from the index.
assert IndexCoversMembers { always all c: Campaign | c.members in idx[c] }

// 3b. PASS. Index exactness: the index holds nothing but members.
assert IndexExact { always all c: Campaign | c.members = idx[c] }

// 3c. PASS. Exactness when no member is ever removed -- isolates noise from
// staleness.
assert IndexExactStableMembership {
  (always Now.ev != RemoveMember) implies (always all c: Campaign | c.members = idx[c])
}

/* 4. PASS. Machine independence: deleting a local directory changes no fact
   another machine reads. This is the claim that lets the directory be optional
   and lets two machines hold the same campaign under directory names that
   differ only in date: neither is authoritative, so nothing has to agree. */
assert MachineIndependence {
  always (Now.ev = DeleteDir implies
    (githubFrame and all c: Campaign, m: Machine - Now.evMachine | (m in c.dirs iff m in c.dirs')))
}

// 5. PASS. Reconstitution: from the anchor alone, member repos and open
// subtasks are recoverable.
assert Reconstitution {
  always all c: Campaign |
    c.members.home = idx[c].home and (c.members & Open) = (idx[c] & Open)
}

/* 6. X. No orphan: no agent is live on a checkout whose campaign directory is
   gone. Nothing enforces "no campaign closes while an agent is live under its
   tree".

   The counterexample, and it is the reason the rule is stated as a local check
   with its blind spot named: two machines hold campaign #N; an agent is live on
   machine 0; the operator on machine 1 deletes its tree. "No campaign closes
   while an agent is live under its tree" is a local check blind to the other
   machine. Enforcing it, plus refusing to drop a member an agent is working,
   makes 6b pass -- nothing enforces either today. */
pred noOrphanNow { all a: Agent | a.st = Live implies (some c: Campaign | a.task in c.members and a.host in c.dirs) }

assert NoOrphan { always noOrphanNow }

// 6b. PASS. Same, assuming the design's stated retirement rule is actually
// enforced.
assert NoOrphanIfGuarded {
  ((always (Now.ev = DeleteDir implies (no a: Agent | a.st = Live and a.host = Now.evMachine)))
   and (always (Now.ev = RemoveMember implies (no a: Agent | a.st = Live and a.task = Now.evIssue))))
  implies (always noOrphanNow)
}

// 7a. X. Termination, as designed: nothing forces progress.
assert Termination {
  (eventually always Now.ev != AddMember) implies
    (eventually all c: Campaign, i: c.members | complete[i])
}

/* Weak fairness: whenever some progress event is enabled on a member issue,
   one eventually fires. It says nothing when nothing is enabled. */
pred progressEnabled {
  some i: Campaign.members |
    (i in Open and no i.pr)                 -- an agent could open a PR
    or (some i.pr and i.pr not in Merged)   -- the PR could be merged
    or i in Open                            -- the issue could be closed
}
pred weakFairness { always (progressEnabled implies eventually Now.ev in OpenPR + MergePR + CloseIssue) }

/* 7b. X, and this counterexample changed the design. A member closed without a
   merged pull request never reads complete, so the campaign never becomes
   closable: closed-and-merged cannot say "dropped". AGENTS.md answers it by
   reading settlement both ways -- closed as completed, or closed as not planned
   -- and 7d below is that reading, checked. */
assert TerminationUnderFairness {
  ((eventually always Now.ev != AddMember)
   and weakFairness)
  implies (eventually all c: Campaign, i: c.members | complete[i])
}

// 7c. PASS. Termination under fairness AND a close-discipline: an issue is
// closed only by a merged PR.
assert TerminationDisciplined {
  ((eventually always Now.ev != AddMember)
   and (always (Now.ev = CloseIssue implies (some Now.evIssue.pr and Now.evIssue.pr in Merged)))
   and (always Now.ev != RemoveMember)
   and weakFairness)
  implies (eventually all c: Campaign, i: c.members | complete[i])
}

// 7d. PASS. Termination under the settlement the design actually adopted. 7b fails
// because a subtask closed as not planned never reads complete; read both ways,
// the same traces terminate. This is the repair AGENTS.md states, checked.
assert TerminationUnderSettlement {
  ((eventually always Now.ev != AddMember)
   and weakFairness)
  implies (eventually all c: Campaign, i: c.members | settled[i])
}

/* Control for 7d, SAT: settlement is strictly weaker than completion at these
   bounds. Without a reachable member that settles with no pull request at all,
   7d would be 7b with a synonym rather than an answer to it. */
run SettledWithoutMerge { eventually (some i: Campaign.members | settled[i] and no i.pr) }
                             for 4 Issue, 3 PR, 2 Campaign, 2 Machine, 2 Agent, 3 Repo, 6 steps

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
check TerminationUnderSettlement for 3 Issue, 2 PR, 1 Campaign, 1 Machine, 1 Agent, 2 Repo, 10 steps
