/*
 * Everything GitHub carries about a campaign -- and the entry point to spec/.
 *
 * Issues, pull requests, the sub-issue index, the campaign issue body, and the
 * sub-issue branch: that last one is a ref on the remote, readable from any
 * machine, which is what makes it a GitHub fact rather than a local one.
 *
 * ORIENTATION
 *
 * Five entities, each opening the one below, so the composed model is the top
 * file and there is no sixth integration file:
 *
 *   github/     issues, PRs, the sub-issue index, the campaign issue body, the claim
 *   directory/  one campaign's directory on one machine, and the checkouts in it
 *   checkout/   the container's outer checkout and its inner clone, and how far behind
 *   session/    a campaign session: one role, bound to one machine
 *   role/       the role: launch, the four messages, retirement
 *
 * Each entity is three modules, and the split is by what the text is FOR:
 *
 *   <entity>/system.als     signatures, observers, events, frame, trace
 *   <entity>/scenarios.als  the disciplines, and every witness `run`
 *   <entity>/checks.als     every `assert` and `check`, and the reachability floor
 *
 * `scenarios` opens its own `system`; `checks` opens its own `scenarios`. A
 * command declared in an OPENED module is not executed, so running a system
 * module runs nothing and the two siblings are where every command lives.
 *
 * WHAT CHECKS WHAT
 *
 * Every command states its own verdict, in the `expect` clause the solver
 * enforces: `expect 0` where the solver says UNSAT -- a check with no
 * counterexample, a run with no instance -- and `expect 1` where it says SAT.
 * `alloy exec -f -t text -c '*'` on any scenarios or checks module exits
 * non-zero and names each command that came out other than its clause says. No
 * comment restates a verdict, and one that did would be a second reader of
 * what the solver already decided.
 *
 * A command someone DELETES misses no expectation, having none left to miss,
 * and nothing generated from these files can see that either. So the command
 * list is stated a second time, in commands.lock.json beside them, which is
 * committed and compared rather than regenerated:
 *
 *   scripts/alloy-check.py spec/campaign/github/scenarios.als -o /tmp/alloy-github
 *   scripts/alloy-check.py --commands spec/campaign      -- and --write to update
 *   scripts/alloy-check.py --digest /tmp/alloy-github/S1_HappyPath-solution-0.txt
 *
 * HOW THE LAYERS COMPOSE
 *
 * Facts conjoin on `open`, so each entity's `step` is written as
 *
 *   stutter, or one of this entity's own events, or
 *   (the event is none of this entity's and this entity's state is framed)
 *
 * and a lower entity therefore frames its own state automatically whenever an
 * upper entity's event fires. No upper entity ever writes a frame for a lower
 * entity's variables.
 *
 * A cross-entity event is ONE `Event` atom, declared in the lowest entity that
 * knows the fact, with a disjunct in each entity above that adds to it: the
 * lower entity owns the fact and the primitive, the upper entity owns the
 * actor and the guard. The primitive stays loose so the refinement above it is
 * satisfiable together with it. Observer fields follow the same rule -- `Now`
 * here, `Site` in directory, `By` in session, `Target` in role -- so no entity
 * declares a field over a signature it does not own.
 */
module github/system

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
/* The sub-issue branch: a ref on the remote, so one set over Issue rather than
   one set per machine. A claim made on one machine is readable from every
   other, which is the whole reason the branch is the claim. */
var sig Claimed in Issue {}

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

/* The GitHub half. The other -- no role live under the tree -- is
   role/system.als's. */
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
        OpenPR, MergePR, CloseIssue, WriteBody, Claim, Release extends Event {}

one sig Now {
  var ev:    one Event,
  var issue: lone Issue
}

fun githubEvents: set Event {
  FileCampaignIssue + AddMember + RemoveMember + OpenPR + MergePR + CloseIssue + WriteBody
  + Claim + Release
}

pred githubFrame {
  Open' = Open and Merged' = Merged and pr' = pr
  and members' = members and sub' = sub and body' = body and Filed' = Filed
  and Claimed' = Claimed
}

pred fileCampaignIssue[c: Campaign] {
  c not in Filed
  no c.members and no c.sub and no c.body
  Filed' = Filed + c
  Open'  = Open + c.campaignIssue
  members' = members and sub' = sub and body' = body
  Merged' = Merged and pr' = pr
  Claimed' = Claimed
  Now.ev = FileCampaignIssue and Now.issue = c.campaignIssue
}

/* The issue and its index entry are one write. Deliberately no actor, machine
   or binding precondition: filing a sub-issue is a record, not a claim, so any
   session on any machine may do it (AGENTS.md § The binding). The binding
   gates writeBody, BOUND, the claim and the launch, which live in session/system.als
   and the claim script, not here. */
pred addMember[c: Campaign, i: Issue] {
  c in Filed
  i not in Campaign.members and i not in Campaign.campaignIssue
  i not in Open and no i.pr
  members' = members + c->i
  sub'     = sub + c->i
  Open'    = Open + i
  Merged' = Merged and pr' = pr and body' = body and Filed' = Filed
  Claimed' = Claimed
  Now.ev = AddMember and Now.issue = i
}

/* The index prunes with the membership. */
pred removeMember[c: Campaign, i: Issue] {
  i in c.members
  members' = members - c->i
  sub'     = sub - c->i
  Open' = Open and Merged' = Merged and pr' = pr and body' = body and Filed' = Filed
  Claimed' = Claimed
  Now.ev = RemoveMember and Now.issue = i
}

pred openPR[i: Issue] {
  i in Campaign.members and i in Open and no i.pr
  some p: PR - Issue.pr | pr' = pr + i->p
  Open' = Open and Merged' = Merged
  members' = members and sub' = sub and body' = body and Filed' = Filed
  Claimed' = Claimed
  Now.ev = OpenPR and Now.issue = i
}

pred mergePR[i: Issue] {
  some i.pr and i.pr not in Merged
  Merged' = Merged + i.pr
  Open' = Open and pr' = pr
  members' = members and sub' = sub and body' = body and Filed' = Filed
  Claimed' = Claimed
  Now.ev = MergePR and Now.issue = i
}

/* Nothing forbids closing an issue whose pull request never merged. */
pred closeIssue[i: Issue] {
  i in Open
  Open' = Open - i
  Merged' = Merged and pr' = pr
  members' = members and sub' = sub and body' = body and Filed' = Filed
  Claimed' = Claimed
  Now.ev = CloseIssue and Now.issue = i
}

/* Deliberately loose. What the list is overwritten WITH is session/system.als's
   `sync`, satisfiable together with this precisely because this does not pin
   the value. */
pred writeBody[c: Campaign] {
  c in Filed
  body' - c->Repo = body - c->Repo
  Open' = Open and Merged' = Merged and pr' = pr
  members' = members and sub' = sub and Filed' = Filed
  Claimed' = Claimed
  Now.ev = WriteBody and no Now.issue
}

/* Deliberately LOOSE -- it does not require the ref to be absent -- so that
   create-ref's refusal is a named discipline above (role/scenarios.als's
   `claimAtomic`) with its absence runnable as a control. */
pred claim[i: Issue] {
  i in Campaign.members and i in Open
  Claimed' = Claimed + i
  Open' = Open and Merged' = Merged and pr' = pr
  members' = members and sub' = sub and body' = body and Filed' = Filed
  Now.ev = Claim and Now.issue = i
}

/* What may be released is guarded above, in role/scenarios.als: the condition
   is about a role, which this layer does not have. */
pred release[i: Issue] {
  i in Claimed
  Claimed' = Claimed - i
  Open' = Open and Merged' = Merged and pr' = pr
  members' = members and sub' = sub and body' = body and Filed' = Filed
  Now.ev = Release and Now.issue = i
}

pred stutter {
  githubFrame
  Now.ev = Stutter and no Now.issue
}

/* Admits a campaign already in flight, an unfiled one, or any mixture:
   session/system.als has to be able to file a campaign issue, and the scenarios have to be
   able to start with one already filed. */
pred githubInit {
  no Merged
  no Claimed
  no pr
  all c: Campaign - Filed | no c.members and no c.sub and no c.body
  Open = Filed.campaignIssue + Campaign.members
  all c: Campaign | c.sub = c.members
}

pred githubStep {
  stutter
  or (some c: Campaign | fileCampaignIssue[c] or writeBody[c])
  or (some c: Campaign, i: Issue | addMember[c,i] or removeMember[c,i])
  or (some i: Issue | openPR[i] or mergePR[i] or closeIssue[i]
                      or claim[i] or release[i])
  or (Now.ev not in Stutter + githubEvents and githubFrame)
}

fact GithubTrace { githubInit and always githubStep }
