#!/usr/bin/env python3
"""Prove `acquire-repo.sh` leaves the campaign's principles where a delegate reads them.

#187 question 5: #176 wrote that channel down as prose and no command wrote the
file, so a delegate launched by the documented procedure got nothing and nothing
recorded it. A case made of strings would not have caught that -- the defect was
the absence of a command -- so every case here runs the SHIPPED function against
a real git checkout and reads the bytes back.

No case reaches the network: `install_principles` is `cp`, `git rev-parse` and
an append, and the clone is made locally by `git init`.

Usage: scripts/acquire-repo-test.py
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

# THIS MACHINE'S GLOBAL GITIGNORE HOLDS `*.local.md`, so `CLAUDE.local.md` is
# ignored here whether or not the script writes anything -- and the first shape
# of this suite passed its "the clone stays clean" case on that ambient rule,
# with the per-clone exclude deleted. Every git command below runs with the
# global and system config emptied, so what is measured is the exclude the
# script writes and nothing the machine happens to carry.
GIT_ENV = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull,
               GIT_CONFIG_SYSTEM=os.devnull)

HERE = Path(__file__).resolve().parent
SCRIPT = (HERE.parent / ".claude" / "skills" / "opening-campaign" / "scripts"
          / "acquire-repo.sh")
RAN, FAILED = [], []


def check(name, ok, detail=""):
    RAN.append(name)
    if not ok:
        FAILED.append(f"{name}{('  -- ' + detail) if detail else ''}")


def install_principles(dest):
    """Run the shipped function, extracted from the shipped file.

    Extracted rather than copied: a fixture holding its own copy would pass
    while the real one was deleted, which is the exact defect this suite is
    about. `acquire-repo.sh` runs `acquire` at import, so the function is
    sliced out instead of the file being sourced."""
    src = SCRIPT.read_text()
    body = src[src.index("install_principles() {"):
               src.index("install_commit_guard() {")]
    harness = ('log() { printf "%s\\n" "$*"; }\n'
               'die() { printf "die: %s\\n" "$*" >&2; exit 1; }\n'
               + body + f'\ninstall_principles "{dest}"\n')
    return subprocess.run(["bash", "-c", harness], capture_output=True,
                          text=True, env=GIT_ENV)


def a_campaign(d, principles=True):
    """A campaign directory with a clone under `repos/`, the shape a launch
    finds. Returns the clone."""
    camp = Path(d) / "demo-260905"
    clone = camp / "repos" / "acme"
    clone.mkdir(parents=True)
    if principles:
        (camp / "AGENTS.md").write_text("# Campaign principles\nBe careful.\n")
    def g(*a):
        subprocess.run(["git", "-C", str(clone), *a], check=True,
                       capture_output=True, env=GIT_ENV)
    g("init", "-q", "-b", "main")
    g("config", "user.email", "t@example.invalid")
    g("config", "user.name", "t")
    (clone / "tracked").write_text("x")
    g("add", "tracked")
    g("commit", "-qm", "c")
    return clone


def text_of(path):
    """The file's bytes, or None when it is not there.

    A bare `read_text()` raises, and an exception ABORTS THE SUITE: the first
    mutation run against this file deleted the write and every case after it
    went unreported, so the run looked like a crash rather than like a named
    failure. A case has to be able to say "the file is missing"."""
    try:
        return path.read_text()
    except OSError:
        return None


def status(clone, *flags):
    r = subprocess.run(["git", "-C", str(clone), "status", "--porcelain",
                        *flags], capture_output=True, text=True, env=GIT_ENV)
    return r.stdout


def main():
    with tempfile.TemporaryDirectory() as d:
        clone = a_campaign(d)
        r = install_principles(clone)
        out = r.stdout + r.stderr
        check("the campaign's AGENTS.md lands as CLAUDE.local.md in the clone",
              (clone / "CLAUDE.local.md").exists(), out[:200])
        check("...with the campaign's own bytes, not a stand-in",
              "Be careful." in (text_of(clone / "CLAUDE.local.md") or ""))
        # THE HALF THAT KEEPS IT OUT OF THE MEMBER REPOSITORY'S HISTORY. Asserted
        # on `git status` and not on the exclude file's text: a line in
        # info/exclude that git does not honour reads identically.
        check("...and the clone is clean, so it is not the delegate's to commit",
              status(clone) == "", repr(status(clone)))
        check("...while `--ignored=matching` still names it, which is what "
              "campaign-local-work reads",
              "CLAUDE.local.md" in status(clone, "--ignored=matching"),
              repr(status(clone, "--ignored=matching")))
        check("...and it says what it wrote and where",
              "principles:" in out and "CLAUDE.local.md" in out, out[:200])

        # Idempotent: a second acquire over the same clone converges, and does
        # not stack a second exclude line.
        install_principles(clone)
        exclude = text_of(clone / ".git" / "info" / "exclude") or ""
        check("a second run does not stack a second exclude line",
              exclude.count("CLAUDE.local.md") == 1, repr(exclude[-80:]))

    # A campaign that adds no principles is a real answer, and it is SAID: a
    # silent skip here is indistinguishable from the defect this closes.
    with tempfile.TemporaryDirectory() as d:
        clone = a_campaign(d, principles=False)
        r = install_principles(clone)
        out = r.stdout + r.stderr
        check("a campaign with no AGENTS.md is reported, not skipped silently",
              "adds no principles" in out, out[:200])
        check("...and nothing is written",
              not (clone / "CLAUDE.local.md").exists())

    # THE CALL SITE, and this one is TEXTUAL rather than executed -- said
    # plainly because a reader is owed the difference. `acquire` clones from
    # GitHub, and no case here may reach the network, so the entry point cannot
    # be run offline. Without this the function was covered and the call was
    # not: deleting `install_principles "$dest"` from `acquire` left all eight
    # cases green, which is the fifth time that shape has appeared in this
    # repository.
    body = SCRIPT.read_text()
    acquire = body[body.index("acquire() {"):]
    check("acquire calls install_principles on every checkout it leaves",
          'install_principles "$dest"' in acquire,
          "the function is covered above; nothing runs it")
    # ...and it runs after the clone exists, or it would write into nothing.
    # Guarded on the call being present at all: `.index` RAISES when the case
    # above has already failed, and an exception aborts the suite instead of
    # reporting -- the same way a bare `read_text()` on the missing file did.
    check("...after the checkout is made, not before",
          'install_principles "$dest"' in acquire
          and acquire.index('install_principles "$dest"')
              > acquire.index("clone_into"))

    for name in FAILED:
        print(f"FAIL  {name}")
    print(f"{len(RAN) - len(FAILED)}/{len(RAN)} cases pass")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
