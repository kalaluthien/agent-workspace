#!/usr/bin/env python3
"""Prove campaign-claim reads a claim off the remote and a checkout, and refuses
to conclude from a reading that did not happen.

The claim is the branch since #176, so what is covered is the join: which refs
exist, where each is checked out, and which of the three groups a row lands in.
The `take` create-ref and the `release` ref delete reach GitHub, so they are
covered through a shimmed `gh` -- the refusals around them are what decide
whether somebody's branch is deleted, and those are pure.

The worktree half runs REAL git against temporary repositories rather than a
parser fixture: `git worktree list --porcelain` is the thing whose output shape
this depends on, and a recorded copy of it would stop being evidence the day git
changes it. Nothing here reaches the network.

Usage: scripts/campaign-claim-test.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

CLAIM = Path(__file__).resolve().parent / "campaign-claim.py"

RAN, FAILED = [], []


def check(name, ok, detail=""):
    RAN.append(name)
    if not ok:
        FAILED.append(f"{name}{(' -- ' + detail) if detail else ''}")


def git(cwd, *args):
    return subprocess.run(["git", "-C", str(cwd), *args],
                          capture_output=True, text=True, check=True)


def a_repo(root, *branches):
    """A repository with a commit, plus one linked worktree per named branch.
    Returns (repo_path, {branch: worktree path})."""
    repo = Path(root).resolve() / "repo"
    repo.mkdir(parents=True)
    git(repo, "init", "-q", "-b", "main")
    git(repo, "config", "user.email", "t@example.invalid")
    git(repo, "config", "user.name", "t")
    (repo / "f").write_text("x")
    git(repo, "add", "f")
    git(repo, "commit", "-qm", "c")
    trees = {}
    for i, b in enumerate(branches):
        w = Path(root).resolve() / f"w{i}"
        git(repo, "worktree", "add", "-q", "-b", b, str(w))
        trees[b] = str(w)
    return repo, trees


# --------------------------------------------------------------- the fixtures

def agent(sid, name, cwd, pane="w1:p1", status="idle"):
    return {"agent_session": {"value": sid}, "name": name, "cwd": cwd,
            "pane_id": pane, "agent_status": status}


def listing(*agents):
    return json.dumps({"result": {"agents": list(agents)}})


GH = """#!/bin/sh
# Every endpoint this suite needs, and a refusal for anything else, so a call
# that escaped a gate is visible as a different failure rather than as silence.
case "$*" in
  *matching-refs*) echo '["refs/heads/campaign-9999/1-alpha","refs/heads/campaign-9999/2-beta"]'; exit 0 ;;
  *"issues/9999"*) echo '["campaign","bound:'"$(hostname -s)"'"]'; exit 0 ;;
  *commits/main*) echo 1111111111111111111111111111111111111111; exit 0 ;;
  *git/refs*) echo 'Reference already exists' >&2; exit 1 ;;
esac
echo "gh shim: refusing $*" >&2
exit 1
"""

GH_ELSEWHERE = GH.replace('"$(hostname -s)"', '"not-this-machine"')

HERDR = """#!/bin/sh
cat <<'JSON'
%s
JSON
"""


def shims(d, gh=GH, herdr=None):
    """A PATH directory holding the shims. `gh` is ALWAYS shimmed: the real one
    reaches the network, and a case that did so has written to production behind
    a green line of output."""
    b = Path(d) / "bin"
    b.mkdir(parents=True, exist_ok=True)
    (b / "gh").write_text(gh)
    (b / "gh").chmod(0o755)
    if herdr is not None:
        (b / "herdr").write_text(HERDR % herdr)
        (b / "herdr").chmod(0o755)
    # Everything else a case legitimately runs, linked in, because PATH is this
    # directory ALONE: with the real PATH behind it, "herdr is not installed"
    # would silently run the real herdr and prove nothing.
    for tool in ("git", "hostname", "sh", "cat", "printf", "uname"):
        found = shutil.which(tool)
        if found and not (b / tool).exists():
            (b / tool).symlink_to(found)
    return b


def claim(args, path_dir, extra_env=None):
    env = dict(os.environ, PATH=str(path_dir), **(extra_env or {}))
    return subprocess.run([sys.executable, str(CLAIM), *args],
                          capture_output=True, text=True, env=env)


# ----------------------------------------------------------------- the cases

def pure_cases(m):
    # --- which sub-issue a branch names ---
    check("a claim branch names its sub-issue",
          m.issue_of_branch("campaign-1/176-github-facts", "1") == "176")
    check("...and a branch of another campaign names none here",
          m.issue_of_branch("campaign-2/176-x", "1") is None)
    # The one that would silently mis-attribute: `17` must not answer for `176`.
    check("a shorter number is not a prefix match",
          m.issue_of_branch("campaign-1/176-x", "1") == "176"
          and m.refs_for_issue(["campaign-1/176-x"], "1", "17") == [])
    check("a second segment with no number claims no sub-issue",
          m.issue_of_branch("campaign-1/topic-only", "1") is None)
    check("a branch outside the campaign prefix is not ours",
          m.issue_of_branch("main", "1") is None)

    refs, why = m.parse_refs('["refs/heads/campaign-1/7-a","refs/tags/v1"]')
    check("a tag in the ref listing is not a claim branch",
          refs == ["campaign-1/7-a"] and why is None)
    refs, why = m.parse_refs("not json")
    check("a ref listing that did not parse is a why, not zero claims",
          refs is None and why)

    # --- which ref a release is about ---
    b, refusal = m.which_branch(["campaign-1/7-a"], "1", "7", None)
    check("one matching ref answers the release", b == "campaign-1/7-a" and not refusal)
    b, refusal = m.which_branch([], "1", "7", None)
    check("no matching ref is a refusal naming --branch",
          b is None and refusal and "--branch" in refusal)
    b, refusal = m.which_branch(["campaign-1/7-a", "campaign-1/7-b"], "1", "7", None)
    check("TWO refs on one sub-issue are refused, never picked between",
          b is None and refusal and "7-a" in refusal and "7-b" in refusal)
    b, refusal = m.which_branch(["campaign-1/7-a", "campaign-1/7-b"], "1", "7",
                                "campaign-1/7-b")
    check("...and --branch names one directly, past the refusal",
          b == "campaign-1/7-b" and not refusal)

    # --- the binding gate ---
    check("only `here` admits a ref cut", m.binding_verdict("here") is None)
    for word in ("elsewhere", "unbound", "exit 2: gh: not found", ""):
        check(f"the binding refuses on {word!r}", bool(m.binding_verdict(word)))

    # --- the herdr half ---
    rows, why = m.parse_agents(listing(agent("s1", "campaign-1-executor-1", "/x")))
    check("a herdr row is read by its session id",
          why is None and rows["s1"]["name"] == "campaign-1-executor-1")
    rows, why = m.parse_agents(listing({"name": "n", "cwd": "/x", "pane_id": "p"}))
    check("a row herdr cannot identify is counted, never dropped",
          why is None and len(rows) == 1
          and list(rows)[0].startswith("<unidentified:"))
    rows, why = m.parse_agents("{}")
    check("herdr output of an unknown shape is a why, not zero sessions",
          rows is None and why)

    # --- the worktree half, as a parse ---
    where = m.parse_worktrees(
        "worktree /a\nHEAD aaa\nbranch refs/heads/campaign-1/7-a\n\n"
        "worktree /b\nHEAD bbb\ndetached\n\n"
        "worktree /c\nHEAD ccc\nbranch refs/heads/main\n")
    check("a worktree's branch is read off its own paragraph",
          where.get("campaign-1/7-a") == ["/a"])
    check("a DETACHED worktree holds no branch and is not an unread reading",
          "/b" not in sum(where.values(), []))
    check("...and the paragraph after it is still read",
          where.get("main") == ["/c"])

    # --- the join ---
    stood = {"campaign-1/7-a": ["/w/7"]}
    sessions = {
        "s1": {"name": "campaign-1-executor-1", "cwd": "/x", "pane": "p1",
               "status": "working"},
        "s2": {"name": "campaign-2-executor-1", "cwd": "/y", "pane": "p2",
               "status": "idle"},
    }
    occupied, vacant, ours = m.classify(
        ["campaign-1/7-a", "campaign-1/8-b"], stood, sessions, "1")
    check("a claim with a checkout is occupied",
          occupied == [("campaign-1/7-a", ["/w/7"])])
    check("a claim with no checkout is vacant",
          vacant == [("campaign-1/8-b", [])])
    check("only sessions of THIS campaign are listed",
          [n for _, r in ours for n in [r["name"]]] == ["campaign-1-executor-1"])
    # A campaign whose number is a prefix of another's must not collect it.
    check("campaign 1 does not collect campaign 11's sessions",
          not m.classify([], {}, {"s": {"name": "campaign-11-executor-1"}},
                         "1")[2])

    check("occupants names every workspace holding the branch",
          m.occupants({"b": ["/w1", "/w2"]}, "b") == ["/w1", "/w2"])
    check("...and none for a branch nothing holds",
          m.occupants({"b": ["/w1"]}, "other") == [])

    # --- the comparison, and the 404 that is not an absence ---
    check("a comparison that did not happen is not an empty branch",
          m.ahead_count(1, "") is None
          and not m.ahead_verdict(None, "", "boom", "o/r", "b")[0])
    check("a branch ahead of main is refused with its count",
          not m.ahead_verdict(3, "3", "", "o/r", "b")[0]
          and "3 commit(s)" in m.ahead_verdict(3, "3", "", "o/r", "b")[1])
    check("a branch holding nothing beyond main is admitted",
          m.ahead_verdict(0, "0", "", "o/r", "b")[0])
    check("only a 404 reads as a gone ref", m.ref_gone(1, "HTTP 404")
          and not m.ref_gone(1, "HTTP 500") and not m.ref_gone(0, ""))
    check("the ref's own endpoint separates gone from unanswered",
          m.ref_probe(0, "") == "present" and m.ref_probe(1, "HTTP 404") == "gone"
          and m.ref_probe(1, "HTTP 500") == "unanswered")
    ok, text = m.merged_head_verdict(0, "[]", "o/r", "b")
    check("a vanished branch with no merged pull request is reported",
          not ok and "never released" in text)
    ok, text = m.merged_head_verdict(0, '[{"number": 9}]', "o/r", "b")
    check("...and one with a merged pull request is nothing beyond main",
          ok and "#9" in text)
    ok, text = m.merged_head_verdict(1, "", "o/r", "b")
    check("a pull request question that failed is not an absence", not ok)


def git_cases(m):
    """The half that runs real git, so what is proved is git's own shape."""
    with tempfile.TemporaryDirectory() as d:
        repo, trees = a_repo(d, "campaign-9999/1-alpha")
        where, unread = m.checkouts([str(repo)])
        check("a real linked worktree is found on its branch",
              not unread and where.get("campaign-9999/1-alpha")
              == [trees["campaign-9999/1-alpha"]])
        check("...and the main worktree's own branch is found beside it",
              where.get("main") == [str(repo)])

        # A root that is not a repository is NAMED, never skipped: a repository
        # that could not be swept is not an empty one.
        where, unread = m.checkouts([str(repo), str(Path(d) / "nothing")])
        check("a root git will not answer for is reported as unread",
              len(unread) == 1 and "nothing" in unread[0]
              and where.get("campaign-9999/1-alpha"))

        root, why = m.repo_root(trees["campaign-9999/1-alpha"])
        check("a linked worktree resolves to the repository that owns it",
              why is None and root == str(repo))
        root, why = m.repo_root(str(Path(d) / "nothing"))
        check("a directory in no repository is not a failure, just no root",
              root is None and why is None)


def live_cases(m):
    """`live` end to end: a fixture remote, a fixture herdr listing, real git.

    Campaign 9999 is used so the fixture branches cannot collide with anything
    actually checked out on the machine the suite runs on -- the group each row
    lands in is then a property of the fixture and not of the day."""
    with tempfile.TemporaryDirectory() as d:
        path = shims(d, herdr=listing(
            agent("s1", "campaign-9999-executor-1", d),
            agent("s2", "campaign-1-planner-9", d)))
        r = claim(["live", "9999"], path)
        out = r.stdout + r.stderr
        check("live names all three readings before any count",
              "reading 1" in out and "reading 2" in out and "reading 3" in out)
        check("...and reads the campaign's refs off the remote",
              "2 claim(s)" in out)
        check("a claim nothing has checked out is in the vacant group",
              "campaign-9999/1-alpha" in out
              and "claims checked out nowhere on this machine (2)" in out)
        check("a live session of this campaign is listed",
              "campaign-9999-executor-1" in out)
        check("...and a session of another campaign is not",
              "campaign-1-planner-9" not in out)
        check("live reaches no verdict", "No verdict" in out and r.returncode == 0)

        # A reading that did not happen must deny every count below it.
        broken = shims(Path(d) / "broken", gh="#!/bin/sh\nexit 1\n",
                       herdr=listing(agent("s1", "campaign-9999-executor-1", d)))
        r = claim(["live", "9999"], broken)
        out = r.stdout + r.stderr
        check("a failed ref listing denies the counts and exits 1",
              r.returncode == 1 and "FAILED" in out
              and "did not happen" in out
              and "claims checked out nowhere" not in out)

        # herdr absent is the same shape from the other side.
        no_herdr = shims(Path(d) / "noherdr")
        r = claim(["live", "9999"], no_herdr)
        check("herdr that cannot be run is a failed reading, not zero sessions",
              r.returncode == 1 and "FAILED" in r.stdout + r.stderr)


def take_cases(m):
    with tempfile.TemporaryDirectory() as d:
        path = shims(d)
        r = claim(["take", "9999", "1", "alpha"], path)
        out = r.stdout + r.stderr
        check("take on an existing ref exits 3, which is the claim working",
              r.returncode == 3 and "already claimed" in out)
        check("...and it says to read who is standing in it",
              "live 9999" in out)

        # The binding, read BEFORE the ref is cut.
        elsewhere = shims(Path(d) / "elsewhere", gh=GH_ELSEWHERE)
        r = claim(["take", "9999", "1", "alpha"], elsewhere)
        out = r.stdout + r.stderr
        check("take refuses when the campaign is bound elsewhere",
              r.returncode == 1 and "bound elsewhere" in out)
        check("...and cuts no ref, so the refusal is before the write",
              "cut from" not in out and "claimed campaign" not in out)


def release_cases(m):
    with tempfile.TemporaryDirectory() as d:
        repo, trees = a_repo(d, "campaign-9999/1-alpha")
        # The refusal only a derived attribution can make: the branch is
        # somebody's workspace right now. The herdr row's cwd is the worktree's
        # OWNING repository, which is how the sweep reaches a worktree at all.
        path = shims(d, herdr=listing(
            agent("s1", "campaign-9999-executor-1", str(repo))))
        r = claim(["release", "9999", "1"], path)
        out = r.stdout + r.stderr
        check("release refuses a branch a workspace is standing in",
              r.returncode == 1 and "checked out in 1 workspace" in out)
        check("...and names the path, so the reader knows where to look",
              trees["campaign-9999/1-alpha"] in out)

        # herdr unreadable: an unread occupant is not an absent one.
        no_herdr = shims(Path(d) / "noherdr")
        r = claim(["release", "9999", "1"], no_herdr)
        check("release refuses when the occupancy reading did not happen",
              r.returncode == 1 and "herdr" in (r.stdout + r.stderr))

        # A sub-issue with no ref of its own is a refusal, never a silent pass.
        r = claim(["release", "9999", "7"], path)
        check("release refuses a sub-issue no ref names",
              r.returncode == 1 and "no ref under campaign-9999/" in r.stderr)


def main():
    import importlib.machinery
    import importlib.util
    spec = importlib.util.spec_from_loader(
        "campaign_claim",
        importlib.machinery.SourceFileLoader("campaign_claim", str(CLAIM)))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)

    for fn in (pure_cases, git_cases, live_cases, take_cases, release_cases):
        fn(m)
    for name in FAILED:
        print(f"FAIL  {name}")
    print(f"{len(RAN) - len(FAILED)}/{len(RAN)} cases pass")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
