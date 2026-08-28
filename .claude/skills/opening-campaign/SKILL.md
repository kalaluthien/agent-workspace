---
name: opening-campaign
description: Opens a campaign in the agent-workspace container, or joins one that already exists — decides new versus follow-up, files the anchor issue, scaffolds its directory on this machine, and acquires the member repositories. Use when a person arrives in the container root with an unstructured request, such as a sentence, an issue number, or a screenshot, and cross-repository work has to start. Not for closing a campaign, and not for the second and later subtasks of a campaign already scaffolded in this directory.
---

# Opening a campaign

Turn one person's unstructured request into a campaign: an anchor issue that is
its identity, a directory that is its workspace, and member repositories ready
to work in.

Finished when all of these hold:

- An open issue in `kalaluthien/agent-workspace` carries the label `campaign`
  and body sections Intent, Scope, Requirements, Plan, Repos, with `Repos` a
  plain `- owner/repo` list.
- `<slug>-<YYMMDD>/` exists at the container root and holds `AGENTS.md`,
  `CLAUDE.md`, `README.md`, `runtime/handover/`, and `scripts/`.
- The campaign's `README.md` is the anchor issue body, and the `- ` entries
  under its `## Repos` heading hold no `<`. Scope the check to that list: a
  correct Requirements section quotes things like `issues/<N>/sub_issues`, so a
  bare `grep '<'` over the whole file reports hits on a clean README.
- `runtime/anchor-body-derived.md` holds the body the README was derived from,
  byte for byte.
- Every entry under `## Repos` resolves to a checkout at
  `<campaign>/repos/<name>/`.
- The reply names the campaign ID, the directory, and the anchor issue URL.

## Procedure

The steps are ordered. The anchor issue number is the campaign ID, so nothing
that needs the ID can run before step 3.

### 1. Decide new or follow-up

```sh
gh issue list -R kalaluthien/agent-workspace --label campaign --state open
```

Read the body of each one that could plausibly cover the request
(`gh issue view <N> -R kalaluthien/agent-workspace`); the title alone does not
carry the scope.

| what you find | what to do |
| --- | --- |
| No open campaign's Scope covers the request | Open a new campaign: continue to step 2. |
| One open campaign's Scope covers it | Join it: file a follow-up subtask, and scaffold the directory here if this machine has none. |
| Two or more could cover it, or the fit is arguable | Ask the person which, naming the candidates. Do not guess. |

Match on Scope, never on `## Repos`. A request that touches a repository an open
campaign already lists, but that its Scope does not cover, opens a new campaign.

Testing, validating, or fixing a campaign's own deliverable is a follow-up on
that campaign, not a new one — the deliverable is not finished until it is shown
to work, and the fixes land on the artifacts that campaign already owns. Scope
is written in artifacts and cannot separate "build X" from "validate X", so this
one is decided here rather than read off the body.

File the follow-up the way "Filing a subtask issue" below says: an issue created
without `--parent` is in no campaign and shows up in no listing, and nothing
reports it.

Then check whether this machine holds the campaign at all. Several sessions may
hold one campaign, on one machine or on several, and none of them is the one
that opened it — so "already scaffolded" is a fact about a directory, not about
the campaign:

```sh
CONTAINER=$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd -P)
ls -d "$CONTAINER"/*-[0-9][0-9][0-9][0-9][0-9][0-9]/ 2>/dev/null
```

A directory whose `README.md` names this campaign — the run ends here; work in
that directory. None — the campaign exists on GitHub but not on this machine, so
run steps 2, 4 and 5 for it, taking its ID and body from the anchor issue. Skip
step 3: it exists only to mint an ID this campaign already has.

Step 2 still runs because neither the slug nor the kind is recoverable from
GitHub — the kind lives in another machine's `AGENTS.md`, which nothing here can
read. Say which kind you picked, so a mismatch with the campaign's other
directories costs one line to correct.

### 2. Name it and pick its kind

Three things fix the campaign:

- **Slug** — kebab-case, meaningful, no date; the date is appended in step 4.
- **Title** — the display name, in the requester's own words, not yours.
- **Kind** — which `assets/agents/*.md` becomes the campaign's `AGENTS.md`.

With a person in the conversation, propose all three in one message and wait for
the answer. Started from a handover brief with nobody waiting, read all three
from the brief and carry on — then state the three choices in the reply, so each
one costs a single line to veto afterwards.

| the campaign exists to | kind |
| --- | --- |
| answer an open question | `research` |
| measure or audit something that already runs | `analysis` |
| find out whether an approach can work at all | `prototyping` |
| move a working system from one form to another | `migration` |

Never leave the kind unstated. It is a one-line correction for the requester and
a wrong set of principles for every delegate if it goes by unseen.

### 3. File the anchor issue

Before scaffolding anything, because its number is the campaign ID.

**Survey again, in the same breath as the create.** Step 1's survey is minutes
old by now, and another session in the container root may have filed in between:
two sessions that each checked before either filed both file, and one scope gets
two campaigns with nothing reporting it.

```sh
gh issue list -R kalaluthien/agent-workspace --label campaign --state open
gh issue create -R kalaluthien/agent-workspace \
  --label campaign --title "<title>" --body-file <path>
```

Read the listing before running the create. Anything new since step 1 that could
cover the request sends you back to step 1's table.

This **narrows the window, it does not close it.** The read and the create are
two calls and nothing makes them one, so two sessions can still interleave
between them. What the re-read buys is that the window is seconds instead of
however long steps 2 and 3 took. If two anchors appear anyway, close one as
`not planned` and say which survived.

Issue #1 in that repository is the worked example of the body shape; read it
before writing yours. Its sections:

| section | holds |
| --- | --- |
| Intent | the one sentence of what this campaign is for |
| Scope | what is in, and an explicit out-of-scope list |
| Requirements | the conditions the finished work must satisfy |
| Plan | a `- [ ]` checklist of the subtasks visible now |
| Repos | a `- owner/name` list of the member repositories |

Scope is what a later run reads to decide new-versus-follow-up in step 1, so
write it to be matched against a request, not admired.

### 4. Scaffold the directory

Resolve the container root once, from the container root, and address every path
below through it — a later step runs with a different working directory:

```sh
CONTAINER=$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd -P)
```

Not `git rev-parse --show-toplevel`. In a linked worktree that returns the
worktree, and the campaign gets scaffolded where the closing skill will never
look for it.

Reject a slug that is not plain kebab-case before it reaches a path. A slug
comes from a person and lands in a `cp` destination, so one containing `../`
writes outside the container:

```sh
printf '%s' "<slug>" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'
```

Then build the directory:

```sh
CAMPAIGN="$CONTAINER/<slug>-$(date +%y%m%d)"
[ -e "$CAMPAIGN" ] && echo "exists, stop" || cp -R <skill>/assets "$CAMPAIGN"
```

`cp -R` over a live campaign exits 0 and replaces a filled-in `README.md` with
placeholders, so the existence test is a gate, not a formality. What to do when
it does exist depends on which campaign is in it: read `$CAMPAIGN/README.md`.
The same campaign — another session on this machine got here first, given the
same slug on the same day — leave the directory alone, skip to step 5, which is
safe to re-run. A different campaign, or unreadable — stop and ask the person.

Then finish it:

- Move the chosen `agents/<kind>.md` to `AGENTS.md` and delete `agents/`.
- Overwrite `README.md` with the anchor issue body, which replaces every
  placeholder at once. The two carry the same five sections in the same shapes,
  so this is the close-time sync run backwards:

  ```sh
  gh issue view <N> -R kalaluthien/agent-workspace --json body --jq .body \
    >| "$CAMPAIGN/README.md"
  cp "$CAMPAIGN/README.md" "$CAMPAIGN/runtime/anchor-body-derived.md"
  sed -n '/^## Repos/,/^## /{/^- /p;}' "$CAMPAIGN/README.md" \
    | grep -q '<' && echo "placeholders survive in ## Repos"
  ```

  `>|`, not `>` — see the redirect gotcha below.
- **Keep the copy.** `runtime/anchor-body-derived.md` is the body exactly as it
  read at the moment this README was derived from it, and it is the only thing
  that can later answer "has the body moved since?". `closing-campaign` step 4
  refuses to overwrite the body without it. Refresh it every time you re-derive
  the README, and after every successful sync. It is scratch, like everything
  else under `runtime/`, and dies with the directory — which is the right
  lifetime, because it is only ever compared against by a session working in
  this tree.
- The `README.md` is the working copy a campaign session edits. Several sessions
  may hold this campaign and each has its own copy, which is why the write back
  to the issue body compares before it writes. A delegate never touches either.
- The directory is git-ignored by the container's allowlist. Nothing durable may
  live only there; if you write something that must survive, it belongs in a
  member repository or on a GitHub issue.

### 5. Acquire the member repositories

For each entry under `## Repos`, by absolute path — step 4 has just created an
empty `$CAMPAIGN/scripts/`, so a relative `scripts/acquire-repo` resolves there
and fails:

```sh
"$CONTAINER/scripts/acquire-repo" <owner/repo> "$CAMPAIGN/repos/<name>"
```

Safe to re-run. Do not clone by hand and do not read the script to work out what
it does — its interface is the contract.

**No `--branch` here.** A branch is named `c<N>/<issue>-<topic>` and no subtask
issue exists yet, so there is no name to pass. The checkout is left on the
repository's default branch and each delegate cuts its own branch when it starts
on its subtask — see "Filing a subtask issue".

That is also what keeps the checkout safe when two sessions hold this campaign.
One directory serves both, so `--branch` here would make a re-run of this step
switch the shared checkout onto another branch, under a delegate already working
in it. Without `--branch`, `acquire-repo` re-runs as a fetch and touches no
branch.

### 6. Report

The campaign ID, the directory path, and the anchor issue URL. Then the first
subtask, and whether you are doing it here or handing it to a repository agent.

### Filing a subtask issue

Both the follow-up path in step 1 and every subtask after step 6 file the same
shape. `--parent` is what puts the issue in the campaign, so an issue filed
without it belongs to no campaign and appears in no listing:

```sh
gh issue create -R <owner/repo> \
  --parent https://github.com/kalaluthien/agent-workspace/issues/<N> \
  --title "<title>" --body-file <path>
```

The body carries a line `Campaign: kalaluthien/agent-workspace#<N>`. That is
prose for a person reading the raw issue; nothing queries it.

**The issue number is half the branch name.** The subtask is worked on
`c<N>/<issue>-<topic>` — campaign number, subtask number, then a short topic —
so the branch cannot be named until the issue exists, and this is the step that
mints it. The campaign number alone keeps two campaigns apart; the subtask
number is what keeps two subtasks of one campaign apart, which matters as soon
as two sessions delegate into one repository and both reach for the same topic
word. Put the branch name in the handover brief, and let the delegate create it:

```sh
git -C "$CAMPAIGN/repos/<name>" switch -c c<N>/<issue>-<topic>
```

Read the campaign's subtasks back from the anchor, in one call, across every
repository:

```sh
gh api --paginate repos/kalaluthien/agent-workspace/issues/<N>/sub_issues
```

`--paginate` is not optional: the endpoint pages at thirty, and a truncated
index reads exactly like a complete one.

If the target repository is not in the anchor's `## Repos` list, add it to the
campaign `README.md`, sync that to the anchor body, and acquire it as in step 5.
The list is what a later open reads to know what to clone; the index does not
depend on it.

**Sync it now, and compare before you write.** Leaving the addition in a local
`README.md` until the campaign closes hides the new repository from every other
session holding this campaign — one of them will open the campaign on its
machine, clone the list, and have no checkout for the subtask you just filed.
And writing the body without comparing is how a repository gets dropped from the
list for good. Use `closing-campaign` step 4's compare-then-write, in full,
including the refresh of `runtime/anchor-body-derived.md` afterwards; it is the
only sanctioned way to write the anchor body, and closing is not the only time
it happens.

## Example

A request that reads "the auth token refresh is broken across api and web",
opened as campaign #7:

```
auth-refactor-260828/
  AGENTS.md      copied from assets/agents/migration.md
  CLAUDE.md      @AGENTS.md
  README.md      the five sections, copied from issue #7's body
  runtime/handover/ scripts/
  runtime/anchor-body-derived.md  issue #7's body as the README was derived from
  repos/api/     on the default branch; subtask #31 is worked on c7/31-token-refresh
  repos/web/     on the default branch; subtask #12 is worked on c7/12-token-refresh
```

## Gotchas

- A request that sounds new is usually a follow-up. Step 1 is the step this
  procedure exists for; skipping it produces a second campaign over the same
  scope, and nothing errors — you get two anchor issues that both look right.
  Two sessions each running step 1 honestly produce the same pair, which is why
  step 3 surveys a second time.
- **You are not the only campaign session.** Any session opened in the container
  root is one, several may hold this campaign at once, and none of them is
  privileged or announced anywhere. Everything durable here is therefore written
  as read-then-write against GitHub, never as "mine because I made it": the
  anchor body is compared before it is overwritten, the directory may already
  exist because a peer built it minutes ago, and the shared checkout is left on
  its default branch so a re-run cannot move it under somebody's delegate.
- Filing the anchor issue after scaffolding gives the directory a slug with no
  ID behind it and branches named for a number you have not got yet. Order
  matters here and nowhere else in the procedure.
- A delegate does not pick up the campaign `AGENTS.md` from its parent
  directories. It reaches the delegate only through
  `--append-system-prompt-file <campaign>/AGENTS.md` at launch; without that
  flag the delegate reads the repository's own file and nothing else, and
  reports nothing wrong.
- Where the campaign file does reach a delegate, it sits beside the
  repository's own conventions. Adding a principle is free; contradicting one
  hands the delegate a conflict it cannot resolve, and it will pick a side
  without telling you.
- `gh issue create` without `--parent` succeeds. It returns a URL and a live
  issue that belongs to no campaign, and only a later listing that comes back
  short shows anything is wrong.
- This machine's zsh sets `noclobber` and leaves `APPEND_CREATE` unset. Plain
  `>` onto a file that exists fails with `file exists`, and plain `>>` onto a
  file that does not exist yet fails with `no such file or directory`, which
  reads like a missing directory. Write `>|` and `>>|`. Neither failure stops
  the steps around it, so a fill that never happened still reports success.
- `git status` in the container root will never show the campaign directory.
  That is the allowlist working, not a missing file.
- Never run one git command across `repos/*`. Each is its own repository with
  its own remote.
