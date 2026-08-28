---
name: opening-campaign
description: Opens a campaign in the agent-workspace container — decides new versus follow-up, files the anchor issue, scaffolds its directory, and acquires the member repositories. Use when a person arrives in the container root with an unstructured request, such as a sentence, an issue number, or a screenshot, and cross-repository work has to start. Not for closing a campaign, and not for the second and later subtasks of a campaign that is already scaffolded.
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
  `CLAUDE.md`, `README.md`, `runtime/`, and `scripts/`.
- No angle-bracket placeholder survives in the campaign's `README.md`.
- Every entry under `Repos:` resolves to a checkout at
  `<campaign>/repos/<name>/` and carries the label `campaign-<N>`.
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
| One open campaign's Scope covers it | File a follow-up subtask on that campaign and stop. |
| Two or more could cover it, or the fit is arguable | Ask the person which, naming the candidates. Do not guess. |

Match on Scope, never on `Repos:`. A request that touches a repository an open
campaign already lists, but that its Scope does not cover, opens a new campaign.

Filing the follow-up ends the run — that campaign is already scaffolded. File it
the way "Filing a subtask issue" below says, including the index steps; a
follow-up landing on a repository the anchor issue does not list is invisible to
every status query.

### 2. Name it and pick its kind

Agree three things with the person in one message, then wait for the answer:

- **Slug** — kebab-case, meaningful, no date; the date is appended in step 4.
- **Title** — the display name, in the person's own words, not yours.
- **Kind** — which `assets/agents/*.md` becomes the campaign's `AGENTS.md`.

| the campaign exists to | kind |
| --- | --- |
| answer an open question | `research` |
| measure or audit something that already runs | `analysis` |
| find out whether an approach can work at all | `prototyping` |
| move a working system from one form to another | `migration` |

Propose the kind you read from the request and let the person veto it. The kind
is a one-line correction for them and a wrong set of principles for every
delegate if you pick it silently.

### 3. File the anchor issue

Before scaffolding anything, because its number is the campaign ID.

```sh
gh issue create -R kalaluthien/agent-workspace \
  --label campaign --title "<title>" --body-file <path>
```

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
CONTAINER=$(git rev-parse --show-toplevel)
```

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

Stop if it already exists and ask the person. `cp -R` over a live campaign exits
0 and replaces a filled-in `README.md` with placeholders.

Then finish it:

- Move the chosen `agents/<kind>.md` to `AGENTS.md` and delete `agents/`.
- Fill every placeholder in `README.md` from the anchor issue body. The two carry
  the same five sections in the same shapes, so the close-time sync is an
  overwrite. The `README.md` is the working copy the campaign session edits; the
  campaign session is the only thing that writes either it or the issue body, and
  a delegate never touches the issue body at all.
- The directory is git-ignored by the container's allowlist. Nothing durable may
  live only there; if you write something that must survive, it belongs in a
  member repository or on a GitHub issue.

### 5. Acquire the member repositories

For each entry under `Repos:`, by absolute path — step 4 has just created an
empty `$CAMPAIGN/scripts/`, so a relative `scripts/acquire-repo` resolves there
and fails:

```sh
"$CONTAINER/scripts/acquire-repo" <owner/repo> "$CAMPAIGN/repos/<name>" \
  --branch c<N>/<topic>
```

Safe to re-run. Do not clone by hand and do not read the script to work out what
it does — its interface is the contract.

Then make the subtask label exist on each of them, as below.

### 6. Report

The campaign ID, the directory path, and the anchor issue URL. Then the first
subtask, and whether you are doing it here or handing it to a repository agent.

### Filing a subtask issue

Both the follow-up path in step 1 and every subtask after step 6 file the same
shape, and both keep the index intact. The index is the anchor's `Repos:` list
plus the label, so a subtask that skips either becomes unfindable with no error.

1. If the target repository is not in the anchor's `Repos:` list, add it to that
   list and to the campaign `README.md`, and acquire it as in step 5.
2. Make the label exist on that repository. `gh issue create --label` fails
   outright on a label the repository does not have, and `--force` makes this
   safe to re-run:

   ```sh
   gh label create campaign-<N> -R <owner/repo> --force \
     --description "Campaign kalaluthien/agent-workspace#<N>"
   ```

3. File the issue with the label and a body carrying the back-reference line
   `Campaign: kalaluthien/agent-workspace#<N>`:

   ```sh
   gh issue create -R <owner/repo> --label campaign-<N> \
     --title "<title>" --body-file <path>
   ```

## Example

A request that reads "the auth token refresh is broken across api and web",
opened as campaign #7:

```
auth-refactor-260828/
  AGENTS.md      copied from assets/agents/migration.md
  CLAUDE.md      @AGENTS.md
  README.md      the five sections, copied from issue #7's body
  runtime/ scripts/
  repos/api/     on branch c7/token-refresh
  repos/web/     on branch c7/token-refresh
```

## Gotchas

- A request that sounds new is usually a follow-up. Step 1 is the step this
  procedure exists for; skipping it produces a second campaign over the same
  scope, and nothing errors — you get two anchor issues that both look right.
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
- `git status` in the container root will never show the campaign directory.
  That is the allowlist working, not a missing file.
- Never run one git command across `repos/*`. Each is its own repository with
  its own remote.
