#!/usr/bin/env python3
"""Refuse a changing call from a session holding no claim on the campaign it is in.

    check-campaign-claim.py    PreToolUse, reading the hook payload on stdin

The pre-tool-use half of the claim gate; scripts/check-commit-claim.py is the
commit half (spec/campaign/orchestration/scenarios.als, `claimBeforeWork` and
`claimBeforeCommit`). A claim is a `campaign-<N>/<issue>-<topic>` branch whose
ref exists on the remote, and nothing on disk (#176).

WHAT IS READ. Two bounded languages. A FILE TOOL names its target. A `gh`
call is one program with a stable grammar: each segment (shlex; ``;|&(){}` ``
split it, and so do the strings another command runs -- the `-c` of a shell
NAMED IN `SHELLS`, alone or last in a cluster like `-lc`, and `eval`'s
operands; the set is the rule and the comment beside it says why, so a shell
absent from it is unread like any other interpreter, as is a string a shell is
merely handed) whose command word is
`gh` -- after `env`, `VAR=x`, `time`, a path -- is looked up in WRITES, and a
segment that will not split refuses. A `gh` TOKEN this cannot read as the call
(`xargs`, a heredoc, or an assignment whose value is `gh`) is read as a write
of unknown kind, since nothing downstream reads a `gh` write. NOT a loop body:
`do` and `then` are prefixes, so `for i in 1 2; do gh issue close 9; done` is
read as the call it is and narrowed to #9. Every other Bash command is ALLOWED UNREAD,
printing so: a shell string is an unbounded language, and a shell write on
campaign work lands at the commit, where the other half reads it.

WHERE A FILE TARGET IS. A base tree -- main checkout, linked worktree anywhere,
delegate clone, all by `git rev-parse --git-common-dir` from the TARGET, never
from cwd -- or a campaign directory at a base root. Anything else is outside.

WHO HOLDS A CLAIM. Derived, never stored. Clause 1: the target's own checkout
is on a claimed branch. Clause 2: the session's repository root (the payload
cwd's common dir, or the base above a cwd inside a campaign directory) has a
worktree on one. Clause 2 is the WEAKER gate -- every session at one root
reads as holding every claim under it, design B's named cost -- and for a
FILE write the commit gate is what holds. A `gh` write has no landing, so
clause 2 is its only gate, narrowed by the issue number: `gh issue <verb> <n>`
needs a claim on `<n>`. `gh issue create` is exempt, the number being minted
there. Every exit prints which clause held, or that neither did, and what was
read: path, branch, and whether the ref came from `origin/` or the remote.

EXIT. 0 allows; 2 refuses with the reading on stderr, where the model reads
it. A `gh` write from a cwd under no base is allowed as not in a campaign.
"""
import importlib.machinery
import importlib.util
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

# What makes a directory this repository's root: the script that cuts a claim.
HERE = Path(__file__).resolve().parent
BASE_MARKER = Path("scripts") / "campaign-claim.py"
# `<slug>-<YYMMDD>`: AGENTS.md's shape for a campaign directory at the root.
CAMPAIGN_DIR = re.compile(r"-\d{6}$")
# The claim's shape. Only `<N>` is read from it.
CLAIM_BRANCH = re.compile(r"^campaign-(\d+)/(\d+)-")

# A name that resolved to no role, as distinct from a role that could not
# be read at all. The table's last row refuses this one; the other falls
# back to the claim reading.
NO_ROLE = "no-role"
NAMELESS = ("A session with no campaign name has no role, and a session with "
            "no role is refused on both planes. Name it: "
            "scripts/campaign-name-session.py <pane> campaign-<N>-<role>-<n>")
FILE_TOOLS = {"Edit", "Write", "NotebookEdit", "MultiEdit"}
PATH_KEYS = ("file_path", "notebook_path", "path")

WRITES = {("issue", v) for v in "close edit comment reopen develop transfer "
          "delete pin unpin lock unlock".split()} \
    | {("pr", v) for v in "create merge comment review edit close reopen ready "
       "lock unlock".split()} \
    | {("label", v) for v in "create edit delete".split()}
# Flags whose value is a separate word, skipped when the subcommand is sought.
VALUED = {"-R", "--repo", "-X", "--method", "-H", "--header", "-F", "--field",
          "-f", "--raw-field", "-b", "--body", "-t", "--title", "-m",
          "--body-file", "-l", "--label", "-a", "--assignee", "--milestone"}
API_WRITE_FLAGS = {"-F", "--field", "-f", "--raw-field", "--input"}
SEPARATORS = {";", "&&", "||", "|", "&", "|&", "(", ")", "{", "}", "`"}
# Words before a command that are not it, and shells that run a string.
PREFIXES = {"env", "command", "time", "nohup", "sudo", "exec", "do", "then",
            "else", "builtin", "nice"}
# A NAMED LIST, not the category: there is no test for "is a shell", so a shell
# absent from this set has its `-c` string unread like any other interpreter's.
# Adding a name reads one more form and promises nothing about the next.
SHELLS = {"sh", "bash", "zsh", "dash", "ksh", "fish"}
# Words whose OPERAND is itself a command string, re-read as one.
EVALS = {"eval"}


def name_pattern():
    """`campaign-name-session.py`'s NAME regex, imported rather than restated.
    That script owns the shape; a second copy here would admit names it
    refuses, and the two would drift apart on the first change to either."""
    src = HERE / "campaign-name-session.py"
    spec = importlib.util.spec_from_loader(
        "cns", importlib.machinery.SourceFileLoader("cns", str(src)))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m.NAME


def role_of(session_id):
    """(campaign issue, role, how). THREE OUTCOMES, KEPT APART, because they
    license different things:

      * a name of the shape the pattern admits -- the role decides, per #185's
        table, and the campaign number bounds an executor;
      * a row found whose name is absent or of another shape -- LOOKED AND
        FOUND NOTHING, which the table's last row refuses;
      * herdr or the pattern unreadable -- COULD NOT LOOK, which falls back to
        the claim reading alone and prints that it did. This guard runs for
        every session on this machine, so a failed read must not wall them
        all; the floor is the pre-#185 behaviour, which is a gate and not a
        bypass.

    The second is returned as `NO_ROLE`; the third as `None`."""
    if not session_id:
        return None, None, "the payload carries no session id"
    try:
        pattern = name_pattern()
    except Exception as e:                  # noqa: BLE001 -- reported, not raised
        return None, None, ("could not read the name pattern from "
                            "campaign-name-session.py "
                            f"({e.__class__.__name__})")
    try:
        r = subprocess.run(["herdr", "agent", "list"], capture_output=True,
                           text=True)
    except OSError as e:
        return None, None, f"herdr could not run ({e.__class__.__name__})"
    if r.returncode != 0:
        return None, None, (f"herdr agent list exited {r.returncode}: "
                            f"{r.stderr.strip()[:100]}")
    try:
        rows = json.loads(r.stdout)["result"]["agents"]
    except (ValueError, KeyError, TypeError) as e:
        return None, None, ("could not parse herdr output "
                            f"({e.__class__.__name__})")
    if not isinstance(rows, list):
        return None, None, "herdr agents was not a list"
    for a in rows:
        if not isinstance(a, dict):
            continue
        if (a.get("agent_session") or {}).get("value") != session_id:
            continue
        name = a.get("name") or ""
        m = pattern.match(name)
        if not m:
            return None, NO_ROLE, (f"session {session_id} is named "
                                   f"{name or 'nothing'}, which the campaign "
                                   f"name pattern does not admit")
        role = "planner" if "-planner-" in name else "executor"
        return m.group(1), role, f"session {session_id} is {name}"
    return None, None, (f"no herdr row names session {session_id}, so its "
                        f"role could not be read")


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
    return r.stdout, None, 0


def checkout_of(path: Path):
    """(main checkout root, this checkout's toplevel, note) for the repository
    holding `path`, read from git and never from a filesystem walk: a linked
    worktree anywhere resolves to its main checkout. (None, None, note) when
    no repository holds it."""
    d = next(d for d in [path, *path.parents] if d.is_dir())
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
    """(inside?, where, checkout toplevel or None, campaign directory or None).

    Inside means campaign work: a base tree read through git, or a campaign
    directory read by shape. The last two are different questions and #185 needs
    both -- a campaign directory sits AT the base root, so a target under it is
    inside the base checkout too and `top` alone cannot tell the code plane from
    campaign-plane scratch."""
    main, top, note = checkout_of(target)
    by_git = main is not None and (main / BASE_MARKER).is_file()
    base = main if by_git else base_above(target)
    if base is None:
        return (False,
                f"in no base tree and no campaign directory ({note or main})",
                top, None)
    camp = campaign_dir_of(target, base)
    if camp is not None:
        return True, f"inside the campaign directory {camp}", top, camp
    return (True,
            f"inside the base {base}" + (f" (checkout {top})" if by_git else ""),
            top, None)


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
        elif line.startswith("prunable") and found and found[-1][0] == path:
            found.pop()                 # a directory git itself marks gone
    return found


def own_claim(cwd: Path):
    """(path, branch, source) when the checkout the session is STANDING IN is
    itself on a claim, else None.

    `held` sweeps one repository root's worktrees, and a member repository's
    clone under a campaign directory is not one of them -- it is a different
    repository. A delegate on its own pushed `campaign-<N>/...` branch there
    therefore read as holding no claim at all. This is the same branch reading
    `held` does, asked of the checkout at hand rather than of the base's
    worktree list."""
    _main, top, _note = checkout_of(cwd)
    if top is None:
        return None
    branch = git(["branch", "--show-current"], top)[0]
    branch = (branch or "").strip()
    if not branch or not CLAIM_BRANCH.match(branch):
        return None
    exists, source = ref_exists(branch, top)
    return (top, branch, source) if exists else None


def session_root(cwd: Path):
    """(root, how). The session's repository root, or the base above a cwd
    inside a campaign directory, or None."""
    main, _top, _note = checkout_of(cwd)
    # A REPOSITORY INSIDE A BASE IS STILL THAT BASE'S. Preferring the common dir
    # unconditionally resolved a cwd in `<base>/<campaign>/repos/<member>/` to
    # the member repository, which carries no marker -- so the ordinary delegate
    # shape read as "in no campaign" and every campaign-plane write there was
    # allowed unread, while `file_call` refused the same target. This is
    # `classify`'s fallback, mirrored, which is what makes the two halves ask
    # one question rather than two that agree on the suite's cases.
    if main is not None and (main / BASE_MARKER).is_file():
        return main, f"cwd {cwd} -> git common dir -> {main}"
    base = base_above(cwd)
    if base is not None:
        return base, (f"cwd {cwd} is inside {main}, which is no base; the base "
                      f"above it is {base}" if main is not None
                      else f"cwd {cwd} is under the base {base} outside any checkout")
    if main is not None:
        return main, f"cwd {cwd} -> git common dir -> {main}"
    return None, f"cwd {cwd} is under no repository and no base"


def held(repo_root, issue=None):
    """([(path, branch, source)], detail lines): the claimed branches checked
    out under `repo_root`, narrowed to sub-issue `issue` when given."""
    trees = worktrees(repo_root)
    if trees is None:
        return [], [f"git worktree list could not be read at {repo_root}"]
    out, detail = [], []
    claims = [(p, b, CLAIM_BRANCH.match(b)) for p, b in trees if CLAIM_BRANCH.match(b)]
    for path, branch, m in claims:
        if issue is not None and m.group(2) != str(issue):
            detail.append(f"{path} is on {branch}, not a claim on #{issue}")
            continue
        exists, source = ref_exists(branch, repo_root)
        (out if exists else detail).append(
            (path, branch, source) if exists else f"{path} is on {branch}, but {source}")
    if not claims:
        detail.append(f"no checkout under {repo_root} is on a campaign branch")
    return out, detail


def segments(command, depth=0):
    """The command's segments as token lists, or (None, why) when shlex will
    not split it. `punctuation_chars` makes `;`, `|`, `&` their own tokens."""
    lex = shlex.shlex(command, posix=True, punctuation_chars="();<>|&{}`")
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
    # A string another command runs is that string's segments too: a shell's
    # -c, spelled alone or last in a cluster (`bash -lc`), and eval's operands.
    for seg in list(out):
        word, rest = head(seg)
        if word is None:
            continue
        inners = []
        if word in SHELLS:
            i = next((j for j, t in enumerate(rest[:-1]) if is_dash_c(t)), None)
            if i is not None:
                inners = [rest[i + 1]]
        elif word in EVALS:
            inners = [t for t in rest[1:] if not t.startswith("-")]
        for text in inners:
            more, why = segments(text, depth + 1)
            if more is None:
                return None, why
            out += more
    # WHAT IS DELIBERATELY NOT READ, and why the line is here. A shell that
    # runs what it is HANDED -- `bash <<< '...'`, `... | bash` -- puts the
    # command in a quoted operand, where the `gh` is one word of one token.
    # Re-reading every multi-word token when such a shell is present closed
    # those two and cost more than they were worth: it refused
    # `gh issue create --body "...gh issue close 9..."` (the create exemption
    # defeated by its own body) and `git commit -m "fix gh issue close parsing"
    # && bash deploy.sh`, machine-wide, on a guard every session runs; and a
    # decoy `-b "gh issue close 7"` re-read into a SECOND issue number let a
    # claim on #7 admit a real write to #9. Both were found by review, and
    # both are the shape this design already declines: one more alternation
    # buys one more form and a new bypass. An operand handed to a shell is a
    # shell string, and a shell string is not read.
    return out, None


def is_dash_c(token):
    """A shell's -c, alone or last in a short-option cluster: `-c`, `-lc`."""
    return (len(token) > 1 and token[0] == "-" and token[1] != "-"
            and token[1:].isalpha() and token.endswith("c"))


def gh_token(token):
    """Whether this token names `gh` -- as the word, as a path, or as the VALUE
    of an assignment, which is how `G=gh; $G issue close 9` hides one."""
    if token.rsplit("/", 1)[-1] == "gh":
        return True
    if "=" in token and not token.startswith("-"):
        return token.split("=", 1)[1].rsplit("/", 1)[-1] == "gh"
    return False


def head(seg):
    """The segment's command word, prefixes and `VAR=x` assignments stripped,
    a path reduced to its basename; and the tokens from it on."""
    i = 0
    while i < len(seg) and (seg[i] in PREFIXES or ("=" in seg[i]
                            and not seg[i].startswith("-"))):
        i += 1
    if i >= len(seg):
        return None, seg
    return seg[i].rsplit("/", 1)[-1], seg[i:]


def gh_words(tokens):
    """The non-flag words after `gh`, a valued flag's value skipped."""
    words, i = [], 1
    while i < len(tokens):
        t = tokens[i]
        i += 2 if t in VALUED else 1
        if not t.startswith("-"):
            words.append(t)
    return words


def gh_write(tokens):
    """(is a write, what) for one segment whose first word is `gh`."""
    words = gh_words(tokens)
    if not words:
        return False, "gh with no subcommand"
    if words[0] == "api":
        # Over ALL tokens: `--method=X` carries its value and can be last,
        # where `-X X` cannot. Slicing the last token off read the attached
        # spelling as absent, which allowed the write.
        method = None
        for j, t in enumerate(tokens):
            if t.startswith("--method="):
                method = t[9:].upper()
                break
            if t in ("-X", "--method") and j + 1 < len(tokens):
                method = tokens[j + 1].upper()
                break
        if method:
            return method != "GET", f"gh api {method}"
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


def issue_target(tokens):
    """The issue number a `gh issue <verb> <n>` names, or None. A write that
    names its sub-issue is narrowed to a claim on it."""
    words = gh_words(tokens)
    if words[:1] != ["issue"]:
        return None
    for t in words[2:]:
        # A PATH IS NOT AN ISSUE NUMBER. Reading the tail of any token with a
        # slash made `--body-file /tmp/123` name issue #123 and refused the
        # write for a claim on a number nobody typed. Only a GitHub issue URL
        # has a tail worth reading; everything else must BE the number.
        bare = t.lstrip("#")
        if bare.isdigit():
            return bare
        if "/issues/" in t:
            tail = t.rstrip("/").rsplit("/", 1)[-1]
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
        "<issue> <topic>, then work in a checkout on its branch.")


def file_call(tool, target: Path, cwd: Path, session_id=""):
    inside, where, top, camp = classify(target)
    if not inside:
        return allow([f"{tool} -> {target} is {where}; not campaign work."])
    read = [f"{tool} -> {target}, {where}."]
    campaign, role, how_role = role_of(session_id)
    read.append(how_role)
    if role == NO_ROLE:
        return refuse(read + [NAMELESS])
    if role == "planner":
        # A PLANNER NEVER TOUCHES CODE, and a checkout is where code lives:
        # a base tree, a linked worktree, a delegate clone, a member
        # repository. A campaign DIRECTORY is campaign-plane scratch, which a
        # planner is precisely for -- refusing it would stop a planner keeping
        # the notes it plans from, and #185 puts the campaign directories on
        # the campaign plane beside the issues.
        #
        # NOT keyed on `top`: a campaign directory sits at the base root, so a
        # target under it is inside the base checkout as well and `top` is set
        # for both. `camp` is the question actually being asked.
        if camp is None and top is not None:
            return refuse(read + [
                f"a planner may not change code, and {target} is in the "
                f"checkout {top}.",
                "Hand it to an executor: a session of its own on this "
                "machine, or a herdr delegate in the repository clone.",
            ])
        return allow(read + ["a planner writes the campaign plane, and a "
                             "campaign directory outside every checkout is "
                             "campaign-plane scratch."])
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
    if role == "executor" and campaign is not None:
        # ITS OWN CAMPAIGN AND NO OTHER. The clauses ask whether SOME claim
        # covers the target; the name says which campaign this session is of,
        # so a claim of another campaign is not this session's to stand on.
        kept = [h for h in holders
                if CLAIM_BRANCH.match(h[1]).group(1) == campaign]
        if holders and not kept:
            return refuse(read + [
                f"the claims under {root} are of another campaign, and this "
                f"session is of campaign #{campaign}.",
                *[f"{h[0]} is on {h[1]}" for h in holders], TAKE])
        holders = kept
    if holders:
        path, branch, source = holders[0]
        return allow(read + [f"Clause 2 (the weaker gate; the commit gate is "
                             f"what holds): {how}; {path} is on {branch}, a "
                             f"claim ({source})."])
    return refuse(read + [f"Clause 2 does not hold: {how}.", *detail, TAKE])


def bash_call(command, cwd: Path, session_id=""):
    segs, why = segments(command)
    if segs is None:
        return refuse([why, "A gh call this cannot split is not read as harmless."])
    gh, stray = [], []
    for seg in segs:
        word, rest = head(seg)
        if word == "gh":
            gh.append((rest, *gh_write(rest)))
        elif any(gh_token(t) for t in seg):
            # A form not listed, a heredoc, xargs: read as a write of unknown
            # kind, because nothing downstream reads a gh write.
            stray.append(" ".join(seg)[:60])
    writes = [rest for rest, is_write, _ in gh if is_write]
    if not writes and not stray:
        return allow([f"{what}." for _, _, what in gh]
                     + ["The command was not read for a target: only a file "
                        "tool's path and a gh write are; its write, if any, is "
                        "gated where it lands, by the pre-commit claim gate."])
    what = ", ".join([w for _, is_write, w in gh if is_write]
                     + [f"a `gh` this cannot read as a call, in `{x}`" for x in stray])
    campaign, role, how_role = role_of(session_id)
    if role == NO_ROLE:
        return refuse([f"{what}: a campaign-plane write.", how_role, NAMELESS])
    if role == "planner":
        # THE ROW THAT PROMPTED #185. A planner writes the campaign plane of
        # ANY campaign -- a comment on a campaign issue it does not work, a
        # sub-issue body, a close, a claim cut for a delegate. There is no
        # claim to hold for any of those, which is why the claim reading alone
        # had no passing form for them and the closes were run by hand.
        return allow([f"{what}: {how_role}, and a planner writes the campaign "
                      f"plane of any campaign."])
    root, how = session_root(cwd)
    # A repository is not a base. `session_root` answers "which repository root"
    # and any git checkout has one, so gating on `root is None` alone walled
    # every campaign-plane write from every unrelated repository on the machine
    # -- and this guard is registered for every session. The marker is what
    # `file_call` already decides on, so both halves ask the same question.
    if root is None or not (root / BASE_MARKER).is_file():
        why = how if root is None else f"{how}, which is a repository and not a base"
        return allow([f"{what}: {why}, so this session is in no campaign."])
    # EVERY issue named must be covered, not one of them. Collapsing two to
    # `None` and asking for any claim at all is a WIDENING: it let a claim on
    # #7 admit `gh issue close 9; gh issue close 7`, and a decoy naming a
    # claimed issue was the shape a review turned into a bypass. A write whose
    # issue this could not read still falls back to the unnarrowed question,
    # which is the weaker gate and is printed as such.
    if role == "executor" and campaign is not None:
        mine, foreign = [], []
        for h in held(root)[0]:
            (mine if CLAIM_BRANCH.match(h[1]).group(1) == campaign
             else foreign).append(h)
        if foreign and not mine:
            return refuse([f"{what}: a campaign-plane write, and every claim "
                           f"under {root} is of another campaign.", how_role,
                           *[f"{h[0]} is on {h[1]}" for h in foreign], TAKE])
    issues = sorted({issue_target(x) for x in writes} - {None})
    unreadable = stray or any(issue_target(x) is None for x in writes)
    own = own_claim(cwd)
    detail, uncovered, covering = [], [], []
    for i in issues:
        holders, d = held(root, i)
        if not holders and own is not None and CLAIM_BRANCH.match(own[1]).group(2) == i:
            holders = [own]
        detail += d
        (covering if holders else uncovered).append((i, holders))
    if uncovered:
        i = uncovered[0][0]
        return refuse([f"{what}: a campaign-plane write, and this session holds "
                       f"no claim covering a write to #{i}.", how, *detail, TAKE])
    if unreadable:
        holders, d = held(root)
        if not holders and own is not None:
            holders = [own]
        if not holders:
            return refuse([f"{what}: a campaign-plane write, and this session "
                           f"holds no claim covering it.", how, *detail, *d, TAKE])
        path, branch, source = holders[0]
        return allow([f"{what}: {how}; {path} is on {branch}, a claim "
                      f"({source})."])
    if not covering:
        if own is not None:
            return allow([f"{what}: the session's own checkout {own[0]} is on "
                          f"{own[1]}, a claim ({own[2]})."])
        return refuse([f"{what}: a campaign-plane write, and this session holds "
                       f"no claim covering it.", how, *detail, TAKE])
    path, branch, source = covering[0][1][0]
    named = ", ".join(f"#{i}" for i, _ in covering)
    return allow([f"{what}: {how}; {path} is on {branch}, a claim "
                  f"({source}). It covers {named}."])


def pre(payload):
    session_id = payload.get("session_id") or ""
    tool = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}
    try:
        cwd = Path(payload.get("cwd") or os.getcwd()).resolve()
        if tool in FILE_TOOLS:
            raw = next((tool_input.get(k) for k in PATH_KEYS if tool_input.get(k)),
                       None)
            if not raw:
                return refuse([f"{tool} names no path this can read."])
            target = cwd / Path(os.path.expanduser(str(raw)))
            return file_call(tool, target.resolve(), cwd, session_id)
    except (OSError, RuntimeError) as e:
        return refuse([f"a path would not resolve ({e.__class__.__name__})."])
    if tool == "Bash":
        return bash_call(tool_input.get("command") or "", cwd, session_id)
    return 0


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError) as e:
        return refuse([f"the hook payload would not read ({e.__class__.__name__})",
                       "A guard that was handed nothing has permitted nothing."])
    event = payload.get("hook_event_name", "")
    if event and event != "PreToolUse":
        return refuse([f"registered on {event}, but this is a PreToolUse guard and "
                       f"blocks nothing there. Re-run scripts/install-hooks.sh."])
    return pre(payload)


if __name__ == "__main__":
    sys.exit(main())
