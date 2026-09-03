#!/usr/bin/env python3
"""Prove campaign-claim reads a record honestly and refuses to conclude from a
dead pid.

Only the readings are covered: `take` and the ref delete in `release` reach
GitHub, and a fixture that mocked them would be testing the mock. What is here
is the half that decides whether a claim gets deleted, which is the half whose
failure destroys somebody's work.

`live` is covered here too, since it is the same script's two-sided reading. Its
herdr half is tested against a recorded listing rather than whatever is running,
so the cases mean the same thing tomorrow; the directory half runs the shipped
script.

No case may reach the network: a case that does writes to production, hidden
inside a green line of output.

Usage: scripts/campaign-claim-test.py
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

CLAIM = Path(__file__).resolve().parent / "campaign-claim.py"
def _free_pid():
    """A pid held by nobody. A hardcoded one passed on a runner and could name a
    live process on a dev machine -- the residue running the other way."""
    p = subprocess.Popen([sys.executable, "-c", ""])
    p.wait()
    return str(p.pid)


DEAD = _free_pid()
DEAD_REC = f"session s1\nname n1\npid {DEAD}\nbranch campaign-1/7-x\n"
DIR = object()   # a fixture that is a directory rather than a file


# A stand-in process table, so the cases that turn on `stale?` do not depend
# on whether a claude happens to be running on the machine the suite runs on.
PS_SHIM = """#!/bin/sh
for a in "$@"; do
  case "$a" in
    *lstart*) echo "Sat Aug 30 12:00:00 2026     claude.exe"; exit 0 ;;
  esac
done
exit 1
"""


def run(args, files=None, mtime=None, env=None, stub_ps=False):
    with tempfile.TemporaryDirectory() as d:
        claims = Path(d) / "runtime" / "claims"
        claims.mkdir(parents=True)
        for name, body in (files or {}).items():
            if body is DIR:
                (claims / name).mkdir()
                continue
            if isinstance(body, bytes):
                (claims / name).write_bytes(body)
            else:
                (claims / name).write_text(body)
            if mtime is not None:
                os.utime(claims / name, (mtime, mtime))
        e = dict(os.environ, **(env or {}))
        if stub_ps:
            shim = Path(d) / "shim"
            shim.mkdir()
            (shim / "ps").write_text(PS_SHIM)
            (shim / "ps").chmod(0o755)
            e["PATH"] = f"{shim}:{e.get('PATH', '')}"
        return subprocess.run([sys.executable, str(CLAIM), *args, "--dir", d],
                              capture_output=True, text=True, env=e)


OLD = 1767225600.0     # 2026-01-01, before any session on this machine
CASES = []


def case(name, args, files=None, mtime=None, env=None, want=None, code=None,
         stub_ps=False):
    CASES.append((name, args, files, mtime, env, want, code, stub_ps))


# The reading that says nothing is here, which must not read like a refusal.
case("an empty claims directory is a reading, not an absence",
     ["list"], want="0 claim(s)", code=0)
case("no record for this subtask says so and names the path it read",
     ["status", "7"], want="verdict none", code=0)

# The verdict that costs work if it is wrong.
case("a dead pid on an old record is stale?, never dead",
     ["status", "7"], {"7": DEAD_REC}, OLD, want="verdict stale?", code=0,
     stub_ps=True)
case("...and it says why, so the reader knows to ask",
     ["status", "7"], {"7": DEAD_REC}, OLD, want="do not read this as free", code=0,
     stub_ps=True)
case("a dead pid on a record written since the last restart is plain dead",
     ["status", "7"], {"7": DEAD_REC}, None, want="verdict dead", code=0)

# A record that cannot answer must say so rather than answer wrongly.
case("a record with no pid is unreadable, not dead",
     ["status", "7"], {"7": "session s1\nname n1\nbranch b\n"},
     want="verdict unreadable", code=0)

# The release gate.
case("release refuses a dead pid with no confirmation",
     ["release", "7"], {"7": DEAD_REC}, OLD, want="not proof the session is gone", code=1)
case("release names the restart evidence when it refuses",
     ["release", "7"], {"7": DEAD_REC}, OLD, want="a restart is likely", code=1,
     stub_ps=True)

# A missing directory is not an empty one.
case("a missing claims directory refuses rather than reading empty",
     ["list"], want=None, code=None)

# `take` is covered only up to the point where it would reach GitHub.
# pid 1 exists on every machine this runs on and is not a claude, so
# the pid reading calls it `other` -- a liveness that is neither dead
# nor alive, and the one the release gate must refuse by name. Hardcoding the
# wire to "dead" would flip this refusal's reason, which is what makes it a
# case.
# A record whose bytes are not text must read as unreadable, not crash.
# The trace and its notes on one stream, in order -- split across stdout and
# stderr, a pipe could reorder them relative to each other.
case("the restart note is on stdout with the rest of the trace",
     ["release", "7"], {"7": DEAD_REC}, OLD, want="note:", code=1)
# A non-file entry under claims/ is counted apart, never dropped.
case("a directory under claims/ is named by list, not skipped",
     ["list"], {"7": DEAD_REC, "9": DIR}, want="is not a file", code=0)
case("an undecodable record reads as unreadable, not as an absence",
     ["status", "7"], {"7": b"\xff\xfe not text\n"}, want="will not decode",
     code=0)
case("release refuses a record whose pid belongs to something else",
     ["release", "7"], {"7": "session s\nname n\npid 1\nbranch campaign-1/7-x\n"},
     want="reads other", code=1)
case("take refuses a subtask this machine already has a record for",
     ["take", "1", "7", "x"], {"7": DEAD_REC},
     want="already claimed", code=3)
case("...and the refusal names the session to go and ask",
     ["take", "1", "7", "x"], {"7": DEAD_REC}, want="session s1", code=3)

# `--local` reaches no network at all, so the whole of it is covered here.
LOCAL_REC = "session mine\nname n1\npid 1\nbranch campaign-1/7-x\nlocal yes\n"
RELEASED_REC = LOCAL_REC + "released 2026-09-02T10:00:00+0900 by mine\n"

case("take --local writes the record and says no ref was cut",
     ["take", "--local", "1", "7", "x"], want="no ref is cut", code=0)
case("...and the record carries `local yes`, which is what release reads",
     ["take", "--local", "1", "7", "x"], want="local yes", code=0)
case("take --local on a live record refuses like any other take",
     ["take", "--local", "1", "7", "x"], {"7": LOCAL_REC},
     want="already claimed", code=3)
# A record that will not decode is a reading that failed. Answering `already
# claimed` would be right by accident; answering 0 would hand out a held claim.
case("take on an undecodable record refuses without concluding",
     ["take", "--local", "1", "7", "x"], {"7": b"\xff\xfe not text\n"},
     want="will not decode", code=1)
# Scoped to unsettled records: a subtask that returns to its starting state
# must be re-takeable, or a re-opened issue can never be worked again.
case("take re-takes a released record and says why it may",
     ["take", "--local", "1", "7", "x"], {"7": RELEASED_REC},
     want="marked released", code=0)

# A name from another campaign is a stale name about to become durable: the
# refusal names both numbers, and fires before any ref or record is written.
case("take refuses a --name from another campaign, naming both numbers",
     ["take", "--local", "1", "7", "x", "--name", "campaign-116-executor-2"],
     want="campaign 116", code=1)
case("...and says what to do about it",
     ["take", "--local", "1", "7", "x", "--name", "campaign-116-executor-2"],
     want="rename first", code=1)
case("take accepts a --name of this campaign",
     ["take", "--local", "1", "7", "x", "--name", "campaign-1-executor-2"],
     want="name campaign-1-executor-2", code=0)

case("release --session marks a local claim released, deleting no ref",
     ["release", "7", "--session", "mine"], {"7": LOCAL_REC},
     want="marked", code=0)
case("...and says there was never a ref to delete",
     ["release", "7", "--session", "mine"], {"7": LOCAL_REC},
     want="no ref was ever cut", code=0)
case("release refuses a local claim held by another session",
     ["release", "7", "--session", "theirs"], {"7": LOCAL_REC},
     want="held by session mine", code=1)
case("release refuses a local claim with no proof of any kind",
     ["release", "7"], {"7": LOCAL_REC},
     want="Pass --session", code=1)
# The PostToolUse half fires on every close, so a second release of the same
# record is ordinary and must not read as a failure.
case("releasing an already-released record is a no-op, not an error",
     ["release", "7", "--session", "mine"], {"7": RELEASED_REC},
     want="already marked released", code=0)


PS = ("Fri Aug  7 13:37:53 2026     claude.exe\n"
      "Mon Aug 31 02:00:00 2026     claude.exe\n"
      "Mon Aug 31 02:00:00 2026     launchd\n")
BEFORE_ALL = 1754000000.0    # Aug 2026, before both claude rows
AFTER_ALL = 1790000000.0     # 2026-09, after both


def pure_cases(m):
    """The restart evidence, against a recorded process table."""
    # Counted as they run, never a constant. A hardcoded total is a suite that
    # cannot report its own shrinkage -- deleting a case still prints the same
    # "N/N pass".
    ran, out = [], []

    def c(name, cond):
        ran.append(name)
        if not cond:
            out.append(name)

    names = frozenset({"claude", "claude.exe"})
    n, why = m.count_newer(PS, names, BEFORE_ALL)
    c("a record older than every session sees them all", why is None and n == 2)
    n, why = m.count_newer(PS, names, AFTER_ALL)
    c("a record newer than every session sees none", why is None and n == 0)
    n, why = m.count_newer(PS, frozenset({"claude"}), BEFORE_ALL)
    c("a name list that misses this install's name finds nothing",
      why is None and n == 0)
    n, why = m.count_newer("not a timestamp     claude.exe\n", names, 0)
    c("an unparseable start time is a why, not a zero", n is None and why)
    n, why = m.count_newer("", names, 0)
    c("an empty process table is zero, not a why", why is None and n == 0)

    # The destructive path's decision, now that it is a calculation and the
    # suite can reach it: the effects around it touch GitHub, and the suite
    # may not.
    rec = {"session": "S1", "branch": "campaign-1/7-x"}
    c("a live record is never releasable",
      m.release_gate(rec, None, "asked the peer", "alive")[0] is None)
    c("nor an `other` one, which is a pid this install cannot name",
      m.release_gate(rec, None, "asked the peer", "other")[0] is None)
    c("nor an unreadable one",
      m.release_gate(rec, None, "asked the peer", "unreadable (x)")[0] is None)
    c("a dead record without a confirmed absence is refused",
      m.release_gate(rec, None, None, "dead")[0] is None)
    c("...and the refusal says a restart renumbers pids",
      "renumbers" in (m.release_gate(rec, None, None, "dead")[1] or ""))
    c("a dead record with one proceeds, on the branch the record names",
      m.release_gate(rec, None, "the peer said so", "dead")[0] == "campaign-1/7-x")

    c("no record and no --branch is refused",
      m.release_gate(None, None, "the peer said so", None)[0] is None)
    c("no record with a branch but no confirmation is refused too",
      m.release_gate(None, "campaign-1/7-x", None, None)[0] is None)
    c("no record is the weaker evidence, so it needs the same confirmation",
      m.release_gate(None, "campaign-1/7-x", "asked everyone", None)[0]
      == "campaign-1/7-x")

    # The blocker: compare and delete must name the same repository.
    c("the comparison is asked of the repository named",
      m.compare_path("a/b", "campaign-1/7-x").startswith("repos/a/b/"))
    c("and the delete happens in that same one",
      m.delete_path("a/b", "campaign-1/7-x").startswith("repos/a/b/"))
    c("a member repository is never compared against the container",
      "agent-workspace" not in m.compare_path("owner/web", "campaign-1/7-x"))

    ok, why = m.ahead_verdict(1, "", "boom", "a/b", "x")
    c("a comparison that failed is not an empty branch", not ok and "did not happen" in why)
    ok, why = m.ahead_verdict(0, "", "", "a/b", "x")
    c("an empty answer is not zero either", not ok)
    ok, why = m.ahead_verdict(0, "3", "", "a/b", "x")
    c("a branch ahead of main is reported, never deleted", not ok and "never deleted" in why)
    ok, why = m.ahead_verdict(0, "0", "", "a/b", "x")
    c("a branch at main is releasable", ok and why is None)
    # The two halves of the guard overlap, so each needs a case that only it
    # catches: a failed call whose stdout happens to read "0" is caught by the
    # returncode half alone.
    ok, why = m.ahead_verdict(1, "0", "boom", "a/b", "x")
    c("a failed call is not empty even when its output says 0", not ok)
    # The two halves change the same verdict, so only the *message* separates
    # them: an answer that is not a number means the question was not answered,
    # and reporting it as "N commits ahead" sends the reader to the wrong repair.
    ok, why = m.ahead_verdict(0, "not a number", "", "a/b", "x")
    c("an answer that is not a number is a failed question, not a count",
      not ok and "did not happen" in why and "commit(s) ahead" not in why)

    # A command that is not installed at all: a failed run carrying its reason,
    # never a traceback. `gh` and `ps` both go through this.
    r = m.run("no-such-command-xyz")
    c("a missing command is a failed run, not an exception",
      r.returncode != 0 and "FileNotFoundError" in r.stderr)

    # The install's process names. A literal, and stated as a fact about this
    # install rather than about claude: an unrecognised name must read `other`,
    # never `dead`, so the literal is allowed to be wrong without a tree being
    # deleted for it.
    c("the install's process names are a frozenset with something in it",
      isinstance(m.NAMES, frozenset) and m.NAMES)

    # The pid reading, now in this script. Each verdict, and each way the
    # question can fail to be asked at all -- the branch whose wrong answer
    # deletes a tree.
    c("a pid that is not a number is unreadable, never dead",
      m.liveness("abc") == (None, "not a pid: 'abc'"))
    c("pid 0 is not a pid either", m.liveness("0")[0] is None)
    c("a negative pid is not a pid", m.liveness("-1")[0] is None)
    c("this process's own pid reads a verdict, not a failure",
      m.liveness(os.getpid())[1] is None)
    c("a pid held by nobody is dead", m.liveness(DEAD) == ("dead", None))
    # pid 1 exists on every machine this runs on and is not a claude, so it is
    # `other` -- a liveness that is neither dead nor alive, and the one the
    # release gate must refuse by name.
    c("a pid held by something this install cannot name is other, not dead",
      m.liveness("1") == ("other", None))
    c("the record reader turns an unreadable pid into a word, not an exception",
      m.alive("abc").startswith("unreadable ("))

    # A record that will not decode is a failed reading, not an absence.
    c("an undecodable record is unreadable, never dead",
      "unreadable" in (m.liveness_of({"unreadable": "UnicodeDecodeError"}) or ""))

    # The wire into the release gate. Replacing it with the constant "dead"
    # left the whole suite green and made a live claim deletable.
    c("a record with no pid reads unreadable, not dead",
      m.liveness_of({"session": "s"}) == "unreadable (no pid)")
    c("no record has no liveness at all", m.liveness_of(None) is None)
    return ran, out


# ------------------------------------------------------------- `live` and its join

# A stand-in herdr, so a case that runs the shipped script end to end does not
# depend on what happens to be installed.
HERDR_SHIM = """#!/bin/sh
echo '{"result":{"agents":[]}}'
"""


def with_herdr(d):
    shim = Path(d) / "bin"
    shim.mkdir(exist_ok=True)
    (shim / "herdr").write_text(HERDR_SHIM)
    (shim / "herdr").chmod(0o755)
    return {"PATH": f"{shim}:/usr/bin:/bin", "HOME": str(d)}


def agent(sid, name=None, pane="w1:p1"):
    a = {"agent_session": {"value": sid} if sid else None,
         "agent_status": "working", "cwd": "/x", "pane_id": pane}
    if name:
        a["name"] = name
    return a


def listing(*agents):
    return json.dumps({"result": {"agents": list(agents)}})


def live(m):
    """The two-sided reading: liveness from herdr, attribution from the records,
    joined on the one key that survives a restart and a rename."""
    ran, out = [], []

    def c(name, cond):
        ran.append(name)
        if not cond:
            out.append(name)

    def run_live(d, env=None):
        return subprocess.run([sys.executable, str(CLAIM), "live", "1", "--dir", d],
                              capture_output=True, text=True, env=env)

    got, why = m.parse_agents(listing(agent("S1", "campaign-1-executor-1")))
    c("a listed session is keyed by its session id", why is None and "S1" in got)
    c("its name comes along", got and got["S1"]["name"] == "campaign-1-executor-1")

    got, why = m.parse_agents(listing(agent("S1")))
    c("a session with no name is still listed",
      why is None and got["S1"]["name"] == "<unnamed>")

    # A session herdr cannot identify still occupies a pane, and dropping it
    # shrinks the count a close gate reads.
    got, why = m.parse_agents(listing(agent(None, pane="w1:p9")))
    key = next(iter(got)) if got else ""
    c("a session herdr cannot identify is counted under a key naming its pane",
      why is None and len(got) == 1 and isinstance(key, str) and "w1:p9" in key)

    # The join, which is the whole point.
    sessions, _ = m.parse_agents(listing(agent("S1", "campaign-1-executor-1")))
    same = {"7": {"session": "S1", "name": "campaign-1-executor-1", "branch": "b"}}
    a, o, i = m.classify(same, sessions)
    c("a claim whose session id is live is answered", len(a) == 1 and not o)
    # ...and is not also counted as holding nothing. The two lists are a
    # partition of the live sessions, and a session appearing on both would be
    # read by a close as one live executor too many.
    c("a session that answers a claim is not also listed as unattributed", not i)

    # The case that separates the two possible keys. The name matches and the
    # session id does not, which is exactly what a rename leaves behind: joining
    # on the name calls this answered, and a close then reads a live claim as
    # attributed to a session that is not the one holding it.
    renamed = {"7": {"session": "S9", "name": "campaign-1-executor-1", "branch": "b"}}
    a, o, i = m.classify(renamed, sessions)
    c("a claim whose name matches but session id does not is unanswered",
      not a and len(o) == 1)
    c("...and that live session is then reported as holding no claim", len(i) == 1)

    # The anchor argument: pins that it is actually read, not merely declared.
    mine = {"7": {"session": "S1", "branch": "campaign-1/7-x"}}
    theirs = {"9": {"session": "S2", "branch": "campaign-2/9-y"}}
    c("a record naming this campaign's branch is not stray",
      m.stray_branches(mine, "1") == [])
    c("a record naming another campaign's branch is stray",
      len(m.stray_branches(theirs, "1")) == 1)
    c("a record with no branch cannot vouch for itself and is stray",
      len(m.stray_branches({"7": {"session": "S1"}}, "1")) == 1)
    c("anchor 1 does not swallow anchor 11",
      len(m.stray_branches({"7": {"branch": "campaign-11/7-x"}}, "1")) == 1)

    got, why = m.parse_agents("not json")
    c("unparseable output is a why, not an empty listing", got is None and why)
    got, why = m.parse_agents(json.dumps({"result": {}}))
    c("a listing with no agents key is a why, not zero sessions",
      got is None and why)

    # A reading that did not happen must not come back as a clean tree.
    with tempfile.TemporaryDirectory() as d:
        r = run_live(d, with_herdr(d))
        out_text = r.stdout + r.stderr
    c("a missing claims directory refuses",
      r.returncode == 1 and "says nothing" in out_text)

    with tempfile.TemporaryDirectory() as d:
        (Path(d) / "runtime" / "claims").mkdir(parents=True)
        r = run_live(d, with_herdr(d))
        out_text = r.stdout + r.stderr
    c("an empty claims directory is read, not refused",
      r.returncode == 0 and "0 claim(s)" in out_text)
    c("and it still says both readings were made",
      "both readings were made" in out_text)

    # A run that asserted nothing is not a pass either.
    # The wire from cmd_live into stray_branches, which the pure cases above
    # cannot reach: replacing the call with [] left the suite green. Run with
    # PATH stripped so herdr cannot be found -- the stray report must not
    # depend on the other reading having worked.
    with tempfile.TemporaryDirectory() as d:
        claims = Path(d) / "runtime" / "claims"
        claims.mkdir(parents=True)
        (claims / "9").write_text("session S9\nbranch campaign-2/9-y\n")
        r = run_live(d, {"PATH": "/nonexistent"})
        out_text = r.stdout + r.stderr
    c("a record from another campaign is reported by the real run",
      "campaign-2/9-y" in out_text and "outside campaign-1" in out_text)
    c("...even when the herdr reading could not be made",
      "did not happen" in out_text and r.returncode == 1)

    # A record that will not decode is a check that did not happen, so it must
    # deny the clean verdict the way a failed herdr read does.
    with tempfile.TemporaryDirectory() as d:
        claims = Path(d) / "runtime" / "claims"
        claims.mkdir(parents=True)
        (claims / "7").write_text("session S1\nbranch campaign-1/7-x\n")
        (claims / "9").write_bytes(b"\xff\xfe not text\n")
        r = run_live(d)
        out_text = r.stdout + r.stderr
    c("an unreadable record denies the clean verdict", r.returncode == 1)
    c("...and is named as unread rather than as a stray file",
      "will not decode" in out_text and "1 unread" in out_text)
    c("...and the run does not claim both readings were made",
      "both readings were made" not in out_text)

    # A non-file entry under claims/ is counted, not silently dropped.
    with tempfile.TemporaryDirectory() as d:
        claims = Path(d) / "runtime" / "claims"
        claims.mkdir(parents=True)
        (claims / "7").write_text("session S1\nbranch campaign-1/7-x\n")
        (claims / "9").mkdir()
        recs, odd = m.claim_records(claims)
        c("a directory under claims/ is named, not dropped",
          len(recs) == 1 and len(odd) == 1 and odd[0].startswith("9 "))

    # `status` and `live` read one record with one parser, so they cannot
    # disagree about what it says.
    body = "session S1\nname n1\npid 4\nbranch campaign-1/7-x\n"
    with tempfile.TemporaryDirectory() as d:
        claims = Path(d) / "runtime" / "claims"
        claims.mkdir(parents=True)
        (claims / "7").write_text(body)
        recs, _ = m.claim_records(claims)
        c("one record parser feeds both readings",
          recs["7"] == m.read_record(claims / "7") == m.fields_of(body))

    # --- the `alive` subcommand, whose printed word is the whole contract.
    def alive_cli(pid):
        r = subprocess.run([sys.executable, str(CLAIM), "alive", str(pid)],
                           capture_output=True, text=True)
        return r.returncode, r.stdout.strip(), r.stderr
    code, word, _ = alive_cli(DEAD)
    c("`alive` prints `dead` for a pid held by nobody, and exits 0",
      code == 0 and word == "dead")
    code, word, _ = alive_cli(1)
    c("`alive` prints `other` for a pid this install cannot name",
      code == 0 and word == "other")
    # The status is about the reading, never the verdict: a failed read that
    # exited like `dead` deletes a tree under a live session.
    code, word, err = alive_cli("abc")
    c("`alive` refuses an unreadable pid on exit 2, printing no verdict",
      code == 2 and word == "" and "not a pid" in err)
    return ran, out


def main():
    failed = 0
    import importlib.machinery, importlib.util
    spec = importlib.util.spec_from_loader(
        "campaign_claim",
        importlib.machinery.SourceFileLoader("campaign_claim", str(CLAIM)))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    pure_ran, pure_failed = pure_cases(m)
    live_ran, live_failed = live(m)
    pure_ran += live_ran
    pure_failed += live_failed
    for name in pure_failed:
        print(f"FAIL  {name}")
    failed += len(pure_failed)
    for name, args, files, mtime, env, want, code, stub_ps in CASES:
        if name.startswith("a missing claims directory"):
            with tempfile.TemporaryDirectory() as d:
                r = subprocess.run([sys.executable, str(CLAIM), "list", "--dir", d],
                                   capture_output=True, text=True)
            ok = r.returncode != 0 and "does not exist" in r.stdout + r.stderr
            if not ok:
                failed += 1
                print(f"FAIL  {name}\n      got exit {r.returncode}: "
                      f"{(r.stdout + r.stderr).strip()[:160]}")
            continue
        r = run(args, files, mtime, env, stub_ps)
        out = r.stdout + r.stderr
        ok = (want is None or want in out) and (code is None or r.returncode == code)
        if not ok:
            failed += 1
            print(f"FAIL  {name}\n      wanted {want!r} and exit {code}, got "
                  f"exit {r.returncode}:\n      {out.strip()[:200]}")
    total = len(CASES) + len(pure_ran)
    print(f"{total - failed}/{total} cases pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
