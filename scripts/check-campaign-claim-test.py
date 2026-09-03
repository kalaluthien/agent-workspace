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
                ("Bash", "grep -r x .", "a search is not a change"),
                ("Bash", 'gh issue create -R o/r --title t --body "run git mv a b"',
                 "a changing word inside quoted argument text is not a change"),
                ("Bash", "gh issue create -R o/r --body-file /tmp/b.md",
                 "filing an issue is not a change"),
                ("Bash", "gh issue create -R o/r --body 'the $(git mv a b) is prose'",
                 "a $( inside a single-quoted body is literal, not a change"),
                ("Bash", 'gh issue create -R o/r --body "$(cat <<\'EOF\'\nrun git mv a b\nEOF\n)"',
                 "a heredoc read into a body keeps only `cat`, not a change"),
                ("Bash", 'gh pr create --title "mv the file" --body-file x.md',
                 "a title is prose, not a change"),
                ("Bash", 'gh issue create -R o/r --title "R&D notes" --body "run git mv x y"',
                 "an & in an earlier title does not unblank a later body")):
            r = ask(root, tool=tool, command=command)
            check(f"{why}", r.returncode == 0,
                  f"exit {r.returncode}: {out(r)[:200]}")

    # The quoted-text carve-out must not swallow the command itself: the same
    # words unquoted are still a change.
    with tempfile.TemporaryDirectory() as d:
        root = container(d, {"demo-260902": {}})
        r = ask(root, tool="Bash", command="git mv a b")
        check("the same words outside quotes are still a change",
              r.returncode == 2, f"exit {r.returncode}: {out(r)[:200]}")
        r = ask(root, tool="Bash", command='echo "x" > out.txt')
        check("a redirect outside the quotes is still a change",
              r.returncode == 2, f"exit {r.returncode}: {out(r)[:200]}")
        # Quoted text that is not a prose sink stays visible, whatever runs it:
        # the sinks that execute text cannot be listed, so nothing else is hidden.
        for command, why in (
                ('gh issue create --body "$(git mv a b)"',
                 "a command substitution inside a double-quoted body is still a change"),
                ('gh issue create --body "`git mv a b`"',
                 "a backtick substitution inside a double-quoted body is still a change"),
                ('eval "git mv a b"', "an eval'd string is still a change"),
                ('bash -c "git mv a b"', "a -c string is still a change"),
                ("bash -lc 'git mv a b'", "a -c in a flag cluster, single-quoted, is still a change"),
                ('bash -cx "git mv a b"', "a -c anywhere in the cluster is still a change"),
                ('ssh host "git mv a b"', "a string handed to ssh is still a change"),
                ("printf '%s' 'git mv a b' | bash", "a string piped into a shell is still a change"),
                ("xargs -t 'git mv a b'", "a sink-like flag on a program other than gh blanks nothing")):
            r = ask(root, tool="Bash", command=command)
            check(why, r.returncode == 2, f"exit {r.returncode}: {out(r)[:200]}")

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

    # The close target is read from the filtered command too: prose in a body
    # must not name the issue a claim is checked against.
    with tempfile.TemporaryDirectory() as d:
        root = container(d, {"demo-260902": {"42": RECORD.replace("campaign-1/7-x", "campaign-1/42-y")}})
        r = ask(root, tool="Bash",
                command='gh issue comment 42 -R o/r --body "see gh issue close 5 today"')
        check("a close named inside a body is not the target the claim is checked against",
              r.returncode == 0, f"exit {r.returncode}: {out(r)[:300]}")

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

    # 12. What the call WRITES TO, which is a different question from where the
    # session sits. Every case here runs from the container root with no claim
    # anywhere -- the setting group 3 proved is a refusal -- so a case that
    # passes does so on the target reading and on nothing else.
    with tempfile.TemporaryDirectory() as d:
        root = container(d, {"demo-260902": {}})
        OUT = "/tmp/check-campaign-claim-fixture.html"

        r = ask(root, tool="Write", path=OUT)
        check("a Write to a path in no container and no campaign is allowed",
              r.returncode == 0, f"exit {r.returncode}: {out(r)[:300]}")
        check("...and the allow names the path it read and the branch taken",
              OUT in out(r) and "allowed, target outside" in out(r), out(r)[:300])

        r = ask(root, tool="Bash", command=f"echo hi > {OUT}")
        check("a shell redirect to a path outside every campaign is allowed",
              r.returncode == 0, f"exit {r.returncode}: {out(r)[:300]}")
        r = ask(root, tool="Bash", command="mkdir -p /tmp/check-campaign-claim-shot")
        check("a mkdir outside every campaign is allowed",
              r.returncode == 0, f"exit {r.returncode}: {out(r)[:300]}")
        check("...and the allow names the form and the operand it read",
              "`mkdir`" in out(r) and "/tmp/check-campaign-claim-shot" in out(r),
              out(r)[:400])
        r = ask(root, tool="Bash", command=f"sed -i 's/a/b/' {OUT}")
        check("a sed -i on a file outside every campaign is allowed",
              r.returncode == 0, f"exit {r.returncode}: {out(r)[:300]}")

        # The other side of the same branch: inside is still the claim's.
        r = ask(root, tool="Write", path=str(root / "demo-260902" / "notes.md"))
        check("a Write under a campaign directory is still refused",
              r.returncode == 2, f"exit {r.returncode}: {out(r)[:300]}")
        r = ask(root, tool="Write", path=str(root / "AGENTS.md"))
        check("a Write inside the container tree is still refused",
              r.returncode == 2, f"exit {r.returncode}: {out(r)[:300]}")

        # A SLASHLESS operand is an operand. The words that look like paths are
        # not the target: with one unrelated outside path in the command,
        # reading those allowed a copy over a container file.
        r = ask(root, tool="Bash", command="cp /tmp/x.md AGENTS.md")
        check("a slashless operand of a matched form denies the call",
              r.returncode == 2, f"exit {r.returncode}: {out(r)[:300]}")
        check("...naming the form and the operand that landed inside",
              "`cp` operand 'AGENTS.md'" in out(r), out(r)[:400])
        r = ask(root, tool="Bash", command="echo hi > /tmp/x ; rm -rf scripts")
        check("a second segment's operand inside denies the whole command",
              r.returncode == 2 and "`rm` operand 'scripts'" in out(r),
              f"exit {r.returncode}: {out(r)[:400]}")
        r = ask(root, tool="Bash", command=f"sed -i '' -e 's/a/b/' AGENTS.md")
        check("a sed -i script is not read as its file operand",
              r.returncode == 2 and "`sed -i` operand 'AGENTS.md'" in out(r),
              f"exit {r.returncode}: {out(r)[:400]}")

        # A git write's target is the repository. Every path in the command is
        # a log or a message file, so none of them may carry an allow -- this
        # is the class the guard exists for.
        for command in ("git push 2>/tmp/err.log", "git commit -m x 2>/tmp/e",
                        "git push origin HEAD | tee /tmp/push.log",
                        "git commit -F /tmp/msg.txt"):
            r = ask(root, tool="Bash", command=command)
            check(f"a git write is refused whatever path it carries: {command}",
                  r.returncode == 2, f"exit {r.returncode}: {out(r)[:300]}")
        check("...and says the target is the repository, not the path it read",
              "target is the repository" in out(r), out(r)[:400])

        # The campaign plane is GitHub issues and has no path at all.
        for command in ("gh issue comment 150 --body-file /tmp/b.md",
                        "gh issue close 150 --comment-file /tmp/c.md"):
            r = ask(root, tool="Bash", command=command)
            check(f"a gh write to the campaign plane is refused: {command}",
                  r.returncode == 2, f"exit {r.returncode}: {out(r)[:300]}")
        check("...and says the campaign plane has no filesystem target",
              "no filesystem target" in out(r), out(r)[:400])
        # With a readable form of its own in the command, only the service-door
        # short-circuit refuses this: the redirect it carries lands outside.
        r = ask(root, tool="Bash", command="gh issue close 150 -R o/r > /tmp/close.log")
        check("a gh campaign write is refused though its redirect lands outside",
              r.returncode == 2, f"exit {r.returncode}: {out(r)[:300]}")
        r = ask(root, tool="Bash",
                command="curl -X POST https://api.example.com/x -o /tmp/out.json")
        check("a writing HTTP request is refused whatever file it writes",
              r.returncode == 2, f"exit {r.returncode}: {out(r)[:300]}")
        r = ask(root, tool="Bash",
                command="curl -X POST https://api.example.com/x | tee /tmp/resp.json")
        check("...and is refused though the form it pipes into lands outside",
              r.returncode == 2, f"exit {r.returncode}: {out(r)[:300]}")
        check("...saying the target is a service, not the file it read",
              "target is a service" in out(r), out(r)[:400])

        # A form this cannot parse, and an operand it cannot resolve: two
        # different "I could not look", and neither is an allow.
        r = ask(root, tool="Bash", command="npm install lodash")
        check("a changing form whose target this cannot read is refused",
              r.returncode == 2, f"exit {r.returncode}: {out(r)[:300]}")
        check("...and says which segment it could not read, not that one was outside",
              "'npm install lodash' is a changing command on its own" in out(r),
              out(r)[:400])
        # A segment the guard cannot parse must answer for ITSELF. Appending a
        # redirect to somewhere harmless used to supply the allow for it, which
        # is finding 1's shape in the operand reading: a write the guard cannot
        # see answered for by one it can.
        for command in ("sh -c 'rm -rf scripts' > /tmp/log",
                        "npm install > /tmp/log",
                        "npm install | tee /tmp/log",
                        "npm install --prefix . 2>/tmp/e"):
            r = ask(root, tool="Bash", command=command)
            check(f"a redirect elsewhere does not answer for an unreadable "
                  f"changing segment: {command}",
                  r.returncode == 2, f"exit {r.returncode}: {out(r)[:300]}")
        check("...and names the segment it could not read",
              "is a changing command on its own" in out(r), out(r)[:400])
        # ...and the case it must NOT catch: `echo` is not changing on its own,
        # so there the redirect genuinely is the write.
        r = ask(root, tool="Bash", command=f"echo hi > {OUT} 2>&1")
        check("a redirect after a command that is not changing on its own allows",
              r.returncode == 0, f"exit {r.returncode}: {out(r)[:300]}")

        r = ask(root, tool="Bash", command="mkdir -p $SCRATCH/x")
        check("an operand this cannot expand is refused",
              r.returncode == 2, f"exit {r.returncode}: {out(r)[:300]}")
        check("...and says the operand is an expansion, not a path outside",
              "is an expansion or a glob" in out(r), out(r)[:400])

        # A claim still allows what the target reading sent to it, so the new
        # branch cannot be what makes group 6 pass.
        root2 = container(Path(d) / "held", {"demo-260902": {"7": RECORD}})
        r = ask(root2, tool="Write", path=str(root2 / "demo-260902" / "notes.md"))
        check("a held claim still allows a write inside its campaign",
              r.returncode == 0, f"exit {r.returncode}: {out(r)[:300]}")

    # 13. A SECOND checkout of the container is a container tree too, and it is
    # under neither this root nor any campaign directory. Only the target's own
    # container lookup refuses it; the root and campaign-directory tests here
    # both say "outside", so this is the one case that pins that clause.
    with tempfile.TemporaryDirectory() as d:
        root = container(d, {"demo-260902": {}})
        elsewhere = container(str(Path(d) / "second"), {})
        r = ask(root, tool="Write", path=str(elsewhere / "AGENTS.md"))
        check("a Write into another checkout of the container is refused",
              r.returncode == 2, f"exit {r.returncode}: {out(r)[:300]}")
        check("...naming the container the target is in, not the one cwd is in",
              str(elsewhere) in out(r), out(r)[:400])
        r = ask(root, tool="Bash", command=f"cp /tmp/x.md {elsewhere}/AGENTS.md")
        check("...and so is a shell copy into it", r.returncode == 2,
              f"exit {r.returncode}: {out(r)[:300]}")

    for f in fails:
        print(f"FAIL  {f}")
    print(f"{len(ran) - len(fails)}/{len(ran)} cases pass")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
