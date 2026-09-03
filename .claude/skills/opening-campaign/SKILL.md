---
name: opening-campaign
description: Opens a campaign in the agent-workspace container, or joins one already open. Use when a person says to open, start, kick off, set up, or join a campaign, or when a request will outlive the session it arrived in — files the anchor issue, binds it to this machine, scaffolds its directory, acquires the member repositories, and files the first subtasks. Not for a request that finishes in the session it arrived in, not for closing a campaign, and not for a later subtask of a campaign already scaffolded here.
---

# Opening a campaign

Finished when all of these hold:

- An open issue in `kalaluthien/agent-workspace` carries the label `campaign`,
  no parent, and the sections of the anchor template `assets/README.md`, with a
  `## Repos` list that `scripts/campaign-repos.py` reads and exits 0 on.
- The anchor's latest `BOUND` comment names this machine.
- `<slug>-<YYMMDD>/` exists at the container root and holds `AGENTS.md`,
  `CLAUDE.md`, `scripts/`, `runtime/handover/`, `runtime/claims/`,
  `runtime/repos`, and a `README.md` and `runtime/anchor-body-derived.md` that
  each hold the anchor issue body byte for byte.
- Every line `scripts/campaign-repos.py` prints resolves to a checkout at
  `<campaign>/repos/<name>/` — vacuous under `- none`, where it prints nothing.
- At least one subtask is filed as a sub-issue of the anchor, and the reply names
  it along with the campaign ID, the directory and the anchor issue URL.

## Procedure

Ordered: the anchor issue number is the campaign ID, so nothing that needs the ID
runs before step 3. Why each guard is shaped this way: `references/rationale.md`.

### 1. Read the binding, then find the directory

A campaign that does not exist yet goes straight to step 2. Otherwise read the
binding before anything else about it, because joining one bound elsewhere is the
mistake this read exists to stop.

```sh
CONTAINER=$(cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")" && pwd -P)
"$CONTAINER"/scripts/campaign-tracker.py bound <N>    # here | elsewhere <machine> | unbound
```

`here` — carry on, and that one read is the whole membership question. Anything
else, a failed read included, stops you: file nothing, scaffold nothing, launch
nothing. Name the machine that holds it; on `unbound`, ask before binding it
here, since having its directory here is not what binds it.

Then find out whether this machine has a directory. "Already scaffolded" is a
fact about a directory, not about the campaign.

```sh
ls -d "$CONTAINER"/*-[0-9][0-9][0-9][0-9][0-9][0-9]/ 2>/dev/null
CAMPAIGN=$(cd "$CONTAINER/<the directory that matched>" && pwd -P)
mkdir -p "$CAMPAIGN/runtime/claims"
```

A directory whose `README.md` names this campaign is the one to work in, peers
working in it too being the normal state. `mkdir -p` because a campaign
scaffolded before that directory existed has none, and a missing one leaves the
close gate unable to enumerate at all.

**No directory at all** — run steps 2, 4 and 5 with the ID and body from the
anchor issue, and skip step 3, which exists only to mint an ID it already has.
Do it before launching or receiving anything: until the directory exists a claim
record has nowhere to be written (`AGENTS.md` § ID, directory, branch). Step 2
still runs, because neither the slug nor the kind is recoverable from GitHub; say
which kind you picked.

### 2. Name it and pick its kind

- **Slug** — kebab-case, meaningful, no date; step 4 appends the date.
- **Title** — the display name, in the requester's own words, not yours.
- **Kind** — which `assets/agents/*.md` becomes the campaign's `AGENTS.md`.

| the campaign exists to | kind |
| --- | --- |
| answer an open question | `research` |
| measure or audit something that already runs | `analysis` |
| find out whether an approach can work at all | `prototyping` |
| move a working system from one form to another | `migration` |

With a person in the conversation, propose all three in one message and wait;
from a handover brief with nobody waiting, read all three from the brief. Either
way state them in the reply, so each costs one line to veto — an unstated kind is
a wrong set of principles for every delegate.

### 3. File the anchor issue

**Survey again, in the same breath as the create.** The routing gate's survey is
minutes old, and two sessions that each surveyed before either filed both file,
so one scope gets two campaigns. Nothing closes that window, because a campaign
that does not exist yet is bound to nobody: if two anchors appear anyway, close
one as `not planned` and say which survived.

```sh
"$CONTAINER"/scripts/campaign-tracker.py anchors
gh issue create -R kalaluthien/agent-workspace \
  --label campaign --title "<title>" --body-file <path>
```

**Fill the anchor template** for the body, `assets/README.md` in this skill — its
sections, each placeholder replaced, and no others. Write Scope to be matched
against a request by the routing gate. The body carries no decomposition
(`AGENTS.md` § The anchor body); step 6 files the first subtasks instead.

**Read the label back before scaffolding anything**, because an anchor filed
without it is invisible to every later survey and the next session opens a second
campaign over the same scope.

```sh
gh issue view <N> -R kalaluthien/agent-workspace --json labels,parent
```

Want `campaign` among `labels` and `parent` null. A non-null `parent` means you
filed a subtask, not an anchor — `gh issue edit <N> --remove-parent` first.

**Then bind it to this machine, in the same step** — everything after is a write
or a launch, both gated on the binding. One of the two occasions a session posts
`BOUND`, read back as `AGENTS.md` § The binding says.

```sh
gh issue comment <N> -R kalaluthien/agent-workspace --body "BOUND $(hostname -s)"
```

### 4. Scaffold the directory

Address every path below through `$CONTAINER` from step 1: a later step runs with
a different working directory. Reject a slug that is not plain kebab-case before
it reaches a path — a slug comes from a person and lands in a `cp` destination,
so one containing `../` writes outside the container.

```sh
printf '%s' "<slug>" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'
CAMPAIGN="$CONTAINER/<slug>-$(date +%y%m%d)"
if mkdir "$CAMPAIGN" 2>/dev/null; then
  cp -R <skill>/assets/. "$CAMPAIGN"/
else
  echo "exists: read $CAMPAIGN/README.md before writing anything in it"
fi
```

**The `mkdir` without `-p` is the gate**, and the only atomic one here: two
sessions arriving with the same slug on the same day cannot both create the tree.
A `[ -e ]` test before the copy is a read and a write with a gap between, and
`cp -R` over a live campaign exits 0 while replacing a filled-in `README.md`
with placeholders.

Being told is not an error. Read `$CAMPAIGN/README.md`: the same campaign — work
in that directory and skip to step 5, which is safe to re-run; a different
campaign, or unreadable — stop and ask.

Then finish it:

- Move the chosen `agents/<kind>.md` to `AGENTS.md` and delete `agents/`.
- Delete `subtask.md` and `handover.md`. Both are filled once *per subtask* from
  the skill's own copy, so neither top-level copy has a reader and a stale one
  could be filled long after.
- Everything else the copy brought stays. Confirm `runtime/claims/` arrived,
  because `closing-campaign` refuses a close when it is missing.
- Overwrite `README.md` with the anchor issue body, which replaces every
  placeholder at once — the close-time sync run backwards:

  ```sh
  gh issue view <N> -R kalaluthien/agent-workspace --json body --jq .body \
    >| "$CAMPAIGN/README.md"
  cp "$CAMPAIGN/README.md" "$CAMPAIGN/runtime/anchor-body-derived.md"
  "$CONTAINER/scripts/campaign-repos.py" "$CAMPAIGN/README.md" \
    >| "$CAMPAIGN/runtime/repos.tmp" &&
    mv "$CAMPAIGN/runtime/repos.tmp" "$CAMPAIGN/runtime/repos" ||
    { rm -f "$CAMPAIGN/runtime/repos.tmp"
      echo "REFUSE: the ## Repos list did not read; runtime/repos was not written"; }
  ```

  A non-zero exit is a body never filled in, or a list the reader refuses; stop
  and fix the body. Keep the `.tmp`-then-`mv`, and keep step 5 reading that file
  rather than a pipe, so a failed read cannot look like a deliberate `- none`.
  `>|`, not `>`.
- **Keep `runtime/anchor-body-derived.md`**, refreshed after every re-derivation
  and every sync — the only thing that can later answer "has the body moved?",
  and `closing-campaign` step 4 refuses without it.

### 5. Acquire the member repositories

Yours whenever you launch a delegate. For each line `scripts/campaign-repos.py`
printed in step 4, by absolute path — step 4 has just created an empty
`$CAMPAIGN/scripts/`, so a relative path resolves there and fails.

```sh
ACQUIRE="$CONTAINER/.claude/skills/opening-campaign/scripts/acquire-repo.sh"
while read -r REPO; do
  "$ACQUIRE" "$REPO" "$CAMPAIGN/repos/${REPO##*/}"
done < "$CAMPAIGN/runtime/repos"
```

`- none` gets no special case: the loop runs zero times and `repos/` is never
created. Say in the reply that no repository was acquired, so a campaign that was
*meant* to have some is one line to correct.

Safe to re-run; do not clone by hand, and do not read the script — its interface
is the contract. **No `--branch` here**: a re-run with one would switch a shared
checkout under a delegate already working in it.

### 6. File the first subtasks, then report

File the subtasks the opening already implies, a campaign whose scope is one
subtask filing one. Then report the campaign ID, the directory path, the anchor
issue URL, and the subtasks filed, saying of the first whether you are doing it
here or handing it to a repository agent.

### Filing a subtask issue

Step 6's subtasks and one the routing gate sent here to join are filed and
claimed the same way. File it as `AGENTS.md` § Subtasks says. **Filing needs no
binding**: any session anywhere may file a sub-issue of any campaign, since the
link is a record and not a claim (`AGENTS.md` § The binding); the claim below is
what the binding gates. **The issue number
is half the branch name, and the branch is the claim**, so the claim cannot be
cut until the issue exists and this is the step that mints it.

```sh
"$CONTAINER/scripts/campaign-claim.py" take <N> <issue> <topic> \
  --dir "$CAMPAIGN" --repo <owner/repo> --name "<this session's ListAgents name>"
```

One call cuts the branch from the named remote and writes the claim record. Exit
3 is the ref already existing, which is the subtask being taken: read who holds
it, and do not push past it. A repo-less campaign claims on the container all the
same — `--repo` defaults there. Give the branch a local checkout only where the
subtask has one, then put the branch name in the handover brief:

```sh
B=campaign-<N>/<issue>-<topic>
git -C "$CAMPAIGN/repos/<name>" fetch origin "$B" &&
  git -C "$CAMPAIGN/repos/<name>" switch -c "$B" --track "origin/$B"
```

**A repository the anchor's `## Repos` list does not name** is a scope change, so
it syncs at that moment rather than at the close: edit the campaign `README.md`,
re-run the reader over it as step 4 does, sync with `closing-campaign` step 4's
compare-then-write in full, then acquire it as in step 5. The first repository
**replaces** `- none`, and `campaign-repos` refuses a list mixing the two.

## Gotchas

The probes and the failures behind these: `references/gotchas.md`.

- A delegate does not pick up the campaign `AGENTS.md` from its parent
  directories; it arrives only through `--append-system-prompt-file`, without
  which nothing reports the omission. Where it does arrive it sits beside the
  repository's own conventions: adding a principle is free, contradicting one
  hands the delegate a conflict it resolves without telling you.
- `gh issue create` without `--parent` succeeds, returning a live issue in no
  campaign; only a later listing coming back short shows anything is wrong.
- This machine's zsh sets `noclobber` and leaves `APPEND_CREATE` unset, so plain
  `>` onto an existing file and plain `>>` onto a missing one fail without
  stopping the steps around them. Write `>|` and `>>|`.
