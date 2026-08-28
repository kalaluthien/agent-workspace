# Campaign design

The reasoning behind the rules in `AGENTS.md`. Read this when a rule looks
arbitrary; read `AGENTS.md` when you need the rule itself.

Status: first design, 2026-08-28. Not yet exercised by a real campaign.

## The unit

A **campaign** is one assignment a person is responsible for, worked across
several repositories at once. It is larger than a ticket and has no size
ceiling: it may be a week of migration or the whole life of a product. It is
split into subtasks, and follow-up subtasks keep arriving until someone decides
it is over.

A campaign is not a repository and it is not a ticket. It is the *place* where
several repositories are worked on together.

## Three planes, three owners

The central rule. Every artifact belongs to exactly one plane, and the plane
decides who owns it, where it is stored, and whether it survives the machine.

| plane | holds | stored in | survives? |
| --- | --- | --- | --- |
| **container** | how campaigns are run: `AGENTS.md`, skills, scripts, assets | the `agent-workspace` git repository | yes, versioned |
| **member repository** | the actual code and its history | each repository's own git remote | yes, versioned |
| **campaign** | the assembly of the two: which repos, what for, how far along | GitHub issues; the directory is a cache | the issues survive, the directory does not |

The campaign directory is deliberately git-ignored. It is a scratch assembly of
things that are each already versioned somewhere else, so committing it would
store a second, staler copy of everything. What must survive lives in GitHub.

## Identity

A campaign is opened by filing one **anchor issue** in `agent-workspace`. Its
issue number is the campaign's ID.

- **ID** — `#N`, the anchor issue number. Short to type, already unique,
  already resolvable from any machine and from the phone.
- **Slug** — a meaningful kebab-case phrase, chosen when the campaign opens.
- **Directory** — `<slug>-<YYMMDD>/` at the container root, e.g.
  `auth-refactor-260828/`. The date disambiguates a slug reused months later
  and sorts usefully in a listing.
- **Branch** — `c<N>/<topic>` in every member repository, e.g. `c7/token-refresh`.
  The campaign number in the branch is what stops two campaigns working the same
  repository from colliding on the remote, and it tells a reviewer which
  campaign a branch came from.
- **Display name** — the anchor issue's title, in the person's own words.

The directory name is a local convenience; the ID is the identity. Two machines
may hold the same campaign under directories that differ only in date, and
nothing breaks, because neither directory is authoritative.

## Gathering issues that live in different repositories

Issues live on the repository whose code changes — that is where a reviewer
expects them, and it is what a pull request can close. A campaign spans
repositories, so its issues are scattered by construction.

The first design used GitHub's own cross-reference timeline as a free index.
That was rejected on two checks: the active repositories here are private while
the container repository is public, and GitHub suppresses a private-to-public
cross-reference from anyone without access to the private side; and a timeline
is not readable with `gh issue view` at all, only through the GraphQL timeline
API. A free index nobody can query is not an index.

What replaces it needs no search and no API beyond `gh issue list`:

- The anchor issue body carries a **`Repos:` list** — the member repositories.
  It changes only when a repository joins the campaign, which is rare, unlike a
  per-issue checklist that must be edited on every subtask.
- Every member issue carries the **label `campaign-<N>`** and one body line
  `Campaign: kalaluthien/agent-workspace#N`. The label is what a query matches;
  the line is what a human clicks.
- The index is therefore a loop over a short, known list:
  `gh issue list -R <repo> --label campaign-<N>` for each entry in `Repos:`.

This works identically on public and private repositories, needs no search
indexing to have caught up, and reads the same from the phone. Nothing has to be
maintained except the repository list.

## Completion and liveness are different questions

The old workspace asked a delegate to print `DONE <name>` and grepped for it.
That conflates two things and is fragile in both: a pane can show the word and
have finished nothing, and a delegate can finish and have its line scrolled
away. The workspace itself already moved past it, folding transcript state into
a computed verdict.

Here the two questions are split and answered by different systems.

- **Completion is a GitHub fact.** A subtask is finished when its issue is
  closed and its PR is merged. Nothing on a terminal screen is evidence. This
  survives the delegate's death, the pane's death, and the machine's reboot,
  and it reads the same from a phone.
- **Liveness is a herdr fact.** Whether a delegate is working, stuck, waiting
  on a prompt, or gone is read from `herdr agent list` presence plus the
  session transcript — never from `agent_status` alone, which reports the
  screen and calls a mid-turn pause `idle`.

A delegate that dies after pushing its branch has still succeeded. A delegate
that is alive and chatty has still done nothing. Keeping the two signals apart
is what makes both usable.

## Who does the work

The campaign session is opened by the person, in the container root, with
whatever they have — a sentence, an issue number, a screenshot of a broken
service. It decides the campaign, scaffolds it, and then, per subtask, chooses:

> **Do it here** when the change fits in one repository, is small enough to
> hold in view at once, and needs nothing from that repository's build or test
> loop. **Spawn a repository agent** otherwise — when the work needs the
> repository's own conventions and toolchain, when it will take many turns, or
> when two repositories must move at the same time.

The predicate is "will I need that repository's context loaded to do this
well?", and the cost being weighed is turns: a spawn costs one launch and one
handover, so anything longer than a handful of turns is cheaper delegated.

## Sessions

- A repository agent is launched by the campaign session, in
  `<campaign>/repos/<repo>/`, with its session UUID chosen in advance
  (`claude --session-id`) so its transcript path is known before it starts, and
  with a readable slug name (`claude --name <role>-<slug>`) so it can be found
  and addressed. herdr's pane-to-session link is write-once, so the link is
  made at launch and never re-made.
- **The handover brief is a file, never a typed line.** herdr types its launch
  command into the pane, and a terminal in canonical mode silently drops a line
  past 1024 bytes — nothing runs, and the launch times out looking like a slow
  agent. So the brief is written to
  `<campaign>/runtime/handover/<issue>.md` and the launched prompt is one short
  sentence naming that path. This also makes every handover readable after the
  fact.
- A repository agent inherits three instruction files by nesting: the
  container's, the campaign's, and the repository's own. That stacking is the
  mechanism that gives a delegate the campaign's engineering principles for
  free, and it is why a campaign `AGENTS.md` must only *add* principles — one
  that contradicts a repository's own conventions puts the delegate in a
  conflict it cannot resolve.
- The herdr **tab** title stays LLM-generated by the existing hook; that is a
  human-readable label, not an identifier. The **name** is the identifier and
  is a slug, because it is what gets searched, addressed, and resumed.
- Campaign sessions point their memory at the container's pool with
  `CLAUDE_COWORK_MEMORY_PATH_OVERRIDE`, because a pool inside a git-ignored
  campaign directory dies with it.

## Retirement

An agent does not close itself. It finishes by pushing its branch and opening
or updating a pull request, then goes idle.

The campaign session retires it once the work is **durable** — the branch is
pushed and the pull request is open. It deliberately does not wait for the
merge: review can take days, and a pane held open across them is the expensive
thing. Review feedback gets a fresh session, briefed from the pull request.

Self-termination is refused for one reason: the only thing that can verify a
delegate's work is something other than that delegate. Retirement is also
refused in the other direction — a campaign cannot be closed while any agent is
still live under its tree, because deleting the directory out from under a
running session destroys work that was never pushed.

## Acquiring repositories

Cloning is one strategy among several that will be wanted, so it is behind a
seam from the start. Callers ask for a repository at a path on a branch and get
a ready checkout; how it got there is not their business.

Only `clone` is implemented. The seam exists so these can be added later
without touching a caller:

- a shared local mirror, when a repository is too large to re-clone per
  campaign;
- a git worktree cut from another campaign's checkout of the same repository;
- a shallow or partial clone, when only recent history matters;
- reusing an existing checkout in place.

Implementing any of them now would be guessing at which one matters. Leaving
the seam costs one function boundary.

## Deliberately absent

- **No ticket system.** Campaigns are triggered by a person, and GitHub issues
  carry the subtasks. A board over campaigns will be built later, as a campaign
  run in this container.
- **No campaign-level git.** See the three planes.
- **No status file, no lock file, no local database.** Every one of them would
  be a second copy of a GitHub fact, and the copy is what goes stale.
- **No virtual environment until something needs one.** `.venv` appears the
  first time a campaign script is run, not at scaffold time.

## Open risks

Named here rather than solved, because each needs a real campaign to settle.

- The nested instruction-file stacking is assumed, not measured. If a session in
  `<campaign>/repos/<repo>/` turns out not to load the campaign's `AGENTS.md`,
  the campaign principles have to be injected into the handover brief instead.
- Retiring at "pull request open" means nobody is watching the review. Until a
  board exists, the person is the one who notices.
- Two machines can open the same campaign into directories whose date suffixes
  differ. Nothing breaks, but a person reading two listings sees two names for
  one thing.
