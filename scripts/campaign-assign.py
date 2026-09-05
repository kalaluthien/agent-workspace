#!/usr/bin/env python3
"""Assign a sub-issue to a session by prompting its pane, the only way to.

    campaign-assign.py <pane> <sub-issue> [--repo owner/repo] [--force]

THE CHANNEL RULE, AND WHY IT NEEDS A SCRIPT

AGENTS.md § The four messages states it: an instruction to a session is a
prompt into its pane; information between sessions is one of the four messages.
A prompt is the session's own user turn, so its hooks run and no relay caveat
applies; a message is a peer's word, which AGENTS.md says is never the
authority -- which is exactly why an instruction must not travel as one.

Stated in prose alone it had already drifted: the rule appeared in two sections
with no criterion between them, and a later assignment to a reused executor,
the answer to a BLOCKED, and a slash command fell between them and were sent
whichever way the sender guessed. This is that rule with a machine behind it.

WHAT IT REFUSES, AND WHY EACH IS A REFUSAL AND NOT A WARNING

  not listed        no herdr row names this pane, so there is nothing to prompt
                    and the pane string is probably stale.
  not idle          a pane mid-turn queues the prompt behind work whose outcome
                    nobody has read, and the assignment lands on a session that
                    may be about to report something that changes it.
  window filled     no release line, in a read that filled the window, so the
                    release may sit above it. An absence beyond the window is
                    not an absence: --lines raises the window, --force skips it.
  not compacted     the pane released a sub-issue and has not compacted since,
                    so the next sub-issue would re-read the last one's whole
                    transcript on every turn. `campaign-claim.py release`
                    enqueues that compaction; this is the reader that says
                    whether it happened. --force is the way past, and it prints
                    what it is overriding.

  A PANE THAT NEVER RELEASED IS NOT REFUSED. A fresh session's context is
  already small, and refusing it would make the first assignment on a machine
  impossible -- which is `orchestrationInit`'s `Compacted = Session` in
  spec/campaign/orchestration/system.als, the same rule read at the other end.

WHAT IT CANNOT DO IS SAID, NEVER SKIPPED

Every reading here can come back absent for a reason that is not an answer: the
listing may not run, the pane's scrollback may not be readable, the marker text
may have scrolled out of the window this reads. Each prints what was read, from
where, and which branch was taken, and none of them silently assigns.

PROBED ON THIS MACHINE 2026-09-05

  * `herdr agent prompt <pane> "/compact"` runs the command; it is not typed as
    text. The pane showed `Compacting conversation... (41s)`.
  * A compacted pane's scrollback holds `Compacted (ctrl+o to see full
    summary)`, which is MARKER below.
  * `herdr agent read <pane> --lines N` refuses a pane that is working
    (`agent_not_idle`: "its alternate-screen history can only be captured by
    scrolling while idle"), so the idle check is not merely polite -- the
    scrollback cannot be read without it. `--source visible` reads a working
    pane but only the visible screen, which is too little for this.
  * A session that compacted came back idle holding no plan it had named
    before compacting. That is why an assignment is a fresh prompt carrying the
    sub-issue number, and why nothing here relies on the session remembering.
"""
import argparse
import importlib.util
import os
import subprocess
import sys

DEFAULT_REPO = "kalaluthien/campaign-base"

# What a compacted pane says, read off a live pane 2026-09-05. Held here as one
# string because it is the harness's wording and will change with it; when it
# does, this line is the whole edit and `read_pane`'s could-not-look branch is
# what a reader hits in the meantime.
MARKER = "Compacted (ctrl+o to see full summary)"

# THE ANCHOR IS THE RELEASE, NOT THE COMPACTION'S SUCCESS, and it is
# `campaign_claim.RELEASED` -- taken from the script that prints it, never
# copied. Keyed on the compaction's own success line, which is how this shipped
# at 114e71a, a release that could NOT compact printed no such line, read as a
# pane that never released, and was assigned: the single case this guard exists
# for. Found by review and reproduced end to end before this was written.
#
# The marker alone cannot answer the question either: a pane that compacted,
# then worked and released again holds an older marker that says nothing about
# now. Hence the ordering in `compaction_verdict`.

# How much scrollback to ask for. A release turn and the compaction after it
# are a few dozen lines; this is wide enough for several and small enough that
# an unreadable pane fails fast.
#
# WHAT HAPPENS AT THE EDGE, because a window is an absence that looks like an
# answer. A pane whose history is longer than this returns exactly LINES lines
# and the release may sit above them -- so "no release line in what I read" is
# `truncated`, not `fresh`, and refuses. Only a read that came back SHORTER
# than the window is evidence the whole history was seen. Both directions now
# fail closed; before this the open one was exactly the case a long transcript
# produces, which is the whole premise of this change.
LINES = 400


def claim_module():
    """campaign-claim.py, imported for its reader of herdr's listing.

    `parse_agents` is that script's, and a second copy here would drift from
    it -- AGENTS.md, "Do not write a second reader of a rule a script owns".
    The listing's shape is one such rule: which key holds the session id, and
    that a row herdr cannot identify is counted rather than dropped."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "campaign-claim.py")
    spec = importlib.util.spec_from_file_location("campaign_claim", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run(*args, **kw):
    """A command that is not installed is a failed run, not a traceback."""
    try:
        return subprocess.run(args, capture_output=True, text=True, **kw)
    except (FileNotFoundError, PermissionError) as e:
        return subprocess.CompletedProcess(
            args, 127, "", f"{args[0]}: {e.__class__.__name__}: {e}")


def row_for(sessions, pane):
    """(row, note) -- the herdr row whose `pane_id` is this pane. Pure.

    Keyed by pane rather than by session id because the caller names a pane:
    a planner reads `herdr agent list` and types what it saw there, and the
    session id is not in that reading."""
    matches = [(sid, row) for sid, row in sorted(sessions.items())
               if row["pane"] == pane]
    if not matches:
        panes = ", ".join(sorted(r["pane"] for r in sessions.values())) or "none"
        return None, (f"no herdr row names pane {pane}. Listed: {panes}")
    if len(matches) > 1:
        return None, (f"{len(matches)} herdr rows name pane {pane}; nothing "
                      f"here can tell which session is in it")
    sid, row = matches[0]
    return row, f"pane {pane} is {row['name']} ({sid}), status {row['status']}"


def idle_verdict(row):
    """(ok, why). Pure. `idle` and `done` are both a finished turn; every other
    word herdr prints is a turn in flight, and an unknown word is treated as
    one, because a status this does not recognise is not evidence of rest."""
    if row["status"] in ("idle", "done"):
        return True, None
    return False, (f"status is {row['status']}, not idle. A prompt to a pane "
                   f"mid-turn queues behind work nobody has read the outcome "
                   f"of.")


def compaction_verdict(text, anchor, limit=LINES):
    """Has this pane compacted since its last release? Pure, over the pane's
    scrollback. Returns (verdict, why) with verdict one of:

      `fresh`       no release line, in a read SHORTER than the window, so
                    the whole history was seen and this pane has not released.
                    Assignable.
      `compacted`   the marker appears after the last release line.
      `stale`       a release line with no marker after it.
      `truncated`   no release line, in a read that FILLED the window, so the
                    release may sit above it. An absence beyond the window is
                    not an absence, so this refuses exactly like `stale`.

    ORDER, NOT PRESENCE, is the whole reading: a pane that compacted, worked,
    and released again holds a marker that is older than its release and says
    nothing about now. Both are searched by last occurrence for that reason."""
    lines = (text or "").splitlines()
    last_release = max((i for i, ln in enumerate(lines)
                        if anchor in ln), default=None)
    if last_release is None and len(lines) >= limit:
        return "truncated", (f"no release line in the {len(lines)} line(s) "
                             f"read, and that filled the window, so the "
                             f"release may be above it. An absence beyond the "
                             f"window is not an absence.")
    if last_release is None:
        return "fresh", (f"nothing in the {len(lines)} line(s) read says this "
                         f"pane released a claim, and the read was shorter "
                         f"than the {limit}-line window, so that is the whole "
                         f"history")
    after = [i for i, ln in enumerate(lines) if MARKER in ln and i > last_release]
    if after:
        return "compacted", (f"released at line {last_release + 1}, compacted "
                             f"at line {after[-1] + 1}")
    return "stale", (f"released at line {last_release + 1} and no {MARKER!r} "
                     f"after it in the {len(lines)} line(s) read")


def read_pane(pane, limit=LINES):
    """(text, why_unread). The scrollback, or the reason there is none.

    Not guarded by HERDR_ENV: that guard is against ACTING on somebody else's
    session, never against reading -- the same reading `campaign-claim.py`
    makes of `agent list`."""
    r = run("herdr", "agent", "read", pane, "--lines", str(limit))
    if r.returncode != 0:
        return None, (f"`herdr agent read {pane} --lines {limit}` exited "
                      f"{r.returncode}: {r.stderr.strip()[:200] or r.stdout.strip()[:200]}")
    return r.stdout, None


def prompt_for(repo, issue):
    """The one sentence. THE BRIEF IS THE SUB-ISSUE (AGENTS.md § Delegate
    launch), so this names it and says nothing else: anything restated here is
    a second copy of the body that goes stale the moment the body is edited."""
    return (f"Work sub-issue {repo}#{issue} now: its body is the whole brief, "
            f"including how to claim, land and report it.")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("pane")
    ap.add_argument("issue")
    ap.add_argument("--repo", default=DEFAULT_REPO)
    ap.add_argument("--lines", type=int, default=LINES,
                    help=f"how much scrollback to read (default {LINES}); "
                         f"raise it when a release sits above the window")
    ap.add_argument("--force", action="store_true",
                    help="assign a pane that has not compacted since its "
                         "last release, saying so")
    args = ap.parse_args()
    issue = args.issue.lstrip("#")

    m = claim_module()
    sessions, why = m.herdr_sessions()
    if sessions is None:
        print(f"refusing: {why}\n  A listing that did not happen is not a pane "
              f"that is not there.", file=sys.stderr)
        return 1
    print(f"read {len(sessions)} session(s) from herdr agent list")

    row, note = row_for(sessions, args.pane)
    if row is None:
        print(f"refusing: {note}", file=sys.stderr)
        return 1
    print(note)

    ok, why = idle_verdict(row)
    if not ok:
        print(f"refusing: {why}", file=sys.stderr)
        return 1

    screen, why_unread = read_pane(args.pane, args.lines)
    if screen is None:
        # I COULD NOT LOOK, which is neither a yes nor a no. It refuses rather
        # than assigning, and `--force` is the way past -- the same door the
        # stale verdict has, because a caller overriding one has the same
        # standing to override the other.
        if not args.force:
            print(f"refusing: {why_unread}\n  Whether {args.pane} compacted "
                  f"since its last release is unknown, and an unknown is not"
                  f"\n  a compaction. Pass --force to assign anyway.",
                  file=sys.stderr)
            return 1
        print(f"--force: {why_unread}; assigning without reading the pane")
        verdict, why = "unread", why_unread
    else:
        verdict, why = compaction_verdict(screen, m.RELEASED, args.lines)
        print(f"{verdict}: {why}")
    if verdict in ("stale", "truncated") and not args.force:
        headline = ("has not compacted since its last release"
                    if verdict == "stale"
                    else "may have released above the window this read")
        print(f"refusing: {args.pane} {headline}.\n  {why}\n"
              f"  Every turn of {args.repo}#{issue} would "
              f"re-read the sub-issue before it. `campaign-claim.py release`"
              f"\n  sends that compaction; if it could not, prompt the pane "
              f"with /compact and retry; if the\n  release is further back "
              f"than the window, raise --lines; otherwise pass --force.",
              file=sys.stderr)
        return 1
    if verdict in ("stale", "truncated"):
        print(f"--force: assigning a pane that has not compacted since its "
              f"last release -- {why}")

    sentence = prompt_for(args.repo, issue)
    # The one call here that DRIVES a pane, so it carries the guard and names
    # its target explicitly -- which is the pane the caller typed, never one
    # this resolved for itself.
    r = run("herdr", "agent", "prompt", args.pane, sentence,
            env=dict(os.environ, HERDR_ENV="1"))
    if r.returncode != 0:
        print(f"refusing: `herdr agent prompt` exited {r.returncode}: "
              f"{r.stderr.strip()[:200]}\n  The sub-issue is not assigned.",
              file=sys.stderr)
        return 1
    print(f"assigned {args.repo}#{issue} to {args.pane}: {sentence}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
