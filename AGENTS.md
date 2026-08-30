# agent-workspace

A container for running **campaigns** — units of work across the repositories
they need — on repositories that live elsewhere. `README.md` says what the
container is; this file is how to work inside it. `spec/alloy/ledger.als` says
why these rules are what they are, in its comments, and points at the three
layers stacked above it.

This project is early. Where a rule is missing, decide, do the work, and write
the decision back here.

# What a campaign is

One assignment a person is responsible for, worked across the repositories it
needs, which may be none. Bigger than a ticket, no size ceiling — a week of
migration or the whole life of a product. It splits into subtasks, and
follow-up subtasks keep arriving until someone decides it is over.

A campaign is not a repository and not a ticket. It is what collects the
subtasks of one assignment, and the repositories — none, one, or several — that
assignment needs.

# Not every request is a campaign

Settle this before anything else. Only a campaign that has to be opened, joined
or closed loads a skill; most of what arrives here loads none.

**A person saying a campaign is over is routed before anything is read.** Load
`closing-campaign` and stop here. Only a person decides a close, and the two
readings below would take a close request for a subtask of the campaign it
closes.

Otherwise, two readings decide it, in this order.

**One: does any open campaign's Scope cover the request?**

```sh
gh issue list -R kalaluthien/agent-workspace --label campaign \
  --state open --limit 200
```

Read the body of each one that could plausibly cover it (`gh issue view <N> -R
kalaluthien/agent-workspace`); the title alone does not carry the Scope. Match
on Scope, never on `## Repos`, and treat testing or fixing a campaign's own
deliverable as covered by it, because Scope is written in artifacts and cannot
separate "build X" from "validate X".

**That tracker holds subtasks and unrelated issues too**, so cross-check the
hand-applied label against the one property a subtask cannot have — no parent.
The three kinds are § When the container is a member of its own campaign.

```sh
gh issue list -R kalaluthien/agent-workspace --state open --limit 200 \
  --json number,title,parent \
  --jq '.[] | select(.parent == null) | "#\(.number)\t\(.title)"'
```

**`--limit` on both, because the default is thirty and newest first, and anchors
are the oldest issues on this tracker.** The second listing fetches every open
issue to filter it, so it truncates hardest exactly where it is most needed: a
tracker whose thirty newest are all subtasks returns no anchor and looks clean.

An issue in that output but not in the labelled listing may be an anchor whose
label was forgotten. § When the container is a member of its own campaign
says how to read its body, and that reading decides, not this listing. A
labelled issue *missing* from it is a subtask wearing the label; say so rather
than joining it.

**Two, only if nothing covers it: is the request finished when this session
ends?** A campaign is work that outlives the sitting — it splits into
subtasks, is handed to agents, and keeps producing follow-ups until a person
calls it over. A question answered, a file corrected, one change that lands
complete, is none of that and needs none of it.

| what the two readings say | what this is |
| --- | --- |
| An open campaign's Scope covers it | **A subtask of that campaign.** Read the binding first (§ Who is a campaign session): filing a sub-issue writes the anchor's index, and that is a write. Then § Running a campaign, "Subtasks", files it. Load `opening-campaign` only to *join* — this machine is not holding the campaign, or has no directory for it. |
| Two or more could cover it, or the fit is arguable | **A question for the person.** Name the candidates; do not guess. |
| Nothing covers it, and it ends with this session | **Not campaign work.** Answer it, or make the change and land it. No anchor, no subtask, no directory, no skill. |
| Nothing covers it, and it will outlive this session | **A new campaign.** Load `opening-campaign`. |

Size is not one of the readings, and asking it first is the mistake this
ordering prevents. A one-line edit inside a campaign's Scope is that campaign's
subtask, because the sub-issue index is the only place its close can look and
work done beside it is invisible there. The converse holds as plainly: a large
change that no campaign's Scope covers and that finishes here is still not a
campaign.

**Not campaign work is not unmanaged work.** The container's own git rules hold
whatever the work is — its own branch, a pull request, and the `pre-commit`
guard that refuses a direct commit to `main`. Those are this repository's rules
rather than a campaign's, so a change lands here without being anybody's
subtask.

# Who is a campaign session

**A campaign runs on one machine at a time, and on that machine one session
holds it.** Any session opened in the container root is a candidate. Which of
three roles it takes is read rather than assumed, from two facts that cost one
call each: the anchor's latest `BOUND` comment says which machine the campaign
is on, and the campaign directory's `runtime/holder` says which session on that
machine holds it.

| what the two readings say | this session is |
| --- | --- |
| `BOUND` names another machine | **not in this campaign.** Stop before any write and before any launch, and name the machine that holds it. |
| `BOUND` names this machine, and there is no directory or its holder is dead | **the holding session.** Take it: scaffold the directory if there is none (`opening-campaign` steps 2 and 4 — step 4 needs the slug and kind step 2 picks), write `runtime/holder`, and carry on. |
| `BOUND` names this machine, and `runtime/holder` names a live session | **an executor session** on one subtask; see below. |
| there is no `BOUND` comment | **not bound yet.** Only a person's word binds an existing campaign; see below. |

**An executor session is an agent, not a second campaign session.** It files the
subtask it was given or takes the one it was handed and claims the branch — and
it writes `runtime/claims/<issue>` for itself when the claim is its own to hold,
which is the case where it works the subtask with its own hands. When it
launches a delegate instead, the claim is the delegate's and the delegate writes
the record; § Talking to a repository agent is the one statement of which is
which. From the claim it is in the protocol below: it answers `STATUS`, sends `REPORT` and `BLOCKED`, stops on `STAND DOWN`,
and never surveys, never syncs, and never closes. It **may** land its own work,
on the three conditions § Talking to a repository agent states — a review read
at the merged sha, written by an agent that did not write the commits, and a
branch containing the current `main` — which is what replaced "an executor never
merges its own pull request". It works the subtask
whichever way § Running a campaign allows, subject to the mode rule there; what
changes is only who it reports to.

The holding session is the peer the person named. When nobody named one, ask
every peer session, and a peer that holds no campaign covering it says so.

**`BOUND <machine>` is a comment on the anchor, and the latest one is
authoritative.** Comments append, so writing one races nothing; that is why the
binding is a comment and not the body. Its first line is `BOUND <machine>` with
the machine from `hostname -s`, and anything after that line is prose for a
person — a migration says there why.

**The reading has one reader, `scripts/campaign-bound <N>`**, and it prints one
of three words:

```sh
scripts/campaign-bound <N>      # here | elsewhere <machine> | unbound
```

`here` is the only one that licenses a write. `elsewhere` names the machine to
say so with. `unbound` licenses asking the person, never binding on your own.
**Read the word, never the exit status** — the status is about the reading, as
it is for `campaign-local-work` and `campaign-session-alive`, and for the same
reason: a failed read that exited like `unbound` would invite a session to bind
a campaign another machine is working.

Four things that reading has to get right, each of which is a way to be wrong,
and all four now live in the script rather than in prose: `--paginate`, because
comments page at thirty and a truncated listing reads exactly like a complete
one; oldest-first, so the *last* match is the current binding and taking the
first returns the original binding forever; the first line only, because a
migration annotates its binding and `tail -1` over whole bodies takes the last
line of that prose (probed 2026-08-29); and a trailing `\r`, which a body stored
with CRLF leaves on the machine name so that it matches nothing. The script also
folds in the comparison against `hostname -s`, which all three call sites ran as
their next line and compared by eye.

Read it before every write to the anchor — body, comment, or sub-issue link —
and before launching any executor onto one of its subtasks.

**A session posts `BOUND` in exactly two cases**: for a campaign it has just
filed itself, and when a person tells it to. The second is migration, and it is
the person's call because its premise is that the other machine has released the
campaign or is dead, and nothing here can observe either. Post it, then read it
back: a later `BOUND` naming somebody else means the campaign was migrated out
from under you, and the latest one still wins. A campaign with no `BOUND`
comment predates this rule; holding its directory is not the fact that binds it,
the person's word is.

**`runtime/holder` is the campaign directory's record of the holding session**,
written when a session takes the campaign and read by every session arriving
after it:

```sh
printf 'session %s\npid %s\n' "$CLAUDE_CODE_SESSION_ID" "$CLAUDE_PID" \
  >| "$CAMPAIGN/runtime/holder"
```

`CLAUDE_PID` is the `claude` process; `$$` is the shell one tool call runs in
and is dead before the next one starts. Liveness has one reader,
`scripts/campaign-session-alive`, and a caller turns its outcomes into one of
five words:

```sh
if [ ! -s "$CAMPAIGN/runtime/holder" ]; then V=none
else
  PID=$(awk '$1 == "pid" { print $2 }' "$CAMPAIGN/runtime/holder")
  V=$("$CONTAINER/scripts/campaign-session-alive" "$PID" 2>&1) || V="unreadable ($V)"
fi
echo "$V"
```

`CONTAINER` is resolved the one way § Three planes gives, which is also where
both skills resolve it before calling this.

**Only `none` and `dead` let you take over**, and they are the two absences this
reader can confirm: no holder was ever recorded, and the recorded pid is held by
nobody. **`dead` is an absence of the process, not of the session.** A harness
restart hands a surviving session a new pid, so any record written before one
reads `dead` while the session that wrote it is still working — measured
2026-08-30, when the claim record for #62 — then at `runtime/executors/62`,
before #59 renamed the directory — named pid 24840, that pid read `dead`,
and the session that wrote it was alive at another pid in the same minute. When
the record predates a restart, `dead` is stale rather than absent, and only
asking the session settles it.
`alive` is the holder still working. `other` is a pid held by something whose
name this install does not know — a recycled pid *or* a differently-named
claude, and nothing here can tell those apart. `unreadable` is the reading
itself failing, and it carries its reason. The last three mean leave it alone,
because the act on the other side destroys a tree or overwrites a live holder,
and only a confirmed absence is safe to act on. **Read the word, never the exit
status** — the status is about the reading, as it is for `campaign-local-work`.
Testing the file before the pid is what keeps a *missing* holder from arriving
as `unreadable`, which would be an absence wearing the word for "I could not
look".

**Never hand-roll the comparison.** It was four prose copies of `[ "$(ps -o
comm= -p "$PID")" = claude ]`, and that test reads a live session as **dead**:
`ps -o comm=` reports how a process was invoked, so the same build answers
`claude` through a wrapper and its full path when exec'd by path. Measured
2026-08-29 on three live sessions of one campaign, two through a wrapper and one
by path, while both readers below were about to run over them. The script keeps
`kill -0` for existence, because a syscall against your own process table cannot
fail the transient way running `ps` can, and reads the name from `ucomm`, which
is invariant across *how* a process was started. `ucomm` is the exec'd file's
basename rather than an identity, so the names it matches are a fact about this
install — which is why an unrecognised one is `other` and not `dead`.

**The name is narrower than the job, and #93 owns that.** The holder role is
not retired — it still decides the scaffold, the anchor body and the close,
which are the campaign-wide writes that genuinely need one writer. What left the
role is **merge authority**, which is now three conditions on the work. So what
this file records is whether a live session on this machine owns this tree, and
that job never depended on the merge rule at all. The path is left standing
because it is a live file with references across every skill and asset, and
moving it inside a sweep is how a migration loses a record.

This lock rots one way, and a restart is the way: staleness is a local process
fact rather than a guess about a machine you cannot see — which is what pinning
the campaign to one machine was bought for — but a pid stops naming its session
the moment the harness restarts, and nothing in the record distinguishes that
from an exit. The session id is the field that survives, and only
`runtime/holder` carries one. It errs towards refusing to take
over, and does so two ways: a pid recycled onto a different `claude` reads
`alive`, and a pid recycled onto anything else reads `other`. Both refuse, and
`spec/alloy/session.als` states them together under R3g — the one place that
residue is written, because a model is a reader that can be measured wrong and
prose is a reader that cannot. Ask rather than overwrite. `runtime/`
dies with the directory, which is the right lifetime — nothing off this machine
reads the holder.

**Holding scaffolds.** `runtime/holder` and `runtime/claims/` have no home
but the campaign directory, so a session that takes a campaign on a machine
with no directory creates one first — `opening-campaign` steps 2 and 4, with
nothing to acquire; step 4 builds `<slug>-<YYMMDD>/` and copies the kind's
principles, so step 2, where both are chosen, cannot be skipped — and a held
campaign has a directory from that moment. Campaign #1
ran without one, and its first claim had nowhere to be recorded
(#52): the record half of the protocol did not exist on exactly the path #46
had made first-class. The fix is the scaffold rather than a second home for the
record, because a record that outlives the tree it describes is what
`runtime/`'s lifetime exists to forbid; `spec/alloy/session.als` R1m and R1n
are the retired branch measured.

Those two readings replace the rule that stood here, *several sessions may hold
one campaign, on one machine or on several*, and they change what the four rules
below are for. Each was written from a witnessed breakage; under the principle
two survive unchanged, one holds by construction, and one inverts.

- **Survey again at the moment you file.** Two sessions that each checked the
  open anchors before either filed will both file, and one scope gets two
  campaigns. Re-reading immediately before `gh issue create` narrows that
  window; it does not close it, because read and create are not atomic. The
  principle buys nothing here: a campaign that does not exist yet is bound to
  nobody, so this is the one window `BOUND` cannot narrow.
- **Claim the branch before you launch onto it**: `campaign-<N>/<issue>-<topic>`,
  created on the remote by create-ref, which refuses an existing ref. The
  campaign number keeps two campaigns apart and the issue number keeps two
  subtasks apart, but two sessions delegating the *same* subtask still landed
  on one branch — until the branch became the claim. A refusal means the
  subtask is taken; read who by, do not push past it. This is what serializes
  executors *within* the bound machine, and the principle leaves it untouched.
- **Retire only an agent on your own machine.** Under the principle every agent
  of a campaign is on the machine it is bound to, so this now holds by
  construction. It is kept for the one window where it does not: just after a
  migration, when an agent may still be running on the machine the campaign
  left. Ask the session that launched it, or leave it.
- **Holding the directory with a live holder *is* owning the campaign.** This
  rule read the other way round, because two sessions given the same slug on the
  same day build the same path and neither could tell whose tree it was.
  `runtime/holder` answers exactly that, so a session arriving to a live holder
  is an executor rather than a peer. What survives of the old blind spot is
  narrow: the local no-live-agent gate still cannot see a machine working this
  campaign against its `BOUND`. So `closing-campaign` still says in the anchor
  issue that it is closing — as the guard for a broken principle, not as the
  normal path.

- **ID** — the number of its anchor issue in `kalaluthien/agent-workspace`.
  Typed as `#N`. The anchor carries the `campaign` label, and that label is what
  makes it findable — every survey lists by it, so an anchor filed without it is
  in nobody's listing and the next session opens a second campaign over the same
  scope.
- **Directory** — `<slug>-<YYMMDD>/` at the container root, git-ignored, and
  **optional off the holding machine**. A campaign is its anchor issue; the
  directory is one machine's cache of it, and the machine that holds the
  campaign always has one, because the holder and claim records live there
  and nowhere else. A campaign legitimately has none here when this machine
  does not hold it — not taken here yet, or bound elsewhere.

  So closing a campaign and deleting a directory are different acts that
  `closing-campaign` happens to perform in one step. Closing is the anchor issue
  changing state; deleting is a cache being dropped, and the campaign survives it
  — demonstrated, not assumed: the settlement listing reads the same from a
  machine whose directory is gone. A campaign bound here with no directory is
  taken first — scaffolded, so the close's gates have a record to read — and
  then closed; the delete removes what the take made.
- **Branch** — `campaign-<N>/<issue>-<topic>` in every member repository, and it
  is the subtask's claim as well as its workspace. `<N>` keeps two campaigns
  from colliding on the remote; the issue number keeps two subtasks of one
  campaign apart; and the branch's *existence* keeps two executors off one
  subtask, because the launcher creates it on the remote before any work:

  ```sh
  SHA=$(gh api repos/<owner>/<repo>/commits/main --jq .sha) || exit 1
  gh api repos/<owner>/<repo>/git/refs \
    -f ref=refs/heads/campaign-<N>/<issue>-<topic> -f sha="$SHA"
  ```

  **The sha comes from the remote**, which is what the claim is cut from — not
  from a checkout, whose `origin/main` may be stale, absent or unfetched, and
  which a repo-less subtask does not have at all. One block claims every
  subtask, and `opening-campaign` adds only the checkout-side `fetch` and
  `switch` for a subtask that has one. It is resolved and checked before the
  create, never written inline: a read that fails and still prints goes up as
  the sha and comes back as the 422 that means "already claimed", so the subtask
  reads as taken and is abandoned.

  create-ref refuses an existing ref server-side, at any SHA (probed
  2026-08-28: HTTP 422 "Reference already exists"), so the claim is atomic
  where a survey-then-file is not. The number is minted when the subtask is
  filed, so the claim follows the filing; the executor then works a branch
  that already exists on the remote, and a crash before the first commit
  still leaves the claim visible from every machine. A claim whose branch
  holds nothing beyond `origin/main` may be released — deleted — only when no
  agent on *your* machine works it; a live agent elsewhere that has not pushed
  loses its claim to that rule, which is one more reason it pushes early.
  The branch is not a name. **Every session on this machine is named
  `campaign-<anchor>-<role>-<n>`** — see § Naming a session — so a name says what a
  session is doing, and a reader who wants the branch reads the claim record or
  GitHub. **Never test a name against a branch**: they are two strings on
  purpose, and a test that treats them as one finds whatever happens to match
  and misses the rest.

# Naming a session

**`campaign-<anchor>-<role>-<n>`.** One rule for every session on this machine,
whatever it is doing.

- `<anchor>` — the campaign's anchor issue number.
- `<role>` — `executor` or `reviewer`.
- `<n>` — a number distinguishing sessions that share the first two, assigned in
  the order they appear.

```
campaign-1-executor-1        an executor on campaign #1
campaign-1-executor-2        another one
campaign-61-executor-1       an executor on campaign #61
campaign-1-reviewer-1        a reviewer on campaign #1
```

**The subtask is deliberately not in the name.** A session works several
subtasks — in parallel or one after another — and renaming it at each handover
would make the name track the work in hand rather than the session. Witnessed
the day this rule was written: a session named for subtask #80 picked up #88 an
hour later, and its name was false from that moment. **A name identifies the
session for as long as it runs; the claim record says which subtask it holds.**

**A delegate is an executor** and gets no role word of its own. Where it runs — a
clone under `<campaign>/repos/`, rather than this checkout — changes how it is
launched and how its liveness is read, not what it is doing.

**A session has two names and neither propagates to the other** (measured
2026-08-30), so `scripts/campaign-name-session` sets both from one call and is
this rule's one consumer — it refuses a name the rule does not admit rather than
applying half of it:

```sh
scripts/campaign-name-session <pane> <name> [<pane> <name> ...]
```

Underneath it is the two herdr calls, which is what to run by hand if the script
is not to hand:

<!-- unguarded: campaign-name-session -- the documented fallback for when the script is not to hand; a reader who needs these two lines cannot call it -->
```sh
herdr agent rename <pane> campaign-<anchor>-<role>-<n>
herdr agent prompt <pane> "/rename campaign-<anchor>-<role>-<n>"
```

The second is the harness name — what `ListAgents` resolves, what a peer
addresses, and what the claim record's `name` field holds. The first is what
`herdr agent list` shows. A session renamed on one path only answers to two
different names depending on who is asking.

**A rename that does not take is a permission question, not a tool guard.**
`herdr agent prompt` drives any pane, the caller's own included; whether a given
call is *allowed* is a permission decision, and it is not stable. Measured
2026-08-30 on one machine: refused on one session, then accepted on that same
session; accepted on a peer, then refused on that same peer minutes later. So
build on no outcome at all. Run the script, read what it reports applied and not
applied, and confirm with `ListAgents`.

**This retires the rule that made a delegate's name its branch with the slash
flattened.** One rule replaces two, so nothing has to remember which kind of
session it is looking at, and **never test a name against a branch** survives as
a consequence rather than as a workaround: they are two strings on purpose, and
under this rule the name does not carry the subtask at all.

# Three planes

Every artifact belongs to exactly one, and the plane decides where it is stored
and whether it survives the machine. Identify the plane before any git command.

| plane | holds | stored in |
| --- | --- | --- |
| **container** | `AGENTS.md`, `CLAUDE.md`, `README.md`, `.gitignore`, `.claude/`, `spec/`, `docs/`, `scripts/` | this repository |
| **member repository** | the code and its history | each repository's own remote |
| **campaign** | which repositories, what for, how far along | GitHub issues |

`spec/` holds what is normative — the models that check the design, as Alloy
files whose comments are the spec. No markdown lives there: prose beside a model
drifts from it, prose inside it cannot. `docs/` holds views drawn for a reader,
as HTML. The two are kept apart and neither inherits the other's rules, so a
markdown file under either is misfiled rather than temporary.

The campaign directory holds no plane of its own. It is a scratch assembly of
things already versioned elsewhere, so it is git-ignored on purpose and nothing
durable may live only there. `.gitignore` is an allowlist over the container
row: a new tracked directory needs its own `!` line.

**A campaign with no member repository does not bend that rule; it is the case
that tests it.** Such a campaign's `<campaign>/scripts/` is tooling and scratch
by design — a script written to answer this campaign's question, thrown away
with the tree. Its lasting results live where any campaign's do: in the anchor
issue and its sub-issues, in this container's memory pool, or in a repository it
lands work in by hand. Making the container a member so that `scripts/` could
survive is the other reading and it is rejected: it would make every repo-less
campaign not repo-less, for the sake of committing scratch.

So the close makes the claim checkable instead of hoped for. Before deleting the
directory, `closing-campaign` lists every entry under it outside `runtime/` and
`repos/` — files, directories, symlinks, because `rm -rf` destroys all of them —
into the closing comment on the anchor, one comment, the one it already posts.
The scaffold's own `AGENTS.md`, `CLAUDE.md`, `README.md` and `scripts/` are on
every such listing, being template copies; the listing filters nothing, because
a filter that guessed would be the thing that dropped the one file somebody
wanted.

**Resolve the container root one way, everywhere:**

```sh
CONTAINER=$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd -P)
```

The container root is the main checkout by definition, and this form returns it
from anywhere — including a linked worktree, where `git rev-parse
--show-toplevel` returns the worktree instead. The two forms agree everywhere
else, so a pair of tools that disagree about which to use tests green and then
strands a campaign: opened inside a worktree by one, invisible to the other,
with a refusal message pointing at the wrong problem.

Never run one git command across member repositories, and never commit their
files here.

# When the container is a member of its own campaign

The container gets cloned into `<campaign>/repos/agent-workspace/`, so one
repository has two checkouts: the **outer** one the campaign session runs from,
and the **inner** clone a delegate works in, which the outer git-ignores. Read
both hazards with one command, before launching a delegate, right after merging
its pull request, and before the campaign session next edits anything here:

```sh
CONTAINER=$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd -P)
git -C "$CONTAINER" fetch origin -q
git -C "$CONTAINER" rev-list --left-right --count origin/main...HEAD   # want "0	0"
```

- **Behind is a merged pull request you have not caught up to.** Editing from
  here can silently revert work that already landed. `git pull --ff-only`, and
  read zero again before editing.
- **The clone must not be behind *at launch*.** The rule first written here —
  "do not clone while the container is ahead" — is the wrong invariant, and a
  live run disproved it: the check read `0	0` immediately before both clones,
  so by that rule the clone was safe, and three commits landed on `origin/main`
  between the clone and the launch, leaving the delegate `3	0` behind. On a
  campaign of any length the remote moving in between is normal, not an edge
  case. So check inside the clone, at launch:

  ```sh
  git -C <campaign>/repos/<repo> fetch origin -q
  git -C <campaign>/repos/<repo> rev-list --left-right --count origin/main...HEAD
  ```

  A delegate launched behind obeys an `AGENTS.md` this session has already
  superseded, and nothing reports it. Pull the clone, then launch. Pushing the
  container before cloning is still worth doing, but it is not sufficient and
  was never the thing that mattered.
- **A skill edited inside the clone does not change the running campaign**, and
  that is deliberate — the tool must not move under a session using it. It takes
  effect only once merged and pulled.
- **One tracker then holds three kinds of issue** — this campaign's anchors,
  this repository's subtasks, and everything else a tracker collects: a person's
  request, a bug somebody else filed. All three are drawn from one number
  sequence.

  **Structure classifies. Body shape is the layer under it, not beside it.** An
  anchor is an issue labelled `campaign` with no parent; a subtask is an issue
  with a parent, labelled or not. The parent relation is the strong half — it is
  an API relation, so no edit to a body can forge it or lose it — and the label
  is applied by hand, so the two readings cross-check each other and both are
  cheap:

  ```sh
  gh issue list -R kalaluthien/agent-workspace --state open --limit 200 \
    --json number,title,parent --jq '.[] | select(.parent == null) | .number'
  ```

  Each kind has a body template — `.claude/skills/opening-campaign/assets/`,
  `README.md` for an anchor and `subtask.md` for a subtask — and filling one is
  what decides the kind at create time, before any relation exists to read. So
  body shape answers the case structure cannot: an issue with no parent and no
  label is an anchor whose label was forgotten if it carries the anchor
  template's sections, and a subtask filed without `--parent` if it carries the
  `Campaign: owner/repo#<N>` line. It never overrules the parent relation, and
  reading it is a person's job — prose is editable and the relation is not.

  **An issue matching neither template is the third kind, and every reader leaves
  it alone**: not surveyed as an anchor, not counted as a subtask, never edited
  or closed by a campaign flow.

  Neither reading is enforced by GitHub, so `scripts/campaign-settlement` reports
  a mismatch instead of guessing — from labels and the parent relation only,
  because a script that classified by prose would change its answer when somebody
  reflows a paragraph. Never survey the container's issues unfiltered: the plain
  `gh issue list` here is mostly subtasks.

# Running a campaign

**Open** — a person arrives in the container root with a sentence, an issue
number, or a screenshot. § Not every request is a campaign says what it is, and
most of what arrives loads no skill at all. Load `opening-campaign` when the
request opens a campaign, or joins one this machine is not yet holding.

**Subtasks** — one subtask is one GitHub issue, filed on the repository whose
code changes, and created **as a sub-issue of the anchor**:

```sh
gh issue create -R <owner/repo> --parent https://github.com/kalaluthien/agent-workspace/issues/<N> ...
```

That one flag is the whole index. Read it back with

```sh
gh api --paginate repos/kalaluthien/agent-workspace/issues/<N>/sub_issues
```

which returns exactly the campaign's members, in any repository, public or
private (probed 2026-08-28: a sub-issue in a private repository lists correctly
under a public parent). `--paginate` is not optional: the endpoint pages at
thirty, and a truncated index reads exactly like a complete one. The link is made by the same command that creates the
issue, so there is no second write to forget, and it is prunable — moving a
subtask out of the campaign removes it from the index, which a back-reference
or a search over body text cannot do.

Fill the body from the subtask template,
`.claude/skills/opening-campaign/assets/subtask.md`: the `Campaign:` line, the
work, and a `Done when` close. That line is prose for a person reading the raw
issue — it is not the index and nothing queries it. What the filled shape does
carry is the issue's kind, readable without an API call; see § When the container
is a member of its own campaign.

**A discovery becomes a subtask at the moment it is found.** Work that turns up
mid-task and falls outside the current subtask's scope is filed then — a
sub-issue of the anchor, body from the same template — by whoever can file it:
the finder, or the campaign session the moment a delegate reports it. A finding
held in a session's memory or parked in a report is invisible to every other
session, dies with the pane that found it, and reaches the close as nothing at
all, because the index is the only place the close can look.

The anchor's **`## Repos`** section still earns its place: it says which
repositories to clone when a campaign is opened, before any subtask exists. It
is a markdown heading followed by a plain `- owner/repo` list, in the issue body
and in the campaign `README.md` alike — the same heading, so a reader written
against one works on the other.

**A campaign with no member repository writes `- none` as the whole list**, body
and `README.md` alike. An *empty* list stays refused, because an empty list is
indistinguishable from a list a bad write dropped, and the list is the only copy
of the campaign's repository index that the close does not delete. `- none` is a
deliberate entry and reads as one.

**`- none` is retired, never joined.** Adding the first repository replaces it:
the list is `- none` alone or it is repositories, never both. A mixed list is
refused because it is *ambiguous* — nothing in it says whether `none` is a
sentinel somebody forgot to remove or a repository the list means to name — and
neither reading can be acted on. The alternative, teaching `acquire-repo` to
skip `none`, moves the refusal to the next machine that opens the campaign and
several steps past the person who could have fixed it; refusing at the list is
refusing where the list is written.

So the list has one reader and it is a script — `scripts/campaign-repos <path>`,
which prints one `owner/repo` per line, prints nothing and exits 0 for a list
that is exactly `- none`, and exits 1 with one line naming which of the five
faults it found: no `## Repos` heading, a malformed line under it — anything
that is not `- owner/repo` or `- none`, which is also what a surviving
`<owner/repo>` placeholder is — an empty list, a mixed list, and two entries
whose checkout directory `repos/<name>/` would collide. `opening-campaign` step
4 runs it and writes `runtime/repos`; step 5 reads that file; its passage on
adding a
repository runs it again before the sync; and `closing-campaign` step 4 runs it
over the README and over the body GitHub stored. A rule nothing must consume is
a rule that drifts, and this one had drifted into three prose copies before it
had a reader.

Two of those five are about a wrong list reading as `- none` rather than as
wrong. A line under the heading that is not a `- ` item was silently skipped, so
a list written `* owner/repo` was an empty list and an empty list is one bad
write away from a lost index; and every entry becomes a checkout at
`repos/<name>/`, so `a/web` beside `b/Web` is one directory on this filesystem
and the second acquire overwrites the first without a word.

Its subtasks are filed on the container tracker, `kalaluthien/agent-workspace`,
as sub-issues of the anchor exactly like any other — it is the only tracker
there is. **And the claim is create-ref on the container** for
`campaign-<N>/<issue>-<topic>`, even when no container code will change: the
branch is the claim before it is a workspace, and without it two executors on
one subtask are serialized by nothing. It is released the way any claim is
released — a claim whose branch holds nothing beyond `origin/main` may be
released, deleted, **only when no agent on your machine works it**.

Read that guard twice here. It rests on an agent being visible, and a repo-less
subtask is worked by a session's own hands or by an in-process subagent — work
whose session does have a row in `herdr agent list`, which carries every session
on this machine, and whose row does not say which subtask it holds. So that
listing can neither confirm nor deny abandonment: its silence is not evidence
that such a claim is free, and a row in it is not evidence that one is held.
`<campaign>/runtime/claims/` is the reading that answers it — the record a
claiming session wrote for itself names the branch it holds and the pid to test
it by, which is what that record exists for — and only a claim named by no
record and answered by no peer (`STATUS`) may be deleted.
Leave it standing if nobody answers: deleting it costs the one thing keeping two
executors off the subtask.

**The one exception is the close.** `closing-campaign` step 5 releases every
`campaign-<N>/` ref on the container that still sits at `origin/main`, and it is
allowed to because by then step 0 has established the campaign is bound here and
step 1 that nothing is live under its tree — by both records, `herdr agent list`
and `runtime/claims/`, which is what makes the sweep sighted for a repo-less
campaign, whose executors the listing shows without saying which subtask they
hold. A ref holding commits is printed there, never deleted. Refs
in member repositories are not swept: a merged pull request releases those.

**Such a subtask closes as completed with no pull request**, and
`scripts/campaign-settlement` prints that row as `dropped [completed, no merged
pull request]`. That is the designed reading, stated in the script's own header:
settled is "the issue is closed", and the merged pull request only says which
kind. Quote the note, never the word, and do not add a second reading to the
script to flatter this case.

**Do it here, hand it to a subagent, or hand it to a delegate** — every subtask
runs one of these ways, and the mode is chosen before the work starts.

**The mode is decided first by the repository, and only then by cost.** An
executor that *changes* a repository runs in a process started in that
repository's checkout: a herdr delegate in `<campaign>/repos/<repo>/` for a
member repository, and the campaign session, an in-process subagent on a
worktree, or an executor session for the container itself, which already has the
container's skills. Reading any repository, and writing under `<campaign>/`
— scripts, notes, fixtures — may run in any mode.

The harness fact it rests on: an in-process subagent and an interactive session
load the skills of the session or directory they were *started in*, never those
of another repository however it is checked out; and a skill marked
`disable-model-invocation: true` is unusable by any agent in any mode, so it must
be spelled out in the brief rather than named.

So a **campaign session working with its own hands** can take only a container
subtask or campaign-directory work. For a member-repository subtask it becomes
the launcher of a delegate, and the claim is then the delegate's: the delegate
writes its own record, exactly as a session working with its own hands does, and
the launcher writes none because it holds no claim. § Talking to a repository
agent says who writes one and who never does.

Then, within what the repository allows, choose by cost:

- **Your own hands** when the change is one small edit, holds in view at once,
  and needs nothing from that repository's build or test loop.
- **An in-process subagent on a git worktree of the repository** when several
  independent subtasks can run at once, or when the work is hands-on enough
  that the session should not spend its own turns on it — and the repository is
  already checked out here, which typically means the container itself.
- **A herdr repository agent in a clone under `<campaign>/repos/<repo>/`** when
  the work needs the repository's own conventions and toolchain, when it will
  take many turns, or when two repositories must move at once.

**Weigh the setup against the work.** The delegate mode is the most specified
and the least used: through campaign #1 every subtask ran by the holder's own
hands or a worktree subagent, and the clone-plus-herdr path first ran on #52.
Its price is fixed and paid per launch — a clone kept fresh at launch, a
handover file, a canary round-trip, a pane read, a sweep at the end — and once
the ancestor import is approved for the clone, the delegate loads every
instruction file twice, the outer checkout's and the clone's, which disagree
whenever the clone is behind (observed on #52). So for the container it is the
mode of last resort: a worktree subagent gets the same conventions from the
checkout it was started in at none of that cost. For a member repository it is
the only mode that changes the code, and its price is the reason to give one
delegate a subtask worth many turns rather than many delegates small ones.

An executor session is a fourth executor and not a fourth mode, because nobody
chooses it: a session that arrives in the container root to a live holder simply
is one. What it then chooses is which of the modes above carries its subtask.

All of them carry the same mechanics. The branch is
`campaign-<N>/<issue>-<topic>`, claimed on the remote by create-ref after the
subtask's issue exists because the number is minted there — a refusal means
another executor holds the subtask. Work is pushed as soon as one commit
exists, so a checkout that dies costs uncommitted work and nothing more. It
lands by a pull request, and § Talking to a repository agent says who reviews and
merges it — except for a subtask whose work lives only under
`<campaign>/scripts/`, which has no commit to land: that one closes as completed
with no pull request, its closing comment saying what was built and where the
close listed it. How that reads in the settlement is above.

**A repo-less campaign has the first two modes and not the third.** The
delegate mode is a clone under `<campaign>/repos/<repo>/`, and there is no
repository to clone; its subagent runs with the campaign directory as its
working directory rather than a worktree of anything. The mechanics above are
otherwise unchanged, the container branch being the claim.

The subagent mode needs none of the delegate rules that exist to cross a
process boundary: no handover file, because the brief is passed in-process and
no terminal can truncate it; no canary, because nothing is injected that could
silently fail to arrive; no herdr liveness, because the subagent reports its
own exit to the session that launched it. Completion is unchanged — it is still
a GitHub fact, read from the subtask's issue and pull request.

Parallelism is a reason to hand over on its own. Several independent subtasks
in one repository are each small enough to do here, and a session that does
them here does them one after another.

**Close** — load the `closing-campaign` skill. A campaign closes when its anchor
issue closes, and only a person decides that. The skill refuses while any open
subtask lacks a disposition: a campaign may close over unfinished work, never
over unexamined work.

**The anchor body is a charter, not a status board.** Intent, Scope and
Requirements say what a person signed up for, and change only when the scope
genuinely changes — their decision, not a session's. The body holds no
decomposition of its own: opening files the first subtasks, and the sub-issue
index is the decomposition from that moment on. Progress and membership are
*derived* from it, by `scripts/campaign-settlement <N>`, and never written into
the body.

So the body is filled when the anchor is filed, and after that written at
exactly two moments: a scope change, and the close — each through the
compare-then-write below. Adding work is neither —
filing a subtask touches only the subtask side, `gh issue create --parent` plus
the branch claim, and the index carries it from there. **When a request reads
both ways** — a change to what the person signed up for, or a subtask inside
that scope — ask them with `AskUserQuestion` before writing either side: the two
readings write different things, and only the person knows which they meant.
Copying the index into the body as subtasks settle is the anti-pattern this
names: a hand copy of a listing that already exists, paid for with one
lost-update window per write.

Two moments is not *write only at open and at close*, which `spec/alloy/`
weighs as `syncAtCloseOnly` and rejects.
Adding a repository **is** a scope change, so it syncs when it happens; held
back until the close it is invisible to every other session holding the
campaign, and the loss it was meant to prevent happens at the close anyway.

The campaign's `README.md` and the anchor issue body carry **the same sections
in the same shapes**, and the anchor template
`.claude/skills/opening-campaign/assets/README.md` is the one copy of that shape
— so syncing one to the other is an overwrite with nothing to merge. A README shaped differently from the body forces the
sync to compose, and a compose step is where the repository index gets silently
dropped.

**Compare then write the anchor issue body.** Re-read it immediately before
`gh issue edit`, and refuse if it has moved since your `README.md` was derived
from it. One campaign, one machine gives the body a single structural writer, so
this ceremony is no longer the everyday guard it was written as — it is demoted
to catching the two things the principle does not cover, and from here they look
identical: a person editing the charter straight on GitHub, which is theirs to
do, and a session writing from a machine the anchor is not `BOUND` to, which is
the principle broken. Without it one of those silently discards the other —
modelled and witnessed, and the loss is worse than it looks because a body write
cannot touch a sub-issue link, so the index goes on naming work in a repository
the `## Repos` list has dropped, and the close then deletes that list's last
copy. Step 4 already reads the body back after writing, so the extra read costs
nothing. Neither a delegate nor an executor session writes the body at all.

# Delegating to a repository agent

**A `herdr` command that drives a pane, or that resolves its target implicitly —
`--current`, or a target left out — is guarded by `test "${HERDR_ENV:-}" = 1`.**
That is the herdr skill's own rule: an agent failing it says it is not running
inside herdr and stops. The launches below are guarded, and so is the retirement
sweep in § Talking to a repository agent. **Listing is not**: `agent list` and
`pane list` answer from outside a pane exactly as from inside, so the liveness
reads in § Completion and liveness and `closing-campaign` step 1 need no guard
and get none. The guard is against acting on somebody else's session, never
against reading.

**What degrades outside a pane is the target, and it degrades silently.** Caller
context is what makes `--current` and an omitted target mean "me": stripped of
`HERDR_*`, `herdr pane current --current` returned the **UI-focused** pane — a
peer session's — where from inside the pane the same command returned the
caller's own (both probed 2026-08-29). So name the target on every
pane-addressing command: `--pane "$HERDR_PANE_ID"`, an explicit pane id, or a
unique agent name. `herdr agent list` is not one of them and could not be told a
target if you wanted to — `Usage: herdr agent list`, no options at all.

**That the guard passes on the container's daily path is a measurement, not a
property, and the first plain-terminal or `-p` session here falsifies it.**
Probed 2026-08-29 over three kinds of session on this machine — a campaign
session, a peer executor session and a freshly `agent start`ed delegate — each
carrying `HERDR_ENV=1` and its own `HERDR_PANE_ID`, while a process started
outside any pane carried neither. The pin is herdr 0.8.2, client and server on
protocol 20, `compatible: yes` (read 2026-08-30). A session the measurement does
not cover is exactly what the guard is for: it reports that it has no pane and
stops rather than driving one.

Launch it in `<campaign>/repos/<repo>/` with
`--append-system-prompt-file <campaign>/AGENTS.md`.

Ancestor instruction files *do* load — but only once that directory has
`hasClaudeMdExternalIncludesApproved` set in `~/.claude.json`, which defaults to
**false** and is asked as an interactive dialog. So a freshly acquired
repository, which is exactly what a delegate is launched into, silently gets the
repository's own `AGENTS.md` and nothing above it: under `-p` the dialog never
appears and the import is declined without a word, and interactively the
delegate sits on a prompt that looks from outside like an agent thinking.

`--append-system-prompt-file` depends on none of that, which is why it is the
mechanism rather than a belt-and-braces addition (both probed 2026-08-28: with
the flag, or with approval granted, the campaign's marker loads; with neither,
only the repository's does).

**Check that it arrived, with a canary.** The flag is absent from `claude
--help`'s option list and the appended text never reaches the session
transcript, so nothing on disk records whether a delegate received the
campaign's principles — and a delegate that silently got nothing looks exactly
like one that got everything and ignored it. Asking it would be the self-report
this design refuses everywhere else, so make the answer unobtainable any other
way:

1. Append a one-line token to the file being injected, unique per launch.
2. Launch with `--append-system-prompt-file <that file>`.
3. **Delete the file**, then ask the delegate for the token.

A delegate that answers correctly is quoting something it cannot read, which is
evidence rather than testimony. Verified 2026-08-28: the token came back intact
from a session whose injected file had already been removed.

The campaign's principles are appended to a delegate that already has the
repository's own, so a campaign `AGENTS.md` only ever *adds*; one that
contradicts a repository's conventions puts the delegate in a conflict it
cannot resolve.

- **Write the brief to a file**, `<campaign>/runtime/handover/<issue>.md`, from
  the template `.claude/skills/opening-campaign/assets/handover.md`, and make the
  launched prompt one short sentence naming that path. herdr types its
  launch line into the pane, and a terminal silently drops a line past 1024
  bytes — nothing runs and the launch looks like a slow agent.
- Choose the session UUID in advance (`claude --session-id`) so the transcript
  path is known before the agent starts, and `--name` it `campaign-<anchor>-executor-<n>`,
  the one naming rule (§ Naming a session). `--name` sets the harness name only;
  give it the same herdr pane name too, because the two do not propagate.
- Put the prompt **before** any variadic flag on the `claude` command line.
  `--add-dir` and `--allowedTools` swallow a trailing prompt as one of their own
  values, and the run dies on "Input must be provided".
- Set `CLAUDE_COWORK_MEMORY_PATH_OVERRIDE` to this container's pool. A memory
  pool inside a git-ignored campaign directory dies with the directory.
- **Deliver the opening prompt with `herdr agent prompt <pane> "<text>"`.** A
  prompt put on the launch line is word-split: a launch ending with a whole
  sentence delivered its first word alone, and the delegate reported it had
  been given no brief while the launch looked successful.

  **This form submits and returns; it does not wait.** Every waiting behaviour
  below belongs to `--wait`, which this form does not pass — checked against
  0.8.2's help, where `--until` is defined as "after `--wait`" and the
  indefinite wait is the *settled-state* wait that only `--wait` starts. Two
  runs of this exact form in one session returned immediately.

  **If you add `--wait`, add a `--timeout` with it**, because without one the
  settled-state wait is indefinite and a driver that waits forever looks
  exactly like an agent thinking.

  Three outcomes, and they are not the same news. Only the first can reach a
  caller who did not pass `--wait`:

  | outcome | what it means |
  | --- | --- |
  | `agent_blocked` | the agent was already at an approval or question dialog. **No input was sent** — the prompt is still yours to deliver once the dialog clears, and clearing it is the person's call. This is a refusal to submit, so it does not need `--wait`. |
  | `agent_prompt_stalled` | an accepted submission that started from a non-working state saw nothing move within 5000 ms. The agent has it; something is holding the turn. Go and look. |
  | `timeout` | your `--timeout` elapsed. The agent may be working normally — a long turn reads exactly like this — so read the pane before concluding anything. |

  `agent_blocked` is the one that is safe to act on immediately, because it is
  the only one that tells you the input never landed.

  **The last two overlap, and which one you get is your own choice of
  `--timeout`.** The 5000 ms is the stall threshold, so a `--timeout` shorter
  than it fires first and the same silence comes back as `timeout` instead of
  `agent_prompt_stalled` — the more informative name lost to the smaller
  number. Set it above 5000 ms to keep the two distinguishable. The help
  states no default for `--timeout`, and this file does not invent one — herdr
  does state one where it has one, so the absence is a fact rather than an
  omission.

  **`--wait` does not track turns.** If the agent is already working when the
  prompt lands, that turn's completion may satisfy the wait — so a launch driver
  can read a previous turn's settling as its own prompt finishing, and get a
  success that means nothing.

# What silently stops a delegate before it starts

Three things halt a fresh delegate, and from outside all three look exactly like
an agent thinking. Clear them at launch or watch for them.

| what | how it shows |
| --- | --- |
| the folder-trust question | the delegate sits on a dialog, having read nothing |
| the external-import question for an ancestor `CLAUDE.md` | same, and declining it silently drops the campaign's principles |
| the first shell-command permission prompt | `--permission-mode acceptEdits` covers edits but not shell, so it stalls on its first `ls` |

The launch line has three ways to eat a prompt, all quiet: the 1024-byte
terminal ceiling, a variadic flag such as `--add-dir` swallowing a trailing
prompt, and the word-splitting above. Put the prompt before any variadic flag,
keep it short, and send the brief as a file path.

**0.8.2 narrows this, and by less than it first appears.** `agent prompt`
refuses an agent that is *already* at an approval or question dialog, returning
`agent_blocked` before sending any input. That catches a delegate you come back
to and find parked — not the row above it, because the first shell-permission
prompt appears *after* the opening prompt is accepted, mid-turn, when there was
nothing to refuse. What would surface that one is `--wait` settling on
`blocked`, which the documented form does not ask for. Whether herdr classifies
the external-import dialog as blocked at all is unmeasured, and this file
records its sibling as unrecognised.

`agent start` narrows a different thing, and not the one previously claimed
here: it does **not** wait for a new pane shell — it requires "an existing pane
at an interactive shell prompt" and creates no layout — and no herdr surface
mentions a first-run prompt. What it does is return only once herdr has detected
the expected agent and judged it ready for input, with a startup timeout that
**defaults to 30000 ms** (`agent start --timeout`, max 300000). An agent blocked
during startup comes back as **`agent_not_ready`**, a fourth status name, and
the name stays usable for `agent read` and `send-keys` (bundled skill at 0.8.2).
That the default is stated here, where `agent prompt --timeout` states none, is
itself the evidence that the absence over there is real.

What none of it retires is the folder-trust row. That dialog was seen once not
to appear on a scratch delegate, and one sighting is not a rule — least of all
for the dialog § Talking to a repository agent already records as the one herdr
misreports, which is where the reading rule for it lives and stays.

That rule now stands **measured rather than provisional**. It was written
against a gap a better mechanism would close, and the mechanism arrived and does
not close it: herdr's own Claude integration hook reports session identity, not
state — `pane.report_agent_session` is its only call, and it carries no status
method. Nothing infers `working` from anything but the screen.

# Completion and liveness are different questions

Never answer one with the other.

- **Completion is a GitHub fact.** A subtask is settled when its issue is closed
  — either as completed with its pull request merged, or as **not planned**,
  which is how a subtask gets dropped. Both readings are needed: with only
  closed-and-merged, a subtask abandoned on purpose never reads settled and its
  campaign can never be closed. Nothing on a terminal screen is evidence. A
  delegate that died after pushing has still succeeded; a delegate that is alive
  and chatty may have done nothing.

  Read it with `scripts/campaign-settlement <N>`, which is the one implementation
  of that reading: closed is settled, and the merged pull request only says which
  kind — `complete`, or `dropped` for everything else that is closed. Do not
  hand-roll a second reader; two of them drift, and the campaign's central
  verdict is the worst place for that.
- **Liveness is readable for both kinds of executor; attribution is not**, and a
  gate holding one without the other is blind to half its executors.
  `herdr agent list` is the liveness: it lists every session on this machine,
  delegate or not — measured 2026-08-30 on herdr 0.8.2, three container
  sessions, none of them a delegate. **It gives no attribution at all.** A row
  carries a name, and under § Naming a session no name carries a subtask, so
  the listing cannot say which claim any row holds. It once could, for
  delegates alone, when a delegate was named its branch; #89 retired that and
  `runtime/claims/` is now the only answer for every kind of executor.
  The claim record, `<campaign>/runtime/claims/<issue>`, supplies the
  attribution and not the liveness: the `pid` it names reads `dead` after a
  harness restart its session survived, so it locates a session rather than
  proving one — and its `session` field is what still identifies that session
  once the `pid` and the `name` have both gone stale. Read a delegate's own progress from the session transcript,
  never from `agent_status` alone, which reports the screen and calls a mid-turn
  pause `idle`.
  **Both readings, every time**: the no-live-agent gate in `closing-campaign` and
  the retirement sweep below each run both.

  `ListAgents` alone will not do it. It gives a name, not a subtask, so presence
  there cannot say which campaign a peer is in — which is why the record exists,
  and why a session that wrote no record can be live under a campaign that
  reads closable — a narrower window than the announcement it replaced, because
  the write is the claimant's own and cannot fail to be received.

  **A `cwd` filter cannot scope a campaign with no directory**, because every
  campaign session's `cwd` is the container root: the session transcript is the
  only discriminator, read through the session id herdr reports.
- **What exists only on this machine is the third question**, and
  `scripts/campaign-local-work <N> [campaign-dir]` is its one reader — the
  container's own `campaign-<N>/` branches and worktrees, the container's
  working tree, and every checkout under the campaign's `repos/`. **The
  directory may be given relative or absolute; the script resolves it**, so no
  caller carries that precondition. Its exit status is about the reading and
  never the verdict, so a failed read cannot read as a clean tree — and neither
  can a reading that did not happen: a place it could not read denies `clear`
  and is counted apart from what it found. `closing-campaign` step 2 is one call to it; a second
  reader written out anywhere else drifts the way the settlement rule would.

An agent never closes itself. It finishes by pushing its branch and opening or
updating a pull request, then goes idle; the campaign session retires it once
that work is durable.

**Who reviews, and in which mode.** The reviewer is launched by the session that
wants the merge, **and the author may be that session** — the non-author
condition (§ Talking to a repository agent, merge condition 2) is on who
*writes* the review, never on who commissions it. That is the one-session
landing, and the model pins it: `A16` is SAT, and the old guard forbidding a
review commissioned by the author is gone precisely because it made the legal
case inexpressible (`P2`). `/code-review <PR#>` is the whole opening prompt
either way, because it is model-invocable. The default is an **in-process subagent**: a review only reads,
so it needs none of what a process boundary is paid for — no handover file, no
canary, no pane, no sweep. A **herdr session** is for a review that will take
many turns, or an `ultra` review, which is person-triggered only and never the
default. Feedback then goes to a *fresh* executor, briefed from the pull request
and the review, because a pane held open across a multi-day review is the
expensive thing.

**The review's default shape: one reviewer per pull request, one verifier per
fix round.** Every angle the review should take is a section of the one
reviewer's brief, and the verifier reads the fix commit against the round's
disposition table. Fan out into parallel reviewers only when the angles are
genuinely independent *and* the budget is known to carry them: eight parallel
angles per pull request died twice on the session limit, and one consolidated
pass found findings of the same quality at a fraction of the spend (#52).

**The pull request is the review's working memory.** A finding that exists only
inside a running session is not yet found. Findings are posted as a comment on
the pull request the moment they consolidate, before anything else is launched,
by whoever consolidated them, and a reviewer that runs long writes findings out as it goes
rather than only in its final report. Findings held in a session's context died
with the session limit twice; findings on the pull request survived everything
and let a fix start while the rest of the review was still running (#52).

# Talking to a repository agent

`spec/alloy/agent.als` is the contract; this is the short form. `ListAgents`
resolves the address; herdr's pane label is not one. Where the address comes
from is the difference between the two kinds of executor — a delegate's was
chosen at launch, and a session working its own claim wrote its own into
`runtime/claims/<issue>` — and § Who is a campaign session says which is which.

Four messages, carrying **only what the agent alone knows**. Anything a message
says about finished work duplicates a GitHub fact, and the copy is what goes
stale. **The claim is not among them**: it is a record the claimant writes for
itself, not an announcement somebody must receive.

| message | direction | carries |
| --- | --- | --- |
| `STATUS` | campaign → agent | doing what, blocked on what, what exists only on this machine, safe to stop |
| `REPORT` | agent → campaign | a pull request URL and the sha it sits at, once per round, unsolicited |
| `BLOCKED` | agent → campaign | a decision that is not the agent's to make |
| `STAND DOWN` | campaign → agent | finish the turn and stop |

- **Every claimant writes a record for itself, at the claim, with no
  exceptions.** A session working a subtask with its own hands writes one; a
  launched delegate writes one; the session that *launched* the delegate writes
  none, because it holds no claim and no working tree, and a second address for
  one claim would make the close gate count it twice.

  **The delegate used to be the exception and #89 killed it.** The exception
  read: a delegate needs no record because its `--name` *is* its branch, so
  `herdr agent list` carries both liveness and attribution for it. Under
  § Naming a session a delegate is named `campaign-<anchor>-executor-<n>` and
  the subtask is deliberately absent, so **no row's name is ever a branch
  again**. Left standing, that exception made a live delegate's claim
  attributable by nothing on the machine: no record to enumerate, and a name
  that says which campaign but not which subtask. The release-claim guard —
  a claim named by no record and answered by no peer may be deleted — would
  then read a live delegate's claim as abandoned and delete it.

  So the two readings split by question, and the split no longer has a
  per-kind exception in it: `herdr agent list` gives **liveness** for every
  session on this machine, delegate or not, and says nothing about which
  subtask any of them holds; `runtime/claims/` gives **attribution** for every
  claim and cannot prove liveness, because its `pid` reads `dead` after a
  restart its session survived. Neither substitutes for the other, and a gate
  that reads one without the other is blind to half of what it is gating.

  **The claimant writes it rather than announcing it**, and that is the change
  #59 made. An announcement can fail to be sent, and its absence was invisible:
  an executor that never announced looked like no executor at all, and the close
  gate read straight past it. A record the claimant writes for itself removes
  the *send* as a way to lose it, which is what an announcement added.

  **It does not make the loss impossible, and the model does not claim it
  does.** The claim is a create-ref on the remote and the record is a local
  `printf`; nothing makes the two atomic, so a session can claim and die before
  writing exactly as it could skip `CLAIMED`. `A1` is UNSAT **by construction**
  — `agent.als` says so itself: the same scenario with no discipline conjoined
  and nothing left to disobey, which makes the unrecorded state inexpressible in
  the model rather than unreachable on disk. What bounds the real window is that
  it is short and that the branch outlives it — a claim with no record is still
  a ref on the remote, visible from every machine (the delete under the record,
  `A10`).

- **The record, and this is the one place its shape is written:**

  ```sh
  printf 'session %s\nname %s\npid %s\nbranch %s\n' \
    "$CLAUDE_CODE_SESSION_ID" "<ListAgents name>" "$CLAUDE_PID" "<branch>" \
    >| "$CAMPAIGN/runtime/claims/<issue>"
  ```

  One file per claimed subtask. **The four fields are not equally durable, and
  a reader has to know which is which:**

  | field | from | survives a harness restart | survives a rename |
  | --- | --- | --- | --- |
  | `session` | `$CLAUDE_CODE_SESSION_ID` | **yes** | yes |
  | `name` | `ListAgents`' first line | no | no |
  | `pid` | `$CLAUDE_PID` | no | yes |
  | `branch` | the claim | yes — it is on the remote | yes |

  `name` is how to reach the session now and `pid` is what makes liveness a
  local `kill -0` rather than a guess, but **`session` is the only field that
  identifies the session across everything that happens to it**, which is why it
  is written first and why the record carries it at all. Measured 2026-08-30: a
  harness restart returned every session with its id intact and a new pid, and
  changed the harness names as well — one peer answered to three names in one
  hour. A record holding only a name and a pid can go stale in both fields while
  the session it names is alive and working, and `kill -0` cannot tell that from
  an exit. #76 owns the general problem; this field is what makes the record
  repairable when it bites.

  **Read the fields for what each can answer.** Liveness is `pid` through
  `scripts/campaign-session-alive`. Addressing is `name`, and a name that no
  longer resolves is a stale record rather than a dead session — re-derive it by
  asking peers which one holds `session`, never by elimination over live
  processes, which cannot see a session id at all. Attribution is `branch`.

  **The claimant writes it because a message received is gone the moment the
  session that received it is**, and whoever runs a close or a sweep later may be
  a session that did not exist at the claim. The record has `runtime/`'s
  lifetime: it is on the bound machine, it dies with the directory, and nothing
  off the machine reads it. It is keyed to no session, so a session that takes
  over a campaign directory inherits every address in it.

  **`$CLAUDE_PID` is the `claude` process**; `$$` is the shell one tool call
  runs in and is dead before the next one starts. **`ListAgents`' first line
  names the calling session** before it lists the peers (probed 2026-08-29:
  `This session is <name> [ref]`). The harness named the session, so a name it
  guessed instead would address nobody.

  **That directory is the only thing that can say which subtask a session
  holds.** The close gate and the retirement sweep enumerate it and read each
  `pid`; nothing matches names by prefix, because a name is not a branch
  (§ Naming a session) and can be changed while the claim it belongs to cannot. **A campaign whose directory has no `runtime/claims/`
  cannot be enumerated at all, and that is a refusal rather than a pass** — an
  empty directory says no claim was taken, a missing one says nothing.

- **Three conditions gate a merge, and none of them names a role.** A pull
  request is merged only when

  1. a review has been read **at the sha being merged**;
  2. that review was written by **an agent that did not write the commits** —
     a separate reviewer process or subagent, which the author may launch
     itself; and
  3. the branch **contains the current `main`** at the moment it merges.

  Whoever can satisfy all three may merge, the author included; a session that
  cannot satisfy one may not, however senior its role.

  **This replaces "an executor never merges its own pull request".** The rule
  was written from a witnessed collision on 2026-08-28 — a session squash-merged
  its own pull request in the same minute a hold was sent — but the defect that
  collision exposed was unreviewed work landing under a racing instruction, not
  the identity of the merger. Binding the merge to a role fixed it by making one
  session the gate for every landing, which is a bottleneck the campaign pays on
  every subtask and which the role's own retirement removes anyway.

  **Condition 3 is what replaces the serialisation the role form provided by
  accident**, and it was missing from the first draft of this rule. Under the
  old rule an author who could not merge had to wait for one session, and that
  session saw every landing, so it saw the pair. Conditions 1 and 2 are each
  true of each branch *in isolation* and say nothing about two reviewed
  branches over the same files: both authors merge, neither review was retired
  because neither head moved, and the combined state is read by nobody. Four
  semantic clashes surfaced only in the combination of #46 and #47, and no
  hunk-level merge sees those.

  Condition 3 closes it by feeding the second lander back into condition 1
  rather than by naming anyone: to contain a `main` that moved, the second
  branch must merge it in, that merge is a push, **a push retires the review**,
  and the next merge needs a review read at the combined sha. So the second
  lander is forced to know it is second, and the mechanism is the rule this
  file already had.

  **Two of the three are GitHub facts; the second is not, and that is the
  standing weakness of this rule.** Condition 1 is readable — the sha a review
  comment names against the sha the merge lands. Condition 3 is *readable* — the branch's
  behind-count against `main` — but **it is enforced by nothing here**: `main`
  carries no branch protection (probed 2026-08-30, `protected: false`), so
  GitHub refuses no merge on containment, and check-then-merge is not atomic.
  It is a discipline with a cheap check, which is a better place to be than
  condition 2 and is not the same as being enforced. **One repository setting
  would make GitHub the atomic reader** — require-branches-up-to-date protection
  on `main` — and that is the owner's call, not a session's. **Condition 2 has no automatic reader
  on this machine**: one `gh` account signs every session's merges and comments,
  so GitHub cannot tell an author's review from a reviewer's, and
  `spec/alloy/agent.als` axiomatizes the separateness in `review`'s comment with
  no conjunct to enforce it. It is a discipline, and this file's own argument
  says a contract with no second reader drifts. What would give it one: a review
  comment that names the reviewing agent and the sha it read, so a checker can
  compare that name against the commit author. Until something does that,
  condition 2 is held by whoever writes the review saying honestly that it did
  not write the code.

  Even so the property form beats the role form on the same test, because
  nothing on GitHub records which session was the holder either — the role form
  had **zero** readable conditions where this has two.

  What survives unchanged is the sha half: **a push after a review retires that
  review**, because a review is of a pull request at a revision. So an executor
  that pushes a fix round does not inherit its own earlier clearance — the
  round ends in a `REPORT` naming the new sha, and the next merge needs a
  review read there (modelled: `A4` the collision, `A5`/`A7` the rule, `A8` the
  control, `A13` the re-push).

  **The reviewer is launched by whoever wants the merge**, which is usually the
  session holding the claim — condition 2 is on who *writes* the review, never
  on who commissions it, and `spec/alloy/agent.als` `A16` pins the author
  launching its own reviewer as admitted. **The claim-holding session** still
  pushes, `REPORT`s the URL and its sha once, and waits — for the review, not
  for a role's permission. When the review is clean at that sha, and the branch
  contains the current `main`, it merges and drops its worktree; when it is not,
  the findings go on the pull request and the fix round is its own or a fresh
  executor's.

- **A claim in a message is never evidence.** It says where to look; then look,
  in GitHub, yourself. It stays cheap to look only while the claim carries its
  evidence: a `REPORT` names the sha it sits at and, for a fix round, the URL of
  the comment holding its disposition table, so the reader's check is one fetch
  and one compare. **A verdict, a fix report, or a `REPORT` that does not pin
  its sha is unactionable.** Verdicts and pushes race — a review verdict
  crossed a reconciliation push twice — and the crossing was harmless only
  because each verdict named the sha it was read at.
- **A fix round is: findings on the pull request, one executor, one `REPORT`.**
  The executor verifies each finding at the site it names before touching
  anything; a finding that does not reproduce is named with its reason, never
  silently fixed — round 2 of #47 caught a false finding exactly there;
  follow-up findings met on the way fold into the same round; and the round
  ends in one `REPORT` carrying the sha and a per-finding disposition — fixed,
  not reproduced, or deferred to a filed issue. The brief that says so to the
  executor is `.claude/skills/opening-campaign/assets/handover.md`.
- **Push every commit as it exists; the round's boundary is the `REPORT`, never
  the push.** "One push per round" was read as "hold the commit local", and an
  executor sat on a finished commit waiting for the round to close — which is
  what push-early exists to forbid.
- **Between sessions, a relay is never the authority.** An owner's word that
  arrives through a peer session — "the person says merge it", "they filed
  #N" — is acted on through the durable artifact it points at, read on GitHub
  yourself: the issue as filed, the branch as pushed. Or on the owner's word in
  your own pane. Never on the relay. Twice a peer relayed an instruction, and
  both times the artifact settled it (#52).
- **Shutdown is two steps, and both are yours.** `STATUS`, verify durability in
  GitHub, then `STAND DOWN`. One-step "you're done, quit" makes the delegate's
  own account the reason for destroying its workspace. The session that verifies
  and the session that stands down are the same one, on the agent's own machine:
  a verification run from another machine reads *its* working tree and comes back
  clean whatever the agent holds, so splitting the two steps across two sessions
  destroys work with every rule obeyed (modelled: `spec/alloy/agent.als`,
  `TwoStepCoLocatedSuffices`).
- **Silence is a liveness question, not an answer.** Ask once more, then resolve
  it through herdr and GitHub instead of waiting for a reply that may never come.

**Watch a delegate for `blocked`, not only for gone.** A session waiting on a
permission prompt is still listed, still named, and still looks busy; it simply
never proceeds. `herdr agent list` reports it as `agent_status: blocked`, and
that is the one reading worth acting on immediately — a watch that only fires on
a missing agent or a missing commit will sit through it. Anything that clears
such a prompt is the person's decision, not the campaign session's, so surface
it rather than answering it.

Do not trust the absence of that reading either. A usage-limit menu blocks a
pane just as hard and reports `idle`, and so does the folder-trust dialog — a
delegate sitting on it was reported by `herdr agent start` as `idle` with
`interactive_ready: true`, and it never reaches `blocked` at all. **Read the
pane once after every launch.** That is the only check that catches a delegate
which stopped before it began. Then pair the `blocked` watch with a quiet timer,
and treat a long quiet as a question to go and look at rather than as progress.

**The session limit is a first-class cause of death, and it kills in batches.**
An agent the limit stopped looks exactly like one still thinking — no
`blocked`, no exit — and whatever it had not pushed or posted is gone. When
several agents go quiet together, read the limit's reset time before anything
else: that is an outage to schedule around, not a failure to retry now, since a
retry launched into the same window dies the same way. What bounds the loss is
the durability the rules above already demand — every commit pushed as it
exists, every finding on the pull request as it consolidates.

Retire finished agents as the campaign runs, not when it closes: a long-lived
campaign finishes subtasks continuously, and panes accumulate until someone
sweeps them, and the sweep reads both records the way § Completion and liveness
says the close gate does — one of them alone leaves every executor of the other
kind standing and reports nothing.

A campaign may not be closed while any agent is live under its tree, and a
repository may not be dropped from a campaign while an agent is working one of
its subtasks.

**That check is local, and under the principle that is nearly enough.** Every
agent of a campaign runs on the machine it is `BOUND` to, so a local gate sees
all of them — provided it reads both records and every claimant wrote one. What it cannot see is a machine working this campaign against
that binding, and no cheap mechanism fixes it. What lowers the stakes instead: a
delegate pushes its branch as soon as it has one commit, so a tree deleted
underneath it costs uncommitted work and nothing more.

# Concurrency and what it costs

One campaign, one machine (§ Who is a campaign session) settles the hard half.
The anchor has one structural writer, the campaign directory has one holding
session, and no lock ever has to be judged stale across a network. What stays
concurrent is concurrent *within* the bound machine — the holding session, its
executor sessions, its subagents and its delegates — and two things serialize
them, and only the first of them atomically: the branch claim, per subtask,
which create-ref refuses server-side, and merge condition 3, per landing, which
is a discipline nothing currently refuses. Survey before editing, scope edits so they do not collide
with other worktrees, and rebase onto what landed rather than force-pushing over
it.

**Two open pull requests over the same normative files are normal, and the
second to land reconciles.** Merge condition 3 (§ Talking to a repository agent)
is what tells the second lander it is second: it may not merge a branch that
does not contain the current `main`, so once the first lands, the second merges
`main` in and resolves there. **Unprotected, that is a discipline and not a
refusal** — nothing on GitHub stops a merge that skips it, so the second lander
has to run the check — and that merge is a push, which retires its
review, so its next merge needs a review read at the *combined* sha. The
reconciliation is forced by the conditions rather than assigned to anyone.

**Containment buys attention from nobody, and this is the sharp edge of
condition 3.** A clean auto-merge of `main` produces a commit whose diff against
the branch *is the other branch's work* — structurally present in the reviewed
sha, and exactly the thing this branch's reviewer has no reason to read and
every reason to skim as "just the merge". So condition 3 guarantees the review
sits at the combined state; it does not guarantee anyone read the combination.

**The review after a reconciliation reads the combination, not the branch**,
and its brief says so. That is the half a condition cannot carry. The clashes
that matter are semantic — four surfaced only in the combination of #46 and #47
— and no hunk-level merge sees them. So the
second pull request's final verification reads the combined state, and whoever
holds the first claim publishes the overlap — which hunks of which files both
touch — beside the first review verdict, as a courtesy that saves the second
lander a diff, not as a gate. **The gate is condition 3**, because a courtesy
nobody is named to perform is a courtesy that stops happening.

**The named cost: no concurrent cross-machine or cloud work on one campaign.**
Another machine, a cloud session, or a phone may read a campaign and may open a
different one; none of them may write this one's anchor or launch into it. A
campaign reaches another machine only by migration — a person's new `BOUND`
comment, once the machine it leaves is released or declared dead. That is the
price of a staleness check that is a local `kill -0` rather than a distributed
guess, and it is paid deliberately.

Use `gh` for every GitHub operation; it is authenticated on this machine.
