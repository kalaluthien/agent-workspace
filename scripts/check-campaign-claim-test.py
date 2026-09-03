#!/usr/bin/env python3
"""Prove the claim guard refuses for the reason it prints, and allows for one too.

Every case runs the shipped script against a fixture container built here --
never the real one -- and hands it a hook payload on stdin. No case reaches the
network: the guard's PreToolUse half makes no request at all, and its PostToolUse
half is covered only up to the point where it would ask GitHub whether an issue
is closed, since a fixture that mocked `gh` would be testing the mock.

WHAT EACH GROUP PINS

Allowing is as load-bearing as refusing here. A guard installed machine-wide that
refused outside a campaign would stop every session on this machine, so the
"exits 0" cases are not filler: they are the ones whose failure is worst.

The refusals are broken apart one at a time, because they share an exit status
and a stream. A case that only asserted `exit 2` would pass while any single
branch was deleted, so each asserts the sentence that branch alone prints.

Usage: scripts/check-campaign-claim-test.py
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
GUARD = HERE / "check-campaign-claim.py"
CLAIM = HERE / "campaign-claim.py"

SESSION = "sid-1"
RECORD = f"session {SESSION}\nname exec-1\npid 1\nbranch campaign-1/7-x\nlocal yes\n"
RELEASED = RECORD + "released 2026-09-02T10:00:00+0900 by " + SESSION + "\n"
OTHER = "session sid-2\nname exec-2\npid 1\nbranch campaign-1/7-x\nlocal yes\n"


def container(d, campaigns):
    """A fixture container: the marker script the guard resolves a root by, and
    the campaign directories asked for. `campaigns` maps a directory name to a
    dict of claim records, or to None for a directory with no runtime/claims/."""
    root = Path(d) / "container"
    (root / "scripts").mkdir(parents=True)
    # A copy and not a symlink: the guard imports it by path, and the record's
    # shape must come from the shipped script rather than a stand-in.
    (root / "scripts" / "campaign-claim.py").write_text(CLAIM.read_text())
    for name, records in campaigns.items():
        camp = root / name
        camp.mkdir()
        if records is None:
            continue
        claims = camp / "runtime" / "claims"
        claims.mkdir(parents=True)
        for issue, body in records.items():
            (claims / issue).write_text(body)
    return root


def ask(cwd, tool="Edit", command=None, session=SESSION, post=False,
        event=None, path=None, stdin=None):
    payload = {
        "session_id": session,
        "cwd": str(cwd),
        "tool_name": tool,
        "tool_input": ({"command": command} if command is not None
                       else {"file_path": path or str(Path(cwd) / "a.txt")}),
        "hook_event_name": event or ("PostToolUse" if post else "PreToolUse"),
    }
    args = [sys.executable, str(GUARD)] + (["--released"] if post else [])
    return subprocess.run(args, input=stdin if stdin is not None
                          else json.dumps(payload),
                          capture_output=True, text=True)


def main():
    ran, fails = [], []

    def check(name, cond, detail=""):
        ran.append(name)
        if not cond:
            fails.append(f"{name}\n      {detail}")

    def out(r):
        return r.stdout + r.stderr

    # 1. Outside a container it must be invisible. This is the case that decides
    # whether a machine-wide registration is safe at all.
    with tempfile.TemporaryDirectory() as d:
        r = ask(d)
        check("no container above cwd exits 0 and says nothing",
              r.returncode == 0 and not out(r).strip(),
              f"exit {r.returncode}: {out(r)[:200]}")

    # 2. A container with no campaign on it is not a campaign session either.
    with tempfile.TemporaryDirectory() as d:
        root = container(d, {})
        r = ask(root)
        check("a container with no campaign directory exits 0",
              r.returncode == 0, f"exit {r.returncode}: {out(r)[:200]}")

    # 3. The refusal, and its four separable parts.
    with tempfile.TemporaryDirectory() as d:
        root = container(d, {"demo-260902": {}})
        r = ask(root)
        check("a changing call with no claim is refused",
              r.returncode == 2, f"exit {r.returncode}: {out(r)[:200]}")
        check("...and the refusal is on stderr, where the model reads it",
              "REFUSED" in r.stderr, out(r)[:200])
        # An empty claims/ is a READING. Asserted apart from the refusal: the
        # refusal happens either way, and only this sentence separates "nobody
        # claimed anything here" from "I could not look".
        check("...and an empty claims directory is reported as read, not missing",
              "is empty: no claim was taken here" in r.stderr, out(r)[:400])
        check("...and it names the session it looked for",
              SESSION in r.stderr, out(r)[:400])
        check("...and it names the directory it read",
              "demo-260902" in r.stderr, out(r)[:400])

    # 4. Not every call is a changing call, and the guard must not be a wall.
    with tempfile.TemporaryDirectory() as d:
        root = container(d, {"demo-260902": {}})
        for tool, command, why in (
                ("Read", None, "a read is not a change"),
                ("Bash", "git status", "a read-only shell command is not a change"),
                ("Bash", "grep -r x .", "a search is not a change")):
            r = ask(root, tool=tool, command=command)
            check(f"{why}", r.returncode == 0,
                  f"exit {r.returncode}: {out(r)[:200]}")

    # 5. The two exemptions, each on its own. They are the paths a refused
    # session has to be able to take to stop being refused.
    with tempfile.TemporaryDirectory() as d:
        root = container(d, {"demo-260902": {}})
        # Redirected on purpose. A bare `campaign-claim.py take` matches no
        # changing form and would pass with the exemption deleted, so a case
        # written that way pins nothing; the redirect is what makes the call
        # changing and the exemption the only thing letting it through.
        r = ask(root, tool="Bash",
                command=f"{root}/scripts/campaign-claim.py take --local 1 7 x "
                        f"> /tmp/claim.log")
        check("taking a claim cannot itself require one", r.returncode == 0,
              f"exit {r.returncode}: {out(r)[:200]}")
        r = ask(root, path=str(root / "demo-260902" / "runtime" / "claims" / "7"))
        check("a write under runtime/ is exempt", r.returncode == 0,
              f"exit {r.returncode}: {out(r)[:200]}")

    # 6. A held claim allows, and only for the session that holds it.
    with tempfile.TemporaryDirectory() as d:
        root = container(d, {"demo-260902": {"7": RECORD}})
        r = ask(root)
        check("a record naming this session allows the call", r.returncode == 0,
              f"exit {r.returncode}: {out(r)[:200]}")
        r = ask(root, session="sid-2")
        check("...and does not allow another session's",
              r.returncode == 2, f"exit {r.returncode}: {out(r)[:200]}")

    # A released record is attribution, not a claim. Its own case, because
    # treating it as one is the exact way a closed sub-issue's claim would keep
    # licensing writes.
    with tempfile.TemporaryDirectory() as d:
        root = container(d, {"demo-260902": {"7": RELEASED}})
        r = ask(root)
        check("a released record licenses nothing", r.returncode == 2,
              f"exit {r.returncode}: {out(r)[:200]}")
        check("...and the refusal says the record it found was released",
              "RELEASED" in r.stderr, out(r)[:400])

    # 7. The delegate's cwd, which is a different git repository. The whole
    # placement question is this case.
    with tempfile.TemporaryDirectory() as d:
        root = container(d, {"demo-260902": {"7": RECORD}})
        clone = root / "demo-260902" / "repos" / "dotclaude"
        clone.mkdir(parents=True)
        r = ask(clone, tool="Bash", command="git commit -m x")
        check("a delegate's clone resolves to its campaign and allows",
              r.returncode == 0, f"exit {r.returncode}: {out(r)[:200]}")
        r = ask(clone, tool="Bash", command="git commit -m x", session="sid-2")
        check("...and refuses a session with no claim from there",
              r.returncode == 2, f"exit {r.returncode}: {out(r)[:200]}")
        check("...naming the campaign its cwd is inside, not every one",
              "cwd is inside demo-260902" in r.stderr, out(r)[:400])

    # A linked worktree is itself a checkout of this repository and holds the
    # marker, so resolving to the NEAREST root would land on a tree with no
    # campaign under it and read as "not in a campaign" -- a silent pass.
    with tempfile.TemporaryDirectory() as d:
        root = container(d, {"demo-260902": {"7": RECORD}})
        tree = root / ".claude" / "worktrees" / "x"
        (tree / "scripts").mkdir(parents=True)
        (tree / "scripts" / "campaign-claim.py").write_text(CLAIM.read_text())
        r = ask(tree, session="sid-2")
        check("a linked worktree resolves to the container, not to itself",
              r.returncode == 2, f"exit {r.returncode}: {out(r)[:200]}")

    # 8. `gh issue close` is per-issue, not per-session. A claim on some other
    # sub-issue must not close this one.
    with tempfile.TemporaryDirectory() as d:
        root = container(d, {"demo-260902": {"7": RECORD}})
        r = ask(root, tool="Bash", command="gh issue close 7 -R a/b")
        check("closing an issue this session holds is allowed",
              r.returncode == 0, f"exit {r.returncode}: {out(r)[:200]}")
        r = ask(root, tool="Bash", command="gh issue close 9 -R a/b")
        check("closing an issue this session does not hold is refused",
              r.returncode == 2, f"exit {r.returncode}: {out(r)[:200]}")
        check("...and the refusal names the issue rather than the call",
              "closing #9" in r.stderr, out(r)[:400])

    # 9. A missing claims/ cannot be enumerated, and that is a refusal. It is
    # the branch whose wrong answer -- treating it as empty -- is silent.
    with tempfile.TemporaryDirectory() as d:
        root = container(d, {"demo-260902": None})
        r = ask(root)
        check("a campaign directory with no runtime/claims/ refuses",
              r.returncode == 2, f"exit {r.returncode}: {out(r)[:200]}")
        check("...and says a missing directory says nothing",
              "a missing one says nothing" in r.stderr, out(r)[:400])
        # And it refuses even when a claim IS held elsewhere: a directory that
        # could not be read may hold anything, so a pass from its neighbour is
        # not a pass for it.
        root2 = container(Path(d) / "two", {"demo-260902": None,
                                            "other-260901": {"7": RECORD}})
        r = ask(root2)
        check("...and one unreadable directory denies a claim found in another",
              r.returncode == 2, f"exit {r.returncode}: {out(r)[:200]}")

    # 10. The guard's own inputs. Each is "I could not look", and none may pass.
    with tempfile.TemporaryDirectory() as d:
        root = container(d, {"demo-260902": {}})
        r = ask(root, stdin="not json")
        check("a payload that will not read refuses", r.returncode == 2,
              f"exit {r.returncode}: {out(r)[:200]}")
        r = ask(root, session="")
        check("a payload with no session_id refuses", r.returncode == 2,
              f"exit {r.returncode}: {out(r)[:200]}")
        check("...and says a claim is attributed by session id",
              "no session_id" in r.stderr, out(r)[:300])
        # The registration and the flag disagreeing is silent in one direction:
        # a PostToolUse slot running the PRE half enforces nothing.
        r = ask(root, event="PostToolUse")
        check("the pre half invoked on the wrong event refuses",
              r.returncode == 2 and "Re-run" in r.stderr,
              f"exit {r.returncode}: {out(r)[:200]}")

    # 11. The PostToolUse half exits 0 whatever happens, because exit 2 there
    # prints and execution continues -- a verdict nobody enforces.
    with tempfile.TemporaryDirectory() as d:
        root = container(d, {"demo-260902": {"7": RECORD}})
        r = ask(root, tool="Bash", command="echo hi", post=True)
        check("the release half ignores a call that closed nothing",
              r.returncode == 0, f"exit {r.returncode}: {out(r)[:200]}")
        r = ask(Path(d), tool="Bash", command="gh issue close 7", post=True)
        check("the release half outside a campaign exits 0",
              r.returncode == 0, f"exit {r.returncode}: {out(r)[:200]}")
        r = ask(root, tool="Bash", command="gh issue close 7", post=True,
                event="PreToolUse")
        check("the release half on the wrong event says so and exits 0",
              r.returncode == 0 and "Re-run" in out(r),
              f"exit {r.returncode}: {out(r)[:200]}")

    for f in fails:
        print(f"FAIL  {f}")
    print(f"{len(ran) - len(fails)}/{len(ran)} cases pass")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
