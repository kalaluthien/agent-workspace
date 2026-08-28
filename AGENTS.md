# agent-workspace

A container for running **campaigns** — cross-repository units of work — on
repositories that live elsewhere. `README.md` says what the container is; this
file is how to work inside it. `docs/design-campaign.md` says why these rules
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
| **container** | `AGENTS.md`, `CLAUDE.md`, `README.md`, `.gitignore`, `.claude/`, `docs/`, `scripts/` | this repository |
| **member repository** | the code and its history | each repository's own remote |
| **campaign** | which repositories, what for, how far along | GitHub issues |

The campaign directory holds no plane of its own. It is a scratch assembly of
things already versioned elsewhere, so it is git-ignored on purpose and nothing
durable may live only there. `.gitignore` is an allowlist over the container
row: a new tracked directory needs its own `!` line.

Never run one git command across member repositories, and never commit their
files here.

# Running a campaign

**Open** — a person arrives in the container root with a sentence, an issue
number, or a screenshot. Check the open anchor issues first: this is a *new*
campaign only when no open campaign's scope covers it. Otherwise the request is
a follow-up subtask on the campaign that already exists. Load the
`opening-campaign` skill.

**Subtasks** — one subtask is one GitHub issue, filed on the repository whose
code changes. Every one of them carries the label `campaign-<N>` and a body line
`Campaign: kalaluthien/agent-workspace#N`. The anchor issue's `Repos:` list plus
that label is the whole index: `gh issue list -R <repo> --label campaign-<N>`
over the list. Nothing else has to be maintained.

**Do it here or hand it over** — do it here when the change fits in one
repository, is small enough to hold in view at once, and needs nothing from that
repository's build or test loop. Spawn a repository agent otherwise: when the
work needs the repository's own conventions and toolchain, when it will take
many turns, or when two repositories must move at once.

**Close** — load the `closing-campaign` skill. A campaign closes when its anchor
issue closes, and only a person decides that.

The campaign's `README.md` and the anchor issue body carry **the same five
sections** — Intent, Scope, Requirements, Plan, Repos — so syncing one to the
other is a plain overwrite with nothing to merge. A README missing `Repos:`
would silently drop the campaign's repository index on the next sync, and that
index is the one thing that has to be maintained.

# Delegating to a repository agent

Launch it in `<campaign>/repos/<repo>/` with
`--append-system-prompt-file <campaign>/AGENTS.md`. That flag is the *only*
thing that gets the campaign's principles into the delegate: instruction files
do **not** load from ancestor directories, with or without a git boundary and
with or without `--add-dir` (probed 2026-08-28). A delegate launched without it
sees the repository's `AGENTS.md` and nothing else.

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

# Completion and liveness are different questions

Never answer one with the other.

- **Completion is a GitHub fact.** A subtask is finished when its issue is
  closed and its pull request is merged. Nothing on a terminal screen is
  evidence. A delegate that died after pushing has still succeeded; a delegate
  that is alive and chatty may have done nothing.
- **Liveness is a herdr fact**, read from `herdr agent list` presence plus the
  session transcript — never from `agent_status` alone, which reports the screen
  and calls a mid-turn pause `idle`.

An agent never closes itself. It finishes by pushing its branch and opening or
updating a pull request, then goes idle; the campaign session retires it once
that work is durable. Review feedback gets a fresh session, briefed from the
pull request — a pane held open across a multi-day review is the expensive
thing.

A campaign may not be closed while any agent is live under its tree.

# Concurrency

Several machines and several agents may hold the same campaign. They read and
write the same GitHub issues, and their local directories never need to agree,
because those hold no state anyone else reads. Survey before editing, scope
edits so they do not collide with other worktrees, and rebase onto what landed
rather than force-pushing over it.

Use `gh` for every GitHub operation; it is authenticated on this machine.
