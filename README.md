# agent-workspace

A container for agent work on other people's repositories.

The root holds no product code. It holds the tooling that sets up a place to
work — clone the repository, open a branch, read the issue, land the PR — and
the record of what was worked on. Everything below the root that an agent
clones or generates is untracked here and owned by its own repository.

> **Draft.** The paragraphs below sketch a starting shape, not a settled
> vision. Expect the scope, the directory names, and the workflow to move once
> the first real job runs through it.

## Shape

| path | holds |
| --- | --- |
| `AGENTS.md` | how an agent works in this container; `CLAUDE.md` imports it |
| `docs/` | views for a reader — what the container is, how a job flows |
| `scripts/` | the container's own tooling |
| *anything else* | cloned repositories and scratch, untracked (see `.gitignore`) |

`.gitignore` is an allowlist: it ignores `/*` and re-admits only the entries
above. A new tracked directory needs its own `!` line, and nothing else can be
committed here by accident.

## Unit of work

One GitHub issue is one job. A job gets its own branch or worktree, its work is
committed there, and it closes through a pull request that names the issue.
Work that never became an issue leaves no record, so it gets an issue too.

## Setup

Git hooks do not clone, so install the machine-wide guard that blocks direct
commits to `main` once per clone:

```sh
printf '%s\n' '#!/usr/bin/env sh' \
  'exec "$HOME/.claude/git-hooks/no-main-commits" "$@"' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

Requires `git`, `gh` (authenticated), and Python 3.
