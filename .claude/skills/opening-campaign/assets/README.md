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

The anchor issue's checklist is the copy that counts. This one is a local
reading aid and may lag.

## Repos

| repository | branch | what changes here |
| --- | --- | --- |
| <owner/repo> | c<N>/<topic> | <one line> |

Subtasks live on each repository as issues labelled `campaign-<N>`:

```sh
gh issue list -R <owner/repo> --label campaign-<N>
```
