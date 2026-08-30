---
name: opening-campaign
description: Opens a campaign in the agent-workspace container, or joins one that already exists — files the anchor issue and binds it to this machine, scaffolds its directory and takes it as the holding session, and acquires the member repositories. Use once AGENTS.md § Not every request is a campaign has decided the request opens a campaign, or joins one this machine is not yet holding. Not for a request that finishes in the session it arrived in, not for closing a campaign, and not for the second and later subtasks of a campaign already scaffolded in this directory.
---

# Opening a campaign

Turn one person's unstructured request into a campaign: an anchor issue that is
its identity, a directory that is its workspace, and member repositories ready
to work in.

Finished when all of these hold:

- An open issue in `kalaluthien/agent-workspace` carries the label `campaign`,
  no parent, and the sections of the anchor template `assets/README.md`, with a
  `## Repos` list that `scripts/campaign-repos` reads and exits 0 on — never a
  bare `grep '<'` over the whole file, which reports hits on a clean README.
- The anchor's latest `BOUND` comment names this machine.
- `<slug>-<YYMMDD>/` exists at the container root and holds `AGENTS.md`,
  `CLAUDE.md`, `README.md`, `runtime/handover/`, `runtime/claims/`,
  `runtime/holder`, `runtime/repos`, and `scripts/`, with `runtime/holder`
  naming this session and a live PID.
- The campaign's `README.md` is the anchor issue body, and
  `runtime/anchor-body-derived.md` holds that body byte for byte.
- Every line `scripts/campaign-repos` prints resolves to a checkout at
  `<campaign>/repos/<name>/` — vacuous under `- none`, where it prints nothing,
  step 5 does nothing, and `repos/` is never created.
- At least one subtask is filed as a sub-issue of the anchor. That index is the
  campaign's decomposition, and the body carries none.
- The reply names the campaign ID, the directory, the anchor issue URL, and the
  subtasks filed.

## Procedure

The steps are ordered. The anchor issue number is the campaign ID, so nothing
that needs the ID can run before step 3. Why each guard is shaped the way it is:
`references/rationale.md`.

### 1. Read the binding, then the holder

You arrive having already been told what the request is, by `AGENTS.md` § Not
every request is a campaign: either no open campaign covers it and you are
opening one — go straight to step 2 — or one does, and this machine is not yet
holding it. **That survey lives there and only there.** Two prose copies of it
would drift, and the copy this skill kept was the one a session reached last.

**Read the binding before anything else about this campaign**, because joining
one bound elsewhere is the mistake this read exists to stop (§ Who is a campaign
session in the container's `AGENTS.md`).

```sh
"$CONTAINER"/scripts/campaign-bound <N>      # here | elsewhere <machine> | unbound
```

`here` — carry on. Anything else, including a failed read, stops you.

Another machine — stop: file nothing, scaffold nothing, launch nothing, and say
which machine holds it and that only the person can move it. No output — the
campaign is unbound, so ask before binding it here; holding its directory is not
what binds it.

Then check whether this machine holds the campaign at all. "Already scaffolded"
is a fact about a directory, not about the campaign:

```sh
CONTAINER=$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd -P)
ls -d "$CONTAINER"/*-[0-9][0-9][0-9][0-9][0-9][0-9]/ 2>/dev/null
```

A directory whose `README.md` names this campaign — bind `CAMPAIGN` to it, and
read its `runtime/holder` before working in it:

```sh
CAMPAIGN=$(cd "$CONTAINER/<the directory that matched>" && pwd -P)
if [ ! -s "$CAMPAIGN/runtime/holder" ]; then V=none
else
  PID=$(awk '$1 == "pid" { print $2 }' "$CAMPAIGN/runtime/holder")
  V=$("$CONTAINER/scripts/campaign-session-alive" "$PID" 2>&1) || V="unreadable ($V)"
fi
echo "$V"
```

**`alive`, `other` or `unreadable`, and the holder is not this session — you are
an executor session** on one subtask. Only `none` and `dead` are confirmed
absences; the other three say the holder may be there and the reading cannot see
it, and overwriting `runtime/holder` on a guess gives one campaign two holders.
`unreadable` carries its reason — read it before deciding anything.
File it or take the one you were given, then decide the mode **before you claim
anything**, because the mode names the branch and the process holding it: a
container or campaign-directory subtask is yours to work, so you write your own
claim record to `$CAMPAIGN/runtime/claims/<issue>` at the claim (§ Talking to a
repository agent has its four fields and the `printf`); a member-repository
subtask makes you the *launcher* of a delegate, which needs no record — its
`--name` is its branch — and makes step 5 yours (§ Delegating to a repository
agent). Either way stop there — you do not scaffold, sync, or close.

**`none`, `dead`, or your own — you are the holding session**; rewrite the file as
step 4 does and carry on. Then `mkdir -p "$CAMPAIGN/runtime/claims"` if this
campaign was scaffolded before that directory existed, because every session
that claims a subtask here writes its own record into it and a missing directory
makes the close gate unable to enumerate at all. You do not write another
session's record; you read them.

**No directory at all** — the campaign is on GitHub but not here, so run steps 2,
4 and 5 with its ID and body from the anchor issue, and skip step 3, which exists
only to mint an ID it already has. Do this before launching or receiving
anything: the directory is the only home `runtime/holder` and
`runtime/claims/` have, so until it exists you are not the holder and a claim
record has nowhere to be written (§ Who is a campaign session, "Holding
scaffolds"). Step 2 still runs because neither the slug nor the kind is
recoverable from GitHub; say which kind you picked.

### 2. Name it and pick its kind

Three things fix the campaign:

- **Slug** — kebab-case, meaningful, no date; the date is appended in step 4.
- **Title** — the display name, in the requester's own words, not yours.
- **Kind** — which `assets/agents/*.md` becomes the campaign's `AGENTS.md`.

With a person in the conversation, propose all three in one message and wait.
From a handover brief with nobody waiting, read all three from the brief and
carry on, then state them in the reply so each costs one line to veto.

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

**Survey again, in the same breath as the create**, because the gate's survey is
minutes old and two sessions that each checked before either filed both file.

```sh
gh issue list -R kalaluthien/agent-workspace --label campaign --state open --limit 200
gh issue create -R kalaluthien/agent-workspace \
  --label campaign --title "<title>" --body-file <path>
```

Read the listing before the create; anything new that could cover the request
sends you back to the gate's table. This narrows the window and does not close
it: if two anchors appear anyway, close one as `not planned` and say which
survived.

**Read the label back before scaffolding anything**, because an anchor filed
without it is invisible to every later survey and the next session opens a second
campaign over the same scope.

```sh
gh issue view <N> -R kalaluthien/agent-workspace --json labels,parent
```

Want `campaign` among `labels` and `parent` null. A non-null `parent` means you
filed a subtask, not an anchor — `gh issue edit <N> --remove-parent` first.

**Then bind the campaign to this machine**, in the same step, because everything
after it is a write or a launch and both are gated on the binding:

```sh
gh issue comment <N> -R kalaluthien/agent-workspace --body "BOUND $(hostname -s)"
```

One of only two occasions a session posts `BOUND` (§ Who is a campaign session).
Read it back the way step 1 does: if the latest is not yours, the campaign was
migrated in the seconds since, so stop and say so.

**Write the body by filling the anchor template**, `assets/README.md` in this
skill — its sections, each placeholder replaced, and no others. Write Scope to
be matched against a request by the gate. The body is a charter and carries no
decomposition (§ Running a campaign); step 6 files the first subtasks instead,
and the sub-issue index is the decomposition from there on.

### 4. Scaffold the directory

Resolve the container root once, from the container root, and address every path
below through it — a later step runs with a different working directory. Not
`git rev-parse --show-toplevel`, which in a linked worktree returns the worktree
and scaffolds the campaign where the closing skill will never look for it.

```sh
CONTAINER=$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd -P)
```

Reject a slug that is not plain kebab-case before it reaches a path, because a
slug comes from a person and lands in a `cp` destination, so one containing `../`
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
placeholders, so the existence test is a gate, not a formality. Read
`$CAMPAIGN/README.md` to decide: the same campaign — another session got here
first with the same slug on the same day — leave it alone, read `runtime/holder`
as step 1 does, and skip to step 5, which is safe to re-run; a different
campaign, or unreadable — stop and ask.

Then finish it:

- Move the chosen `agents/<kind>.md` to `AGENTS.md` and delete `agents/`.
- Delete `subtask.md` and `handover.md`. Both are filled from the skill's own
  copy — `AGENTS.md` names `assets/subtask.md` for a subtask and
  `assets/handover.md` for a brief, and a brief is written to
  `runtime/handover/<issue>.md`, never to `handover.md` — so neither top-level
  copy has a reader, and a copy in a git-ignored directory can be filled long
  after it has gone stale.

  What separates these two from `README.md`, which is filled rather than
  deleted: a campaign has one `README.md` and something reads it, so the copy
  is the artifact. A subtask template and a brief template are instantiated
  once *per subtask*, so a single copy at the campaign root is not an unfilled
  artifact — there is nothing it could be filled with. Count the instances
  before deciding whether a templated copy is filled or deleted.
- Everything else the copy brought stays, and that is all of it: `CLAUDE.md`,
  one line of `@AGENTS.md`; `README.md`, overwritten below; `runtime/handover/`
  and `runtime/claims/`, a `.gitkeep` each — confirm `runtime/claims/`
  arrived, because `closing-campaign` refuses a close when it is missing; and
  `scripts/`, which arrives holding a `.gitkeep` and nothing else.
- Overwrite `README.md` with the anchor issue body, which replaces every
  placeholder at once — the close-time sync run backwards:

  ```sh
  gh issue view <N> -R kalaluthien/agent-workspace --json body --jq .body \
    >| "$CAMPAIGN/README.md"
  cp "$CAMPAIGN/README.md" "$CAMPAIGN/runtime/anchor-body-derived.md"
  "$CONTAINER/scripts/campaign-repos" "$CAMPAIGN/README.md" \
    >| "$CAMPAIGN/runtime/repos.tmp" &&
    mv "$CAMPAIGN/runtime/repos.tmp" "$CAMPAIGN/runtime/repos" ||
    { rm -f "$CAMPAIGN/runtime/repos.tmp"
      echo "REFUSE: the ## Repos list did not read; runtime/repos was not written"; }
  ```

  A non-zero exit is a body never filled in, or a `## Repos` list the reader
  refuses; its one line on stderr says which, so stop and fix the body. Keep the
  `.tmp`-then-`mv`, and keep step 5 reading that file rather than a pipe: both
  exist so a failed read cannot look like a deliberate `- none`. `>|`, not `>`.
- **Take the campaign, in `runtime/holder`**, when you claim the directory rather
  than when you leave it, since only the claim knows what holding means for the
  work about to start:

  ```sh
  printf 'session %s\npid %s\n' "$CLAUDE_CODE_SESSION_ID" "$CLAUDE_PID" \
    >| "$CAMPAIGN/runtime/holder"
  ```

  Overwrite a holder whose PID is dead; a live one means step 1 already sent you
  down the executor path.
- **Keep `runtime/anchor-body-derived.md`** — the only thing that can later
  answer "has the body moved?", and `closing-campaign` step 4 refuses without it.
  Refresh it whenever you re-derive the README, and after every successful sync.
- The `README.md` is the holding session's working copy, and neither a delegate
  nor an executor session touches either copy.
- The directory is git-ignored. Nothing durable may live only there.

### 5. Acquire the member repositories

For each line `scripts/campaign-repos` printed in step 4, by absolute path —
step 4 has just created an empty `$CAMPAIGN/scripts/`, so a relative
`scripts/acquire-repo` resolves there and fails:

```sh
while read -r REPO; do
  "$CONTAINER/scripts/acquire-repo" "$REPO" "$CAMPAIGN/repos/${REPO##*/}"
done < "$CAMPAIGN/runtime/repos"
```

`- none` needs no special case here and gets none: the loop runs zero times and
`repos/` is never created. Say in the reply that no repository was acquired, so a
campaign that was *meant* to have some is one line to correct.

`${REPO##*/}` is safe only because step 4 already ran the reader, which refuses
two entries whose checkout directory would collide. Safe to re-run; do not clone
by hand, and do not read the script — its interface is the contract.

**No `--branch` here**, because no subtask issue exists yet to name one, and
because a re-run without it is a fetch that touches no branch where a re-run with
one would switch a shared checkout under a delegate already working in it.

### 6. File the first subtasks, then report

The decomposition lives in the sub-issue index and nowhere else, so file the
subtasks the opening already implies before reporting — "Filing a subtask issue"
below is the shape, and a campaign whose scope is one subtask files one.

Report the campaign ID, the directory path, the anchor issue URL, and the
subtasks filed, saying of the first whether you are doing it here or handing it
to a repository agent.

### Filing a subtask issue

A follow-up the gate sent here to join, and every subtask after step 6, file the
same shape. `--parent` is what puts the issue in the campaign, so an issue filed
without it belongs to no campaign and appears in no listing:

```sh
gh issue create -R <owner/repo> \
  --parent https://github.com/kalaluthien/agent-workspace/issues/<N> \
  --title "<title>" --body-file <path>
```

`--body-file` takes the subtask template filled in — `assets/subtask.md` in this
skill: the `Campaign:` line, the work, and a `Done when` close. Nothing queries
that line; the shape is what makes the issue readable as a subtask.

**The issue number is half the branch name, and the branch is the claim**, so the
branch cannot be named until the issue exists and this is the step that mints it.
Create it on the remote before launching anyone onto it, and read a refusal as
the subtask being already taken. One block claims every subtask, in a member
repository or on the container: **the sha comes from the remote**, which is what
the claim is cut from, never from a checkout whose `origin/main` may be stale,
absent or unfetched — and a repo-less subtask has no checkout to ask.

```sh
BRANCH=campaign-<N>/<issue>-<topic>
CO="$CAMPAIGN/repos/<name>"        # leave it unset when the subtask has no checkout
SHA=$(gh api repos/<owner>/<repo>/commits/main --jq .sha) || exit 1
gh api repos/<owner>/<repo>/git/refs -f ref="refs/heads/$BRANCH" -f sha="$SHA"
if [ -d "${CO:-}" ]; then
  git -C "$CO" fetch origin "$BRANCH" &&
    git -C "$CO" switch -c "$BRANCH" --track "origin/$BRANCH"
fi
```

The read goes into a variable and is checked, because a failed one that still
prints goes up as the sha and comes back as the `422` this skill teaches means
"already claimed" — so the subtask reads as taken and is abandoned. What the
checkout form did and why the API retires it: `references/gotchas.md`. Put the
branch name in the handover brief.

**A repo-less campaign files on the container tracker and claims there**, even
when no container code will change: `<owner>/<repo>` is
`kalaluthien/agent-workspace` and there is no `$CO` for the checkout side, which
is why that side is an `if` rather than a `&&` chain — the chain's last command
exits non-zero when there is no checkout, and the claim it just made would read
as a failure to a `set -e` shell.
Such a subtask runs by your own hands or in an in-process subagent rooted at the
campaign directory; the delegate-in-a-clone mode needs a checkout. It closes as
completed with no pull request, which `scripts/campaign-settlement` prints as
`dropped [completed, no merged pull request]` — the designed reading.

Read the campaign's subtasks back from the anchor, in one call, across every
repository:

```sh
gh api --paginate repos/kalaluthien/agent-workspace/issues/<N>/sub_issues
```

`--paginate` is not optional: the endpoint pages at thirty, and a truncated index
reads exactly like a complete one.

If the target repository is not in the anchor's `## Repos` list, add it to the
campaign `README.md`, sync that to the anchor body, and acquire it as in step 5.
**Adding the first repository replaces `- none`; it never joins it** (§ Running a
campaign). Run the reader over the README before you sync, as step 4 does:

```sh
"$CONTAINER/scripts/campaign-repos" "$CAMPAIGN/README.md" \
  >| "$CAMPAIGN/runtime/repos.tmp" &&
  mv "$CAMPAIGN/runtime/repos.tmp" "$CAMPAIGN/runtime/repos" ||
  { rm -f "$CAMPAIGN/runtime/repos.tmp"
    echo "REFUSE: the ## Repos list did not read; nothing was synced"; }
```

The campaign stops being repo-less at that moment, and everything vacuous for it
— step 5, the close's sweep over `repos/*/` — starts having work to do.

**Sync it now, and compare before you write**, because adding a repository is a
scope change, one of the two moments the anchor body is written at, and one left
local until the close hides the repository from every other session. Use
`closing-campaign` step 4's compare-then-write in full, including the refresh of
`runtime/anchor-body-derived.md`; it is the only sanctioned way to write the
body.

## Example

A request that reads "the auth token refresh is broken across api and web",
opened as campaign #7:

```
auth-refactor-260828/
  AGENTS.md      copied from assets/agents/migration.md
  CLAUDE.md      @AGENTS.md
  README.md      issue #7's body, section for section
  runtime/handover/ runtime/claims/ scripts/
  runtime/anchor-body-derived.md  issue #7's body as the README was derived from
  runtime/holder                  the session holding #7 on this machine
  repos/api/     on the default branch; #31 is worked on campaign-7/31-token-refresh
  repos/web/     on the default branch; #12 is worked on campaign-7/12-token-refresh
```

## Gotchas

The probes and the failures behind these: `references/gotchas.md`.

- A request that sounds new is usually a follow-up, and skipping the gate's
  survey produces two anchor issues that both look right with nothing erroring.
- **You may not be this campaign's session**, and the two reads in step 1 decide
  it — in that order, because a campaign bound elsewhere is not yours to read a
  holder file for.
- Filing the anchor issue after scaffolding gives the directory a slug with no ID
  behind it and branches named for a number you have not got yet.
- A delegate does not pick up the campaign `AGENTS.md` from its parent
  directories; it arrives only through `--append-system-prompt-file`, and without
  that flag nothing reports the omission.
- Where it does arrive it sits beside the repository's own conventions: adding a
  principle is free, contradicting one hands the delegate a conflict it resolves
  without telling you.
- `gh issue create` without `--parent` succeeds, returning a live issue in no
  campaign; only a later listing coming back short shows anything is wrong.
- This machine's zsh sets `noclobber` and leaves `APPEND_CREATE` unset, so plain
  `>` onto an existing file and plain `>>` onto a missing one both fail without
  stopping the steps around them. Write `>|` and `>>|`.
- `git status` in the container root will never show the campaign directory; that
  is the allowlist working.
- Never run one git command across `repos/*`. Each has its own remote.
