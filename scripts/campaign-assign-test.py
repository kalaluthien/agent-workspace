#!/usr/bin/env python3
"""Cases for campaign-assign.py, over a stubbed `herdr` on PATH.

AN ALLOW CASE BESIDE EVERY REFUSAL. A guard is only worth its refusals if the
thing it admits still gets through, and a refusing check with no allow case
reads identically to one that refuses everything.

The stub answers three subcommands -- `agent list`, `agent read`, `agent
prompt` -- and logs every prompt, so "the assignment was sent" is asserted on
what herdr was ASKED, never on an exit status: a run that refused and a run
that sent the prompt to the wrong pane both exit 0 or 1 for reasons this suite
has to separate.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ASSIGN = HERE / "campaign-assign.py"

RAN, FAILED = [], []


def check(name, ok, detail=""):
    RAN.append(name)
    if not ok:
        FAILED.append(f"{name}" + (f" -- {detail}" if detail else ""))


MARKER = "Compacted (ctrl+o to see full summary)"
RELEASED = "sent /compact to w1:p2; it runs when this turn ends"


def agent(sid, name, pane, status="idle"):
    return {"agent_session": {"value": sid}, "name": name, "cwd": "/tmp",
            "pane_id": pane, "agent_status": status}


HERDR = """#!/bin/sh
log="%s"
case "$1 $2" in
  "agent list")
    cat <<'JSON'
%s
JSON
    exit 0 ;;
  "agent read")
    %s ;;
  "agent prompt")
    printf 'HERDR_ENV=%%s pane=%%s prompt=%%s\\n' "${HERDR_ENV:-unset}" "$3" "$4" >> "$log"
    exit %s ;;
esac
echo "herdr shim: refusing $*" >&2
exit 1
"""


def shims(d, rows, screen="", read_exit=0, prompt_exit=0):
    """A PATH holding only the stub. PATH is this directory ALONE, so a call
    that escaped the stub would run nothing rather than silently reaching the
    real herdr and driving somebody's pane."""
    b = Path(d) / "bin"
    b.mkdir(parents=True, exist_ok=True)
    if read_exit == 0:
        read_arm = "cat <<'SCREEN'\n%s\nSCREEN\n    exit 0" % screen
    else:
        read_arm = ('echo \'{"error":{"code":"agent_not_idle"}}\' >&2; exit %d'
                    % read_exit)
    listing = json.dumps({"result": {"agents": rows}})
    (b / "herdr").write_text(
        HERDR % (str(Path(d) / "prompts.log"), listing, read_arm, prompt_exit))
    (b / "herdr").chmod(0o755)
    for tool in ("sh", "cat", "printf", "python3", "git"):
        found = shutil.which(tool)
        if found and not (b / tool).exists():
            (b / tool).symlink_to(found)
    return b


def prompts(path_dir):
    """Every prompt the stub was asked to send. An absent log is no calls."""
    log = Path(path_dir).parent / "prompts.log"
    return ([ln for ln in log.read_text().splitlines() if ln.strip()]
            if log.exists() else [])


def assign(args, path_dir):
    env = dict(os.environ, PATH=str(path_dir))
    # The suite runs inside a herdr pane, so HERDR_ENV=1 is already here; left
    # in, a case asserting the script set the guard would pass while the script
    # set nothing.
    env.pop("HERDR_ENV", None)
    return subprocess.run([sys.executable, str(ASSIGN), *args],
                          capture_output=True, text=True, env=env)


def pure_cases(m):
    rows = {"S1": {"name": "campaign-1-executor-1", "status": "idle",
                   "cwd": "/tmp", "pane": "w1:p1"},
            "S2": {"name": "campaign-1-executor-2", "status": "working",
                   "cwd": "/tmp", "pane": "w1:p2"}}
    row, note = m.row_for(rows, "w1:p2")
    check("row_for finds the row by pane, not by position",
          row is not None and row["name"] == "campaign-1-executor-2", note)
    row, note = m.row_for(rows, "w9:p9")
    check("a pane no row names lists the panes that were there",
          row is None and "w1:p1" in note and "w1:p2" in note, note)
    two = {"A": dict(rows["S1"]), "B": dict(rows["S1"])}
    row, note = m.row_for(two, "w1:p1")
    check("two rows on one pane refuse rather than pick one",
          row is None and "2 herdr rows" in note, note)

    ok, why = m.idle_verdict({"status": "idle"})
    check("idle is assignable", ok and why is None)
    ok, why = m.idle_verdict({"status": "done"})
    check("...and so is done, which is also a finished turn", ok)
    ok, why = m.idle_verdict({"status": "working"})
    check("working is refused, and the refusal says why it matters",
          not ok and "queues behind work" in why, why)
    ok, why = m.idle_verdict({"status": "unheard-of"})
    check("a status this does not recognise is not evidence of rest",
          not ok and "unheard-of" in why, why)

    v, why = m.compaction_verdict("nothing about a release here\nor here\n")
    check("a pane that never released is fresh, not stale",
          v == "fresh" and "2 line(s)" in why, f"{v} {why}")
    v, why = m.compaction_verdict(f"work\n{RELEASED}\n{MARKER}\n")
    check("a marker after the release line is compacted", v == "compacted", why)
    v, why = m.compaction_verdict(f"work\n{RELEASED}\nstill going\n")
    check("a release with no marker after it is stale",
          v == "stale" and "released at line 2" in why, why)
    # ORDER, NOT PRESENCE. This is the case the obvious implementation fails.
    v, why = m.compaction_verdict(f"{MARKER}\nwork\n{RELEASED}\nstill going\n")
    check("a marker BEFORE the release line does not count as compacted",
          v == "stale", f"{v} {why}")
    v, why = m.compaction_verdict("")
    check("an empty read is fresh with the count said, not a crash",
          v == "fresh" and "0 line(s)" in why, f"{v} {why}")

    sentence = m.prompt_for("kalaluthien/campaign-base", "42")
    check("the prompt names the sub-issue and defers to its body",
          "kalaluthien/campaign-base#42" in sentence
          and "whole brief" in sentence, sentence)


def end_to_end_cases():
    rows = [agent("S1", "campaign-1-executor-1", "w1:p1"),
            agent("S2", "campaign-1-executor-2", "w1:p2")]

    with tempfile.TemporaryDirectory() as d:
        # ALLOW: idle, compacted since its last release.
        ok = shims(Path(d) / "ok", rows, screen=f"{RELEASED}\n{MARKER}\n")
        r = assign(["w1:p2", "198"], ok)
        out = r.stdout + r.stderr
        sent = prompts(ok)
        check("an idle, compacted pane is assigned",
              r.returncode == 0 and "assigned kalaluthien/campaign-base#198"
              in out, f"exit {r.returncode}: {out[:300]}")
        check("...by exactly one guarded prompt to the pane named",
              len(sent) == 1 and "pane=w1:p2" in sent[0]
              and "HERDR_ENV=1" in sent[0] and "#198" in sent[0], repr(sent))
        check("...and never to the other pane",
              not any("pane=w1:p1" in ln for ln in sent), repr(sent))

        # ALLOW: a pane that has never released at all.
        fresh = shims(Path(d) / "fresh", rows, screen="a fresh session\n")
        r = assign(["w1:p2", "198"], fresh)
        check("a pane that never released is assigned too",
              r.returncode == 0 and len(prompts(fresh)) == 1,
              f"exit {r.returncode}: {(r.stdout + r.stderr)[:250]}")

        # REFUSE: released and not compacted since.
        stale = shims(Path(d) / "stale", rows, screen=f"{RELEASED}\nworking\n")
        r = assign(["w1:p2", "198"], stale)
        out = r.stdout + r.stderr
        check("a pane that has not compacted since its release is refused",
              r.returncode == 1 and "has not compacted since its last release"
              in out, f"exit {r.returncode}: {out[:300]}")
        check("...and nothing was sent",
              prompts(stale) == [], repr(prompts(stale)))
        # ...and --force is the way past, printing what it overrides.
        forced = shims(Path(d) / "forced", rows,
                       screen=f"{RELEASED}\nworking\n")
        r = assign(["w1:p2", "198", "--force"], forced)
        out = r.stdout + r.stderr
        check("--force assigns it and says what it is overriding",
              r.returncode == 0 and "--force: assigning a pane that has not"
              in out and len(prompts(forced)) == 1,
              f"exit {r.returncode}: {out[:300]}")

        # REFUSE: not idle. Asserted on the pane's own status, and the read arm
        # is left working so a pass cannot come from an unreadable screen.
        busy = shims(Path(d) / "busy",
                     [agent("S1", "campaign-1-executor-1", "w1:p1"),
                      agent("S2", "campaign-1-executor-2", "w1:p2",
                            status="working")],
                     screen=f"{RELEASED}\n{MARKER}\n")
        r = assign(["w1:p2", "198"], busy)
        out = r.stdout + r.stderr
        check("a working pane is refused before anything is sent",
              r.returncode == 1 and "not idle" in out
              and prompts(busy) == [], f"exit {r.returncode}: {out[:300]}")

        # REFUSE: no row names the pane.
        gone = shims(Path(d) / "gone", rows, screen=f"{RELEASED}\n{MARKER}\n")
        r = assign(["w9:p9", "198"], gone)
        out = r.stdout + r.stderr
        check("a pane herdr does not list is refused, and the panes are named",
              r.returncode == 1 and "no herdr row names pane w9:p9" in out
              and "w1:p1" in out and prompts(gone) == [],
              f"exit {r.returncode}: {out[:300]}")

        # I COULD NOT LOOK is neither a yes nor a no.
        unread = shims(Path(d) / "unread", rows, read_exit=1)
        r = assign(["w1:p2", "198"], unread)
        out = r.stdout + r.stderr
        check("a scrollback that would not read refuses, saying it could not look",
              r.returncode == 1 and "an unknown is not" in out
              and "agent read" in out and prompts(unread) == [],
              f"exit {r.returncode}: {out[:300]}")
        forced_unread = shims(Path(d) / "forcedunread", rows, read_exit=1)
        r = assign(["w1:p2", "198", "--force"], forced_unread)
        out = r.stdout + r.stderr
        check("...and --force gets past that one too, saying what it did not read",
              r.returncode == 0 and "assigning without reading the pane" in out
              and len(prompts(forced_unread)) == 1,
              f"exit {r.returncode}: {out[:300]}")

        # THE SEND ITSELF FAILING is not an assignment.
        broke = shims(Path(d) / "broke", rows, screen=f"{RELEASED}\n{MARKER}\n",
                      prompt_exit=4)
        r = assign(["w1:p2", "198"], broke)
        out = r.stdout + r.stderr
        check("a prompt that would not send reports it and is not an assignment",
              r.returncode == 1 and "exited 4" in out
              and "is not assigned" in out, f"exit {r.returncode}: {out[:300]}")

        # herdr absent: a listing that did not happen is not an empty machine.
        nowhere = Path(d) / "nowhere" / "bin"
        nowhere.mkdir(parents=True)
        r = assign(["w1:p2", "198"], nowhere)
        out = r.stdout + r.stderr
        check("herdr that cannot be run is a failed reading, not an absent pane",
              r.returncode == 1 and "did not happen" in out,
              f"exit {r.returncode}: {out[:300]}")


def main():
    import importlib.machinery
    import importlib.util
    spec = importlib.util.spec_from_loader(
        "campaign_assign",
        importlib.machinery.SourceFileLoader("campaign_assign", str(ASSIGN)))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)

    pure_cases(m)
    end_to_end_cases()
    for name in FAILED:
        print(f"FAIL  {name}")
    print(f"{len(RAN) - len(FAILED)}/{len(RAN)} cases pass")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
