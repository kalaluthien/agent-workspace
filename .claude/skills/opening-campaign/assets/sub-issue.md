Campaign: kalaluthien/campaign-base#<N>
Repository: <owner/repo whose code changes, or none>
Branch: campaign-<N>/<issue>-<topic>

<What is wrong or missing now, and what says so. One paragraph, no preamble.>

<The work: what to change, and what constrains how — an ordering against another
sub-issue, a decision already made, a file that is off limits. Bullets or numbered
steps.>

Done when <the condition that settles this issue, readable off the closed issue —
the merged pull request, or for a repo-less sub-issue the closing comment — rather
than off a claim>.

## Working it

This body is the whole brief, so this section is here on every sub-issue. It
points rather than restates: the rules are in the base's `AGENTS.md`, which a
delegate reaches through the `--add-dir <base>` its launch passes, and a second
copy of them here would be the one that goes stale.

- **The branch above is already claimed on the remote.** Check it out and work
  on it. Push every commit the moment it exists — a checkout that dies costs
  uncommitted work and nothing more.
- **Land by pull request against `main`**, opened on the first commit, body
  closing this issue with `Closes kalaluthien/campaign-base#<issue>`. Merge
  `origin/main` in before merging; resolve on the branch, never force-push.
- **You may land your own work**, and the three conditions that gate it are
  `AGENTS.md` § Merge conditions. One of them is a review you did not write, so
  **commission it yourself**: an in-process subagent, always, with the model and
  the level named — `AGENTS.md` § Review, and
  `.claude/skills/opening-campaign/references/reviewing.md` for the call.
- **The four messages** are `AGENTS.md` § The four messages. `REPORT` once when
  the pull request is open, unsolicited, naming its URL and the sha it sits at,
  **and ask for the review there**: a push retires any review before it and
  nobody is named to notice. If you ask and nothing comes, say so and stop — a
  silent wait reads exactly like work.
- **A fix round** is `AGENTS.md` § The fix round: reproduce each finding at the
  site it names before touching anything, and close the round with one `REPORT`
  plus a comment at that sha carrying one row per finding.
- **You do not write the campaign issue's body.** It is written at a scope
  change and at the close, and a sub-issue is neither.
