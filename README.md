# agent-workspace

A container for running **campaigns** — units of work across the repositories
they need — on repositories that live elsewhere.

A campaign is one assignment a person is responsible for, worked across the
repositories it needs, which may be none. It is bigger than a ticket and has no
size ceiling. It gets a directory on the machine that holds it — the
repositories it needs are assembled inside it, and its subtasks are handed to
agents — and that directory is one machine's cache of a campaign that lives on
GitHub. When it is over the directory is deleted and nothing is lost, because
everything durable was already somewhere else.

## Shape

```
agent-workspace/
  AGENTS.md CLAUDE.md README.md .gitignore    tracked here
  .claude/skills/opening-campaign
  .claude/skills/closing-campaign
  spec/  docs/  scripts/
  auth-refactor-260828/          a campaign, git-ignored
    AGENTS.md CLAUDE.md          engineering principles for this campaign
    README.md                    the anchor issue body, section for section
    runtime/                     data, state, artifacts, handover briefs
    scripts/                     scripts built for this campaign; scratch,
                                 listed at the close and deleted with the directory
    repos/api/  repos/web/       member repositories, each its own git repo
```

`.gitignore` is an allowlist: it ignores `/*` and re-admits only the container's
own files. Campaign directories and everything cloned into them stay untracked,
so a campaign can never be committed into the wrong repository by accident.

## Where things live

| what | lives in |
| --- | --- |
| how campaigns are run | this repository |
| the code being changed | each member repository's own remote |
| what a campaign is and how far along it is | GitHub issues |

A campaign's identity is its **anchor issue** in this repository. Subtasks are
issues on the repositories whose code changes — the container's own tracker when
none does — each filed as a sub-issue of that anchor, and the link the creating
command makes is the whole index. That makes
GitHub the single record: a campaign can move from one machine to another, and a
phone can read it, without anything local having to agree. It runs on one
machine at a time, and the anchor's latest `BOUND` comment says which.

## Setup

Git hooks do not clone, so install the guard that blocks direct commits to
`main` once per clone:

```sh
printf '%s\n' '#!/usr/bin/env sh' \
  'exec "$HOME/.claude/git-hooks/no-main-commits" "$@"' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

Requires `git`, `gh` (authenticated), `herdr`, `uv`, and Python 3.

## Reading order

`AGENTS.md` for the rules. `spec/alloy/ledger.als` for why they are those rules,
what was rejected, and which risks are still open — it is the entry point to
`spec/`, which is Alloy models and nothing else, each one's comments carrying the
part of the spec it checks. The four are layers, each `open`ing the one below —
`ledger`, `repos`, `session`, `agent` — so one file is one conceptual module and
the top one is the whole composed model. `spec/alloy/agent.als` for how a
campaign session and its executors talk.
