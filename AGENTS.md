# agent-workspace

A container for running **campaigns**: units of work across the repositories they
need, on repositories that live elsewhere. `README.md` says what the container is
and `spec/campaign/*/*.als` why these rules are what they are; this is how to work
here.

**Much of what used to be written here is now enforced.** `scripts/campaign-primitives.py`
lists this repository's scripts and hooks; run it in full for what each decides. It
cannot see what lives off this tree — `main`'s branch protection, the machine-wide
git hooks — so its silence is not evidence that no mechanism exists. Use `gh` for
every GitHub operation; it is authenticated here.

**Ask the person only what no check can settle** — preference, scope, a
destructive stake. Everything else, decide and do, and report the decision.

# The campaign

One assignment a person is responsible for, worked across the repositories it
needs, which may be none. Bigger than a ticket, no size ceiling. It splits into
sub-issues, and follow-ups keep arriving until someone decides it is over.

## Routing an arriving request

Settle this before anything else. Most of what arrives here loads no skill.
**The routing is the planner's reading**: the session a person hands a request
to reads it here, and what it files and distributes from that reading is the
planner role (§ The binding).

**A person saying a campaign is over is routed before anything is read.** Load
`closing-campaign` and stop, or the readings below take the close for a sub-issue.

Otherwise, two readings, in this order.

**One: does any open campaign's Scope cover the request?** `scripts/campaign-tracker.py campaign-issues`
lists the open campaign issues — **never survey the tracker unfiltered**, since it holds
three kinds of issue and only structure classifies them; where structure cannot
answer, both templates are in `.claude/skills/opening-campaign/assets/`, and **an
issue matching neither is the third kind, which every reader leaves alone**. Read
the body of each campaign issue that could plausibly cover the request — the title does
not carry the Scope. Match on Scope, never on `## Repos`, and treat testing or
fixing a campaign's own deliverable as covered by it.

**Two, only if nothing covers it: is the request finished when this session
ends?** A campaign outlives the sitting.

| what the two readings say | what this is |
| --- | --- |
| An open campaign's Scope covers it | **A sub-issue of that campaign.** Read the binding first (§ The binding), then § Sub-issues. Load `opening-campaign` only to *join* — this machine has no directory for the campaign yet. |
| Two or more could cover it, or the fit is arguable | **A question for the person.** Name the candidates; do not guess. |
| Nothing covers it, and it ends with this session | **Not campaign work.** Answer it, or make the change and land it. |
| Nothing covers it, and it will outlive this session | **A new campaign.** Load `opening-campaign`. |

**Size is not one of the readings**, and asking it first is the mistake this
ordering prevents. A one-line edit inside a Scope is that campaign's sub-issue.

## The three planes

Every artifact belongs to exactly one, and the plane decides where it is stored
and whether it survives the machine. Identify the plane before any git command.

| plane | holds | stored in |
| --- | --- | --- |
| **container** | `AGENTS.md`, `CLAUDE.md`, `README.md`, `.gitignore`, `.claude/`, `spec/`, `docs/`, `scripts/`, `.github/` | this repository |
| **member repository** | the code and its history | each repository's own remote |
| **campaign** | which repositories, what for, how far along | GitHub issues |

`spec/` is normative and is Alloy whose comments are the spec, and an HTML
diagram may sit beside a model; `docs/` is views drawn for a reader, as HTML.
Neither holds markdown, and that is the part a guard refuses. Two `pre-commit`
guards refuse a commit that breaks either — `check-tree-shape` and
`check-rule-readers`, whose header gives the syntax exempting a block that must
hold a guarded form. **Do not write a second reader of a rule a script owns**:
two of them drift.

The campaign directory holds no plane of its own: git-ignored scratch, and
**nothing durable may live only there** — a repo-less campaign lands its results
in the campaign issue and its sub-issues, the memory pool, or a repository by hand.

**Resolve the container root one way, everywhere:**

```sh
CONTAINER=$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd -P)
```

The container root is the main checkout by definition, and this form returns it
from a linked worktree too, where `--show-toplevel` returns the worktree instead.
Never run one git command across member repositories.

### The container as its own member

The container gets cloned into `<campaign>/repos/agent-workspace/`, so one
repository has two checkouts. **Behind is a merged pull request you have not
caught up to**, and editing from the outer one can silently revert it; **the clone
must not be behind at launch**; and **a skill edited inside the clone does not
change the running campaign**. Commands: `.claude/skills/opening-campaign/references/launching.md`.

# Session identity

## The binding

**A campaign runs on one machine at a time, and every session on that machine is
an equal session of it.** No session holds it; each campaign-wide write names its
own guard.

One reading decides whether a session is in the campaign, and `campaign-tracker bound <N>`
is its one reader: `here`, `elsewhere <machine>`, or `unbound`. **Read the word,
never the exit status**, as for `campaign-local-work` and `campaign-claim alive`.

| the word | this session is |
| --- | --- |
| `here` | **a session of this campaign.** Name this session first (§ The session name), then work the directory if there is one, scaffold it if there is none (`opening-campaign` steps 2 and 4), and take a sub-issue. |
| `elsewhere` | **not in this campaign.** Stop before any write and any launch, and name the machine. |
| `unbound` | **not bound yet.** Only a person's word binds an existing campaign. |

**The binding gates four things**: the campaign issue body, a `BOUND` comment, a claim,
and a launch. Read it before each of those. Only one of the four has a machine
behind it: `campaign-claim take` reads the binding before it cuts a ref and
refuses on anything but `here`. The body write, the `BOUND` comment, a launch,
and a `--local` claim are gated by this rule and the model alone
(`spec/campaign/session/scenarios.als`, `boundOnly`), so read the word yourself
before each. **The sub-issue link is outside it**: any session on any machine
may file a sub-issue of any campaign, one it is not a session of included,
because a sub-issue is a record and not a claim — the atomic gate stays
`campaign-claim take`'s create-ref, and the model's `addMember`
(`spec/campaign/github/system.als`) has no actor, machine, or binding
precondition. What the filer still owes: file from the template, and leave
adding a repository the work needs to `## Repos` to a bound session, since that
is a scope change (`opening-campaign`, "A repository the campaign issue's `## Repos` list does not name").

**`BOUND <machine>` is a comment on the campaign issue, and the latest one wins.** Its
first line is `BOUND <machine>` from `hostname -s`; anything after is prose.

**A session posts `BOUND` in exactly two cases**: for a campaign it has just filed
itself, and when a person tells it to — migration, and the person's call because
nothing here can observe its premise. Post it, then read it back; a later `BOUND`
naming somebody else means the campaign was migrated out from under you.

**A session of a campaign is a planner or an executor, and the request decides
which shape it takes.** A simple request has an executor only: the session files
the sub-issue and works it. A request that needs decomposition has a **planner**,
which takes the request, files the sub-issues and distributes them, and separate
**executors**, each a session of its own spawned as a herdr delegate
(`.claude/skills/opening-campaign/references/launching.md`) and never as the
planner's subagent — a subagent shares the planner's pane and dies with it, and a
claim record needs a session id of its own; the planner's own hands and an
in-process subagent on a worktree are the planner executing a sub-issue itself
(§ Execution mode). **A planner holds no branch claim of its own**: it claims
only when it executes a sub-issue itself, and is that sub-issue's executor then.
The model is `Planner` in `spec/campaign/orchestration/system.als`.

**No role licenses a write, nor does asking**: a session that cannot satisfy a
guard does not make the write. **The planner claims the branch before it
launches onto it**, with `campaign-claim take --session <the delegate's session
id> --name <the delegate's name>`: the branch is cut now, and the record is the
delegate's from the start, because a record is attributed by `session` and the
planner chose the delegate's before launching. A record written that way carries
no pid, since the delegate's does not exist yet; `live` joins on the session id
and reads it fine.

## The session name

**`campaign-<campaign issue>-<role>-<n>`**, the role being `planner` or
`executor`, for every session on this machine; `<n>` is one counter across both
roles, assigned in the order sessions appear, so two do not both pick `-1`. **Set it at
the start of every session of a campaign, whichever path started it** — the
`here` reading above, `opening-campaign` step 3, or a delegate launch — because a
session that arrived from another campaign keeps that campaign's name until
something sets it. The one pattern lives in `scripts/campaign-name-session.py`,
and `campaign-claim take` reads it from there: a name of another campaign, or of
the wrong shape, is refused at the first claim, which is where a stale name
would otherwise become durable.

**The sub-issue is deliberately not in the name**, because a session works several;
the claim record says which one it holds. **Never test a name against a branch**:
they are two strings on purpose, and a test treating them as one finds whatever
happens to match and misses the rest.

**A session has two names and neither propagates to the other**, so
`scripts/campaign-name-session.py <pane> <name>` sets both and refuses a name the rule
does not admit; read what it reports applied, and confirm with `ListAgents`, which
resolves the harness name a claim record holds. `herdr agent list` shows the pane.

## ID, directory, branch

- **ID** — the campaign issue's number in `kalaluthien/agent-workspace`, typed `#N`.
  The campaign issue carries the `campaign` label; every survey lists by it, so a campaign issue
  filed without it is in nobody's listing.
- **Directory** — `<slug>-<YYMMDD>/` at the container root, git-ignored, optional
  off the bound machine. A campaign *is* its campaign issue; the directory is one
  machine's cache, and holds the claim records, which live nowhere else.
- **Branch** — `campaign-<N>/<issue>-<topic>`, the sub-issue's claim as well as its
  workspace. `campaign-claim` cuts it from the remote and writes the record;
  create-ref refuses an existing ref server-side, so the claim is atomic where a
  survey-then-file is not. **`take --local` writes the record and no ref**, for
  work that lands no commit; there the atomicity is `O_EXCL` on the record, which
  serializes this machine and not every machine — the ceiling the binding sets.

# Campaign work

**Open** — load `opening-campaign` when the request opens a campaign, or joins one
this machine has no directory for. **Close** — load `closing-campaign`; only a
person decides a close.

## Sub-issues

One sub-issue is one GitHub issue, **filed on this container's tracker whatever
repository its code lives in**, and created **as a sub-issue of the campaign issue**:

```sh
gh issue create -R kalaluthien/agent-workspace --parent https://github.com/kalaluthien/agent-workspace/issues/<N> ...
```

That one flag is the whole index, and `campaign-tracker index <N>` reads it
back. Fill the body from `.claude/skills/opening-campaign/assets/sub-issue.md`.
**A member repository receives only the branch and its pull request**, so its
own issue conventions are never touched, and a repository this account does not
own, or a sub-issue moving two repositories at once, needs no special case. The
pull request body closes the sub-issue with the keyword and the full name,
`Closes kalaluthien/agent-workspace#<issue>`: `campaign-tracker settlement`
reads `closedByPullRequestsReferences`, which a keyword populates and a bare
mention does not, and the short `#<issue>` closes the member repository's own
issue of that number instead. Which repository the work lands in is the
template's `Repository:` line, since the issue's own location no longer says.

**A discovery becomes a sub-issue at the moment it is found**, by whoever can file
it: one held in a session's memory dies with its pane.

**A sub-issue whose work lives only under `<campaign>/scripts/` has no commit to
land**: it closes as completed with no pull request, its closing comment saying
what was built. Quote `campaign-tracker settlement`'s note for that row, not its verdict.

## The `## Repos` list

**`## Repos`** says which repositories to clone when a campaign is opened, and
`scripts/campaign-repos.py <path>` is its one reader; `- none` is the whole list for
a repo-less campaign. **Work that lands no commit is claimed all the same**, with `campaign-claim take
--local`: the record alone, no ref. **`scripts/check-campaign-claim.py` is what
makes that true rather than remembered** — a `PreToolUse` guard answering "is
this a change to campaign work that no unreleased claim of this session covers",
refusing the ones that are. A change landing outside every container tree and
every campaign directory is not campaign work and is not refused; how the guard
reads a target, and what it does when it cannot, is its docstring's.
`install-hooks.sh` registers it in
`~/.claude/settings.json`, because a delegate's clone is a different repository
and reads none of this one's settings.

## Execution mode

**Do it here, hand it to a subagent, or hand it to a delegate.** The planner
chooses the mode before the work starts, **first by the repository and only then
by cost**; the first two are the planner executing the sub-issue itself, and the
third is a separate executor (§ The binding).

An executor that *changes* a repository runs in a process started in that
repository's checkout: a herdr delegate in `<campaign>/repos/<repo>/` for a member
repository, and a session or an in-process subagent on a worktree for the
container. Reading any repository, and writing under `<campaign>/`, may run in any
mode. The harness fact underneath: a subagent and an interactive session load the
skills of the session or directory they were *started in*, and a skill marked
`disable-model-invocation: true` must be spelled out in a brief, never named.
**A repo-less campaign therefore has the first two modes and not the third.**

Then, within what the repository allows, choose by cost:

- **your own hands** for one small edit needing nothing from the build loop;
- **a subagent on a worktree** when several sub-issues can run at once, or the work
  would eat the session's turns;
- **a herdr delegate in a clone** when the work needs the repository's own
  toolchain, will take many turns, or two repositories must move together.

**Weigh the setup against the work**: the delegate's price is paid per launch, so
for the container it is the mode of last resort. All modes share the mechanics —
the branch is claimed by `campaign-claim take` after the issue exists, because the
number is minted there; the `post-commit` hook pushes; it lands by a pull request.

**Open that pull request on the first commit, not when the work is ready.** The
hook has already pushed the branch, so a late pull request only keeps published
work out of sight. An open one is where a review writes its findings, and it is
what survives the session that opened it.

## The campaign issue body

**The campaign issue body is a charter, not a status board.** Intent, Scope and
Requirements say what a person signed up for and change only when the scope
genuinely changes; the sub-issue index is the decomposition, and
`campaign-tracker settlement <N>` derives progress from it. So the body is written
at exactly two moments — a scope change, and the close. Adding work is neither,
and **when a request reads both ways**, ask with `AskUserQuestion` first. Adding a
repository **is** a scope change, so it syncs when it happens; held back until the
close it is invisible to every other session.

`closing-campaign` step 4 is the only sanctioned write, at either moment: it
compares the body against the copy the campaign `README.md` was derived from and
refuses when it has moved, so one write cannot silently discard another.

## Delegate launch

Any `herdr` command that drives a pane, or resolves its target implicitly, is
guarded by `test "${HERDR_ENV:-}" = 1` and names its target explicitly; the guard
is against acting on somebody else's session, never against reading.

A delegate is launched by the planner in `<campaign>/repos/<repo>/` with
`--append-system-prompt-file <campaign>/AGENTS.md`, because ancestor instruction
files load only behind a dialog that defaults to declining. Four invariants: the
brief is **a file** named by a one-sentence prompt; the prompt is delivered by
**`herdr agent prompt`**, never on the launch line; **a canary** proves the
injection arrived, since nothing on disk records it; and **read the pane once
after every launch**, because the dialogs that halt a fresh delegate do not all
report `blocked`. A campaign `AGENTS.md` only ever *adds*. The full procedure —
the launch line, the outcome names, the canary and the three dialogs — is
`.claude/skills/opening-campaign/references/launching.md`.

# The running agent

## Completion, liveness, and local-only work

Three readings, and never answer one with another.

- **Completion is a GitHub fact.** A sub-issue is settled when its issue is closed —
  as completed with its pull request merged, or as **not planned**, which is how a
  sub-issue gets dropped. Both readings are needed, or a sub-issue dropped on purpose
  never reads settled and its campaign can never close. **Nothing on a terminal
  screen is evidence.** `campaign-tracker settlement <N>` is the one reader.
- **Liveness and attribution are different readings, and a gate needs both.**
  `herdr agent list` gives liveness for every session here and no attribution;
  `runtime/claims/` gives attribution and cannot prove liveness, its `pid` reading
  dead after a restart its session survived. `campaign-claim live <N>` makes both
  and joins them on the harness session id, the only field *on both sides* that
  survives a restart and a rename; it concludes nothing, a close reads its counts.
  Read a delegate's progress from its transcript, never from `agent_status`, which
  reports the screen and calls a mid-turn pause `idle`.
- **What exists only on this machine is the third question**, and
  `scripts/campaign-local-work.py <N> [dir]` is its one reader.

## The four messages

`spec/campaign/orchestration/system.als` is the contract; this is the short
form. `ListAgents` resolves the address; herdr's pane label is not one.

| message | direction | carries |
| --- | --- | --- |
| `STATUS` | campaign → agent | doing what, blocked on what, what exists only on this machine, safe to stop |
| `REPORT` | agent → campaign | a pull request URL and the sha it sits at, once per round, unsolicited |
| `BLOCKED` | agent → campaign | a decision that is not the agent's to make |
| `STAND DOWN` | campaign → agent | finish the turn and stop |
| `STOOD DOWN` | agent → campaign issue | a comment, first line `STOOD DOWN <name> <session-id>`, posted by `campaign-claim stood-down` after the agent's work is on GitHub and its claims are released |

Four messages between sessions, carrying **only what the agent alone knows**:
anything about finished work duplicates a GitHub fact, and the copy is what goes
stale. **The claim is not among them** — it is a record, not an announcement.
**`STOOD DOWN` is the one that leaves a record**, because the close gate reads
agreement from it: `campaign-claim live` joins the comment to the session's
herdr row, so a stood-down peer passes the close whatever its cwd, and a peer
that has not is asked, never killed.

**A verdict, a fix report, or a `REPORT` that does not pin its sha is
unactionable**: verdicts and pushes race. **Between sessions, a relay is never the
authority** — an owner's word arriving through a peer is acted on through the
durable artifact it points at, read on GitHub yourself, or in your own pane.

**Shutdown is two steps, and both are yours.** `STATUS`, verify durability in
GitHub, then `STAND DOWN` — on the agent's own machine, since a verification run
from elsewhere reads *its* working tree and comes back clean regardless.

## The claim record

**Every claimant writes a record, and `scripts/campaign-claim.py` writes it**, so the
shape lives in one place and a delegate runs the script rather than copying it.
The session that *launched* a delegate writes none *of its own*: it holds no
claim, and a second address would make the close gate count one claim twice --
the record it writes at launch names the delegate's session, not its own. Each field answers
one question — liveness from `pid`, addressing from `name`, and `session` when both
have gone stale, it being the only field on **either side of the join** surviving a
restart and a rename. A name that no longer resolves is a stale record, not a dead
session: re-derive it by asking peers which one holds `session`. **A directory with
no `runtime/claims/` cannot be enumerated, and that is a refusal rather than a
pass**: an empty one says no claim was taken, a missing one says nothing.

## Merge conditions

**Three conditions gate a merge, and none names a role.** A pull request merges
only when (1) a review has been read **at the sha being merged**, (2) that review
was written by **an agent that did not write the commits**, and (3) the branch
**contains the current `main`** when it merges. Whoever satisfies all three may
merge, the author included; a session that cannot satisfy one may not.

Condition 3 serializes landings: 1 and 2 are each true of a branch *in isolation*,
so containing a `main` that moved means merging it in, that merge is a push, **a
push retires the review**, and the next merge needs a review at the combined sha.
**Condition 3 is enforced by GitHub; condition 1 is readable and read by nothing.**
Whether it still bites is `main`'s `required_status_checks.contexts`, and
`.github/workflows/check.yml`'s header says why. **A branch that has never been a
pull request head has no `check` at all**, so the fast-forward of `main` that
~/.claude/CLAUDE.md § Git prescribes is refused — `HTTP 409: Required status check
"check" is expected`. Land through the pull request, whose head sha carries it.
**Condition 2 has no automatic reader**: one `gh` account signs every session's
merges, so it is held by whoever writes the review saying honestly that it did not
write the code.

**The push that retires a review does not start the next one, and whoever pushed
it asks**, because **a silent wait is indistinguishable from work**: the `REPORT`
names the new sha *and* asks; a session that asked and received nothing stops.

## The fix round

**A fix round is: findings on the pull request, one executor, one `REPORT`.** The
executor verifies each finding at the site it names before touching anything.
Follow-ups fold into the same round, whose boundary is the `REPORT` and never a
push, and which ends in one `REPORT` carrying the sha and a per-finding
disposition. **Check that disposition against the findings list mechanically**: a
round claiming "all fixed" without re-running its sweep is what keeps happening.

## Review

**Every review runs as an in-process subagent. There is no other way to run one** —
not a default and not the cheapest option, the one mode. It is launched by whoever
wants the merge, the author included: merge condition 2 is on who *writes* it.

**Name the model and the level on every launch**, and they answer different
questions: the model by the **depth** of the change, because a weaker reader
returns "looks fine" on exactly the reasoning that needed a reader; the level by
**how much there is to read**, `medium` being the baseline. **The level is the
first token after the command and nowhere else**; asking in the brief sets nothing.

**A session that cannot start a subagent is blocked**: it says so and the pull
request waits, which is never a licence to review some other way. The call itself,
the two knobs in full, the three wrong modes and the shape of a round are
`.claude/skills/opening-campaign/references/reviewing.md`.

## Watching and retiring

**Watch a delegate for `blocked`, not only for gone** — a session at a permission
prompt is still listed and never proceeds, and clearing it is the person's
decision. **Do not trust the absence of that reading either**: a usage-limit menu
and the folder-trust dialog both report `idle`; silence is a liveness question.

**The session limit is a first-class cause of death, and it kills in batches.** An
agent it stopped looks exactly like one still thinking; when several go quiet
together, read the reset time first — an outage to schedule around, not a retry.

Retire finished agents as the campaign runs, not when it closes, and sweep with
all three readings (`campaign-claim live`). A campaign may not close while any
session holds a live claim, or sits under its tree with no `STOOD DOWN` on the
campaign issue; nor may a repository be dropped while an agent works one of its
sub-issues.

# Concurrency

One campaign, one machine settles the hard half: no lock is ever judged stale
across a network. It does not settle the campaign's own writes — the binding
serializes neither the campaign issue body nor the shared directory.

**Two open pull requests over the same normative files are normal, and the second
to land reconciles**, and **containment buys attention from nobody**: a clean
auto-merge produces a commit whose diff against the branch *is* the other branch's
work, exactly what a reviewer skims as "just the merge". So **the review after a
reconciliation reads the combination**, and its brief says so — **the gate is
condition 3**.

**The named cost: no concurrent cross-machine or cloud work on one campaign.**
Another machine may read a campaign, may file a sub-issue of it, and may open a
different one; none may write this one's campaign issue body or `BOUND`, claim, or launch
into it. A campaign reaches another machine only by
migration — the price of a staleness check that is a local `kill -0`.
