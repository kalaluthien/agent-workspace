#!/usr/bin/env python3
"""Prove the claim guard refuses for the reason it prints, and allows for one too.

Every case runs the shipped script against a fixture built here -- never the
real base -- and hands it a hook payload on stdin. The fixture is a real
repository with a real remote (a local bare one), because after #176 a claim
is a branch whose ref exists on the remote and the guard reads refs and
checkouts and nothing else. No case reaches the network.

WHAT EACH GROUP PINS

Allowing is as load-bearing as refusing. A guard installed machine-wide that
refused outside a campaign would stop every session on this machine, so the
"exits 0" cases are not filler: they are the ones whose failure is worst. And
an allow that prints WHY -- which clause admitted it, or that the command was
not read and the commit gate covers it -- is the whole of F1's closing, so the
sentence is asserted and not only the status.

The refusals are broken apart one at a time, because they share an exit status
and a stream. A case that only asserted `exit 2` would pass while any single
branch was deleted, so each asserts the sentence that branch alone prints.

#180's reproduction rows are the cases under "where the session sits", each
named for its row.

Usage: scripts/check-campaign-claim-test.py
"""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
GUARD = HERE / "check-campaign-claim.py"
CLAIM = HERE / "campaign-claim.py"


def git(cwd, *args):
    return subprocess.run(["git", "-C", str(cwd), "-c", "user.email=t@t",
                           "-c", "user.name=t", *args],
                          capture_output=True, text=True)


class Fixture:
    """A base with a remote, one campaign directory, and the checkouts asked
    for. `claims` are branches cut and pushed, each in a worktree at a SIBLING
    path (outside the base root, which is #180's shape); `unpushed` are
    campaign branches in worktrees whose ref exists nowhere on the remote;
    `feature` is a worktree on a plain branch."""

    def __init__(self, d, claims=("campaign-1/7-x",), unpushed=(), feature=None):
        self.d = Path(d)
        self.remote = self.d / "r.git"
        self.base = self.d / "base"
        # `main` pinned by hand: the cases assert the branch by name, and a
        # runner's init.defaultBranch is whatever its git ships (`master` on
        # the CI image).
        subprocess.run(["git", "init", "-q", "--bare", "--initial-branch=main",
                        str(self.remote)], check=True)
        subprocess.run(["git", "clone", "-q", str(self.remote), str(self.base)],
                       capture_output=True, check=True)
        git(self.base, "symbolic-ref", "HEAD", "refs/heads/main")
        (self.base / "scripts").mkdir()
        (self.base / "scripts" / "campaign-claim.py").write_text(CLAIM.read_text())
        self.camp = self.base / "demo-260904"
        self.camp.mkdir()
        # The allowlist shape check-tree-shape requires, which also ignores
        # the campaign directory: the commit gate's suite commits through the
        # installed hooks over this same fixture.
        (self.base / ".gitignore").write_text(
            "/*\n!/.gitignore\n!/scripts/\n!/spec/\n!/docs/\n")
        git(self.base, "add", "-A")
        git(self.base, "commit", "-qm", "init")
        git(self.base, "push", "-q", "origin", "HEAD")
        self.trees = {}
        for i, b in enumerate(claims):
            git(self.base, "branch", b)
            git(self.base, "push", "-q", "origin", b)
            self.trees[b] = self.worktree(f"wt-c{i}", b)
        for i, b in enumerate(unpushed):
            git(self.base, "branch", b)
            self.trees[b] = self.worktree(f"wt-u{i}", b)
        if feature:
            git(self.base, "branch", feature)
            self.trees[feature] = self.worktree("wt-f", feature)

    def worktree(self, name, branch, under=None):
        path = (under or self.d) / name
        r = git(self.base, "worktree", "add", "-q", str(path), branch)
        assert r.returncode == 0, r.stderr
        return path.resolve()

    def clone(self, branch=None):
        """A delegate's clone under the campaign directory."""
        dest = self.camp / "repos" / "campaign-base"
        dest.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "clone", "-q", str(self.remote), str(dest)],
                       capture_output=True, check=True)
        if branch:
            git(dest, "switch", "-q", "--track", f"origin/{branch}")
        return dest.resolve()


def ask(cwd, tool="Edit", command=None, path=None, event=None, stdin=None,
        tool_input=None):
    payload = {
        "session_id": "sid-1",
        "cwd": str(cwd),
        "tool_name": tool,
        "tool_input": tool_input if tool_input is not None else (
            {"command": command} if command is not None
            else {"file_path": path or str(Path(cwd) / "a.txt")}),
        "hook_event_name": event or "PreToolUse",
    }
    return subprocess.run([sys.executable, str(GUARD)],
                          input=stdin if stdin is not None else json.dumps(payload),
                          capture_output=True, text=True)


UNREAD = "was not read for a target"
GATE = "pre-commit claim gate"


def main():
    ran, fails = [], []

    def check(name, cond, detail=""):
        ran.append(name)
        if not cond:
            fails.append(f"{name}\n      {detail}")

    def out(r):
        return r.stdout + r.stderr

    # 1. Outside every base and campaign directory. The case that decides
    # whether a machine-wide registration is safe at all.
    with tempfile.TemporaryDirectory() as d:
        r = ask(d, path=str(Path(d) / "x.md"))
        check("a Write to a path in no base and no campaign is allowed",
              r.returncode == 0 and "not campaign work" in r.stdout, out(r)[:200])
        check("...and the allow names the path and says it looked",
              str(Path(d).resolve() / "x.md") in r.stdout
              and "no base tree and no campaign directory" in r.stdout, out(r)[:300])
        r = ask(d, tool="Bash", command="gh issue close 9")
        check("a gh write from a cwd in no repository and no base is allowed "
              "as not in a campaign",
              r.returncode == 0 and "in no campaign" in r.stdout, out(r)[:200])
        r = ask(d, tool="Bash", command="rm -rf x")
        check("a shell command outside is allowed unread",
              r.returncode == 0 and UNREAD in r.stdout, out(r)[:200])
        # A REPOSITORY IS NOT A BASE, and this guard is registered for every
        # session on the machine: gating the gh half on "has a repository root"
        # walled every campaign-plane write in every unrelated checkout. The
        # case above cannot catch it -- its cwd has no repository at all.
        plain = Path(d) / "plain"
        plain.mkdir()
        subprocess.run(["git", "init", "-q", "-b", "main", str(plain)], check=True)
        for cmd in ("gh issue close 9", "gh pr merge 9 --merge",
                    "gh pr comment 9 --body x"):
            r = ask(plain, tool="Bash", command=cmd)
            check(f"`{cmd}` from an ordinary git repository that is no base is "
                  f"allowed, naming why",
                  r.returncode == 0 and "in no campaign" in r.stdout
                  and "not a base" in r.stdout, out(r)[:300])

    # 2. The two clauses, and the refusal when neither holds.
    with tempfile.TemporaryDirectory() as d:
        f = Fixture(d, feature="feature")
        wt7 = f.trees["campaign-1/7-x"]
        r = ask(d, path=str(wt7 / "a.md"))
        check("clause 1: a write into a checkout on a claimed branch is allowed "
              "from any cwd",
              r.returncode == 0 and "Clause 1" in r.stdout
              and "campaign-1/7-x, a claim" in r.stdout, out(r)[:300])
        check("...and says the ref was read from the local origin/ copy",
              "refs/remotes/origin/campaign-1/7-x" in r.stdout, out(r)[:300])
        r = ask(f.trees["feature"], path=str(f.base / "AGENTS.md"))
        check("clause 2: a write into the main checkout on main is allowed when "
              "the session's root has a worktree on a claim",
              r.returncode == 0 and "Clause 2" in r.stdout
              and str(wt7) in r.stdout, out(r)[:400])
        check("...and it says clause 1 did not hold and why",
              "Clause 1 does not hold" in r.stdout and "on main, not a campaign "
              "branch" in r.stdout, out(r)[:400])
        check("...and calls itself the weaker gate, naming the commit gate",
              "weaker gate" in r.stdout and "commit gate is what holds" in r.stdout,
              out(r)[:400])
        r = ask(f.base, path=str(f.camp / "notes.md"))
        check("a write under the campaign directory is campaign work, named as such",
              r.returncode == 0 and "inside the campaign directory" in r.stdout,
              out(r)[:300])
        r = ask(f.base, tool="Bash", command="perl -pi -e s/a/b/ AGENTS.md")
        check("a shell write inside is allowed unread, saying the commit gate "
              "covers it",
              r.returncode == 0 and UNREAD in r.stdout and GATE in r.stdout,
              out(r)[:300])

    with tempfile.TemporaryDirectory() as d:
        f = Fixture(d, claims=(), feature="feature")
        r = ask(f.base, path=str(f.base / "AGENTS.md"))
        check("a write into the base with no claim anywhere is refused",
              r.returncode == 2, f"exit {r.returncode}: {out(r)[:300]}")
        check("...on stderr, where the model reads it", "REFUSED" in r.stderr)
        check("...saying neither clause held, and what it read",
              "Clause 1 does not hold" in r.stderr and "Clause 2 does not hold"
              in r.stderr and "no checkout under" in r.stderr, out(r)[:400])
        check("...and says how to take one", "campaign-claim.py take" in r.stderr)
        # A REMEDY THAT DOES NOT RUN IS NOT A REMEDY. `--dir` went with the
        # record in #176 and argparse now rejects it, so the refusal sent the
        # reader to a command that fails. Asserted against `take --help`
        # rather than against a literal, so the next retired flag is caught
        # too.
        usage = subprocess.run([sys.executable, str(CLAIM), "take", "--help"],
                               capture_output=True, text=True).stdout
        remedy = next(x for x in r.stderr.splitlines()
                      if "campaign-claim.py take" in x)
        unknown = [w.strip(",.") for w in remedy.split()
                   if w.startswith("--") and w.strip(",.") not in usage]
        check("...and every option the remedy prints is one `take` accepts",
              not unknown, f"not in `take --help`: {unknown}; remedy: {remedy}")
        r = ask(f.base, path=str(f.camp / "notes.md"))
        check("a write under the campaign directory with no claim is refused",
              r.returncode == 2 and "inside the campaign directory" in r.stderr,
              out(r)[:300])
        r = ask(f.base, tool="Bash", command="gh issue close 9")
        check("a gh write with no claim is refused",
              r.returncode == 2 and "no claim covering a write to #9" in r.stderr,
              out(r)[:300])

    # 3. The ref is the claim, and a ref that cannot be read is not an absence.
    with tempfile.TemporaryDirectory() as d:
        f = Fixture(d, claims=(), unpushed=("campaign-1/8-y",))
        wt8 = f.trees["campaign-1/8-y"]
        r = ask(wt8, path=str(wt8 / "a.md"))
        check("a campaign branch whose ref is on no remote is not a claim",
              r.returncode == 2 and "no such head" in r.stderr, out(r)[:400])
        check("...and says it asked the remote, having found no local copy",
              "ls-remote origin campaign-1/8-y" in r.stderr, out(r)[:400])
        git(f.base, "remote", "set-url", "origin", str(f.d / "nowhere.git"))
        r = ask(wt8, path=str(wt8 / "a.md"))
        check("a remote that cannot be asked is printed as unreadable, not absent",
              r.returncode == 2 and "could not be read" in r.stderr
              and "no such head" not in r.stderr, out(r)[:400])

    # 4. Where the session sits: #180's rows, on a worktree at a sibling path.
    with tempfile.TemporaryDirectory() as d:
        f = Fixture(d, claims=(), feature="feature")
        wt1 = f.trees["feature"]
        r = ask(wt1, path=str(wt1 / "scripts" / "x.py"))
        check("#180 row 6: a Write into a sibling worktree, cwd inside it, no "
              "claim, is refused", r.returncode == 2, f"exit {r.returncode}: {out(r)[:300]}")
        check("...naming the MAIN checkout as the base it read",
              f"inside the base {f.base.resolve()}" in r.stderr, out(r)[:400])
        r = ask(wt1, path=str(f.base / "AGENTS.md"))
        check("#180 row 7: a Write from there into the main checkout is refused",
              r.returncode == 2, out(r)[:300])
        r = ask(wt1, path=str(f.camp / "notes.md"))
        check("#180 row 8: a Write from there into the campaign directory is refused",
              r.returncode == 2, out(r)[:300])
        r = ask(wt1, tool="Bash", command="gh issue close 999")
        check("#180 row 11: gh issue close from there with no claim is refused",
              r.returncode == 2 and "a write to #999" in r.stderr, out(r)[:300])
        r = ask(wt1, tool="Bash", command=f"rm -rf {f.camp}")
        check("#180 row 10: a shell delete of the campaign directory is allowed "
              "UNREAD -- the named cost -- and says the commit gate is the reader",
              r.returncode == 0 and UNREAD in r.stdout and GATE in r.stdout,
              out(r)[:300])
        r = ask(wt1, tool="Bash", command="git commit -m x")
        check("#180 row 9: git commit is not read here; it is the commit gate's",
              r.returncode == 0 and UNREAD in r.stdout, out(r)[:300])
    with tempfile.TemporaryDirectory() as d:
        f = Fixture(d, feature="feature")
        wt1 = f.trees["feature"]
        r = ask(wt1, path=str(wt1 / "scripts" / "x.py"))
        check("...and the same Write with a claim held under the root is allowed",
              r.returncode == 0 and "Clause 2" in r.stdout, out(r)[:300])
        git(f.base, "branch", "feature2")
        nested = f.worktree("x", "feature2", under=f.base / ".claude" / "worktrees")
        r = ask(nested, path=str(nested / "scripts" / "x.py"))
        check("a worktree nested under .claude/worktrees/ resolves to the base too",
              r.returncode == 0 and f"inside the base {f.base.resolve()}" in r.stdout,
              out(r)[:300])
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "nogit"
        p.mkdir()
        r = ask(p, path=str(p / "x.md"))
        check("a directory with no marker and no git is allowed, printing that "
              "it looked and found no base",
              r.returncode == 0 and "not a git repository" in r.stdout
              and "not campaign work" in r.stdout, out(r)[:300])

    # 5. A delegate's clone under the campaign directory is a base tree of its
    # own, and its claim is its own branch.
    with tempfile.TemporaryDirectory() as d:
        f = Fixture(d, claims=("campaign-1/7-x",))
        clone = f.clone()
        r = ask(clone, path=str(clone / "AGENTS.md"))
        check("a clone on main under the campaign directory, holding nothing, "
              "is refused", r.returncode == 2 and f"inside the base {clone}"
              in r.stderr, out(r)[:400])
        git(clone, "switch", "-q", "--track", "origin/campaign-1/7-x")
        r = ask(clone, path=str(clone / "AGENTS.md"))
        check("...and on a claimed branch it is allowed by clause 1",
              r.returncode == 0 and "Clause 1" in r.stdout, out(r)[:300])

    # 6. gh: the table, the exemption, the narrowing, the parse.
    with tempfile.TemporaryDirectory() as d:
        f = Fixture(d, claims=())
        for cmd, what in [
            ("gh pr comment 5 --body hi", "gh pr comment"),
            ("gh pr review 5 --approve", "gh pr review"),
            ("gh pr edit 5 --title x", "gh pr edit"),
            ("gh pr merge 5 --merge", "gh pr merge"),
            ("gh pr create --title x --body y", "gh pr create"),
            ("gh issue reopen 5", "gh issue reopen"),
            ("gh issue develop 5", "gh issue develop"),
            ("gh issue transfer 5 o/r", "gh issue transfer"),
            ("gh issue delete 5 --yes", "gh issue delete"),
            ("gh issue edit 5 --body x", "gh issue edit"),
            ("gh issue comment 5 --body x", "gh issue comment"),
            ("gh api repos/o/r/issues -f title=x", "gh api with a field"),
            ("gh api -X PATCH repos/o/r/issues/5 --input body.json", "gh api PATCH"),
            ("gh api --method=DELETE repos/o/r/issues/5", "gh api DELETE"),
        ]:
            r = ask(f.base, tool="Bash", command=cmd)
            check(f"`{cmd}` is a campaign-plane write and is refused without a claim",
                  r.returncode == 2 and what in r.stderr,
                  f"exit {r.returncode}: {out(r)[:200]}")
        for cmd in ("gh issue create --title x --body 'git mv a b; gh issue close 3'",
                    "gh issue view 5", "gh pr view 5 --json state",
                    "gh api repos/o/r/issues/5", "gh repo clone o/r"):
            r = ask(f.base, tool="Bash", command=cmd)
            check(f"`{cmd}` is not a write and is allowed",
                  r.returncode == 0, f"exit {r.returncode}: {out(r)[:200]}")
        r = ask(f.base, tool="Bash", command="gh issue create --title x")
        check("...and the issue-create allow names the exemption",
              "minted there" in r.stdout, out(r)[:200])
        r = ask(f.base, tool="Bash", command='gh pr comment 5 --body "unbalanced')
        check("a gh command shlex cannot split is refused, naming why",
              r.returncode == 2 and "would not split" in r.stderr
              and "No closing quotation" in r.stderr, out(r)[:200])
        r = ask(f.base, tool="Bash", command="echo ok && gh issue close 5")
        check("a gh write in a later segment is read",
              r.returncode == 2 and "a write to #5" in r.stderr, out(r)[:200])
        r = ask(f.base, tool="Bash", command="gh -R o/r issue close 5")
        check("a valued flag before the subcommand does not hide it",
              r.returncode == 2 and "a write to #5" in r.stderr, out(r)[:200])
        r = ask(f.base, tool="Bash",
                command="gh issue close https://github.com/o/r/issues/12 -R o/r")
        check("the closed issue is read from a URL too",
              r.returncode == 2 and "a write to #12" in r.stderr, out(r)[:200])
        # Position must not hide the call: every executing form the old
        # SERVICE_DOORS regex caught, the table catches too.
        for cmd in ("(gh issue close 5)",
                    "{ gh issue close 5; }", "/opt/homebrew/bin/gh issue close 5",
                    "env gh issue close 5", "GH_TOKEN=x gh issue close 5",
                    "command gh issue close 5", "time gh issue close 5",
                    "for i in 1; do gh issue close 5; done",
                    "if true; then gh issue close 5; fi",
                    "bash -c 'gh issue close 5'",
                    # The four the fix round's own spec-conformance audit found
                    # still open at 1918ce7: a backquoted call, eval's operand,
                    # and a -c spelled last in a short-option cluster.
                    "`gh issue close 5`", 'eval "gh issue close 5"',
                    "bash -lc 'gh issue close 5'", "sh -ec 'gh issue close 5'"):
            r = ask(f.base, tool="Bash", command=cmd)
            check(f"`{cmd!r}` is read as the gh write it is",
                  r.returncode == 2 and "a write to #5" in r.stderr,
                  f"exit {r.returncode}: {out(r)[:200]}")
        for cmd in ("xargs gh issue close", "echo gh issue close 5",
                    "echo hi\ngh issue close 5", "cat <<EOF\nsee gh\nEOF",
                    # The fourth: an assignment's VALUE names gh and the call
                    # itself is an expansion this cannot resolve.
                    "G=gh; $G issue close 5"):
            r = ask(f.base, tool="Bash", command=cmd)
            check(f"`{cmd!r}`: a gh token this cannot read as the call is a "
                  f"write of unknown kind, refused without a claim",
                  r.returncode == 2 and "cannot read as a call" in r.stderr
                  and GATE not in r.stdout, f"exit {r.returncode}: {out(r)[:200]}")
        r = ask(f.base, tool="Bash", command="gh api -X GET search/issues -f q=x")
        check("gh api with an explicit GET is a read, fields or not",
              r.returncode == 0 and "gh api GET" in r.stdout, out(r)[:200])
        # `--method=X` carries its value, so it can be the LAST token where
        # `-X X` cannot. The method scan sliced the last token off and read the
        # attached spelling as absent, which allowed the write.
        r = ask(f.base, tool="Bash",
                command="gh api repos/o/r/issues/1 --method=DELETE")
        check("an attached --method= is read even as the last word",
              r.returncode == 2 and "gh api DELETE" in r.stderr, out(r)[:300])
        r = ask(f.base, tool="Bash",
                command="gh api repos/o/r/issues/1 --method=GET")
        check("...and an attached GET is still a read", r.returncode == 0
              and "gh api GET" in r.stdout, out(r)[:300])
        # A STRING HANDED TO A SHELL IS NOT READ, and these say so rather than
        # leaving it to the absence of a case. Reading them cost two blocking
        # findings -- a machine-wide over-refusal and a decoy that widened the
        # claim check -- so the boundary is here and is asserted here.
        for cmd in ('bash <<< "gh issue close 5"',
                    "echo 'gh issue close 5' | bash",
                    "echo hi | bash", "ls -la | wc -l"):
            r = ask(f.base, tool="Bash", command=cmd)
            check(f"`{cmd}` is allowed unread: a string a shell is handed is a "
                  f"shell string",
                  r.returncode == 0 and UNREAD in r.stdout, out(r)[:300])
        # The over-refusals that reading them produced, each an ordinary
        # command on a guard every session runs.
        for cmd in ('gh issue create --title t --body "then gh issue close 9"'
                    ' && bash run.sh',
                    'git commit -m "fix gh issue close parsing" && bash deploy.sh',
                    'echo "see gh docs" | bash'):
            r = ask(f.base, tool="Bash", command=cmd)
            check(f"`{cmd[:44]}...` is allowed: a quoted string is data",
                  r.returncode == 0, out(r)[:300])
        for sh in ("ksh", "fish"):
            r = ask(f.base, tool="Bash", command=f"{sh} -c 'gh issue close 5'")
            check(f"{sh} runs a -c string like every other shell that does",
                  r.returncode == 2 and "a write to #5" in r.stderr, out(r)[:200])
        # `do` is a PREFIX, so a for-body is read as the call it is -- the
        # docstring used to name it as unreadable, which was the other way
        # round.
        r = ask(f.base, tool="Bash",
                command="for i in 1 2; do gh issue close 9; done")
        check("a loop body is read as the call it is, not as a stray token",
              r.returncode == 2 and "a write to #9" in r.stderr
              and "cannot read as a call" not in r.stderr, out(r)[:300])
    with tempfile.TemporaryDirectory() as d:
        f = Fixture(d, claims=("campaign-1/7-x",))
        # THE ORDINARY DELEGATE SHAPE. A member repository under a campaign
        # directory is a git repository with no marker, so resolving a cwd to
        # its own common dir read it as "in no campaign" and allowed every
        # campaign-plane write there, while file_call refused the same target.
        # Both halves are asserted, because the bug was that they disagreed.
        member = f.camp / "repos" / "member"
        member.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "init", "-q", "-b", "main", str(member)], check=True)
        r = ask(member, tool="Bash", command="gh issue close 9")
        check("a gh write from inside a member clone is judged by the base "
              "above it, not by the clone",
              r.returncode == 2 and "no claim covering a write to #9" in r.stderr,
              out(r)[:400])
        r = ask(member, path=str(member / "a.txt"))
        check("...and the file half resolves the same target to the same "
              "campaign, which is what the two halves must agree on",
              str(f.camp) in out(r), out(r)[:400])
        r = ask(f.base, tool="Bash", command="gh issue close 7 -R a/b")
        check("closing the sub-issue a held claim names is allowed",
              r.returncode == 0 and "covers #7" in r.stdout, out(r)[:300])
        r = ask(f.base, tool="Bash", command="gh issue close 9 -R a/b")
        check("closing another sub-issue is refused, naming the issue",
              r.returncode == 2 and "a write to #9" in r.stderr
              and "not a claim on #9" in r.stderr, out(r)[:300])
        r = ask(f.base, tool="Bash", command="gh issue edit 9 --body x")
        check("every gh issue write naming a number is narrowed to it, not only close",
              r.returncode == 2 and "a write to #9" in r.stderr, out(r)[:300])
        r = ask(f.base, tool="Bash", command="gh issue comment 7 --body x")
        check("...and one naming the held claim's issue is allowed",
              r.returncode == 0 and "covers #7" in r.stdout, out(r)[:300])
        # EVERY ISSUE NAMED MUST BE COVERED. Collapsing two to "any claim at
        # all" let a claim on #7 admit a write to #9 standing beside it -- and
        # a decoy naming #7 was the shape a review turned into a bypass.
        r = ask(f.base, tool="Bash",
                command="gh issue close 9; gh issue close 7")
        check("a claim on one issue does not admit a write to another beside it",
              r.returncode == 2 and "a write to #9" in r.stderr, out(r)[:400])
        r = ask(f.base, tool="Bash",
                command="gh issue close 7; gh issue comment 7 --body x")
        check("...and two writes to the SAME claimed issue are allowed",
              r.returncode == 0 and "It covers #7" in r.stdout, out(r)[:400])
        r = ask(f.base, tool="Bash", command="gh pr comment 5 --body hi")
        check("a gh write that names no issue is covered by any held claim",
              r.returncode == 0 and "campaign-1/7-x, a claim" in r.stdout,
              out(r)[:300])
        # A worktree directory that is gone is a claim git itself calls
        # prunable, and clause 2 must not stand on it.
        shutil.rmtree(f.trees["campaign-1/7-x"])
        r = ask(f.base, path=str(f.base / "AGENTS.md"))
        check("a prunable worktree does not hold clause 2 open",
              r.returncode == 2 and "no checkout under" in r.stderr, out(r)[:300])

    # 7. F1/F2/F3: the probes the verb parser missed. Allowed, and the allow
    # says the command was not read and what covers it. That sentence is the
    # closing of F1: an allow that said nothing was the hole.
    with tempfile.TemporaryDirectory() as d:
        f = Fixture(d, claims=())
        for cmd in ("git -C /x commit -m y", "git -c a=b push",
                    "git -C /x cherry-pick abc",
                    "python3 -c 'open(\"AGENTS.md\",\"w\")'",
                    "perl -pi -e s/a/b/ AGENTS.md", "npm run build",
                    "sed -i s/a/b/ AGENTS.md", "install-hooks.sh"):
            r = ask(f.base, tool="Bash", command=cmd)
            check(f"`{cmd}` is allowed printing that it was unread and the "
                  f"commit gate covers it",
                  r.returncode == 0 and UNREAD in r.stdout and GATE in r.stdout,
                  f"exit {r.returncode}: {out(r)[:200]}")

    # 8. The payload and the registration.
    with tempfile.TemporaryDirectory() as d:
        f = Fixture(d)
        r = ask(f.base, stdin="{ not json")
        check("a payload that will not read refuses", r.returncode == 2
              and "permitted nothing" in r.stderr, out(r)[:200])
        r = ask(f.base, event="PostToolUse")
        check("invoked on any event but PreToolUse it refuses and says so",
              r.returncode == 2 and "PostToolUse" in r.stderr
              and "install-hooks" in r.stderr, out(r)[:200])
        r = ask(f.base, tool="Write", tool_input={})
        check("a file tool naming no path refuses",
              r.returncode == 2 and "names no path" in r.stderr, out(r)[:200])
        r = ask(f.base, tool="Read", tool_input={"file_path": str(f.base / "x")})
        check("a tool this guard has no opinion about exits 0",
              r.returncode == 0, out(r)[:200])

    if not ran:
        print("FAIL  the suite ran no case at all")
        return 1
    for x in fails:
        print(f"FAIL  {x}")
    print(f"{len(ran) - len(fails)}/{len(ran)} cases pass")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
