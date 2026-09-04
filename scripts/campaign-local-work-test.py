#!/usr/bin/env python3
"""Prove campaign-local-work names what it cannot account for under `runtime/`.

The script's other readings run git against real checkouts and are covered by
running it; this is the one calculation in it, and it had no suite at all --
which is how its `handover/` reading was deleted without anything going red.

No case may reach the network or a real campaign directory.

Usage: scripts/campaign-local-work-test.py
"""
import importlib.machinery
import importlib.util
import subprocess
import sys
import tempfile
import pathlib
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "campaign-local-work.py"
RAN, FAILED = [], []


def check(name, ok, detail=""):
    RAN.append(name)
    if not ok:
        FAILED.append(f"{name}{('  -- ' + detail) if detail else ''}")


class Rep:
    """The reporter's methods this reads, recorded rather than printed."""

    def __init__(self):
        self.lines = []
        self.rows = []

    def report(self, line):
        self.lines.append(line)

    def unread(self, line):
        self.lines.append(line)

    def add(self, repo, kind, ident, check, clears, note="", counted=True):
        self.rows.append((repo, kind, ident))


def a_clone(root, *files):
    """A member checkout under `<campaign>/repos/`, with `files` written into it
    and excluded in its own `.git/info/exclude` -- the shape a delegate launch
    leaves behind."""
    clone = pathlib.Path(root) / "repos" / "acme"
    clone.mkdir(parents=True)
    def g(*a):
        subprocess.run(["git", "-C", str(clone), *a], check=True,
                       capture_output=True)
    g("init", "-q", "-b", "main")
    g("config", "user.email", "t@example.invalid")
    g("config", "user.name", "t")
    (clone / "tracked").write_text("x")
    g("add", "tracked")
    g("commit", "-qm", "c")
    exclude = clone / ".git" / "info" / "exclude"
    exclude.parent.mkdir(parents=True, exist_ok=True)
    for name in files:
        (clone / name).write_text("body\n")
        with exclude.open("a") as fh:
            fh.write(name + "\n")
    return clone


def main():
    spec = importlib.util.spec_from_loader(
        "clw", importlib.machinery.SourceFileLoader("clw", str(SCRIPT)))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)

    with tempfile.TemporaryDirectory() as d:
        runtime = Path(d) / "runtime"
        runtime.mkdir()

        # What the scaffold ships and step 4 writes. A REPORT here is a false
        # one on every fresh campaign, which is how a real finding stops being
        # read.
        (runtime / ".gitkeep").touch()
        (runtime / "repos").write_text("owner/repo\n")
        (runtime / "campaign-issue-body-derived.md").write_text("body\n")
        rep = Rep()
        m.read_runtime(d, rep)
        check("a freshly scaffolded runtime/ reports nothing", not rep.lines)

        # ...and anything else is NAMED. Generic on purpose: this used to name
        # `handover/` specifically, so retiring that reading left the files on
        # disk unreported one step before a close destroys them.
        (runtime / "claims").mkdir()
        rep = Rep()
        m.read_runtime(d, rep)
        check("an entry the script cannot name is reported",
              len(rep.lines) == 1 and "claims" in rep.lines[0])
        check("...and the known entries are not named beside it",
              "repos" not in rep.lines[0]
              and ".gitkeep" not in rep.lines[0])

        # A campaign directory with no runtime/ at all is not a failure: the
        # reading simply has nothing to say.
        rep = Rep()
        m.read_runtime(str(Path(d) / "nothing-here"), rep)
        check("a campaign directory with no runtime/ reports nothing",
              not rep.lines)

    # THE DELEGATE'S PRINCIPLES ARE NOT LOCAL-ONLY WORK. `CLAUDE.local.md` is
    # written into each clone and excluded in that clone's `.git/info/exclude`,
    # and `git status --porcelain --ignored=matching` reports an info/exclude'd
    # file exactly as it reports a build directory -- probed 2026-09-04, it
    # comes back `!! CLAUDE.local.md`. Counting it made every campaign that ever
    # launched a delegate read NOT clear for ever: a close gate that cannot pass.
    #
    # `read_checkouts` and not the filter alone: the skip is a branch inside
    # that loop, and a case that re-implemented the condition would pass with
    # the branch deleted.
    with tempfile.TemporaryDirectory() as d:
        clone = a_clone(d, "CLAUDE.local.md", "build-output")
        rep = Rep()
        m.read_checkouts(d, rep)
        kinds = {(k, i) for _, k, i in rep.rows}
        check("the campaign's principles in a clone are not counted as work",
              ("ignored", "CLAUDE.local.md") not in kinds, str(kinds))
        # ...and the exemption is by name: every OTHER ignored file still counts,
        # or this would be a hole rather than a carve-out.
        check("...while any other ignored file still counts",
              ("ignored", "build-output") in kinds, str(kinds))

    for name in FAILED:
        print(f"FAIL  {name}")
    print(f"{len(RAN) - len(FAILED)}/{len(RAN)} cases pass")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
