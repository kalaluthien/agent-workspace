#!/usr/bin/env python3
"""Refuse a changing call from a session holding no claim on the campaign it is in.

    check-campaign-claim.py    PreToolUse, reading the hook payload on stdin

The pre-tool-use half of the claim gate; scripts/check-commit-claim.py is the
commit half, and the two are one rule read at two moments
(spec/campaign/orchestration/scenarios.als, `claimBeforeWork` and
`claimBeforeCommit`). A claim is a `campaign-<N>/<issue>-<topic>` branch whose
ref exists on the remote, and nothing on disk: `campaign-claim take` cuts it,
`release` deletes it.

WHAT IS READ, AND WHAT IS DELIBERATELY NOT

Two bounded languages, and no third. A FILE TOOL names its target outright. A
`gh` COMMAND is one program with a stable grammar: its segment is split with
shlex, its subcommand looked up in WRITES, and a segment that will not split
is a refusal naming why, never a guess. Every other Bash command is ALLOWED
UNREAD, printing that it was not read and that the commit gate covers it: an
arbitrary shell string is an unbounded language, and eighteen patches of a
shell reader here each added one alternation for the previous bypass. The
named cost: a shell write on campaign work by a claim-less session is refused
where it LANDS -- the commit, or the `gh` write carrying a repo-less result to
the campaign issue -- and not at the moment it is made.

WHERE A FILE TARGET IS

Campaign work is a base tree -- the main checkout, a linked worktree wherever
it sits, a delegate's clone, all resolved by `git rev-parse --git-common-dir`
from the TARGET and never from cwd -- or a campaign directory at a base root.
Anything else is outside and allowed whatever the session holds: refusing a
write to `/tmp` enforces nothing about a sub-issue.

WHO HOLDS A CLAIM

Derived, never stored. A file target is covered when (1) its own checkout is
on a claimed branch -- the checkout IS the claim's workspace, whoever edits it
-- or (2) the session's repository root (the payload cwd's common dir, or the
base above a cwd inside a campaign directory) has a worktree on a claimed
branch. Clause 2 is the WEAKER gate: every session whose cwd resolves to the
same root reads as holding every claim under it, the cost design B of #176
names, and it is why the pre-commit gate is the one that holds -- it reads the
committing checkout's branch and nothing about who sits where. A `gh` write
has no target and is covered by clause 2 alone; `gh issue close <n>` is
narrowed to a claim on `<n>`; `gh issue create` is exempt, the number being
minted there. Every exit prints which clause admitted the call, or that
neither did, and what was read: path, branch, and whether the ref came from
the local `origin/` copy or the remote.

EXIT

0 allows, 2 refuses with the reading on stderr, where the model reads it; any
other status is this script's own failure. A `gh` write from a cwd under no
base and no campaign directory is not in a campaign, and is allowed saying so.
"""
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

# What makes a directory this repository's root: the script that cuts a claim.
BASE_MARKER = Path("scripts") / "campaign-claim.py"
# `<slug>-<YYMMDD>`: AGENTS.md's shape for a campaign directory at the root.
CAMPAIGN_DIR = re.compile(r"-\d{6}$")
# The claim's shape. Only `<N>` is read from it.
CLAIM_BRANCH = re.compile(r"^campaign-(\d+)/(\d+)-")

FILE_TOOLS = {"Edit", "Write", "NotebookEdit", "MultiEdit"}
PATH_KEYS = ("file_path", "notebook_path", "path")

# Campaign-plane writes; `api` with a method or field is read in gh_write.
WRITES = {("issue", v) for v in "close edit comment reopen develop transfer "
          "delete pin unpin lock unlock".split()} \
    | {("pr", v) for v in "create merge comment review edit close reopen ready "
       "lock unlock".split()} \
    | {("label", v) for v in "create edit delete".split()}
# Flags whose value is a separate word, skipped when the subcommand is sought.
VALUED = {"-R", "--repo", "-X", "--method", "-H", "--header", "-F", "--field",
          "-f", "--raw-field", "-b", "--body", "-t", "--title", "-m"}
API_WRITE_FLAGS = {"-F", "--field", "-f", "--raw-field", "--input"}
SEPARATORS = {";", "&&", "||", "|", "&", "|&"}


def git(args, cwd):
    """(stdout, why_failed, exit status) for one git command; stdout is None
    on any non-zero exit."""
    try:
        r = subprocess.run(["git", "-C", str(cwd), *args],
                           capture_output=True, text=True)
    except OSError as e:
        return None, f"git could not run ({e.__class__.__name__})", None
    if r.returncode != 0:
        tail = r.stderr.strip().splitlines()
        return None, (tail[-1] if tail else f"git exited {r.returncode}"), r.returncode
    return r.stdout, None, r.returncode


def checkout_of(path: Path):
    """(main checkout root, this checkout's toplevel, note) for the repository
    holding `path`, read from git and never from a filesystem walk: a linked
    worktree anywhere resolves to its main checkout. (None, None, note) when
    no repository holds it."""
    d = path
    while not d.is_dir():
        if d.parent == d:
            return None, None, f"no directory on the way to {path} exists"
        d = d.parent
    out, why, _ = git(["rev-parse", "--path-format=absolute", "--git-common-dir",
                       "--show-toplevel"], d)
    if out is None:
        return None, None, f"{d}: {why}"
    common, top = (line.strip() for line in out.splitlines()[:2])
    return Path(common).parent.resolve(), Path(top).resolve(), None


def base_above(path: Path):
    """The topmost ancestor holding the marker: a path inside a campaign
    directory rather than a checkout."""
    return next((d for d in reversed([path, *path.parents])
                 if (d / BASE_MARKER).is_file()), None)


def campaign_dir_of(path: Path, base: Path):
    return next((d for d in [path, *path.parents]
                 if d.parent == base and CAMPAIGN_DIR.search(d.name)), None)


def classify(target: Path):
    """(inside?, where, checkout toplevel or None). Inside means campaign work:
    a base tree read through git, or a campaign directory read by shape."""
    main, top, note = checkout_of(target)
    if main is not None and (main / BASE_MARKER).is_file():
        camp = campaign_dir_of(target, main)
        if camp is not None:
            return True, f"inside the campaign directory {camp}", top
        return True, f"inside the base {main} (checkout {top})", top
    base = base_above(target)
    if base is not None:
        camp = campaign_dir_of(target, base)
        if camp is not None:
            return True, f"inside the campaign directory {camp}", top
        return True, f"inside the base {base}", top
    return False, f"in no base tree and no campaign directory ({note or main})", top


def ref_exists(branch, repo_root):
    """(True/False/None, source). The local `origin/` copy first, the remote
    only when that is absent: a claim just cut and not yet fetched must not
    read as no claim, and a remote that cannot be asked is not an absence."""
    out, _, _ = git(["show-ref", "--verify", "--quiet",
                     f"refs/remotes/origin/{branch}"], repo_root)
    if out is not None:
        return True, f"refs/remotes/origin/{branch} in {repo_root}"
    out, why, rc = git(["ls-remote", "--exit-code", "--heads", "origin", branch],
                       repo_root)
    if out is not None:
        return True, f"ls-remote origin {branch}"
    if rc == 2:
        return False, f"ls-remote origin {branch}: no such head"
    return None, f"ls-remote origin {branch} could not be read ({why})"


def branch_of(top):
    out, _, _ = git(["branch", "--show-current"], top)
    return out.strip() or None if out is not None else None


def claim_on(top):
    """(branch or None, verdict, source) for one checkout: is its branch a
    claim, read as the ref's existence."""
    branch = branch_of(top)
    if not branch or not CLAIM_BRANCH.match(branch):
        return branch, False, f"{top} is on {branch or 'no branch'}, not a campaign branch"
    exists, source = ref_exists(branch, top)
    return branch, exists, source


def worktrees(repo_root):
    """[(path, branch)] from `git worktree list`, or None when unreadable."""
    out, _, _ = git(["worktree", "list", "--porcelain"], repo_root)
    if out is None:
        return None
    found, path = [], None
    for line in out.splitlines():
        if line.startswith("worktree "):
            path = Path(line[9:])
        elif line.startswith("branch refs/heads/") and path is not None:
            found.append((path, line[18:]))
    return found


def session_root(cwd: Path):
    """(root, how). The session's repository root, or the base above a cwd
    inside a campaign directory, or None."""
    main, _top, _note = checkout_of(cwd)
    if main is not None:
        return main, f"cwd {cwd} -> git common dir -> {main}"
    base = base_above(cwd)
    if base is not None:
        return base, f"cwd {cwd} is under the base {base} outside any checkout"
    return None, f"cwd {cwd} is under no repository and no base"


def held(repo_root, issue=None):
    """([(path, branch, source)], detail lines): the claimed branches checked
    out under `repo_root`, narrowed to sub-issue `issue` when given."""
    trees = worktrees(repo_root)
    if trees is None:
        return [], [f"git worktree list could not be read at {repo_root}"]
    out, detail = [], []
    for path, branch in trees:
        m = CLAIM_BRANCH.match(branch)
        if not m:
            continue
        if issue is not None and m.group(2) != str(issue):
            detail.append(f"{path} is on {branch}, not a claim on #{issue}")
            continue
        exists, source = ref_exists(branch, repo_root)
        if exists:
            out.append((path, branch, source))
        else:
            detail.append(f"{path} is on {branch}, but {source}")
    if not trees or not any(CLAIM_BRANCH.match(b) for _, b in trees):
        detail.append(f"no checkout under {repo_root} is on a campaign branch")
    return out, detail


def segments(command):
    """The command's segments as token lists, or (None, why) when shlex will
    not split it. `punctuation_chars` makes `;`, `|`, `&` their own tokens."""
    lex = shlex.shlex(command, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    try:
        tokens = list(lex)
    except ValueError as e:
        return None, f"the command would not split ({e})"
    out, cur = [], []
    for t in tokens + [";"]:
        if t not in SEPARATORS:
            cur.append(t)
        elif cur:
            out.append(cur)
            cur = []
    return out, None


def gh_words(tokens):
    """The non-flag words after `gh`, a valued flag's value skipped."""
    words, i = [], 1
    while i < len(tokens):
        t = tokens[i]
        if t.startswith("-"):
            if t in VALUED and "=" not in t:
                i += 1
        else:
            words.append(t)
        i += 1
    return words


def gh_write(tokens):
    """(is a write, what) for one segment whose first word is `gh`."""
    words = gh_words(tokens)
    if not words:
        return False, "gh with no subcommand"
    if words[0] == "api":
        method = next((tokens[j + 1].upper() if t in ("-X", "--method")
                       else t[9:].upper() for j, t in enumerate(tokens[:-1])
                       if t in ("-X", "--method") or t.startswith("--method=")),
                      None)
        if method and method != "GET":
            return True, f"gh api {method}"
        if any(t in API_WRITE_FLAGS or t.split("=")[0] in API_WRITE_FLAGS
               for t in tokens):
            return True, "gh api with a field, which POSTs"
        return False, "gh api with no method and no field"
    pair = tuple(words[:2])
    if pair == ("issue", "create"):
        return False, "gh issue create, exempt: the number is minted there"
    if pair in WRITES:
        return True, "gh " + " ".join(pair)
    return False, "gh " + " ".join(pair) + ", not a write"


def close_target(tokens):
    """The issue number a `gh issue close` names, or None."""
    for t in gh_words(tokens)[2:]:
        tail = t.rstrip("/").rsplit("/", 1)[-1].lstrip("#")
        if tail.isdigit():
            return tail
    return None


def refuse(lines):
    print("check-campaign-claim: REFUSED.\n  " + "\n  ".join(lines), file=sys.stderr)
    return 2


def allow(lines):
    print("check-campaign-claim: allowed. " + " ".join(lines))
    return 0


TAKE = ("Take the claim first: scripts/campaign-claim.py take <campaign issue> "
        "<issue> <topic> --dir <campaign>, then work in a checkout on its branch.")


def file_call(tool, target: Path, cwd: Path):
    inside, where, top = classify(target)
    if not inside:
        return allow([f"{tool} -> {target} is {where}; not campaign work."])
    read = [f"{tool} -> {target}, {where}."]
    if top is not None:
        branch, is_claim, source = claim_on(top)
        if is_claim:
            return allow(read + [f"Clause 1: the target's checkout {top} is on "
                                 f"{branch}, a claim ({source})."])
        read.append(f"Clause 1 does not hold: {source}.")
    root, how = session_root(cwd)
    if root is None:
        return refuse(read + [how, "No checkout to read a claim from.", TAKE])
    holders, detail = held(root)
    if holders:
        path, branch, source = holders[0]
        return allow(read + [f"Clause 2 (the weaker gate; the commit gate is "
                             f"what holds): {how}; {path} is on {branch}, a "
                             f"claim ({source})."])
    return refuse(read + [f"Clause 2 does not hold: {how}.", *detail, TAKE])


def bash_call(command, cwd: Path):
    segs, why = segments(command)
    if segs is None:
        return refuse([why, "A gh call this cannot split is not read as harmless."])
    gh = [(s, *gh_write(s)) for s in segs if s and s[0] == "gh"]
    writes = [s for s, is_write, _ in gh if is_write]
    if not writes:
        return allow([f"{what}." for _, _, what in gh]
                     + ["The command was not read for a target: only a file "
                        "tool's path and a gh write are; its write, if any, is "
                        "gated where it lands, by the pre-commit claim gate."])
    what = ", ".join(w for _, is_write, w in gh if is_write)
    root, how = session_root(cwd)
    if root is None:
        return allow([f"{what}: {how}, so this session is in no campaign."])
    issue = next((close_target(s) for s in writes
                  if gh_words(s)[:2] == ["issue", "close"]), None)
    holders, detail = held(root, issue)
    if holders:
        path, branch, source = holders[0]
        return allow([f"{what}: {how}; {path} is on {branch}, a claim "
                      f"({source})."
                      + (f" It covers #{issue}." if issue else "")])
    subject = f"closing #{issue}" if issue else what
    return refuse([f"{what} writes to the campaign plane, and this session "
                   f"holds no claim for {subject}.", how, *detail, TAKE])


def pre(payload):
    tool = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}
    try:
        cwd = Path(payload.get("cwd") or os.getcwd()).resolve()
    except OSError as e:
        return refuse([f"cwd would not resolve ({e.__class__.__name__})."])
    if tool in FILE_TOOLS:
        raw = next((tool_input.get(k) for k in PATH_KEYS if tool_input.get(k)),
                   None)
        if not raw:
            return refuse([f"{tool} names no path this can read."])
        try:
            target = Path(os.path.expanduser(str(raw)))
            target = (target if target.is_absolute() else cwd / target).resolve()
        except (OSError, RuntimeError) as e:
            return refuse([f"{raw!r} would not resolve ({e.__class__.__name__})."])
        return file_call(tool, target, cwd)
    if tool == "Bash":
        return bash_call(tool_input.get("command") or "", cwd)
    return 0


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError) as e:
        return refuse([f"the hook payload would not read ({e.__class__.__name__})",
                       "A guard that was handed nothing has permitted nothing."])
    event = payload.get("hook_event_name", "")
    if event and event != "PreToolUse":
        return refuse([f"registered on {event}, but this is a PreToolUse guard "
                       f"and blocks nothing there. Re-run scripts/install-hooks.sh."])
    return pre(payload)


if __name__ == "__main__":
    sys.exit(main())
