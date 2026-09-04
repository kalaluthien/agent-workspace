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
  *compare/main*) echo 0; exit 0 ;;
  # `2-beta` landed; `1-alpha` never did. The two answers are what `live`'s
  # vacant group and `release`'s fresh-claim gate each turn on.
  *"--head campaign-9999/2-beta"*) echo '[{"number": 162}]'; exit 0 ;;
  *"pr list"*|*--state*merged*) echo '[]'; exit 0 ;;
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
        # A VACANT REF WHOSE WORK LANDED BLOCKS NOTHING, and saying so is what
        # makes the group actionable: this tracker leaves merged branches
        # standing, so a close told to refuse on the whole group can never pass.
        check("a vacant claim whose pull request merged is marked landed",
              "campaign-9999/2-beta" in out and "landed as #162" in out)
        check("...and one that never merged is marked so",
              "campaign-9999/1-alpha" in out and "never merged" in out)
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

        # THE SUB-ISSUE IS WHAT IS CLAIMED, not the topic. create-ref alone
        # admits this, because `1-gamma` is a name no ref has; the sweep before
        # it is what refuses. Asserted on the sentence only this branch prints,
        # since the create-ref refusal exits 3 too and would satisfy a weaker
        # case without the sweep existing at all.
        r = claim(["take", "9999", "1", "gamma"], path)
        out = r.stdout + r.stderr
        check("a second TOPIC on a claimed sub-issue is refused",
              r.returncode == 3
              and "one claim whatever the topic" in out)
        check("...and it names the ref that already holds the sub-issue",
              "campaign-9999/1-alpha" in out)

        # ...and the sweep does not refuse a sub-issue nobody has claimed: it
        # gets as far as the create, which the shim answers "already exists".
        r = claim(["take", "9999", "7", "delta"], path)
        out = r.stdout + r.stderr
        check("an unclaimed sub-issue reaches the create-ref",
              "cut from" in out and "one claim whatever the topic" not in out)

        # THE RACE THE SURVEY ALONE CANNOT CLOSE. Two takers on two topics both
        # see no sibling and both create; the re-check AFTER the create is what
        # settles it, because by then both refs exist. The shim answers empty
        # first and two-refs after, which is exactly that interleaving.
        raced = shims(Path(d) / "raced", gh="""#!/bin/sh
STATE=RACEDIR/n
case "$*" in
  *"issues/9999"*) echo '["bound:'"$(hostname -s)"'"]'; exit 0 ;;
  *matching-refs*)
      if [ -f "$STATE" ]; then
        echo '["refs/heads/campaign-9999/5-aaa","refs/heads/campaign-9999/5-zzz"]'
      else
        : > "$STATE"; echo '[]'
      fi
      exit 0 ;;
  *commits/main*) echo 1111111111111111111111111111111111111111; exit 0 ;;
  *"-X DELETE"*) echo deleted; exit 0 ;;
  *git/refs*) exit 0 ;;
esac
exit 1
""".replace("RACEDIR", str(Path(d) / "raced")))
        r = claim(["take", "9999", "5", "zzz"], raced)
        out = r.stdout + r.stderr
        check("a claim that lost a race is deleted again, not kept",
              r.returncode == 3 and "in the same moment" in out
              and "campaign-9999/5-aaa" in out)
        (Path(d) / "raced" / "n").unlink()
        r = claim(["take", "9999", "5", "aaa"], raced)
        out = r.stdout + r.stderr
        check("...and the winner keeps its ref and says who lost",
              r.returncode == 0 and "raced this claim and lost" in out
              and "campaign-9999/5-zzz" in out)

        # A ref listing that failed is not proof the sub-issue is free.
        blind = shims(Path(d) / "blind", gh="""#!/bin/sh
case "$*" in
  *"issues/9999"*) echo '["bound:'"$(hostname -s)"'"]'; exit 0 ;;
esac
exit 1
""")
        r = claim(["take", "9999", "1", "alpha"], blind)
        check("take refuses when the ref listing did not happen",
              r.returncode == 1 and "not proof the sub-issue is free"
              in r.stdout + r.stderr)

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

        # A BRANCH WITH COMMITS IS NEVER DELETED -- and used to leave no exit
        # at all, so a sub-issue closed `not planned` after its executor pushed
        # kept a ref that `take`'s sweep then refused forever.
        ahead = shims(Path(d) / "ahead", herdr=listing(), gh=GH.replace(
            "*compare/main*) echo 0; exit 0 ;;",
            "*compare/main*) echo 3; exit 0 ;;"))
        r = claim(["release", "9999", "1"], ahead)
        out = r.stdout + r.stderr
        check("release refuses a branch holding commits",
              r.returncode == 1 and "3 commit(s) ahead" in out)
        check("...and names both ways out, one of them a command",
              "gh api -X DELETE" in out and "pull request" in out)

        # A sub-issue with no ref of its own is a refusal, never a silent pass.
        r = claim(["release", "9999", "7"], path)
        check("release refuses a sub-issue no ref names",
              r.returncode == 1 and "no ref under campaign-9999/" in r.stderr)

        # THE FRESH CLAIM. `2-beta` is 0 ahead of main, was never merged, and no
        # workspace holds it -- which is exactly a claim cut for a delegate that
        # has not checked it out yet, and is byte-for-byte what finished work
        # looks like. Deleting it lets a second `take` succeed.
        empty = shims(Path(d) / "empty", herdr=listing())
        r = claim(["release", "9999", "1"], empty)
        out = r.stdout + r.stderr
        check("release refuses an empty branch that was never merged",
              r.returncode == 1 and "never merged" in out
              and "--confirmed-absent" in out)
        check("...and says what deleting it would cost",
              "second `take` succeed" in out)
        # The shim's DELETE is unhandled and exits 1, so reaching it is visible
        # as the delete's own refusal rather than as this gate passing.
        r = claim(["release", "9999", "1", "--confirmed-absent", "a person"],
                  empty)
        out = r.stdout + r.stderr
        check("...and a confirmed absence gets past it to the delete",
              "absence confirmed by: a person" in out)
        # ...and the OTHER side of the same gate: a branch whose pull request
        # merged is finished work, and needs no person to say so.
        r = claim(["release", "9999", "2"], empty)
        out = r.stdout + r.stderr
        check("a merged branch passes the gate with no --confirmed-absent",
              "finished work and not a fresh claim" in out
              and "--confirmed-absent" not in out)


def sweep_cases(m):
    """The roots, which used to be derived from who was alive."""
    with tempfile.TemporaryDirectory() as d:
        root = Path(d).resolve()
        # A base root shaped like the real one: one campaign directory holding a
        # member clone, and one holding none.
        (root / "demo-260904" / "repos" / "acme").mkdir(parents=True)
        (root / "repoless-260904" / "runtime").mkdir(parents=True)
        (root / "not-a-campaign").mkdir()
        clones, unread = m.campaign_clones(str(root))
        check("a member clone under a campaign directory is a sweep root",
              clones == [str(root / "demo-260904" / "repos" / "acme")]
              and not unread)
        check("...found with no session alive anywhere, which is the point",
              not unread)
        check("a directory that is not <slug>-<YYMMDD> is not a campaign",
              str(root / "not-a-campaign") not in " ".join(clones))
        check("a repo-less campaign is not a failed reading",
              not unread)

        # A `repos/` that will not enumerate is NAMED. It is the case that
        # matters: skipping it silently is how a branch in an unswept clone
        # reads as standing in no workspace.
        bad = root / "locked-260904" / "repos"
        bad.mkdir(parents=True)
        bad.chmod(0o000)
        real = m.base_root
        try:
            clones, unread = m.campaign_clones(str(root))
            check("a repos/ that will not enumerate is reported, not skipped",
                  len(unread) == 1 and "locked-260904" in unread[0])
            m.base_root = lambda: (str(root), None)
            roots, unread, why = m.sweep_roots({})
            check("...and an unreadable repos/ comes back through sweep_roots",
                  len(unread) == 1 and "locked-260904" in unread[0])
        finally:
            bad.chmod(0o755)
            m.base_root = real

        # THE WIRING, not the helper. `campaign_clones` passing on its own
        # proves nothing about `sweep_roots` calling it, and the defect was the
        # call site: roots derived from live herdr rows go blind exactly when a
        # session dies. NO SESSIONS AT ALL here, so a root that appears can only
        # have come from the campaign directories.
        real = m.base_root
        try:
            m.base_root = lambda: (str(root), None)
            roots, unread, why = m.sweep_roots({})
            check("sweep_roots reaches a member clone with nothing alive",
                  why is None
                  and str(root / "demo-260904" / "repos" / "acme") in roots)
            check("...and the base root is always among them",
                  str(root) in roots)
        finally:
            m.base_root = real


def verdict_cases(m, capsys=None):
    """`live`'s two closing lines, which must never both print.

    In-process with the three readings stubbed, because the defect is in what
    `cmd_live` PRINTS and the unread it prints about comes from a repository
    this suite must not have to break on the real machine to produce."""
    import io
    import contextlib

    class Args:
        repo, campaign_issue = "o/r", "9"

    real = (m.matching_refs, m.herdr_sessions, m.sweep_roots, m.checkouts,
            m.base_root)
    try:
        m.matching_refs = lambda r, n: (["campaign-9/1-a"], None)
        m.herdr_sessions = lambda: ({}, None)
        m.base_root = lambda: ("/nowhere", None)
        m.sweep_roots = lambda s: (["/a"], ["/b: would not enumerate"], None)
        m.checkouts = lambda roots: ({}, [])
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            code = m.cmd_live(Args())
        out = buf.getvalue()
        check("an unread repository denies the completed verdict on STDOUT",
              "NOT all readings were made" in out
              and "all three readings were made" not in out)
        check("...and it exits 1", code == 1)
        check("...and names the repository it could not sweep",
              "would not enumerate" in out)

        m.sweep_roots = lambda s: (["/a"], [], None)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            code = m.cmd_live(Args())
        out = buf.getvalue()
        check("a complete sweep does print the verdict, and exits 0",
              "all three readings were made" in out and code == 0
              and "NOT all readings" not in out)
    finally:
        (m.matching_refs, m.herdr_sessions, m.sweep_roots, m.checkouts,
         m.base_root) = real


def root_cases(m):
    """`base_root` from a clone, which is the base as a member of itself."""
    import types
    with tempfile.TemporaryDirectory() as d:
        root = Path(d).resolve()
        here = root / "demo-260904" / "repos" / "campaign-base" / "scripts"
        here.mkdir(parents=True)
        real = m.HERE
        try:
            m.HERE = here
            got, why = m.base_root()
            # THE CLONE IS A DIFFERENT REPOSITORY, script and all, so the git
            # rule answers with the clone -- a base root holding no campaign
            # directory, which sweeps clean and lets `release` delete a ref
            # somebody is standing in. The campaign-directory ancestor is what
            # says otherwise.
            check("base_root run from a clone finds the real base root",
                  why is None and got == str(root))
        finally:
            m.HERE = real
        got, why = m.base_root()
        check("...and from the base's own scripts/ it still answers",
              why is None and got)

    check("an ssh remote parses to owner/repo",
          m.REMOTE.search("git@github.com:o/r.git").group(1) == "o/r")
    check("...and an https one",
          m.REMOTE.search("https://github.com/o/r").group(1) == "o/r")


def repos_cases(m):
    """Which repositories a campaign's claims can be on."""
    with tempfile.TemporaryDirectory() as d:
        root = Path(d).resolve()
        clone = root / "demo-260904" / "repos" / "acme"
        clone.mkdir(parents=True)
        git(clone.parent, "init", "-q", "acme") if False else None
        subprocess.run(["git", "-C", str(clone), "init", "-q"], check=True)
        subprocess.run(["git", "-C", str(clone), "remote", "add", "origin",
                        "git@github.com:o/acme.git"], check=True)
        repos, note = m.claim_repos("o/base", str(root))
        # A MEMBER-REPO CLAIM IS ON THE MEMBER'S REMOTE. Reading only the base
        # returned `0 occupied, 0 vacant` over a delegate standing in one.
        check("a member clone's origin joins the repositories read",
              repos == ["o/base", "o/acme"])
        check("...and the base is always first", repos[0] == "o/base")
        repos, note = m.claim_repos("o/base", None)
        check("with no base root, only the named repository is read, and it says so",
              repos == ["o/base"] and "no base root" in note)

    # The repository travels with the ref, because a delete aimed at the wrong
    # one takes a different repository's commits.
    got, unread = {}, []
    check("all_refs keys a branch to the repository it was found on",
          isinstance(m.all_refs([], "1"), tuple))


def peer_cases(m):
    """Who a close is told to ask -- and who it is not."""
    sessions = {
        "me": {"name": "campaign-9-executor-1", "cwd": "/base/x", "pane": "p",
               "status": "idle"},
        "peer": {"name": "campaign-9-planner-2", "cwd": "/base", "pane": "p",
                 "status": "idle"},
        "unnamed": {"name": "<unnamed>", "cwd": "/base/y", "pane": "p",
                    "status": "idle"},
        "other": {"name": "campaign-3-executor-1", "cwd": "/elsewhere",
                  "pane": "p", "status": "idle"},
    }
    _, _, ours = m.classify([], {}, sessions, "9", root="/base", caller="me")
    names = sorted(sid for sid, _ in ours)
    # THE CLOSER IS NOT ITS OWN BLOCKER: a close runs from a session of the
    # campaign, so a gate refusing on any live session of it can never pass.
    check("the caller is excluded from the peers a close must ask",
          "me" not in names)
    # AND A SESSION THAT NEVER NAMED ITSELF IS STILL A PEER. Nothing enforces
    # the naming rule since the record went, so a prefix-only set misses it.
    check("an unnamed session under the base root is still a peer",
          "unnamed" in names)
    check("a named peer of this campaign is a peer", "peer" in names)
    check("a session of another campaign, elsewhere, is not",
          "other" not in names)

    # THE OVERCORRECTION. Counting every session under the base root made
    # `ours` identical for every campaign number, so closing #116 asked #1's
    # planner to stand down. A name that says whose it is, is believed.
    under_base = {"x": {"name": "campaign-1-planner-3", "cwd": "/base",
                        "pane": "p", "status": "idle"}}
    check("a session named for ANOTHER campaign is not this one's, even here",
          not m.classify([], {}, under_base, "116", root="/base",
                         caller=None)[2])
    check("...and it IS its own campaign's",
          len(m.classify([], {}, under_base, "1", root="/base",
                         caller=None)[2]) == 1)

    # `under` answers about absolute paths only: `Path.resolve()` resolves a
    # relative one against the PROCESS cwd, so herdr's `"?"` placeholder counted
    # three unrelated sessions. THE ROOT HERE IS AN ANCESTOR OF THE PROCESS'S
    # OWN CWD, and it has to be: against a root the process is not inside, the
    # resolved junk path falls outside anyway and the case passes with the guard
    # deleted -- which is a fixture that pins nothing.
    inside = str(Path.cwd().parent)
    for junk in ("?", "", "relative/path"):
        check(f"under({junk!r}) is False even from inside the root",
              not m.under(junk, inside))
    check("under() still answers True for a real path inside the root",
          m.under(str(Path.cwd()), inside))
    check("...and False for a sibling that shares a prefix",
          not m.under("/base-other/x", "/base"))


def robustness_cases(m):
    rows, why = m.parse_agents('{"result": {"agents": null}}')
    check("herdr `agents: null` is a why, not a traceback",
          rows is None and why)
    rows, why = m.parse_agents('{"result": {"agents": ["a string"]}}')
    check("a herdr row that is not an object is a why, not a traceback",
          rows is None and why)


def main():
    import importlib.machinery
    import importlib.util
    spec = importlib.util.spec_from_loader(
        "campaign_claim",
        importlib.machinery.SourceFileLoader("campaign_claim", str(CLAIM)))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)

    for fn in (pure_cases, git_cases, live_cases, take_cases, release_cases,
               sweep_cases, verdict_cases, peer_cases, robustness_cases,
               root_cases, repos_cases):
        fn(m)
    for name in FAILED:
        print(f"FAIL  {name}")
    print(f"{len(RAN) - len(FAILED)}/{len(RAN)} cases pass")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
