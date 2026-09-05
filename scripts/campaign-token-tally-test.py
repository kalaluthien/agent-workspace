#!/usr/bin/env python3
"""Prove the tally counts each API message once and attributes it by place, not by prose.

Every case runs against a synthetic transcript tree written into a temporary
directory: no case reads this machine's real `~/.claude/projects`, and none
reaches the network -- the pull-request map is handed in as a file and `gh` is
never called.

The cases are one per branch of the method, because a tally is the shape of
program that returns a plausible number however wrong it is. Deleting the
folding branch, the off-base filter, the timestamp filter, the worktree rule,
the branch rule, the brief rule or the parent rule each makes exactly one named
case fail.

Usage: scripts/campaign-token-tally-test.py
"""
import json
import subprocess
import sys
import os
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "campaign-token-tally.py"
RAN, FAILED = [], []


def check(name, ok, detail=""):
    RAN.append(name)
    if not ok:
        FAILED.append(f"{name}{('  -- ' + detail) if detail else ''}")


def usage(out, new=100, read=50, settled=True):
    u = {"input_tokens": new, "cache_creation_input_tokens": 0,
         "cache_read_input_tokens": read, "output_tokens": out}
    if settled:
        u["iterations"] = [{"output_tokens": out}]
    return u


def assistant(mid, ts, cwd, branch="main", session="s1", out=100, blocks=None,
              new=100, read=50, settled=True, model="claude-opus-5", agent=None):
    return {"type": "assistant", "timestamp": ts, "cwd": cwd, "gitBranch": branch,
            "sessionId": session, "uuid": mid + "-" + str(out), "agentId": agent,
            "isSidechain": bool(agent),
            "message": {"id": mid, "role": "assistant", "model": model,
                        "content": blocks or [{"type": "text", "text": "x"}],
                        "usage": usage(out, new, read, settled)}}


def user(ts, cwd, text, session="s1", branch="main", agent=None):
    return {"type": "user", "timestamp": ts, "cwd": cwd, "gitBranch": branch,
            "sessionId": session, "uuid": "u" + ts, "agentId": agent,
            "isSidechain": bool(agent),
            "message": {"role": "user", "content": [{"type": "text", "text": text}]}}


def write(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as fh:
        for record in records:
            fh.write(json.dumps(record) + "\n")


def run(root, base, command, pr_map, extra=()):
    out = subprocess.run(
        [sys.executable, str(SCRIPT), command, "--root", str(root),
         "--base", str(base), "--pr-map", str(pr_map),
         "--since", "2026-01-02T00:00:00Z", "--until", "2026-01-03T00:00:00Z",
         *extra],
        capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(f"{command} failed: {out.stderr}")
    return out.stdout


def row(text, first):
    """The row whose first column is `first`, as a list of cells."""
    for line in text.splitlines():
        cells = line.split()
        if cells and cells[0] == first:
            return cells
    return None


def build(tmp):
    """One synthetic corpus, holding one shape per branch of the method."""
    base = tmp / "campaign-base"
    (base / "camp-260101" / "worktrees" / "300").mkdir(parents=True)
    root = tmp / "projects"
    day = "2026-01-02T"

    # A worktree turn, and the message written as three records: two placeholder
    # records and the settled one, all repeating the same input and cache.
    wt = str(base / "camp-260101" / "worktrees" / "300")
    folded = [
        assistant("m-fold", day + "01:00:00Z", wt, out=2, settled=False,
                  blocks=[{"type": "thinking", "thinking": "t"}]),
        assistant("m-fold", day + "01:00:01Z", wt, out=2, settled=False,
                  blocks=[{"type": "text", "text": "y"}]),
        assistant("m-fold", day + "01:00:02Z", wt, out=500, settled=True,
                  blocks=[{"type": "tool_use", "name": "Bash", "id": "t1",
                           "input": {"command": "scripts/campaign-tracker.py index 1"}}]),
    ]
    # A worktree whose directory was deleted when its sub-issue closed.
    dead = str(base / "camp-260101" / "worktrees" / "302")
    # A turn on a claim branch at the base root, and one that is only prose.
    prose = ("the branch is campaign-1/306-topic and issue 305 and "
             "kalaluthien/campaign-base#305 -- none of this is a place")
    write(root / "proj" / "s1.jsonl", [
        {"type": "agent-name", "sessionId": "s1", "agentName": "campaign-1-executor-9"},
        *folded,
        {"type": "user", "timestamp": day + "01:00:03Z", "cwd": wt,
         "gitBranch": "main", "sessionId": "s1", "uuid": "r1",
         "message": {"role": "user", "content": [
             {"type": "tool_result", "tool_use_id": "t1",
              "content": [{"type": "text", "text": "R" * 400}]}]}},
        assistant("m-branch", day + "02:00:00Z", str(base),
                  branch="campaign-1/301-topic", out=70),
        assistant("m-dead", day + "02:10:00Z", dead, out=60),
        assistant("m-prose", day + "02:20:00Z", str(base), out=40,
                  blocks=[{"type": "text", "text": prose}]),
        # Outside the window by its own timestamp, in a file written just now.
        assistant("m-old", "2026-01-01T00:00:00Z", wt, out=999),
        # Outside every base root: a workspace this campaign does not own.
        assistant("m-elsewhere", day + "02:30:00Z", str(tmp / "elsewhere"), out=888),
    ])
    # A subagent named by its own brief, and one that has none.
    write(root / "proj" / "s1" / "subagents" / "agent-a1.jsonl", [
        # Launched from the worktree of *another* sub-issue, which is what a
        # review of one pull request started from a session working a second
        # one records on every record it writes.
        user(day + "03:00:00Z", wt, "/code-review high 400\n\nreview it",
             session="s1", agent="a1"),
        assistant("m-review", day + "03:01:00Z", wt, out=30, session="s1",
                  model="claude-fable-5-1", agent="a1"),
    ])
    write(root / "proj" / "s1" / "subagents" / "agent-a2.jsonl", [
        user(day + "02:05:00Z", str(base), "find every reader of the guard",
             session="s1", agent="a2"),
        assistant("m-child", day + "02:06:00Z", str(base), out=20, session="s1",
                  agent="a2"),
    ])
    pr_map = tmp / "prs.json"
    pr_map.write_text(json.dumps([{"number": 400, "headRefName": "campaign-1/303-x"}]))
    return root, base, pr_map


def main():
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d).resolve()   # the transcript records a real path, so must we
        root, base, pr_map = build(tmp)
        issues = run(root, base, "issues", pr_map)
        sessions = run(root, base, "sessions", pr_map)
        reviews = run(root, base, "reviews", pr_map)
        echo = run(root, base, "tool-echo", pr_map)

        # ONE MESSAGE IS ONE TURN. Three records, one turn, and the settled
        # record's output -- not the placeholder's 2, and not the sum of three
        # input counts.
        r300 = row(issues, "300")
        check("a message written as three records is one turn",
              r300 and r300[1] == "1", str(r300))
        check("...its output is the settled record's, not the placeholder's",
              r300 and r300[3] == "500", str(r300))
        check("...and its input is counted once, not once per record",
              r300 and r300[5] == "100" and r300[6] == "50", str(r300))

        # PLACE, IN ORDER. Worktree, then branch, then the brief of a subagent.
        check("a cwd under worktrees/<issue> names the issue", r300 is not None)
        r301 = row(issues, "301")
        check("a campaign branch names the issue when the cwd does not",
              r301 and r301[3] == "90", str(r301))
        r303 = row(issues, "303")
        check("a review subagent is attributed by the pull request in its brief",
              r303 and r303[3] == "30", str(r303))
        check("...even though it ran in another sub-issue's worktree",
              r300 and r300[1] == "1", str(r300))
        check("...and counts as a subagent turn, apart from its parent",
              r303 and r303[2] == "1", str(r303))

        # A DELETED WORKTREE IS STILL THIS CAMPAIGN'S WORK. The filter is
        # containment in the base root, never whether the path still resolves.
        r302 = row(issues, "302")
        check("a worktree that no longer exists still attributes its turns",
              r302 and r302[3] == "60", str(r302))

        # WHAT IS NOT READ. A bare number, an issue reference and a branch name
        # in prose all leave the turn unattributed.
        unattr = row(issues, "unattributed")
        check("prose naming a branch or an issue attributes nothing",
              unattr and "40" in unattr, str(unattr))
        check("...and issue 305 and 306 have no row at all",
              row(issues, "305") is None and row(issues, "306") is None)

        # THE WINDOW IS THE MESSAGE'S OWN TIMESTAMP. The file was written now;
        # the turn inside it is from yesterday.
        check("a turn older than the window is dropped though its file is new",
              "999" not in issues and "1 outside the window" in issues, issues[:400])
        check("a cwd outside every base root is dropped and counted",
              "888" not in issues and "1 with a cwd outside" in issues, issues[:400])

        # THE FLOOR IS NAMED. Two of the three folded records were unsettled,
        # but the message settled, so nothing here is a floor.
        check("a corpus whose messages all settled says so by saying nothing",
              "unsettled turns" not in issues, issues[:400])

        # A SUBAGENT WITH NO BRIEF FALLS BACK TO ITS PARENT'S ISSUE.
        check("a subagent with no issue in its brief takes its parent's",
              r301 and r301[2] == "1", str(r301))

        # SESSIONS NAME THE SUBAGENT BY ITS PARENT, which is the only place the
        # name is written.
        check("a subagent's row names the session that started it",
              "(subagent of campaign-1-executor-9)" in sessions, sessions)

        # REVIEWS READ THE LEVEL AND THE PULL REQUEST FROM THE BRIEF.
        check("a review round is one row, with its pull request and level",
              row(reviews, "400") and row(reviews, "400")[1] == "high",
              reviews)

        # TOOL-ECHO PAIRS A SCRIPT CALL WITH THE BYTES ITS RESULT CARRIED.
        tracker = row(echo, "campaign-tracker")
        check("a call to one of this repository's scripts is counted with its result",
              tracker and tracker[1] == "1" and int(tracker[2]) >= 400, str(tracker))

    for name in FAILED:
        print(f"FAIL  {name}")
    print(f"{len(RAN) - len(FAILED)}/{len(RAN)} cases pass")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
