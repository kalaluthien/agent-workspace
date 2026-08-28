# agent-workspace

A container for running **campaigns** — cross-repository units of work — on
repositories that live elsewhere.

A campaign is one assignment a person is responsible for, worked across several
repositories at once. It is bigger than a ticket and has no size ceiling. It
gets a directory here, the repositories it needs are assembled inside it, and
its subtasks are handed to agents. When it is over the directory is deleted and
nothing is lost, because everything durable was already somewhere else.

## Shape

```
agent-workspace/
  AGENTS.md CLAUDE.md README.md .gitignore    tracked here
  .claude/skills/opening-campaign
  .claude/skills/closing-campaign
  spec/  docs/  scripts/
  auth-refactor-260828/          a campaign, git-ignored
    AGENTS.md CLAUDE.md          engineering principles for this campaign
    README.md                    Intent, Scope, Requirements, Plan
    runtime/                     data, state, artifacts, handover briefs
    scripts/                     reusable scripts for this campaign
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
issues on the repositories whose code changes, each labelled `campaign-<N>`.
That makes GitHub the single record: two machines can run the same campaign, and
a phone can read it, without anything local having to agree.

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

`AGENTS.md` for the rules. `spec/design-campaign.md` for why they are those
rules, what was rejected, and which risks are still open.
