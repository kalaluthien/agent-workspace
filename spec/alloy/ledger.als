/*
 * The campaign's record on GitHub -- and the entry point to spec/.
 *
 *
 * ORIENTATION
 *
 * spec/ is Alloy and nothing else. One Alloy file is one conceptual module: its
 * SYSTEM part is the design of the script, skill or agent that implements it,
 * and its SCENARIOS part is the design of that module's tests. What a model
 * checks is stated in its own comments, next to the construct that checks it. A
 * spec written beside a model drifts from it; a spec written in the model file
 * cannot.
 *
 * Four layers, each opening the one below, so the composed model is the top file
 * and there is no fifth integration file:
 *
 *   ledger.als    issues, the sub-issue index, settlement, the anchor body   34
 *   repos.als     a member repository from one machine and on its remote    18
 *   session.als   a campaign session, several at once                       24
 *   agent.als     the executor: launch, the four messages, retirement       43
 *
 * (the trailing number is that file's command count; 119 in all)
 *
 *   agent -> session -> repos -> ledger
 *
 * Each file runs on its own and each carries its own verdict table:
 *
 *   alloy exec -f -o /tmp/alloy-ledger -t text -c '*' spec/alloy/ledger.als
 *
 * A raw trace repeats every static signature in every state; condense it:
 *   scripts/alloy-trace-digest /tmp/alloy-ledger/Sanity-solution-0.txt
 *
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
 * knows the fact, with a disjunct in each layer above that adds to it. The rule:
 * the lower layer owns the fact and the primitive event, the upper layer owns
 * the actor and the guard. `WriteBody` here is the primitive -- it says only
 * that one campaign's `## Repos` list is overwritten -- and session.als's `sync`
 * says whose README it was overwritten from. The primitive stays loose on
 * purpose, so the refinement above it is satisfiable together with it.
 *
 * Observer fields follow the same rule. This layer's `Now` carries the event and
 * the issue it is about; each layer above adds its own `one sig` observer for
 * the arguments it introduces (repos: `Site`, session: `By`, agent: `Target`),
 * so no layer declares a field over a signature it does not own.
 *
 *
 * STATUS
 *
 * First design, 2026-08-28; restructured into layers the same day. Campaign #1
 * is exercising it as it is written -- a smoke test, a protocol test and an e2e
 * drill have each contradicted a rule here, and each correction is folded into
 * the model rather than kept as an erratum.
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
 *   Branch        campaign-<N>/<issue>-<topic>. The campaign number stops two
 *                 campaigns working one repository from colliding on the
 *                 remote, and it tells a reviewer which campaign a branch came
 *                 from; the subtask's issue number separates subtasks within a
 *                 campaign, which only matters once several sessions hold it at
 *                 once.
 *   Display name  the anchor issue's title, in the person's own words.
 *
 * The directory name is a local convenience; the ID is the identity.
 * repos.als's MachineIndependence is that claim checked.
 *
 *
 * THIS LAYER
 *
 * Everything about a campaign that survives the machine: the issues, the pull
 * requests, the sub-issue index, and the anchor issue's body. It mentions no
 * machine, no session and no agent, which is why every verdict below reads the
 * same from any of them.
 *
 *   event         performed by
 *   FileAnchor    gh issue create -R kalaluthien/agent-workspace --label campaign
 *                 (opening-campaign step 3)
 *   AddMember     gh issue create -R <owner/repo> --parent <anchor url>
 *   RemoveMember  gh issue edit <n> -R <owner/repo> --remove-parent
 *   OpenPR        gh pr create --body "Closes #<n>"
 *   MergePR       gh pr merge --squash --delete-branch
 *   CloseIssue    gh issue close <n>, or the merge that closes it
 *   WriteBody     gh issue edit <N> --body-file (closing-campaign step 4)
 *
 * The reader is scripts/campaign-settlement <N>, which is the one
 * implementation of `settled` below: it prints one line per subtask --
 * complete, dropped, or open -- then whether the campaign is closable.
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
 * X is a counterexample; a check that passes reads UNSAT, and a run that finds
 * a witness reads SAT. Each row is restated beside its own command below; this
 * is the inventory, not the explanation. Measured 2026-08-28 against this file.
 *
 *   ClosedImpliesComplete            X     closed is not completed
 *   IndexCoversMembers               pass  no member is missing from the index
 *   IndexExact                       pass  the index holds nothing but members
 *   IndexExactStableMembership       pass
 *   Reconstitution                   pass  the anchor alone recovers the campaign
 *   Termination                      X     nothing forces progress
 *   TerminationUnderFairness         X     closed-and-merged cannot say "dropped"
 *   TerminationDisciplined           pass
 *   TerminationUnderSettlement       pass  the reading AGENTS.md adopted
 *   SettledWithoutMerge              SAT   control: settlement is weaker
 *   Sanity                           SAT
 *   S1_HappyPath                     SAT
 *   S2_SubtaskDropped                SAT
 *   S5_FollowUpAfterSettled          SAT
 *   S6_RepoJoinsMidFlight            SAT
 *   S8_CloseWithOpenSubtask          SAT
 *   S10_SubtaskMovedOut              SAT
 *   S11_MergedButIssueLeftOpen       SAT
 *   S12_TwoCampaignsOneRepo          SAT
 *   S13_ReopenAfterMerge             UNSAT the finding: no reopen after a PR
 *   S13a_ControlCompletes            SAT
 *   S13b_ReopenAnyClosed             SAT
 *   S13c_ReopenWithPR                UNSAT the actual blocker
 *   S14_FollowUpAfterClose           SAT
 *   S16a_ContainerMemberUnderNarrowReading  UNSAT the narrow reading forbade it
 *   S18_PlainContainerIssue          SAT   the tracker's third kind exists
 *   S18a_PlainContainerIssueUnderClosedWorld  UNSAT control: the clause bites
 *   Cov_*                            SAT   every own event fires in some trace
 *
 * Every pass was proved able to fail by mutation, re-run 2026-08-29 against
 * this model as it now stands -- all four mutations, all seven checks red:
 * dropping `addMember`'s sub-issue write reddens all four index and
 * reconstitution checks; removing `TerminationDisciplined`'s close-discipline
 * clause reddens it; dropping `weakFairness` reddens TerminationUnderSettlement.
 * `ledgerFrame` in the fall-through branch of `ledgerStep` is proved
 * load-bearing from above -- dropping it reddens repos.als's
 * MachineIndependence and agent.als's NoLostWork, which is the composition
 * idiom itself under test.
 *
 * The date is part of the claim. This file changed after the 2026-08-28 run --
 * the container clause left `WellFormed`, and S18/S18a arrived -- so the proof
 * was carried out again rather than inherited: a mutation score is about the
 * model in front of you, and an older one silently claims something about a
 * model that no longer exists.
 *
 * WHAT MOVED, AND WHAT CHANGED WITH IT
 *
 * The four termination assertions carry a premise their predecessors did not
 * need: `some Campaign.members`. The old `init` asserted it as a fact, because
 * that model started with a campaign already in flight. This layer's `init` also
 * admits the empty world an unfiled campaign starts from -- session.als needs it
 * to file an anchor at all -- and in that world "all members are complete" is
 * vacuously true at time zero, which would turn the two counterexamples into
 * passes. The premise restores exactly the old hypothesis. All four verdicts
 * reproduce.
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
 *   indexed forever and the anchor reconstitutes a growing superset: IndexExact,
 *   IndexExactStableMembership and Reconstitution all red.
 *
 *   B -- a checklist of member issues in the anchor body. The index entry is a
 *   second write to a different object and may simply not happen, which loses
 *   the issue with nothing anywhere to contradict it. The only scheme where
 *   IndexCoversMembers was red, and the only silent total loss of the four.
 *
 *   C -- a `campaign-<N>` label on every member issue. Correct on totality and
 *   on staleness, but the label object must be created per repository before an
 *   issue there can carry it, and removing a subtask leaves the label behind as
 *   a stale mark: IndexExact red.
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
 * No construct in any of the four layers exercises these. Modelling them was
 * weighed and is not worth it -- each is a fact about text, a platform's timing,
 * or another tool's internals rather than a property of the lifecycle.
 *
 * Text well-formedness, `gh` latency and search-index consistency, herdr's
 * liveness derivation, issues in repositories the reader's token cannot see, the
 * delegation mechanics (--append-system-prompt-file, the canary, the 1024-byte
 * launch line, all of which live in agent.als's header), and whether a merged
 * pull request does what was asked.
 *
 * Adequacy in general. A merged pull request that does not do what was asked
 * reads complete in every row. Verifying that the work exists is not reviewing
 * it.
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
 * differ. Nothing breaks -- repos.als's MachineIndependence is exactly that --
 * but a person reading two listings sees two names for one thing.
 */
module ledger

/* ==================== SYSTEM ==================== */

/* ---------------- static structure ---------------- */

sig Repo {}
one sig Container extends Repo {}

sig PR {}

sig Issue {
  home:   one Repo,
  var pr: lone PR               -- the pull request that would close this issue
}

sig Campaign {
  anchor:      one Issue,       -- the anchor issue in the container repo; the campaign ID
  var members: set Issue,       -- ground truth: the subtasks that belong to the campaign
  var sub:     set Issue,       -- the index: GitHub's native sub-issue link
  var body:    set Repo         -- the anchor issue body's `## Repos` list
}

var sig Open   in Issue {}      -- issues currently open on GitHub
var sig Merged in PR {}         -- pull requests currently merged
var sig Filed  in Campaign {}   -- the anchor issue exists on GitHub

fact WellFormed {
  all c: Campaign | c.anchor.home = Container
  all disj c1, c2: Campaign | c1.anchor != c2.anchor
  always all p: PR | lone pr.p
  always all i: Issue | some i.pr implies i.pr' = i.pr    -- a PR link is never undone
  always all c: Campaign | c.anchor not in c.members
  always all disj c1, c2: Campaign | no c1.members & c2.members
  always all p: PR | p in Merged implies some pr.p
}

/* Completion is a GitHub fact and mentions no agent.

   The old workspace asked a delegate to print `DONE <name>` and grepped for it.
   That conflates completion with liveness and is fragile in both: a pane can
   show the word and have finished nothing, and a delegate can finish and have
   its line scrolled away. Splitting them is the point -- completion is read
   from GitHub, survives the delegate's death, the pane's death and the
   machine's reboot, and reads the same from a phone; liveness is a herdr fact
   and appears nowhere in this layer. ClosedImpliesComplete below is the cheaper
   reading, refuted; the cheapest -- "the agent said so" -- is refuted in
   agent.als, which is the only layer that has an agent to say it. */
pred complete[i: Issue] { i not in Open and some i.pr and i.pr in Merged }

/* Settlement, the reading AGENTS.md adopted after TerminationUnderFairness
   below: a subtask is settled when its issue is closed, either as completed or
   as dropped -- closed as not planned, with no merged pull request behind it.
   Completion alone has no way to say "dropped", which is what that
   counterexample is. */
pred dropped[i: Issue] { i not in Open and not complete[i] }
pred settled[i: Issue] { complete[i] or dropped[i] }

/* The GitHub half of a close decision. The other half -- that no agent is live
   under the campaign's tree -- is agent.als's, because it is the only layer
   with an agent in it. */
pred closable[c: Campaign]      { all i: c.members | settled[i] }
pred campaignClosed[c: Campaign] { c.anchor not in Open }

/* The design's close rule, as a trace constraint: the anchor is closed only
   from a closable state. S8 is what happens without it. */
pred closeDiscipline[c: Campaign] {
  always ((Now.ev = CloseIssue and Now.issue = c.anchor) implies closable[c])
}

/* Realism: on GitHub a subtask issue is closed by its merged pull request. A
   trace that closes first and merges later satisfies `settled` the whole way
   and is not the path anyone runs, so the scenarios that mean "merged" say so. */
pred mergeClosed[s: set Issue] {
  always (all i: s | (Now.ev = CloseIssue and Now.issue = i)
                     implies (some i.pr and i.pr in Merged))
}

/* THE CLAUSE THAT WAS A FACT TWICE, and is a scenario predicate now.

   It says: an issue homed on the container belongs to some campaign, as an
   anchor or as a member. As a global fact it sprang the same trap twice.

   First it read `implies i in Campaign.anchor` -- every container-homed issue
   must BE an anchor -- which forbade the container being a member of its own
   campaign while still permitting the odd case of one campaign's anchor being
   another's member, so a coarse probe read SAT and hid it. Widened 2026-08-28.

   Then, widened, it still carried no `always`, so it was read at the initial
   state and demanded that a container-homed subtask ALREADY be a member --
   which `addMember` refuses. That made a container-homed subtask unfilable in
   any trace that also files its campaign, and that is exactly the campaign with
   no member repository: the container tracker is the only place its subtasks
   can go. session.als's R4 is UNSAT against that form and SAT without it.

   Both were the model contradicting the design, and the third reading is not
   worth guessing at: AGENTS.md says the container's tracker holds THREE kinds
   of issue -- anchors, subtasks, and a person's request or somebody else's bug
   that no campaign flow touches. A global fact cannot admit the third kind and
   still say anything, so this stops being one. It is stated here, conjoined by
   the scenarios that actually depend on a closed world of campaign issues, and
   `containerIsAnchorOnly` below keeps the original narrow reading runnable
   beside it. */
pred containerIssuesAreCampaignIssues {
  all i: Issue | i.home = Container implies (i in Campaign.anchor or eventually i in Campaign.members)
}

/* D's original reading, kept runnable so the widenings above stay visible. */
pred containerIsAnchorOnly { always all i: Issue | i.home = Container implies i in Campaign.anchor }

fun campaignOf[i: Issue]: lone Campaign { members.i }
fun anchorOf[i: Issue]: lone Campaign { anchor.i }

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

/* ---------------- observable events ---------------- */

abstract sig Event {}
one sig Stutter, FileAnchor, AddMember, RemoveMember,
        OpenPR, MergePR, CloseIssue, WriteBody extends Event {}

/* This layer's observer. Every layer above adds its own for the arguments it
   introduces, and none of them touches these two fields except to name the
   issue its own event is about. */
one sig Now {
  var ev:    one Event,
  var issue: lone Issue
}

fun ledgerEvents: set Event {
  FileAnchor + AddMember + RemoveMember + OpenPR + MergePR + CloseIssue + WriteBody
}

pred ledgerFrame {
  Open' = Open and Merged' = Merged and pr' = pr
  and members' = members and sub' = sub and body' = body and Filed' = Filed
}

/* opening-campaign step 3: the anchor issue is created, labelled `campaign`. */
pred fileAnchor[c: Campaign] {
  c not in Filed
  no c.members and no c.sub and no c.body
  Filed' = Filed + c
  Open'  = Open + c.anchor
  members' = members and sub' = sub and body' = body
  Merged' = Merged and pr' = pr
  Now.ev = FileAnchor and Now.issue = c.anchor
}

/* `gh issue create --parent`: the issue and its index entry are one write. */
pred addMember[c: Campaign, i: Issue] {
  c in Filed
  i not in Campaign.members and i not in Campaign.anchor
  i not in Open and no i.pr
  members' = members + c->i
  sub'     = sub + c->i
  Open'    = Open + i
  Merged' = Merged and pr' = pr and body' = body and Filed' = Filed
  Now.ev = AddMember and Now.issue = i
}

/* `gh issue edit <n> --remove-parent`: the index prunes with the membership. */
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

/* Nothing in the design forbids closing an issue whose PR never merged. */
pred closeIssue[i: Issue] {
  i in Open
  Open' = Open - i
  Merged' = Merged and pr' = pr
  members' = members and sub' = sub and body' = body and Filed' = Filed
  Now.ev = CloseIssue and Now.issue = i
}

/* THE PRIMITIVE, and it is deliberately loose: one campaign's `## Repos` list
   is overwritten with something, and nothing else in the ledger moves. What it
   is overwritten WITH is not this layer's business -- session.als's `sync` says
   it came from that session's README, and the two are satisfiable together
   precisely because this one does not pin the value. */
pred writeBody[c: Campaign] {
  c in Filed
  body' - c->Repo = body - c->Repo         -- only c's list may change
  Open' = Open and Merged' = Merged and pr' = pr
  members' = members and sub' = sub and Filed' = Filed
  Now.ev = WriteBody and no Now.issue
}

pred stutter {
  ledgerFrame
  Now.ev = Stutter and no Now.issue
}

/* The world this layer admits at time zero: a campaign already in flight, an
   unfiled campaign with nothing yet, or any mixture. The looser of the two
   starting worlds the old models used, because session.als has to be able to
   file an anchor and the e2e scenarios have to be able to start with one
   already filed. */
pred init {
  no Merged
  no pr
  all c: Campaign - Filed | no c.members and no c.sub and no c.body
  Open = Filed.anchor + Campaign.members
  all c: Campaign | c.sub = c.members
}

pred ledgerStep {
  stutter
  or (some c: Campaign | fileAnchor[c] or writeBody[c])
  or (some c: Campaign, i: Issue | addMember[c,i] or removeMember[c,i])
  or (some i: Issue | openPR[i] or mergePR[i] or closeIssue[i])
  /* An event declared in a layer above: this layer frames its own state and
     says nothing about the observer fields that layer owns. */
  or (Now.ev not in Stutter + ledgerEvents and ledgerFrame)
}

fact Trace { init and always ledgerStep }

/* ==================== SCENARIOS ==================== */

/* ---------------- properties ---------------- */

// X. The cheaper reading -- "the issue is closed" -- is not completion.
assert ClosedImpliesComplete {
  always all c: Campaign, i: c.members | i not in Open implies complete[i]
}

// PASS. Index totality: no member is missing from the index.
assert IndexCoversMembers { always all c: Campaign | c.members in idx[c] }

// PASS. Index exactness: the index holds nothing but members.
assert IndexExact { always all c: Campaign | c.members = idx[c] }

// PASS. Exactness when no member is ever removed -- isolates noise from
// staleness.
assert IndexExactStableMembership {
  (always Now.ev != RemoveMember) implies (always all c: Campaign | c.members = idx[c])
}

// PASS. Reconstitution: from the anchor alone, member repos and open subtasks
// are recoverable.
assert Reconstitution {
  always all c: Campaign |
    c.members.home = idx[c].home and (c.members & Open) = (idx[c] & Open)
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

/* The four termination claims share one hypothesis: a campaign that has work in
   it. `init` here also admits the empty world session.als files an anchor from,
   and in that world the conclusion is vacuously true at time zero, so the
   premise is what keeps the two counterexamples counterexamples. */
pred hasWork { some Campaign.members }

// X. Termination, as designed: nothing forces progress.
assert Termination {
  (hasWork and (eventually always Now.ev != AddMember)) implies
    (eventually all c: Campaign, i: c.members | complete[i])
}

/* X, and this counterexample changed the design. A member closed without a
   merged pull request never reads complete, so the campaign never becomes
   closable: closed-and-merged cannot say "dropped". AGENTS.md answers it by
   reading settlement both ways -- closed as completed, or closed as not planned
   -- and TerminationUnderSettlement below is that reading, checked. */
assert TerminationUnderFairness {
  (hasWork
   and (eventually always Now.ev != AddMember)
   and weakFairness)
  implies (eventually all c: Campaign, i: c.members | complete[i])
}

// PASS. Termination under fairness AND a close-discipline: an issue is
// closed only by a merged PR.
assert TerminationDisciplined {
  (hasWork
   and (eventually always Now.ev != AddMember)
   and (always (Now.ev = CloseIssue implies (some Now.issue.pr and Now.issue.pr in Merged)))
   and (always Now.ev != RemoveMember)
   and weakFairness)
  implies (eventually all c: Campaign, i: c.members | complete[i])
}

// PASS. Termination under the settlement the design actually adopted.
// TerminationUnderFairness fails because a subtask closed as not planned never
// reads complete; read both ways, the same traces terminate. This is the repair
// AGENTS.md states, checked.
assert TerminationUnderSettlement {
  (hasWork
   and (eventually always Now.ev != AddMember)
   and weakFairness)
  implies (eventually all c: Campaign, i: c.members | settled[i])
}

/* ---------------- witnesses ---------------- */

/* Control for TerminationUnderSettlement, SAT: settlement is strictly weaker
   than completion at these bounds. Without a reachable member that settles with
   no pull request at all, that assertion would be TerminationUnderFairness with
   a synonym rather than an answer to it. */
pred SettledWithoutMerge { eventually (some i: Campaign.members | settled[i] and no i.pr) }

pred Sanity { eventually (some Merged and some i: Issue | complete[i]) }

/* Each scenario below is a witness request: read the trace as a script. Every
   one is judged by one observable, and it is always GitHub:
 *
 *     scripts/campaign-settlement <anchor-number> [owner/repo]
 *
 * Nothing on a terminal screen counts, which is the rule these scenarios exist
 * to exercise. Each write-up names where it can run:
 *   real      safe against repositories you care about; it writes nothing you
 *             would not write anyway
 *   fixture   needs the throwaway repositories below; it merges, mangles a
 *             close, or destroys a workspace
 *   blocked   cannot be run as written -- see the scenario
 *
 *
 * THE FIXTURE
 *
 * The anchor goes in the real container repository, because the campaign ID IS
 * a container issue number and a drill with a fake ID exercises nothing. The
 * member repositories are throwaway, because most scenarios end in a merged
 * pull request or a deliberately mangled close.
 *
 *   gh repo create <you>/e2e-fixture-a --private --add-readme
 *   gh repo create <you>/e2e-fixture-b --private --add-readme
 *   TITLE="Drill: e2e scenarios"
 *   gh issue create -R kalaluthien/agent-workspace --title "$TITLE" \
 *     --body "Drill anchor. Close when done."
 *   ANCHOR=$(gh issue list -R kalaluthien/agent-workspace \
 *     --search "$TITLE in:title" --limit 1 --json number --jq '.[0].number')
 *
 * Every subtask is created as a sub-issue in one command -- the whole index:
 *
 *   gh issue create -R <you>/e2e-fixture-a \
 *     --parent https://github.com/kalaluthien/agent-workspace/issues/$ANCHOR \
 *     --title "..." --body "Campaign: kalaluthien/agent-workspace#$ANCHOR"
 *
 * Tear down with `gh issue close $ANCHOR -R kalaluthien/agent-workspace` and
 * `gh repo delete <you>/e2e-fixture-{a,b}`.
 */

/* The plain path: two repositories, two subtasks, both settled by merge, then
   the campaign closes. */
/* FOR REAL -- fixture. Create two subtasks, one per fixture repo. In each:
   branch campaign-$ANCHOR/<n>-<topic> for subtask <n>, one commit, `git push -u
   origin`, `gh pr create --body "Closes #<n>"`, `gh pr merge --squash
   --delete-branch`. Then `scripts/campaign-settlement $ANCHOR`.
   PASS: both rows read `complete` and the listing says `closable`. Close the
   anchor only after that line -- that ordering IS the design's close rule. */
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

/* One subtask dropped -- closed as not planned, no pull request ever -- and the
   campaign still reaches closable. */
/* FOR REAL -- fixture. As S1 for the first subtask. For the second, open no pull
   request at all and run `gh issue close <n> -R <repo> --reason "not planned"`.
   PASS: one row `complete`, one `dropped`, and `closable` still reached. This
   is the case TerminationUnderFairness says closed-and-merged alone cannot
   express. */
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

/* A follow-up subtask arrives after everything else settled, so the campaign
   re-opens work instead of closing. */
/* FOR REAL -- real. Take a campaign whose listing reads `closable` and do NOT
   close the anchor. Create one more sub-issue with `--parent`. Re-run the
   script.
   PASS: the settled count falls below the total -- the campaign went back to
   work instead of closing. */
pred S5_FollowUpAfterSettled {
  one c: Campaign {
    #c.members = 1
    mergeClosed[Issue - c.anchor]
    always Now.ev != RemoveMember          -- no emptying the campaign to fake "all settled"
    some i1: c.members, i2: Issue - c.members - c.anchor {
      -- the first subtask is complete and the campaign has not closed; then the
      -- follow-up lands and the campaign has open work again
      eventually (complete[i1] and c.anchor in Open
                  and Now.ev = AddMember and Now.issue = i2)
      eventually (i2 in c.members and not settled[i2])
      eventually complete[i2]
    }
    closeDiscipline[c]
    eventually (closable[c] and campaignClosed[c])
  }
}

/* A repository joins the campaign mid-flight: the added subtask's home is a
   repository no existing member lives in. */
/* FOR REAL -- real. As S5, but file the new subtask in a repository no existing
   subtask lives in, and clone it into `<campaign>/repos/<repo>/`.
   PASS: the listing shows a second `owner/repo` prefix and the anchor's
   `## Repos` section is updated to match. The listing is the index; `Repos` is
   only the clone list, so a mismatch between them is the defect to look for. */
pred S6_RepoJoinsMidFlight {
  one c: Campaign {
    #c.members = 1
    #(c.members.home) = 1
    mergeClosed[Issue - c.anchor]
    always Now.ev != RemoveMember
    eventually (Now.ev = AddMember
                and Now.issue not in c.members
                and Now.issue.home not in c.members.home)
    eventually (#c.members = 2 and #(c.members.home) = 2
                and (all i: c.members | complete[i]))
  }
}

/* The campaign is closed with a subtask still open. The model allows it --
   nothing guards the anchor's close -- so a real run must report it. */
/* FOR REAL -- fixture. Settle one subtask, leave the other open, then
   `gh issue close $ANCHOR -R kalaluthien/agent-workspace`.
   PASS: the script prints `REPORT: the anchor is closed with subtasks still
   open`. Nothing prevents the close -- the point is that the report exists, not
   that the close is blocked. Fixture only: an anchor closed over live work is a
   mess to explain on a real campaign. */
pred S8_CloseWithOpenSubtask {
  one c: Campaign {
    #c.members = 2
    always Now.ev not in AddMember + RemoveMember
    mergeClosed[c.members]
    some disj i1, i2: c.members |
      eventually (Now.ev = CloseIssue and Now.issue = c.anchor
                  and complete[i1] and i2 in Open)
    eventually (campaignClosed[c] and (some i: c.members | i in Open))
  }
}

/* A subtask is moved out of the campaign. The sub-issue index prunes with it,
   so the index equals membership before and after. */
/* FOR REAL -- real. `gh issue edit <n> -R <repo> --remove-parent`.
   PASS: the row disappears from `scripts/campaign-settlement` immediately, and
   the issue itself is untouched. That prunability is the whole reason the
   sub-issue link beat a back-reference line, which can never un-say a mention. */
pred S10_SubtaskMovedOut {
  one c: Campaign {
    #c.members = 2
    mergeClosed[c.members]
    always Now.ev != AddMember
    some disj i1, i2: c.members {
      always (Now.ev = RemoveMember implies Now.issue = i2)   -- exactly one moves out
      eventually (Now.ev = RemoveMember and Now.issue = i2)
      eventually complete[i1]
      eventually c.members = i1
    }
    always (all d: Campaign | d.members = idx[d])             -- the index prunes with it
    closeDiscipline[c]
    eventually (closable[c] and campaignClosed[c])
  }
}

/* The pull request merged but nobody closed the issue -- a missing
   "Closes #N". The subtask never reads complete and the campaign never becomes
   closable, with nothing on screen to say so. */
/* FOR REAL -- fixture. Open a pull request whose body omits `Closes #<n>`,
   merge it, and leave the issue open.
   PASS: the row reads `open` while `gh pr view <p> --json state` reads MERGED.
   The failure this drills is silent -- the campaign simply never becomes
   closable, with nothing anywhere saying why. */
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

/* Two campaigns work the same repository at once. Both settle; neither touches
   the other's members. This is what the campaign-<N>/ branch rule buys. */
/* FOR REAL -- real. Open two anchors, each with one subtask in the same fixture
   repository, on branches campaign-<N1>/... and campaign-<N2>/... . Merge both.
   PASS: each anchor's listing shows only its own subtask, and the two branches
   never collided on the remote. Real-safe, and the reason the branch naming
   rule carries the campaign number. */
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

/* Review feedback on a merged subtask: the issue is reopened after it read
   complete. UNSAT, and the controls below pin why -- not a bound artifact.
   Reopening a closed issue is reachable (S13b, via remove-then-re-add), but only
   for an issue that never had a pull request: `addMember` guards on `no i.pr`,
   and `WellFormed` never undoes a pr link. So any issue that ever had a PR is
   closed forever (S13c, UNSAT). */
/* FOR REAL -- blocked, and the block is the finding. GitHub has no such
   restriction that this machine's `gh` documents: `gh issue reopen <n>` takes
   only an optional comment and names no condition about a closing pull request
   (`gh issue reopen --help`, gh 2.96.0). NOT VERIFIED BY A WRITE -- the
   one-line probe is `gh issue reopen <n> -R <fixture-repo>` on an issue closed
   by a merged pull request, and it needs a fixture repository and permission to
   write. Until it is run, treat "GitHub permits it" as a hypothesis. If it
   holds, the model -- not the design -- is what needs a reopen event, and
   "review feedback gets a fresh session" is the design's answer to a case the
   model cannot state. */
pred S13_ReopenAfterMerge {
  one c: Campaign | some i: c.members {
    eventually complete[i]
    eventually (complete[i] and after (i in Open))
  }
}

/* Controls for the UNSAT above. An UNSAT is a finding only if the same bounds
   admit the pieces separately. S13a: completion is reachable here (SAT).
   S13b: a closed issue can reopen, and the event that reopens it is the
   re-add, not the anchor filing this layer's wider `init` also admits (SAT).
   S13c: one that ever had a pull request cannot (UNSAT) -- that is the actual
   blocker. */
pred S13a_ControlCompletes { some i: Campaign.members | eventually complete[i] }
pred S13b_ReopenAnyClosed  {
  some i: Issue | eventually (i not in Open and Now.ev = AddMember and Now.issue = i
                              and after (i in Open))
}
pred S13c_ReopenWithPR     { some i: Issue | eventually (some i.pr and i not in Open and after (i in Open)) }

/* A follow-up subtask arrives after the anchor was already closed. Nothing in
   the design guards the anchor's close against later sub-issues. */
/* FOR REAL -- fixture. Close the anchor legitimately (the listing reads
   `closable`), then create a new sub-issue with `--parent` pointing at the
   closed anchor.
   PASS: the command succeeds and the listing shows a closed anchor with an
   `open` subtask. Nothing in the design guards against this, so it is worth
   knowing it is reachable before a real campaign does it by accident. */
pred S14_FollowUpAfterClose {
  one c: Campaign {
    #c.members = 1
    mergeClosed[Issue - c.anchor]
    always Now.ev != RemoveMember
    closeDiscipline[c]                     -- the anchor closed legitimately
    some i2: Issue - c.members - c.anchor {
      eventually (campaignClosed[c] and Now.ev = AddMember and Now.issue = i2)
      eventually (campaignClosed[c] and i2 in c.members and i2 in Open and not settled[i2])
    }
  }
}

/* Under the narrow reading, the container cannot be a member of its own
   campaign at all: a container-homed issue must BE the anchor. UNSAT, and that
   is the finding -- the model forbade what was about to happen for real. The
   rest of that scenario, the two checkouts and their hazards, is repos.als's,
   because it is about a machine. */
pred S16a_ContainerMemberUnderNarrowReading {
  containerIsAnchorOnly
  some c: Campaign, i: c.members | i.home = Container
}

/* S18 -- numbered past S17c because S16b and S16c are repos.als's, and the
   four files share one S-sequence once they are composed.

   THE THIRD KIND. AGENTS.md says the container's tracker holds anchors,
   subtasks, and issues no campaign flow touches at all -- a person's request,
   somebody else's bug -- and says every reader leaves that third kind alone. So
   the model has to admit one. It did not while
   `containerIssuesAreCampaignIssues` was a clause of WellFormed: an issue that
   never joins a campaign was UNSAT at any bound, and no verdict said so, which
   is how the same clause trapped the design twice. SAT now. */
pred S18_PlainContainerIssue {
  some i: Issue | i.home = Container and always (i not in Campaign.anchor + Campaign.members)
}

/* S18a. Control for S18, and the reason the clause is kept rather than
   deleted: conjoined as a predicate it still says exactly what it always said,
   so a scenario that wants a closed world of campaign issues can still ask for
   one. UNSAT, which is S18 forbidden on purpose rather than by accident. */
pred S18a_PlainContainerIssueUnderClosedWorld {
  containerIssuesAreCampaignIssues and S18_PlainContainerIssue
}

/* ---------------- reachability floor ----------------
 * Every event this layer owns fires in some trace. An event no trace can reach
 * would silently remove a whole question from the commands above, and an
 * over-tight frame is the cheapest way to make that happen without any command
 * turning red.
 */
pred Cov_FileAnchor   { eventually Now.ev = FileAnchor }
pred Cov_AddMember    { eventually Now.ev = AddMember }
pred Cov_RemoveMember { eventually Now.ev = RemoveMember }
pred Cov_OpenPR       { eventually Now.ev = OpenPR }
pred Cov_MergePR      { eventually Now.ev = MergePR }
pred Cov_CloseIssue   { eventually Now.ev = CloseIssue }
pred Cov_WriteBody    { eventually Now.ev = WriteBody }

/* ---------------- commands ---------------- */

check ClosedImpliesComplete      for 4 Issue, 3 PR, 2 Campaign, 3 Repo, 6 steps
check IndexCoversMembers         for 4 Issue, 3 PR, 2 Campaign, 3 Repo, 6 steps
check IndexExact                 for 4 Issue, 3 PR, 2 Campaign, 3 Repo, 6 steps
check IndexExactStableMembership for 4 Issue, 3 PR, 2 Campaign, 3 Repo, 6 steps
check Reconstitution             for 4 Issue, 3 PR, 2 Campaign, 3 Repo, 6 steps
check Termination                  for 3 Issue, 2 PR, 1 Campaign, 2 Repo, 10 steps
check TerminationUnderFairness     for 3 Issue, 2 PR, 1 Campaign, 2 Repo, 10 steps
check TerminationDisciplined       for 3 Issue, 2 PR, 1 Campaign, 2 Repo, 10 steps
check TerminationUnderSettlement   for 3 Issue, 2 PR, 1 Campaign, 2 Repo, 10 steps

run SettledWithoutMerge  for 4 Issue, 3 PR, 2 Campaign, 3 Repo, 6 steps
run Sanity               for 4 Issue, 3 PR, 2 Campaign, 3 Repo, 6 steps

run S1_HappyPath                for exactly 3 Issue, 2 PR, exactly 1 Campaign, exactly 3 Repo, 12 steps
run S2_SubtaskDropped           for exactly 3 Issue, 2 PR, exactly 1 Campaign, exactly 3 Repo, 12 steps
run S5_FollowUpAfterSettled     for exactly 3 Issue, 2 PR, exactly 1 Campaign, exactly 2 Repo, 14 steps
run S6_RepoJoinsMidFlight       for exactly 3 Issue, 2 PR, exactly 1 Campaign, exactly 3 Repo, 14 steps
run S8_CloseWithOpenSubtask     for exactly 3 Issue, 2 PR, exactly 1 Campaign, exactly 3 Repo, 12 steps
run S10_SubtaskMovedOut         for exactly 3 Issue, 2 PR, exactly 1 Campaign, exactly 3 Repo, 12 steps
run S11_MergedButIssueLeftOpen  for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Repo, 8 steps
run S12_TwoCampaignsOneRepo     for exactly 4 Issue, 2 PR, exactly 2 Campaign, exactly 2 Repo, 14 steps
run S13_ReopenAfterMerge        for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Repo, 10 steps
run S13a_ControlCompletes       for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Repo, 10 steps
run S13b_ReopenAnyClosed        for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Repo, 10 steps
run S13c_ReopenWithPR           for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Repo, 10 steps
run S14_FollowUpAfterClose      for exactly 3 Issue, 2 PR, exactly 1 Campaign, exactly 2 Repo, 14 steps
run S16a_ContainerMemberUnderNarrowReading for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 2 Repo, 6 steps
run S18_PlainContainerIssue              for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Repo, 6 steps
run S18a_PlainContainerIssueUnderClosedWorld for exactly 2 Issue, 1 PR, exactly 1 Campaign, exactly 1 Repo, 6 steps

run Cov_FileAnchor   for 4 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps
run Cov_AddMember    for 4 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps
run Cov_RemoveMember for 4 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps
run Cov_OpenPR       for 4 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps
run Cov_MergePR      for 4 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps
run Cov_CloseIssue   for 4 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps
run Cov_WriteBody    for 4 Issue, 2 PR, 2 Campaign, 3 Repo, 8 steps
