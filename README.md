# campaign-base

A base for running **campaigns** — units of work across the repositories
they need — on repositories that live elsewhere.

A campaign is one assignment a person is responsible for, worked across the
repositories it needs, which may be none. It is bigger than a ticket and has no
size ceiling. It gets a directory on the machine that holds it — the
repositories it needs are assembled inside it, and its sub-issues are handed to
agents — and that directory is one machine's cache of a campaign that lives on
GitHub. When it is over the directory is deleted and nothing is lost, because
everything durable was already somewhere else.

## Shape

```
campaign-base/
  AGENTS.md CLAUDE.md README.md .gitignore    tracked here
  .claude/skills/opening-campaign
  .claude/skills/closing-campaign
  spec/  docs/  scripts/
  auth-refactor-260828/          a campaign, git-ignored
    AGENTS.md CLAUDE.md          engineering principles for this campaign
    README.md                    the campaign issue body, section for section
    runtime/                     data, state, artifacts, handover briefs
    scripts/                     scripts built for this campaign; scratch,
                                 listed at the close and deleted with the directory
    repos/api/  repos/web/       member repositories, each its own git repo
```

`.gitignore` is an allowlist: it ignores `/*` and re-admits only the base's
own files. Campaign directories and everything cloned into them stay untracked,
so a campaign can never be committed into the wrong repository by accident.

## Where things live

| what | lives in |
| --- | --- |
| how campaigns are run | this repository |
| the code being changed | each member repository's own remote |
| what a campaign is and how far along it is | GitHub issues |

A campaign's identity is its **campaign issue** in this repository. Sub-issues are
issues in this repository too, whichever repository their code lives in — each
filed as a sub-issue of that campaign issue, and the link the creating command
makes is the whole index; a member repository receives only branches and pull
requests. That makes
GitHub the single record: a campaign can move from one machine to another, and a
phone can read it, without anything local having to agree. It runs on one
machine at a time, and the campaign issue's latest `BOUND` comment says which.

## Setup

Git hooks do not clone, so run the installer once per clone:

```sh
scripts/install-hooks.sh
```

It installs the `pre-commit` that chains the machine-wide no-commits-on-`main`
guard with this repository's three (`check-rule-readers`, `check-tree-shape`,
`check-cross-references`), the `post-commit` that pushes a campaign branch on
its first commit, and the harness claim guard in `~/.claude/settings.json`. It
refuses rather than overwrites a hook it did not write, so a hand-written
shim in the slot is the one thing that stops it — remove that first.

Requires `git`, `gh` (authenticated), `herdr`, `uv`, and Python 3.

## Reading order

`AGENTS.md` for the rules. `spec/campaign/github/system.als` for why they are
those rules, what was rejected, and which risks are still open — it is the entry
point to `spec/`, which is Alloy models with an HTML diagram allowed beside one;
each model's comments carry the part of the spec it checks. `spec/campaign/` is
one module in five entities, each `open`ing the one below — `github`,
`directory`, `synchronization`, `session`, `orchestration` — so the top one is
the whole composed model. Each entity is three files: `system.als` is the
signatures, events and trace, `scenarios.als` the witnesses, `checks.als` the
assertions. `spec/campaign/diagram.html` for the shape of all of it, and
`spec/campaign/orchestration/system.als` for how a campaign session and its
agents talk.
