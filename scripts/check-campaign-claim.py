#!/usr/bin/env python3
"""Refuse a changing call from a session holding no claim on the campaign it is in.

    check-campaign-claim.py              PreToolUse: the guard
    check-campaign-claim.py --released   PostToolUse: mark a closed sub-issue's
                                         claim released

Both read the hook payload on stdin. This is the reader AGENTS.md's claim rule
never had: `campaign-tracker settlement` reads issue state, `campaign-claim live`
reads records that exist, and an open sub-issue with no record read exactly like
one nobody had started. Absence passed, so the rule was obeyed on the paths that
happened to pass through a `take` and skipped on the own-hands path -- which is
every local-only sub-issue.

WHAT COUNTS AS A CHANGING CALL

`Edit`, `Write` and `NotebookEdit` always. `Bash` only when the command matches
the changing-command pattern, which ~/.claude/hooks/stop-takeaway-check.py
already owns and this imports BY PATH rather than copying: two regexes for one
question drift, and the copy that drifts is the one nobody re-runs. It is
imported and not moved into this repository because the pattern is machine-wide
-- the Stop hook that owns it runs in every session on this machine, campaign or
not -- and a repository-local copy would be the second reader all over again,
with the direction of the dependency reversed.

The pattern is matched against the command with its quoted strings emptied
(`outside_quotes`): text handed to a command as an argument is not a command,
and `gh issue create --body "... git mv ..."` must file the issue whose number
the claim is minted from.

That pattern has no opinion about service doors, because a takeaway check does
not need one. The three `gh` writes a claim actually gates -- closing, editing
and commenting on an issue, and merging a pull request -- are added here, in
SERVICE_DOORS, and are this script's own.

An import that fails is a refusal, not a pass: a guard that cannot read the
pattern it guards by has permitted nothing.

WHICH CAMPAIGN, AND WHAT IT DOES WHEN IT CANNOT TELL

The container root is the topmost ancestor of `cwd` holding this repository's
own marker, so a linked worktree under `.claude/worktrees/` and a delegate's
clone under `<campaign>/repos/<repo>/` both resolve to it rather than to
themselves. No container above `cwd` means this session is not in a campaign at
all and the hook exits 0 -- it is installed machine-wide and most sessions on
this machine are nobody's campaign.

Inside a container, the directories searched are: the one campaign directory
`cwd` sits in, if it sits in one; otherwise every campaign directory at the
root. The union is deliberate, and it is what makes the container root
answerable at all: a session there could be working either open campaign, and
the question the guard can actually decide is not "which campaign is this" but
"does this session hold a claim anywhere on this machine". Refusing on the
ambiguity instead would refuse every write in the container whenever two
campaigns are open.

A container with no campaign directory exits 0. A campaign directory with no
`runtime/claims/` REFUSES: an empty one says no claim was taken, a missing one
says nothing, and only the first is a reading.

EXIT

PreToolUse: 0 allows, 2 refuses with the reading on stderr, where the model
reads it. Any other non-zero is this script's own failure and refuses nothing --
which is why every refusal above is spelled 2 and none of them is an exception
escaping.

PostToolUse: always 0. Exit 2 there prints and execution continues, so a guard
installed on it would enforce nothing; the release is an effect, not a verdict,
and what it did or could not do goes to stdout.
"""
import importlib.machinery
import importlib.util
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CLAIM = HERE / "campaign-claim.py"

# What makes a directory this repository's root rather than any checkout with an
# AGENTS.md in it -- and the campaign directory beside it has one of those. The
# marker is the script this one reuses, so a root it names is a root whose
# reader exists.
CONTAINER_MARKER = Path("scripts") / "campaign-claim.py"

# `<slug>-<YYMMDD>`. AGENTS.md's shape, read as a shape: nothing derives the
# list of campaigns from GitHub, because the question is which directories are
# on THIS machine.
CAMPAIGN_DIR = re.compile(r"-\d{6}$")

STOP_HOOK = Path.home() / ".claude" / "hooks" / "stop-takeaway-check.py"

# This script's own, and only these three: closing, editing or commenting on an
# issue, and merging a pull request. Every one of them is a write to the
# campaign plane that a peer reads as authoritative.
SERVICE_DOORS = re.compile(
    r"\bgh\b[^|;&]*\bissue\s+(close|edit|comment)\b"
    r"|\bgh\b[^|;&]*\bpr\s+merge\b")

# `gh issue close <n>`, with the number wherever the flags leave it.
CLOSE_TARGET = re.compile(r"\bgh\b[^|;&]*\bissue\s+close\b([^|;&]*)")

FILE_TOOLS = {"Edit", "Write", "NotebookEdit", "MultiEdit"}
PATH_KEYS = ("file_path", "notebook_path", "path")


def load(path, name):
    """Import a script by path. Returns (module, why_unreadable)."""
    try:
        spec = importlib.util.spec_from_loader(
            name, importlib.machinery.SourceFileLoader(name, str(path)))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    except Exception as e:                      # noqa: BLE001 -- any of them
        return None, f"{path}: {e.__class__.__name__}: {e}"
    return module, None


def container_root(cwd: Path):
    """The topmost ancestor of cwd that is this repository's root, or None.

    Topmost and not nearest: a linked worktree is itself a checkout of this
    repository and holds the marker, and stopping there would resolve to a tree
    that has no campaign directory under it and read as "not in a campaign"."""
    found = None
    for d in [cwd, *cwd.parents]:
        if (d / CONTAINER_MARKER).is_file():
            found = d
    return found


def campaign_dirs(root: Path, cwd: Path):
    """(directories, note). The one cwd is in, else every one at the root."""
    here = [d for d in [cwd, *cwd.parents]
            if d.parent == root and d.is_dir() and CAMPAIGN_DIR.search(d.name)]
    if here:
        return here, f"cwd is inside {here[0].name}"
    try:
        every = sorted(d for d in root.iterdir()
                       if d.is_dir() and CAMPAIGN_DIR.search(d.name))
    except OSError as e:
        return None, f"could not list {root} ({e.__class__.__name__})"
    return every, f"cwd is not inside a campaign directory; searched all "\
                  f"{len(every)} at the root"


def claims_of(claim_module, directory):
    """(records, refusal) for one campaign directory. A missing claims/ is the
    refusal; an empty one is a reading."""
    claims = directory / "runtime" / "claims"
    if not claims.is_dir():
        return None, (f"{claims} does not exist, so no claim here can be "
                      f"enumerated. An empty directory says no claim was "
                      f"taken; a missing one says nothing.")
    recs, unread = claim_module.claim_records(claims)
    return (recs, unread), None


def held_by(claim_module, records, session_id, issue=None):
    """The records this session holds, unreleased. `issue` narrows to one.

    The released test is campaign-claim's own, so what "released" means is
    written where the mark is written."""
    out = []
    for name, rec in sorted(records.items()):
        if issue is not None and name != str(issue):
            continue
        if rec.get("session", "") != session_id:
            continue
        if claim_module.is_released(rec):
            continue
        out.append((name, rec))
    return out


QUOTED = re.compile(r'"(?:[^"\\]|\\.)*"|\'[^\']*\'')
# A quoted span the shell still executes: it holds a command substitution, or
# it is the argument of `eval` or of a `-c` (bash -c, sh -c, python -c).
EXECUTED_INSIDE = re.compile(r"\$\(|`")
EXECUTES_NEXT = re.compile(r"(?:\beval|\s-c)\s*$")


def outside_quotes(command):
    """The command with every quoted string emptied -- except one the shell
    would execute -- so a pattern matched against it sees the words that run
    and not the text they are handed. `gh issue create --body "... git mv a b
    ..."` files an issue; the `mv` inside its body is prose, and matching it
    refused the one step that cannot hold a claim yet, since the number is
    minted there. A span holding `$(` or a backtick, or following `eval` or
    `-c`, is kept whole: the shell runs what is inside it."""
    def keep_or_blank(m):
        if EXECUTED_INSIDE.search(m.group(0)) or EXECUTES_NEXT.search(command[:m.start()]):
            return m.group(0)
        return '""'
    return QUOTED.sub(keep_or_blank, command)


def changing(payload, changing_command):
    """(is it a changing call, why). Returns (False, reason) for a call this
    guard has no opinion about, so the allow path can say which one it was."""
    tool = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}
    if tool in FILE_TOOLS:
        for key in PATH_KEYS:
            target = tool_input.get(key)
            if target and "runtime" in Path(str(target)).parts:
                return False, f"{tool} under runtime/, which is the claim's own home"
        return True, f"{tool} changes a file"
    if tool != "Bash":
        return False, f"{tool} changes nothing this guard reads"
    command = outside_quotes(tool_input.get("command") or "")
    if "campaign-claim.py" in command:
        # Taking a claim cannot itself require one.
        return False, "the command runs campaign-claim.py"
    if SERVICE_DOORS.search(command):
        return True, "the command writes to the campaign plane through gh"
    if changing_command.search(command):
        return True, "the command matches the changing-command pattern"
    return False, "the command matches no changing form, outside quoted text"


def close_target(command):
    """The issue number a `gh issue close` names, or None."""
    m = CLOSE_TARGET.search(command)
    if not m:
        return None
    for word in m.group(1).split():
        if word.lstrip("#").isdigit():
            return word.lstrip("#")
    return None


def refuse(lines):
    print("check-campaign-claim: REFUSED.", file=sys.stderr)
    for line in lines:
        print(f"  {line}", file=sys.stderr)
    return 2


def read_payload():
    """(payload, why_unreadable). A hook handed nothing is not a hook that saw
    an allowed call."""
    try:
        return json.load(sys.stdin), None
    except (ValueError, OSError) as e:
        return None, f"the hook payload would not read ({e.__class__.__name__})"


def setting(payload):
    """(root, dirs, note, refusal_lines) -- where this session is, or why the
    question could not be answered."""
    cwd = payload.get("cwd") or os.getcwd()
    try:
        cwd = Path(cwd).resolve()
    except OSError as e:
        return None, None, None, [f"cwd {cwd!r} would not resolve "
                                  f"({e.__class__.__name__})."]
    root = container_root(cwd)
    if root is None:
        return None, None, f"no container above {cwd}", None
    dirs, note = campaign_dirs(root, cwd)
    if dirs is None:
        return root, None, note, [note]
    return root, dirs, note, None


def pre(payload, claim_module, changing_command):
    session_id = payload.get("session_id") or ""
    root, dirs, note, refusal_lines = setting(payload)
    if refusal_lines:
        return refuse(refusal_lines + [
            "This guard could not read where it is, which is not the same as "
            "reading that there is no claim to check."])
    if root is None:
        return 0                       # not a campaign session; not this hook's
    if not dirs:
        return 0                       # a container with no campaign on it

    is_changing, why = changing(payload, changing_command)
    if not is_changing:
        return 0

    if not session_id:
        return refuse([
            "the payload carries no session_id, so no record can be matched to "
            "this session.",
            f"read {root}; {note}",
            "A claim is attributed by session id and by nothing else."])

    command = (payload.get("tool_input") or {}).get("command") or ""
    issue = close_target(command)

    found, unread, missing = {}, [], []
    for d in dirs:
        result, refusal_line = claims_of(claim_module, d)
        if refusal_line:
            missing.append(refusal_line)
            continue
        recs, odd = result
        found[d] = recs
        unread += [f"{d.name}: {o}" for o in odd]

    if missing:
        return refuse(missing + [
            f"read {root}; {note}",
            "A directory that cannot be enumerated is a refusal, not a pass."])

    holders = [(d, name, rec) for d, recs in found.items()
               for name, rec in held_by(claim_module, recs, session_id, issue)]
    if holders:
        return 0

    detail = []
    for d, recs in found.items():
        if not recs:
            detail.append(f"{d.name}/runtime/claims/ is empty: no claim was "
                          f"taken here.")
        for name, rec in sorted(recs.items()):
            mark = " RELEASED" if claim_module.is_released(rec) else ""
            detail.append(f"{d.name}/runtime/claims/{name}: session "
                          f"{rec.get('session', '<absent>')} "
                          f"({rec.get('name', '<no name>')}){mark}")
    subject = (f"closing #{issue}" if issue else "this call")
    return refuse([
        f"{why}, and this session holds no claim for {subject}.",
        f"read {root}; {note}",
        *detail,
        *unread,
        f"this session is {session_id}",
        "Take the claim first, on the sub-issue's own issue:",
        "  scripts/campaign-claim.py take --local <anchor> <issue> <topic> "
        "--dir <campaign>",
        "A sub-issue worked without one is unreadable as in-progress by every "
        "peer, which is what this refuses.",
    ])


def closed_on_github(issue, command):
    """(True/False/None, evidence). None means the reading did not happen.

    GitHub and not the tool's own output: AGENTS.md says completion is a GitHub
    fact, and a shell whose stdout looked like success is not one."""
    repo = None
    words = command.split()
    for flag in ("-R", "--repo"):
        if flag in words:
            i = words.index(flag)
            if i + 1 < len(words):
                repo = words[i + 1]
    cmd = ["gh", "issue", "view", str(issue), "--json", "state"]
    if repo:
        cmd += ["-R", repo]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True)
    except OSError as e:
        return None, f"could not run gh ({e.__class__.__name__})"
    if r.returncode != 0:
        return None, f"gh exited {r.returncode}: {r.stderr.strip()[:120]}"
    try:
        state = json.loads(r.stdout)["state"]
    except (ValueError, KeyError, TypeError):
        return None, "gh returned something this could not read"
    return state == "CLOSED", f"{' '.join(cmd)} says {state}"


def released(payload, claim_module):
    """Mark a closed sub-issue's claim released. Always exits 0."""
    session_id = payload.get("session_id") or ""
    command = (payload.get("tool_input") or {}).get("command") or ""
    issue = close_target(command)
    if not issue:
        return 0
    root, dirs, note, refusal_lines = setting(payload)
    if root is None or not dirs or refusal_lines:
        print(f"check-campaign-claim --released: not releasing #{issue}: "
              f"{note or (refusal_lines or ['unreadable'])[0]}")
        return 0

    ok, evidence = closed_on_github(issue, command)
    if ok is None:
        print(f"check-campaign-claim --released: #{issue} NOT released -- "
              f"{evidence}. The claim still stands; release it by hand.")
        return 0
    if not ok:
        print(f"check-campaign-claim --released: #{issue} is not closed "
              f"({evidence}), so its claim stands.")
        return 0

    for d in dirs:
        rec = claim_module.read_record(d / "runtime" / "claims" / str(issue))
        if not rec or "unreadable" in rec:
            continue
        r = subprocess.run(
            [sys.executable, str(CLAIM), "release", str(issue),
             "--session", session_id, "--dir", str(d)],
            capture_output=True, text=True)
        print(f"check-campaign-claim --released: {evidence}; "
              f"campaign-claim release in {d.name} exited {r.returncode}")
        print((r.stdout + r.stderr).strip())
        return 0
    print(f"check-campaign-claim --released: {evidence}, and no record for "
          f"#{issue} was found in {', '.join(d.name for d in dirs)}.")
    return 0


def main() -> int:
    post = "--released" in sys.argv
    payload, why = read_payload()
    if why:
        if post:
            print(f"check-campaign-claim --released: {why}")
            return 0
        return refuse([why, "A guard that was handed nothing has permitted "
                            "nothing."])

    event = payload.get("hook_event_name", "")
    want = "PostToolUse" if post else "PreToolUse"
    if event and event != want:
        # The registration and the flag disagree. Said out loud, because the
        # wrong one of these is silent: a guard on PostToolUse blocks nothing
        # whatever it exits.
        message = (f"registered on {event} but invoked as the {want} half. "
                   f"Re-run scripts/install-hooks.sh.")
        if post:
            print(f"check-campaign-claim: {message}")
            return 0
        return refuse([message])

    claim_module, why = load(CLAIM, "campaign_claim")
    if why:
        message = f"could not import the claim reader -- {why}"
        if post:
            print(f"check-campaign-claim --released: {message}")
            return 0
        return refuse([message, "The record's shape lives in one script, and "
                                "this is not it."])

    if post:
        return released(payload, claim_module)

    stop_hook, why = load(STOP_HOOK, "stop_takeaway_check")
    if why:
        return refuse([
            f"could not import the changing-command pattern -- {why}",
            "It is owned by that hook and read here, never copied. Without it "
            "this guard cannot tell a changing Bash call from a read."])
    pattern = getattr(stop_hook, "CHANGING_COMMAND", None)
    if pattern is None:
        return refuse([
            f"{STOP_HOOK} no longer defines CHANGING_COMMAND.",
            "The pattern was renamed or removed there; this guard reads it by "
            "that name and has no copy to fall back on."])
    return pre(payload, claim_module, pattern)


if __name__ == "__main__":
    sys.exit(main())
