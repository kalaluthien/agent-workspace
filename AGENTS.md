# agent-workspace

A container for running **campaigns** — cross-repository units of work — on
repositories that live elsewhere. `README.md` says what the container is; this
file is how to work inside it. `spec/design-campaign.md` says why these rules
are what they are.

This project is early. Where a rule is missing, decide, do the work, and write
the decision back here.

# What a campaign is

One assignment a person is responsible for, worked across several repositories
at once. Bigger than a ticket, no size ceiling — a week of migration or the
whole life of a product. It splits into subtasks, and follow-up subtasks keep
arriving until someone decides it is over.

A campaign is not a repository and not a ticket. It is the place where several
repositories are worked on together.

- **ID** — the number of its anchor issue in `kalaluthien/agent-workspace`.
  Typed as `#N`.
- **Directory** — `<slug>-<YYMMDD>/` at the container root, git-ignored.
- **Branch** — `c<N>/<topic>` in every member repository, so two campaigns
  working one repository never collide on the remote.

# Three planes

Every artifact belongs to exactly one, and the plane decides where it is stored
and whether it survives the machine. Identify the plane before any git command.

| plane | holds | stored in |
| --- | --- | --- |
| **container** | `AGENTS.md`, `CLAUDE.md`, `README.md`, `.gitignore`, `.claude/`, `spec/`, `docs/`, `scripts/` | this repository |

`spec/` holds what is normative — the design and the models that check it, as
markdown. `docs/` holds views drawn for a reader, as HTML. The two are kept
apart and neither inherits the other's rules, so a markdown file under `docs/`
is misfiled rather than temporary.
| **member repository** | the code and its history | each repository's own remote |
| **campaign** | which repositories, what for, how far along | GitHub issues |

The campaign directory holds no plane of its own. It is a scratch assembly of
things already versioned elsewhere, so it is git-ignored on purpose and nothing
durable may live only there. `.gitignore` is an allowlist over the container
row: a new tracked directory needs its own `!` line.

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
- **Ahead *before* the clone means the delegate will read stale rules.** The
  clone is cut from `origin/main`, so a delegate launched while the container
  holds unpushed commits obeys an `AGENTS.md` this session has already
  superseded. Push first; cloning while ahead is the defect.
- **A skill edited inside the clone does not change the running campaign**, and
  that is deliberate — the tool must not move under a session using it. It takes
  effect only once merged and pulled.

# Running a campaign

**Open** — a person arrives in the container root with a sentence, an issue
number, or a screenshot. Check the open anchor issues first: this is a *new*
campaign only when no open campaign's scope covers it. Otherwise the request is
a follow-up subtask on the campaign that already exists. Load the
`opening-campaign` skill.

**Subtasks** — one subtask is one GitHub issue, filed on the repository whose
code changes, and created **as a sub-issue of the anchor**:

```sh
gh issue create -R <owner/repo> --parent https://github.com/kalaluthien/agent-workspace/issues/<N> ...
```

That one flag is the whole index. Read it back with

```sh
gh api repos/kalaluthien/agent-workspace/issues/<N>/sub_issues
```

which returns exactly the campaign's members, in any repository, public or
private (probed 2026-08-28: a sub-issue in a private repository lists correctly
under a public parent). The link is made by the same command that creates the
issue, so there is no second write to forget, and it is prunable — moving a
subtask out of the campaign removes it from the index, which a back-reference
or a search over body text cannot do.

Add a body line `Campaign: kalaluthien/agent-workspace#N` as prose for a human
reading the raw issue. It is not the index and nothing queries it.

The anchor's **`## Repos`** section still earns its place: it says which
repositories to clone when a campaign is opened, before any subtask exists. It
is a markdown heading followed by a plain `- owner/repo` list, in the issue body
and in the campaign `README.md` alike — the same heading, so a reader written
against one works on the other.

**Do it here or hand it over** — do it here when the change fits in one
repository, is small enough to hold in view at once, and needs nothing from that
repository's build or test loop. Spawn a repository agent otherwise: when the
work needs the repository's own conventions and toolchain, when it will take
many turns, or when two repositories must move at once.

**Close** — load the `closing-campaign` skill. A campaign closes when its anchor
issue closes, and only a person decides that.

The campaign's `README.md` and the anchor issue body carry **the same five
sections in the same shapes** — Intent, Scope, Requirements, Plan, and `Repos`
as a plain `- owner/repo` list — so syncing one to the other is an overwrite
with nothing to merge. A README shaped differently from the body forces the
sync to compose, and a compose step is where the repository index gets silently
dropped.

**The campaign session is the anchor issue body's only writer.** A delegate
never edits it — not to tick a Plan box, not to add a repository. The Plan is
the owner's plan and progress is read from the subtask issues, which are the
things that actually close. One writer is what makes the overwrite safe; two
writers would make every close silently discard whatever the other one did.

# Delegating to a repository agent

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

The campaign's principles are appended to a delegate that already has the
repository's own, so a campaign `AGENTS.md` only ever *adds*; one that
contradicts a repository's conventions puts the delegate in a conflict it
cannot resolve.

- **Write the brief to a file**, `<campaign>/runtime/handover/<issue>.md`, and
  make the launched prompt one short sentence naming that path. herdr types its
  launch line into the pane, and a terminal silently drops a line past 1024
  bytes — nothing runs and the launch looks like a slow agent.
- Choose the session UUID in advance (`claude --session-id`) so the transcript
  path is known before the agent starts, and give it a slug name
  (`claude --name <role>-<slug>`) so it can be found and addressed.
- Put the prompt **before** any variadic flag on the `claude` command line.
  `--add-dir` and `--allowedTools` swallow a trailing prompt as one of their own
  values, and the run dies on "Input must be provided".
- Set `CLAUDE_COWORK_MEMORY_PATH_OVERRIDE` to this container's pool. A memory
  pool inside a git-ignored campaign directory dies with the directory.
- **Deliver the opening prompt with `herdr agent prompt <pane> "<text>"`.** A
  prompt put on the launch line is word-split: a launch ending with a whole
  sentence delivered its first word alone, and the delegate reported it had been
  given no brief while the launch looked successful.

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

# Completion and liveness are different questions

Never answer one with the other.

- **Completion is a GitHub fact.** A subtask is settled when its issue is closed
  — either as completed with its pull request merged, or as **not planned**,
  which is how a subtask gets dropped. Both readings are needed: with only
  closed-and-merged, a subtask abandoned on purpose never reads settled and its
  campaign can never be closed. Nothing on a terminal screen is evidence. A
  delegate that died after pushing has still succeeded; a delegate that is alive
  and chatty may have done nothing.
- **Liveness is a herdr fact**, read from `herdr agent list` presence plus the
  session transcript — never from `agent_status` alone, which reports the screen
  and calls a mid-turn pause `idle`.

An agent never closes itself. It finishes by pushing its branch and opening or
updating a pull request, then goes idle; the campaign session retires it once
that work is durable. Review feedback gets a fresh session, briefed from the
pull request — a pane held open across a multi-day review is the expensive
thing.

# Talking to a repository agent

`spec/agent-protocol.md` is the contract; this is the short form. Address an
agent by the name given at launch, which `ListAgents` resolves — herdr's pane
label is not an address.

Four messages, carrying **only what the agent alone knows**. Anything a message
says about finished work duplicates a GitHub fact, and the copy is what goes
stale.

| message | direction | carries |
| --- | --- | --- |
| `STATUS` | campaign → agent | doing what, blocked on what, what exists only on this machine, safe to stop |
| `REPORT` | agent → campaign | a pull request URL, once, unsolicited |
| `BLOCKED` | agent → campaign | a decision that is not the agent's to make |
| `STAND DOWN` | campaign → agent | finish the turn and stop |

- **A claim in a message is never evidence.** It says where to look; then look,
  in GitHub, yourself.
- **Shutdown is two steps.** `STATUS`, verify durability in GitHub, then
  `STAND DOWN`. One-step "you're done, quit" makes the delegate's own account
  the reason for destroying its workspace.
- **Silence is a liveness question, not an answer.** Ask once more, then resolve
  it through herdr and GitHub instead of waiting for a reply that may never come.

Retire finished agents as the campaign runs, not when it closes: a long-lived
campaign finishes subtasks continuously, and panes accumulate until someone
sweeps them.

A campaign may not be closed while any agent is live under its tree, and a
repository may not be dropped from a campaign while an agent is working one of
its subtasks.

**That check is local and cannot see another machine.** An operator deleting a
campaign tree here is blind to an agent live on the same campaign elsewhere, and
no cheap mechanism fixes it. What lowers the stakes instead: a delegate pushes
its branch as soon as it has one commit, so a tree deleted underneath it costs
uncommitted work and nothing more.

# Concurrency

Several machines and several agents may hold the same campaign. They read and
write the same GitHub issues, and their local directories never need to agree,
because those hold no state anyone else reads. Survey before editing, scope
edits so they do not collide with other worktrees, and rebase onto what landed
rather than force-pushing over it.

Use `gh` for every GitHub operation; it is authenticated on this machine.
