# Campaign design

The reasoning behind the rules in `AGENTS.md`. Read this when a rule looks
arbitrary; read `AGENTS.md` when you need the rule itself.

Status: first design, 2026-08-28. Campaign #1 is exercising it as it is
written — a smoke test, a protocol test and an e2e drill have each contradicted
a rule here, and each correction is folded into the text rather than kept as an
erratum.

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

**The container can also be a member repository of a campaign**, and this
container's own machinery is built that way. Nothing in the three planes forbids
it — the container plane is a repository like any other — but it puts two
checkouts of one repository in play at once: the outer one the campaign session
runs from, and a clone nested inside it that the outer ignores. `AGENTS.md`
carries the rule that keeps them in step, and scenario 16 in `alloy/` is the
witness for what goes wrong without it. Worth stating because the modelled
version of this design originally ruled the case out, so it was possible to read
the whole scheme as forbidding it.

## Identity

A campaign is opened by filing one **anchor issue** in `agent-workspace`. Its
issue number is the campaign's ID.

- **ID** — `#N`, the anchor issue number. Short to type, already unique,
  already resolvable from any machine and from the phone.
- **Slug** — a meaningful kebab-case phrase, chosen when the campaign opens.
- **Directory** — `<slug>-<YYMMDD>/` at the container root, e.g.
  `auth-refactor-260828/`, and **optional**. The date disambiguates a slug
  reused months later and sorts usefully in a listing. A campaign legitimately
  has none on a given machine: the campaign is its anchor issue and the
  directory is one machine's cache of it, so closing a campaign and deleting a
  directory are different acts. #1, which built this machinery, never had one.
- **Branch** — `c<N>/<issue>-<topic>` in every member repository, e.g.
  `c7/31-token-refresh`. The campaign number separates campaigns; the subtask's
  issue number separates subtasks within one, which only matters once several
  sessions hold a campaign at once.
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

Four schemes were modelled in Alloy (`spec/alloy/`) and checked against index
totality, machine independence, and reconstitution:

| scheme | verdict |
| --- | --- |
| back-reference line, read from GitHub's cross-reference timeline | append-only, so a subtask moved out stays indexed forever; the anchor reconstitutes a growing superset. Also suppressed private-to-public, and unreadable with `gh issue view` |
| a checklist in the anchor body | a second write to another object; skipping it loses the issue with nothing to contradict it — the only silent total loss of the four |
| a `campaign-<N>` label per issue | correct, but the label must be created per repository and survives removal as a stale mark |
| **GitHub's native sub-issue link** | **the only one where the index equals membership in every reachable state** |

The sub-issue link wins on cost as well as correctness: `gh issue create
--parent <anchor-url>` makes the link in the same command that creates the
issue, so there is no second write to forget, and `gh api
repos/.../issues/<N>/sub_issues` reads the whole index in one call with no
repository list to loop over and no search index to have caught up.

Its one open question was whether a sub-issue may live in a different
repository, and a private one, under a public parent. Probed 2026-08-28: it can.

## Completion and liveness are different questions

The old workspace asked a delegate to print `DONE <name>` and grepped for it.
That conflates two things and is fragile in both: a pane can show the word and
have finished nothing, and a delegate can finish and have its line scrolled
away. The workspace itself already moved past it, folding transcript state into
a computed verdict.

Here the two questions are split and answered by different systems.

- **Completion is a GitHub fact.** A subtask is settled when its issue is
  closed. The merged pull request behind it only says which kind of closed —
  `complete`, or `dropped` for every other close. Settlement had to be widened
  to that: closed-and-merged alone cannot say "dropped", so a subtask abandoned
  on purpose, moved to a duplicate, or closed by hand with nothing to merge
  never reads settled and its campaign can never be closed. That is
  `campaign-D`'s assertion 7b, and it is why `scripts/campaign-settlement`
  counts a closed issue as settled whatever closed it. Nothing on a terminal
  screen is evidence. This survives the delegate's death, the pane's death, and
  the machine's reboot, and it reads the same from a phone.
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
- A repository agent inherits the campaign's instruction file by nesting only
  where an approval has been granted, and a fresh checkout has not granted it.
  The first measurement here read as a flat "ancestors never load", which was
  wrong: the probe ran under `-p`, where the external-import dialog never
  appears and the import is declined silently. Setting
  `hasClaudeMdExternalIncludesApproved` for the directory makes all three
  levels load. But that flag is per-directory, defaults to false, and is asked
  interactively — so the one situation the design cares about, a delegate
  launched into a repository acquired minutes ago, is precisely the situation
  where it is unset. `--append-system-prompt-file <campaign>/AGENTS.md` depends
  on no approval, so it is the mechanism. The campaign file is *appended to* a
  delegate that already carries the repository's own, which is why it may only
  add principles.
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

## Several sessions, one campaign

Any session opened in the container root is a campaign session, and several may
hold one campaign at once. That is the owner's intent, and it was not what the
design said: the word appeared five times without ever being defined, and one
rule — that the campaign session is the anchor body's only writer — contradicted
it outright. `alloy/campaign-multi.als` drops the one-session assumption and
finds eight ways two sessions break each other; `alloy/multi-session.md` carries
the witnesses.

The repair is one shape applied twice: **re-read immediately before you write.**
Compare-then-write on the anchor body is UNSAT for the lost update at identical
bounds, and re-surveying at the moment of filing is UNSAT for the duplicate
campaign. It was checked against the obvious alternative — writing the body only
at open and close — which still loses the update and additionally hides a
repository added mid-campaign from every other session.

Two of the eight are narrowed rather than closed, and the contract says so
rather than implying otherwise. Filing is still not atomic, so two sessions can
still produce two anchors for one scope. And a local gate cannot see a delegate
alive on another machine, so a campaign can still be closed out from under one;
what makes that survivable is not a lock but that a delegate pushes as soon as
it has a commit, which is why that rule sits where it does.

Concurrency here is deliberately cheap and honest rather than correct. A lock
would need a place to live, and every candidate is either a second copy of a
GitHub fact or a file the campaign directory takes with it when it goes.

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

- Retiring at "pull request open" means nobody is watching the review. Until a
  board exists, the person is the one who notices.
- Two machines can open the same campaign into directories whose date suffixes
  differ. Nothing breaks, but a person reading two listings sees two names for
  one thing.
