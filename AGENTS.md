# agent-workspace

A container for agent work on repositories that live elsewhere. Read `README.md`
for what the container is; this file is how to work inside it.

This project is early. Where a rule below is missing, decide, do the work, and
write the decision back here.

# Two kinds of directory

The kind decides which git repository a change lands in, so identify it before
any git command.

**Container-owned** — `AGENTS.md`, `CLAUDE.md`, `README.md`, `.gitignore`,
`.claude/`, `docs/`, `scripts/`. These are the root repository, and a change
here is committed to it. `.gitignore` is an allowlist over exactly this set, so
a new tracked directory needs its own `!` line before git will see it.

**Cloned repositories** — everything else. Each is an independent git
repository with its own context and its own `AGENTS.md`. Never run one git
command across them, never commit their files to the root, and read the
repository's own documents before working in it.

# One issue, one job

Work is tracked as GitHub issues and pull requests on the repository the work
lands in, not here.

- File the issue before the first write that outlives the session — a commit, a
  document, a deploy. A job filed after it is finished is a record nobody reads.
- Give the job its own branch or worktree. The `main` guard refuses direct
  commits, and a refused commit means the wrong branch is checked out.
- Close the job through a pull request that names the issue. A task is finished
  when it is committed, merged, and pushed.
- Use `gh` for every GitHub operation; it is authenticated on this machine.

# Concurrency

Several agents may hold this container at once. Survey before editing, scope
edits so they do not collide with other worktrees and uncommitted changes, and
rebase onto what landed rather than force-pushing over it.
