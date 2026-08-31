# agent-workspace

A container for running **campaigns** — units of work across the repositories
they need — on repositories that live elsewhere. `README.md` says what the
container is; this file is how to work inside it, and `spec/alloy/*.als` says in
its comments why these rules are what they are.

This project is early. Where a rule is missing, decide, do the work, and write
the decision back here.

**Much of what used to be written here is now enforced.**
`scripts/campaign-primitives` lists every mechanism and what it decides, and a
`SessionStart` hook prints it. Ask it before writing a check by hand, and use
`gh` for every GitHub operation; it is authenticated on this machine.

# What a campaign is

One assignment a person is responsible for, worked across the repositories it
needs, which may be none. Bigger than a ticket, no size ceiling. It splits into
subtasks, and follow-ups keep arriving until someone decides it is over. It is not
a repository and not a ticket: it is what collects the subtasks of one assignment
and the repositories that assignment needs.

# Not every request is a campaign

Settle this before anything else. Most of what arrives here loads no skill.

**A person saying a campaign is over is routed before anything is read.** Load
`closing-campaign` and stop. Only a person decides a close, and the readings
below would take a close request for a subtask of the campaign it closes.

Otherwise, two readings, in this order.

**One: does any open campaign's Scope cover the request?** `scripts/campaign-anchors`
lists the open anchors and cross-checks the hand-applied `campaign` label against
the one property a subtask cannot have — no parent. Read the body of each anchor
that could plausibly cover the request; the title does not carry the Scope. Match
on Scope, never on `## Repos`, and treat testing or fixing a campaign's own
deliverable as covered by it.

**Two, only if nothing covers it: is the request finished when this session
ends?** A campaign outlives the sitting. A question answered, a file corrected,
one change that lands complete, is not.

| what the two readings say | what this is |
| --- | --- |
| An open campaign's Scope covers it | **A subtask of that campaign.** Read the binding first (§ Who is a campaign session), then § Running a campaign, "Subtasks". Load `opening-campaign` only to *join* — this machine has no directory for the campaign yet. |
| Two or more could cover it, or the fit is arguable | **A question for the person.** Name the candidates; do not guess. |
| Nothing covers it, and it ends with this session | **Not campaign work.** Answer it, or make the change and land it. |
| Nothing covers it, and it will outlive this session | **A new campaign.** Load `opening-campaign`. |

Size is not one of the readings, and asking it first is the mistake this ordering
prevents. A one-line edit inside a Scope is that campaign's subtask, because the
sub-issue index is the only place its close can look; a large change no Scope
covers that finishes here is still not a campaign.

**Not campaign work is not unmanaged work.** This repository's own git rules hold
whatever the work is: its own branch, a pull request, and the `pre-commit` guard.

# Who is a campaign session

**A campaign runs on one machine at a time, and every session on that machine is
an equal session of it.** No session holds the campaign; each campaign-wide write
names its own guard (§ Running a campaign, "The three campaign-wide writes").

One reading decides whether a session is in the campaign, and `scripts/campaign-bound <N>`
is its one reader. It prints `here`, `elsewhere <machine>`, or `unbound`. **Read
the word, never the exit status** — the status is about the reading, as it is for
`campaign-local-work` and `campaign-session-alive`.

| the word | this session is |
| --- | --- |
| `here` | **a session of this campaign.** Work the directory if there is one, scaffold it if there is none (`opening-campaign` steps 2 and 4), and take a subtask. |
| `elsewhere` | **not in this campaign.** Stop before any write and any launch, and name the machine. |
| `unbound` | **not bound yet.** Only a person's word binds an existing campaign. |

Read it before every write to the anchor — body, comment, or sub-issue link —
and before launching any executor onto one of its subtasks.

**`BOUND <machine>` is a comment on the anchor, and the latest one wins.**
Comments append, so writing one races nothing. Its first line is `BOUND <machine>`
from `hostname -s`; anything after is prose for a person.

**A session posts `BOUND` in exactly two cases**: for a campaign it has just filed
itself, and when a person tells it to. The second is migration, and it is the
person's call because its premise — that the other machine has released the
campaign or is dead — is something nothing here can observe. Post it, then read
it back; a later `BOUND` naming somebody else means the campaign was migrated out
from under you.

**Every session of a campaign is an executor.** It files or takes a subtask,
claims the branch, works it whichever way § Running a campaign allows, answers
`STATUS`, sends `REPORT` and `BLOCKED`, and stops on `STAND DOWN`. It may land
its own work on the three merge conditions, and may make the campaign-wide writes
on their own guards. **No role licenses a write, and neither does asking**: a
session that cannot satisfy a guard does not make the write.

When a person names a peer to ask, that name is an address and nothing more.

**Four rules, each written from a witnessed breakage:**

- **Survey again at the moment you file.** Two sessions that each surveyed before
  either filed will both file, and one scope gets two campaigns. Re-reading
  immediately before `gh issue create` narrows that window; nothing closes it,
  because a campaign that does not exist yet is bound to nobody.
- **Claim the branch before you launch onto it**, with `campaign-claim take`. A
  refusal means the subtask is taken: read who by, do not push past it.
- **Retire only an agent on your own machine.** Holds by construction under the
  binding; kept for the window just after a migration.
- **The tree is shared, and the only files in it that are anybody's are the claim
  records**, each written by its own claimant and edited by nobody else. The local
  gate cannot see a machine working this campaign against its `BOUND`, so
  `closing-campaign` says on the anchor that it is closing.

- **ID** — the anchor issue's number in `kalaluthien/agent-workspace`, typed `#N`.
  The anchor carries the `campaign` label; every survey lists by it, so an anchor
  filed without it is in nobody's listing.
- **Directory** — `<slug>-<YYMMDD>/` at the container root, git-ignored, optional
  off the bound machine. A campaign *is* its anchor issue; the directory is one
  machine's cache, and the bound machine has one from the moment anybody works the
  campaign there, because the claim records live there and nowhere else. So
  closing a campaign and deleting a directory are different acts that
  `closing-campaign` performs in one step.
- **Branch** — `campaign-<N>/<issue>-<topic>`, the subtask's claim as well as its
  workspace. `campaign-claim` cuts it from the remote and writes the record;
  create-ref refuses an existing ref server-side, so the claim is atomic where a
  survey-then-file is not, and a crash before the first commit still leaves it
  visible from every machine. **A name is not a branch** (§ Naming a session).

# Naming a session

**`campaign-<anchor>-<role>-<n>`**, for every session on this machine.
`<role>` is `executor` — the only one, since a review is a subagent and has no
session of its own. `<n>` distinguishes sessions sharing the first two.

**The subtask is deliberately not in the name.** A session works several subtasks,
in parallel or one after another. A name identifies the session for as long as it
runs; the claim record says which subtask it holds.

**A session has two names and neither propagates to the other**, so
`scripts/campaign-name-session <pane> <name>` sets both and refuses a name the
rule does not admit. The harness name is what `ListAgents` resolves and what a
claim record's `name` field holds; the pane name is what `herdr agent list` shows.
**A rename that does not take is a permission question**, and permission is not
stable — the same call was refused and then accepted on one session minutes apart.
Build on no outcome: run the script, read what it reports applied, confirm with
`ListAgents`.

# Three planes

Every artifact belongs to exactly one, and the plane decides where it is stored
and whether it survives the machine. Identify the plane before any git command.

| plane | holds | stored in |
| --- | --- | --- |
| **container** | `AGENTS.md`, `CLAUDE.md`, `README.md`, `.gitignore`, `.claude/`, `spec/`, `docs/`, `scripts/`, `.github/` | this repository |
| **member repository** | the code and its history | each repository's own remote |
| **campaign** | which repositories, what for, how far along | GitHub issues |

`spec/` is normative and is Alloy whose comments are the spec; `docs/` is views
drawn for a reader, as HTML. `check-tree-shape` refuses markdown under either,
and refuses a tracked top-level name with no `!` line in `.gitignore`.

The campaign directory holds no plane of its own: a scratch assembly of things
versioned elsewhere, git-ignored on purpose, and nothing durable may live only
there. **A campaign with no member repository tests that rule rather than
excepting it** — its `<campaign>/scripts/` is scratch by design, and its lasting
results live in the anchor issue and its sub-issues, in this container's memory
pool, or in a repository it lands work in by hand.

**Resolve the container root one way, everywhere:**

```sh
CONTAINER=$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd -P)
```

The container root is the main checkout by definition, and this form returns it
from a linked worktree too, where `--show-toplevel` returns the worktree instead.
Two tools disagreeing about which to use test green and then strand a campaign.

Never run one git command across member repositories, and never commit their
files here.

# When the container is a member of its own campaign

The container gets cloned into `<campaign>/repos/agent-workspace/`, so one
repository has two checkouts: the **outer** one a session runs from and the
**inner** clone a delegate works in, which the outer git-ignores.

```sh
git -C "$CONTAINER" fetch origin -q
git -C "$CONTAINER" rev-list --left-right --count origin/main...HEAD   # want "0	0"
```

- **Behind is a merged pull request you have not caught up to.** Editing from
  here can silently revert work that landed. Pull, then read zero again.
- **The clone must not be behind *at launch*** — check inside the clone, at
  launch, not before cloning: the remote moving in between is normal, and a
  delegate launched behind obeys an `AGENTS.md` already superseded.
- **A skill edited inside the clone does not change the running campaign**, and
  that is deliberate: the tool must not move under a session using it.
- **One tracker then holds three kinds of issue** — anchors, subtasks, and
  everything else a tracker collects. **Structure classifies:** an anchor has the
  `campaign` label and no parent; a subtask has a parent. The parent relation is
  an API relation, so no edit to a body can forge or lose it, while the label is
  applied by hand — the two cross-check each other.

  Body shape is the layer under that, for the case structure cannot answer: an
  issue with no parent and no label is an anchor whose label was forgotten if it
  carries the anchor template's sections, and a subtask filed without `--parent`
  if it carries the `Campaign:` line. It never overrules the parent relation, and
  reading it is a person's job. **An issue matching neither template is the third
  kind, and every reader leaves it alone.** `campaign-settlement` reports a
  mismatch instead of guessing. Never survey this tracker unfiltered.

# Running a campaign

**Open** — load `opening-campaign` when the request opens a campaign, or joins one
this machine has no directory for.

**Subtasks** — one subtask is one GitHub issue, filed on the repository whose code
changes, and created **as a sub-issue of the anchor**:

```sh
gh issue create -R <owner/repo> --parent https://github.com/kalaluthien/agent-workspace/issues/<N> ...
```

That one flag is the whole index; `scripts/campaign-subtasks <N>` reads it back.
The link is made by the same command that creates the issue, so there is no
second write to forget, and it is prunable — moving a subtask out of the campaign
removes it from the index, which a back-reference cannot do. Fill the body from
`.claude/skills/opening-campaign/assets/subtask.md`.

**A discovery becomes a subtask at the moment it is found**, by whoever can file
it: a finding held in a session's memory dies with its pane and reaches the close
as nothing.

**`## Repos`** says which repositories to clone when a campaign is opened.
`- none` is the whole list for a repo-less campaign; an *empty* list is refused,
being indistinguishable from one a bad write dropped, and `- none` is retired
rather than joined. `scripts/campaign-repos <path>` is its one reader.

A repo-less campaign's subtasks are filed on the container tracker as sub-issues
of the anchor, and **the claim is still create-ref on the container**, even when
no container code will change: the branch is the claim before it is a workspace.
A claim whose branch holds nothing beyond `origin/main` may be released — by
`scripts/campaign-claim release`, which refuses on anything but a confirmed
absence, because `dead` is not proof a session is gone. Such a subtask closes as
completed with no pull request, which `campaign-settlement` prints as `dropped
[completed, no merged pull request]`; quote the note, never the word.

**Do it here, hand it to a subagent, or hand it to a delegate.** The mode is
chosen before the work starts, **first by the repository and only then by cost**.
An executor that *changes* a repository runs in a process started in that
repository's checkout: a herdr delegate in `<campaign>/repos/<repo>/` for a member
repository, and a session of the campaign or an in-process subagent on a worktree
for the container. Reading any repository, and writing under `<campaign>/`, may
run in any mode. The harness fact underneath: an in-process subagent and an
interactive session load the skills of the session or directory they were
*started in*, and a skill marked `disable-model-invocation: true` is unusable by
any agent, so it must be spelled out in a brief rather than named.

Then, within what the repository allows, choose by cost: **your own hands** for
one small edit needing nothing from that repository's build loop; **a subagent on
a worktree** when several subtasks can run at once or the work would eat the
session's turns; **a herdr delegate in a clone** when the work needs the
repository's own toolchain, will take many turns, or two repositories must move
together.

**Weigh the setup against the work.** The delegate's price is paid per launch, so
for the container it is the mode of last resort — a worktree subagent gets the
same conventions at none of it. For a member repository it is the only mode that
changes the code, which is why one delegate gets a subtask worth many turns rather
than many delegates small ones.

All modes share the mechanics. The branch is claimed by `campaign-claim take`
after the issue exists, because the number is minted there. Work is pushed as
soon as one commit exists — the `post-commit` hook does this, and says so when it
cannot. It lands by a pull request under the three merge conditions.

**Close** — load `closing-campaign`. A campaign closes when its anchor closes, and
only a person decides that. The skill refuses while any open subtask lacks a
disposition: a campaign may close over unfinished work, never over unexamined work.

**The anchor body is a charter, not a status board.** Intent, Scope and
Requirements say what a person signed up for and change only when the scope
genuinely changes. The body holds no decomposition; the sub-issue index is the
decomposition, and `scripts/campaign-settlement <N>` derives progress from it.
So the body is written at exactly two moments — a scope change, and the close.
Adding work is neither. **When a request reads both ways**, ask with
`AskUserQuestion` before writing either side.

Adding a repository **is** a scope change, so it syncs when it happens; held back
until the close it is invisible to every other session and the loss it was meant
to prevent happens anyway.

**Compare then write the anchor issue body.** Re-read it immediately before
`gh issue edit` and refuse if it has moved since your `README.md` was derived
from it: two sessions on the one bound machine are both sessions of the campaign,
so the binding never serialized the body and the comparison is what does. Without
it one write silently discards another — and a body write cannot touch a
sub-issue link, so the index goes on naming work in a repository the `## Repos`
list has dropped, and the close deletes that list's last copy.

**Read the binding first, then name the cause.** `campaign-bound` saying anything
but `here` means *you* are out of position, and the write stops there whatever the
diff says. With it bound here, a moved body has three causes that look identical
at the point of refusal, and `.claude/skills/closing-campaign/references/rationale.md`
says how to tell them apart.

**The three campaign-wide writes**, each on its own guard and on nothing else:
the **scaffold** on the binding plus `mkdir` without `-p`, which refuses a name
that exists, so one session wins and the other works in what it made; the
**anchor body** on the two-moment rule for *when* and compare-then-write for
*how*; and the **close** on a person's word, the binding, every open subtask
dispositioned, nothing live under the tree, nothing that exists only here, and the
close said on the anchor first.

One window is left uncovered and named rather than papered over: a session that
has just scaffolded a directory and is still cloning into it holds no claim and
nothing uncommitted, so the close's gates cannot see it. What it stands to lose is
template copies and fresh clones.

# Delegating to a repository agent

**Any `herdr` command that drives a pane, or resolves its target implicitly, is
guarded by `test "${HERDR_ENV:-}" = 1`**, and names its target explicitly. The
guard is against acting on somebody else's session, never against reading, so
`agent list` needs none.

A delegate is launched in `<campaign>/repos/<repo>/` with
`--append-system-prompt-file <campaign>/AGENTS.md`, because ancestor instruction
files load only behind a dialog that defaults to declining. Four invariants:

- **The brief is a file**, named by a one-sentence prompt. A terminal drops a
  launch line past 1024 bytes and nothing says so.
- **The prompt is delivered by `herdr agent prompt`**, never on the launch line,
  where it is word-split.
- **A canary proves the injection arrived**, since nothing on disk records it and
  asking the delegate would be the self-report this design refuses.
- **Read the pane once after every launch** — three dialogs halt a fresh delegate
  and two report `idle`, so this catches one that stopped before it began.

A campaign `AGENTS.md` only ever *adds*; one contradicting the repository's own
conventions puts the delegate in a conflict it cannot resolve.

The full procedure — the launch line, the outcome names, the canary, the three
dialogs, and what the guard was measured against — is
`.claude/skills/opening-campaign/references/launching.md`.

# Completion and liveness are different questions

Never answer one with the other.

- **Completion is a GitHub fact.** A subtask is settled when its issue is closed —
  as completed with its pull request merged, or as **not planned**, which is how a
  subtask gets dropped. Both readings are needed, or a subtask abandoned on
  purpose never reads settled and its campaign can never close. Nothing on a
  terminal screen is evidence: a delegate that died after pushing has succeeded; a
  delegate alive and chatty may have done nothing. `scripts/campaign-settlement <N>`
  is the one implementation.
- **Liveness and attribution are different readings and a gate needs both.**
  `herdr agent list` gives liveness for every session on this machine and no
  attribution at all; `runtime/claims/` gives attribution and cannot prove
  liveness, because its `pid` reads dead after a restart its session survived.
  `scripts/campaign-live <N>` makes both and joins them on the harness session id,
  the only field surviving both a restart and a rename. It concludes nothing: a
  close reads its counts. Read a delegate's progress from its transcript, never
  from `agent_status`, which reports the screen and calls a mid-turn pause `idle`.
- **What exists only on this machine is the third question**, and
  `scripts/campaign-local-work <N> [dir]` is its one reader.

An agent never closes itself: it finishes by pushing and opening or updating a
pull request, then goes idle, and the session that launched it retires it once
its work is durable.

**Every review runs as an in-process subagent. There is no other way to run one.**
Not a default and not the cheapest option — the one mode. A review changes no
working tree, so it needs nothing a process boundary is paid for.

```
Agent(subagent_type: "general-purpose", model: "<named below>",
      description: "Review PR <N>",
      prompt: "/code-review <low|medium|high|xhigh|max> <PR#>\n\n…")
```

`general-purpose` because `fork` inherits the author's context and would review
the author's own reasoning. **Name the model, always.** **Two knobs answering
different questions.** The **model** by the depth of the
change — a correctness that is not local takes the heavier one, because a weaker
reader returns "looks fine" on exactly the reasoning that needed a reader; judge
the change, not the launcher's own model. The **level** by how much there is to
read; `medium` is the baseline. **The level is the first token after the command
and nowhere else** — asking for it in the brief sets nothing, and omitting it
runs the review at a level chosen by neither the launcher nor the work.

**Three ways to get this wrong**: a peer session, reading the diff yourself and
calling it reviewed, or a herdr session. The one exception is an `ultra` review,
which a person triggers and no session may launch. A session that cannot start a
subagent is **blocked** — it says so and the pull request waits, which is never a
licence to review some other way.

**One reviewer per pull request, one verifier per fix round**, every angle a
section of the one brief. Fan out only when the angles are independent and the
budget carries them: eight parallel angles died twice on the session limit, and
one consolidated pass found findings of the same quality far cheaper.

**The pull request is the review's working memory.** A finding that exists only
inside a running session is not yet found: post them the moment they consolidate,
before anything else is launched, and write them out as you go.

# Talking to a repository agent

`spec/alloy/agent.als` is the contract; this is the short form. `ListAgents`
resolves the address; herdr's pane label is not one.

| message | direction | carries |
| --- | --- | --- |
| `STATUS` | campaign → agent | doing what, blocked on what, what exists only on this machine, safe to stop |
| `REPORT` | agent → campaign | a pull request URL and the sha it sits at, once per round, unsolicited |
| `BLOCKED` | agent → campaign | a decision that is not the agent's to make |
| `STAND DOWN` | campaign → agent | finish the turn and stop |

Four messages, carrying **only what the agent alone knows**. Anything a message
says about finished work duplicates a GitHub fact, and the copy is what goes
stale. **The claim is not among them**: it is a record the claimant writes for
itself, not an announcement somebody must receive — an announcement can fail to
be sent, and its absence is invisible.

**Every claimant writes a record, and `scripts/campaign-claim` writes it**, so the
shape lives in one place and a delegate runs the script rather than copying it.
The session that *launched* a delegate writes none: it holds no claim, and a
second address for one claim would make the close gate count it twice. Each field
answers one question — liveness from `pid`, addressing from `name`, and `session`
when both have gone stale, it being the only field surviving a restart and a
rename. **A directory with no `runtime/claims/` cannot be enumerated, and that is
a refusal rather than a pass**: an empty one says no claim was taken, a missing
one says nothing.

- **Three conditions gate a merge, and none names a role.** A pull request merges
  only when (1) a review has been read **at the sha being merged**, (2) that review
  was written by **an agent that did not write the commits**, and (3) the branch
  **contains the current `main`** when it merges. Whoever satisfies all three may
  merge, the author included; a session that cannot satisfy one may not.

  Condition 3 is what serializes landings: 1 and 2 are each true of a branch *in
  isolation*, so to contain a `main` that moved the second branch must merge it
  in, that merge is a push, **a push retires the review**, and the next merge
  needs a review at the combined sha.

  **Condition 3 is enforced by GitHub; condition 1 is readable and read by
  nothing.** `main` requires the check `check`, `strict: true`,
  `enforce_admins: true` — and `strict` enforces nothing until `contexts` names a
  check, so a reader asking whether it still bites reads `contexts`.
  `.github/workflows/check.yml` carries what keeps that run reachable. A
  `pull_request` check resolves from the **merge commit**, so a branch predating
  the workflow still produces one; a check missing on an open pull request means
  its head has not moved since, and clears on its next push. **Condition 2 has no
  automatic reader**: one `gh` account signs every session's merges, so it is held
  by whoever writes the review saying honestly that it did not write the code.

  **The push that retires a review does not start the next one, and whoever pushed
  it asks**, because **a silent wait is indistinguishable from work**. So the
  `REPORT` names the new sha *and* asks for the review, in the pull request — and
  the wait is bounded: a session that has asked and received nothing says so and
  stops. The reviewer is launched by whoever wants the merge, the author included;
  a long fix round can go to a fresh executor briefed from the pull request.

- **A claim in a message is never evidence.** It says where to look; then look, in
  GitHub, yourself. **A verdict, a fix report, or a `REPORT` that does not pin its
  sha is unactionable** — verdicts and pushes race, and the crossing was harmless
  only because each verdict named the sha it was read at.
- **A fix round is: findings on the pull request, one executor, one `REPORT`.**
  The executor verifies each finding at the site it names before touching anything;
  one that does not reproduce is named with its reason, never silently fixed.
  Follow-up findings fold into the same round, which ends in one `REPORT` carrying
  the sha and a per-finding disposition. **Check that disposition against the
  findings list mechanically before posting it** — a round that says "all fixed"
  without re-running its own sweep is the shape this repository keeps meeting.
- **Push every commit as it exists; the round's boundary is the `REPORT`, never the
  push.** "One push per round" was read as "hold the commit local".
- **Between sessions, a relay is never the authority.** An owner's word arriving
  through a peer is acted on through the durable artifact it points at, read on
  GitHub yourself — or on the owner's word in your own pane.
- **Shutdown is two steps, and both are yours.** `STATUS`, verify durability in
  GitHub, then `STAND DOWN`. The session that verifies and the one that stands down
  are the same, on the agent's own machine: a verification run from elsewhere reads
  *its* working tree and comes back clean whatever the agent holds.
- **Silence is a liveness question, not an answer**: ask once more, then resolve
  it through herdr and GitHub.

**Watch a delegate for `blocked`, not only for gone** — a session at a permission
prompt is still listed and never proceeds, and clearing such a prompt is the
person's decision. **Do not trust the absence of that reading either**: a
usage-limit menu and the folder-trust dialog both report `idle`.

**The session limit is a first-class cause of death, and it kills in batches.** An
agent it stopped looks exactly like one still thinking. When several go quiet
together, read the reset time first: that is an outage to schedule around, not a
failure to retry now.

Retire finished agents as the campaign runs, not when it closes, and sweep with
both readings. A campaign may not close while any agent is live under its tree,
nor a repository be dropped while an agent works one of its subtasks.

# Concurrency and what it costs

One campaign, one machine settles the hard half: no lock is ever judged stale
across a network. It does not settle the campaign's own writes — the binding
serializes neither the anchor body nor the shared directory. Three things
serialize what remains, two of them server-side: the branch claim, which
create-ref refuses; merge condition 3, which branch protection refuses; and
compare-then-write, which nothing refuses and a session can skip by forgetting.

**Two open pull requests over the same normative files are normal, and the second
to land reconciles**, and **containment buys attention from nobody**: a clean
auto-merge produces a commit whose diff against the branch *is* the other
branch's work — structurally present in the reviewed sha, and exactly what a
reviewer skims as "just the merge". So **the review after a reconciliation reads
the combination**, and its brief says so; the clashes that matter are semantic and
no hunk-level merge sees them. Whoever holds the first claim publishes the overlap
as a courtesy — **the gate is condition 3**.

**The named cost: no concurrent cross-machine or cloud work on one campaign.**
Another machine may read a campaign and may open a different one; none may write
this one's anchor or launch into it. A campaign reaches another machine only by
migration. That is the price of a staleness check that is a local `kill -0` rather
than a distributed guess, and it is paid deliberately.
