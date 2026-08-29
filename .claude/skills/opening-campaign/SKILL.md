---
name: opening-campaign
description: Opens a campaign in the agent-workspace container, or joins one that already exists — decides new versus follow-up, files the anchor issue and binds it to this machine, scaffolds its directory and takes it as the holding session, and acquires the member repositories. Use when a person arrives in the container root with an unstructured request, such as a sentence, an issue number, or a screenshot, and cross-repository work has to start. Not for closing a campaign, and not for the second and later subtasks of a campaign already scaffolded in this directory.
---

# Opening a campaign

Turn one person's unstructured request into a campaign: an anchor issue that is
its identity, a directory that is its workspace, and member repositories ready
to work in.

Finished when all of these hold:

- An open issue in `kalaluthien/agent-workspace` carries the label `campaign`,
  no parent, and the sections of the anchor template `assets/README.md`, with
  `Repos` a plain `- owner/repo` list.
- The anchor's latest `BOUND` comment names this machine.
- `<slug>-<YYMMDD>/` exists at the container root and holds `AGENTS.md`,
  `CLAUDE.md`, `README.md`, `runtime/handover/`, `runtime/executors/`,
  `runtime/holder`, and `scripts/`, with `runtime/holder` naming this session
  and a live PID.
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

**That repository holds subtasks too**, because it is a member of its own
campaigns, and issues that are neither — a person's request, somebody else's
bug. The `campaign` label is applied by hand at create time, so cross-check it
against the one property a subtask cannot have:

```sh
gh issue list -R kalaluthien/agent-workspace --state open \
  --json number,title,parent \
  --jq '.[] | select(.parent == null) | "#\(.number)\t\(.title)"'
```

An anchor is the issue nothing is the parent of, so every anchor is in that
output whether or not it was labelled. An issue it names that the labelled
listing does not may be an anchor whose label was forgotten — read its body
before deciding no campaign covers the request, and read it for shape, which is
what tells the three kinds apart when neither reading places it. The anchor
template's sections mean the label was forgotten; a `Campaign: owner/repo#<N>`
first line means a subtask filed without `--parent`; neither means an issue that
is in no campaign at all, and that one you leave alone rather than survey, join,
or edit. A labelled issue *missing* from the output is a subtask wearing the
label, or a campaign filed under another campaign; say so rather than joining
it.

| what you find | what to do |
| --- | --- |
| No open campaign's Scope covers the request | Open a new campaign: continue to step 2. |
| One open campaign's Scope covers it | Read the binding below, then the holder. **In that order** — they decide whether you may touch this campaign at all, and as what. |
| Two or more could cover it, or the fit is arguable | Ask the person which, naming the candidates. Do not guess. |

The two readings, and the three roles they give, are § Who is a campaign session
in the container's `AGENTS.md`. What follows is how to run them here.

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

**Then read the binding, before anything else about this campaign.** A campaign
runs on one machine at a time, and joining one bound elsewhere is the mistake
this read exists to stop — the full rule is § Who is a campaign session in the
container's `AGENTS.md`.

```sh
gh api --paginate repos/kalaluthien/agent-workspace/issues/<N>/comments \
  --jq '.[] | select(.body | startswith("BOUND ")) | .body' | tail -1
hostname -s
```

Another machine — stop. File nothing, scaffold nothing, launch nothing; say
which machine holds it, and that only the person can move it by posting a new
`BOUND` comment once that machine is released or dead. No output at all — the
campaign predates the rule and is unbound; ask the person before binding it
here, because holding its directory is not what binds it.

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
PID=$(awk '$1 == "pid" { print $2 }' "$CAMPAIGN/runtime/holder" 2>/dev/null)
kill -0 "$PID" 2>/dev/null && [ "$(ps -o comm= -p "$PID")" = claude ]
```

Alive, and not this session — you are an **executor session** on one subtask.
File it or take the one you were given, and then, **before you claim anything**,
decide the mode: § Running a campaign in the container's `AGENTS.md` says an
executor that changes a repository runs in a process started in that
repository's checkout. You may work a container subtask or campaign-directory
work yourself; a member-repository subtask makes you the *launcher* of a
delegate. That decision names the branch you are about to claim and the process
that will hold it, so it cannot come after the claim.

**Working it yourself** — claim the branch, then send the holding session
`CLAIMED <branch> <your ListAgents name> <your $CLAUDE_PID>`, whose format and
fields are § Talking to a repository agent in the container's `AGENTS.md`. Read
your own name off the first line of `ListAgents`, which names the calling
session. Skipping the announcement is not a small omission: it is the only thing
that puts you in `<campaign>/runtime/executors/`, and that directory is the only
place the holder's close gate looks for you.

**Launching a delegate** — send no `CLAIMED`. The claim is the delegate's, its
`--name` is its branch, and `herdr agent list` is where the holder reads it;
announcing it under your name would give one process two addresses. Step 5 below
*is* yours in this case — the delegate needs its repository checked out — and §
Delegating to a repository agent in the container's `AGENTS.md` is the launch.

Either way, stop there: from here you are an agent, and § Talking to a
repository agent is your half of it. You do not scaffold, sync, or close.

Dead, missing, or your own — you are the holding session; rewrite the file as
step 4 does and carry on in that directory. **When a `CLAIMED` reaches you**,
record it before doing anything else, because a message is gone with the session
that received it. The record's three fields and the `printf` that writes them are
§ Talking to a repository agent in the container's `AGENTS.md`; write it to
`$CAMPAIGN/runtime/executors/<issue>`, after `mkdir -p "$CAMPAIGN/runtime/executors"`
if this campaign was scaffolded before that directory existed.

No directory at all — the campaign exists on GitHub but not on this machine, so
run steps 2, 4 and 5 for it, taking its ID and body from the anchor issue. Skip
step 3: it exists only to mint an ID this campaign already has, and the campaign
is already bound.

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

**Read the label back before scaffolding anything.** `--label campaign` is what
makes the anchor findable at all, and an anchor filed without it is invisible to
every later survey, so the next session opens a second campaign over the same
scope and nothing reports it (probed: an unlabelled parent issue does not appear
in step 1's labelled listing).

```sh
gh issue view <N> -R kalaluthien/agent-workspace --json labels,parent
```

Want `campaign` among `labels` and `parent` null. A non-null `parent` means you
filed a subtask, not an anchor — `gh issue edit <N> --remove-parent` before
going on.

**Then bind the campaign to this machine**, in the same step, because everything
after it is a write or a launch and both are gated on the binding:

```sh
gh issue comment <N> -R kalaluthien/agent-workspace --body "BOUND $(hostname -s)"
```

This is one of only two occasions a session posts `BOUND` — a campaign it filed
itself. The other is a person's word, and that one is a migration; see § Who is
a campaign session in the container's `AGENTS.md`. Read it back the way step 1
reads it, and if the latest `BOUND` is not yours, somebody migrated the campaign
in the seconds since: stop and say so.

**Write the body by filling the anchor template**, `assets/README.md` in this
skill — its sections, each placeholder replaced, and no others. That file is the
one copy of the anchor's shape: step 4 copies it into the campaign directory as
the placeholder `README.md` and then replaces it with what you write here, and a
later survey classifies by the shape you leave behind. Issue #1 in that
repository is the worked example; read it beside the template.

Scope is what a later run reads to decide new-versus-follow-up in step 1, so
write it to be matched against a request, not admired. `## Plan` is the
decomposition as it stands now and is never revised afterwards — the body is a
charter, and progress is read from the sub-issue index instead (§ Running a
campaign in the container's `AGENTS.md`).

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
same slug on the same day — leave the directory alone and read `runtime/holder`
as step 1 does: a live holder makes you an executor session, a dead one makes
you the holder, and either way skip to step 5, which is safe to re-run. A
different campaign, or unreadable — stop and ask the person.

Then finish it:

- Confirm `runtime/executors/` came with the copy — it holds a `.gitkeep` and
  nothing else. It is where a received `CLAIMED` is recorded, and
  `closing-campaign` refuses a close when it is missing: an empty one says no
  executor announced, an absent one says nothing at all.
- Move the chosen `agents/<kind>.md` to `AGENTS.md` and delete `agents/`.
- Delete `subtask.md`. It came along with the copy, but a subtask is filed from
  the skill's own copy at `assets/subtask.md`; a second copy sitting in a
  git-ignored directory is one that can be filled long after it has gone stale.
- Overwrite `README.md` with the anchor issue body, which replaces every
  placeholder at once. The two carry the same sections in the same shapes —
  both are `assets/README.md` filled in — so this is the close-time sync run
  backwards:

  ```sh
  gh issue view <N> -R kalaluthien/agent-workspace --json body --jq .body \
    >| "$CAMPAIGN/README.md"
  cp "$CAMPAIGN/README.md" "$CAMPAIGN/runtime/anchor-body-derived.md"
  sed -n '/^## Repos/,/^## /{/^- /p;}' "$CAMPAIGN/README.md" \
    | grep -q '<' && echo "placeholders survive in ## Repos"
  ```

  `>|`, not `>` — see the redirect gotcha below.
- **Take the campaign, in `runtime/holder`.** It is what every later session
  reads to know whether this machine's copy already has a holding session:

  ```sh
  printf 'session %s\npid %s\n' "$CLAUDE_CODE_SESSION_ID" "$CLAUDE_PID" \
    >| "$CAMPAIGN/runtime/holder"
  ```

  Write it when you claim the directory, not when you leave it: only the claim
  knows what holding means for the work about to start. Overwrite a holder whose
  PID is dead; a live one means the directory is somebody's, and step 1 already
  sent you down the executor path.
- **Keep the copy.** `runtime/anchor-body-derived.md` is the body exactly as it
  read at the moment this README was derived from it, and it is the only thing
  that can later answer "has the body moved since?". `closing-campaign` step 4
  refuses to overwrite the body without it. Refresh it every time you re-derive
  the README, and after every successful sync. It is scratch, like everything
  else under `runtime/`, and dies with the directory — which is the right
  lifetime, because it is only ever compared against by a session working in
  this tree.
- The `README.md` is the working copy the holding session edits, and the write
  back to the issue body still compares before it writes — against a person's
  own edit to the charter, and against a machine writing the anchor it is not
  bound to. Neither a delegate nor an executor session touches either copy.
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

**No `--branch` here.** A branch is named `campaign-<N>/<issue>-<topic>` and no
subtask issue exists yet, so there is no name to pass. The checkout is left on the
repository's default branch and each delegate cuts its own branch when it starts
on its subtask — see "Filing a subtask issue".

That is also what keeps the checkout safe when an executor session shares this
campaign's directory. One checkout serves both it and the holding session, so
`--branch` here would make a re-run of this step switch it onto another branch,
under a delegate already working in it. Without `--branch`, `acquire-repo`
re-runs as a fetch and touches no branch.

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

`--body-file` takes the subtask template filled in — `assets/subtask.md` in this
skill: the `Campaign:` line, the work, and a `Done when` close. The line is prose
for a person reading the raw issue and nothing queries it; the shape is what
makes the issue readable as a subtask by anyone who has not yet read `--parent`
back.

**The issue number is half the branch name, and the branch is the claim.** The
subtask is worked on `campaign-<N>/<issue>-<topic>` — campaign number, subtask
number, then a short topic — so the branch cannot be named until the issue
exists, and this is the step that mints it. The campaign number keeps two
campaigns apart; the subtask number keeps two subtasks of one campaign apart.
What keeps two *executors* off one subtask is the claim: create the branch on
the remote before launching anyone onto it, and read a refusal as the subtask
being already taken —

```sh
gh api repos/<owner>/<repo>/git/refs \
  -f ref=refs/heads/campaign-<N>/<issue>-<topic> \
  -f sha=$(git -C "$CAMPAIGN/repos/<name>" rev-parse origin/main)
git -C "$CAMPAIGN/repos/<name>" fetch origin campaign-<N>/<issue>-<topic>
git -C "$CAMPAIGN/repos/<name>" switch -c campaign-<N>/<issue>-<topic> \
  --track origin/campaign-<N>/<issue>-<topic>
```

Put the branch name in the handover brief; the delegate finds its branch
already on the remote, which is also how a reader on any machine knows the
subtask is held before its first commit lands.

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

**Sync it now, and compare before you write.** Adding a repository is a scope
change, which is one of the two moments the anchor body is written at all — the
other is the close, and filing the subtask itself is not one of them, because
the sub-issue index already carries it. Leaving the addition in a local
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
  README.md      issue #7's body, section for section
  runtime/handover/ runtime/executors/ scripts/
  runtime/anchor-body-derived.md  issue #7's body as the README was derived from
  runtime/holder                  the session holding #7 on this machine
  repos/api/     on the default branch; #31 is worked on campaign-7/31-token-refresh
  repos/web/     on the default branch; #12 is worked on campaign-7/12-token-refresh
```

## Gotchas

- A request that sounds new is usually a follow-up. Step 1 is the step this
  procedure exists for; skipping it produces a second campaign over the same
  scope, and nothing errors — you get two anchor issues that both look right.
  Two sessions each running step 1 honestly produce the same pair, which is why
  step 3 surveys a second time.
- **You may not be this campaign's session**, and the two reads in step 1 are
  what decide it — in that order, because a campaign bound elsewhere is not yours
  to read a holder file for. Everything durable is still written as read-then-write
  against GitHub rather than as "mine because I made it": the anchor body is
  compared before it is overwritten, the directory may already exist, and the
  shared checkout is left on its default branch so a re-run cannot move it under
  somebody's delegate.
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
