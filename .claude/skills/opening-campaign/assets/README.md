# <TITLE — the campaign's display name, in the person's own words>

Campaign #<N> — [anchor issue](https://github.com/kalaluthien/agent-workspace/issues/<N>)

## Intent

<One sentence: what this campaign is for. Same sentence as the anchor issue.>

## Scope

In:

- <what this campaign covers>

Out:

- <what it deliberately does not cover, and where that work goes instead>

## Requirements

- <a condition the finished work must satisfy, checkable rather than admirable>

## Plan

- [ ] <subtask> — <owner/repo>
- [ ] <subtask> — <owner/repo>

This file and the anchor issue body carry the same five sections, so syncing
one to the other is an overwrite. The issue is the copy that counts.

## Repos

- <owner/repo>
- <owner/repo>

Each is checked out under `repos/`, on branch `c<N>/<topic>`. Subtasks live on
each repository as issues labelled `campaign-<N>`:

```sh
gh issue list -R <owner/repo> --label campaign-<N>
```
