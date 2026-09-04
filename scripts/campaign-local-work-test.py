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
import sys
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "campaign-local-work.py"
RAN, FAILED = [], []


def check(name, ok):
    RAN.append(name)
    if not ok:
        FAILED.append(name)


class Rep:
    """The reporter's one method this reads, recorded rather than printed."""

    def __init__(self):
        self.lines = []

    def report(self, line):
        self.lines.append(line)


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

    for name in FAILED:
        print(f"FAIL  {name}")
    print(f"{len(RAN) - len(FAILED)}/{len(RAN)} cases pass")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
