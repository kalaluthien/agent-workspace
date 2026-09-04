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

The pattern is matched against the command with its PROSE spans blanked
(`outside_quotes`): the argument of --body, --title, --message, -m, -t is text
a service is handed, and `gh issue create --body "... git mv ..."` must file
the issue whose number the claim is minted from. Every other quoted span stays
visible, because the sinks that execute text cannot be listed.

It is also matched with every HYPHENATED WORD blanked (`verb_match`), the one
local layer that subtracts from the imported pattern rather than adding to it:
`\binstall\b` matches `install-hooks.sh` because `-` is a word boundary, and a
fresh clone with no claim must be able to run the installer. A word after
`git ` is left alone, so `git merge-file` and `git commit-tree` are still read
as the `git merge` and `git commit` forms the pattern names. The mask serves
the search only; operands are read from the command as written.

That pattern has no opinion about service doors, because a takeaway check does
not need one. The three `gh` writes a claim actually gates -- closing, editing
and commenting on an issue, and merging a pull request -- are added here, in
SERVICE_DOORS, and are this script's own. Nor does it know `sed`'s long
`--in-place` spelling, which a takeaway check can miss and a claim guard
cannot, since this is the exact word write_targets() reads its target from --
added here too, in IN_PLACE_SED.

An import that fails is a refusal, not a pass: a guard that cannot read the
pattern it guards by has permitted nothing.

WHAT IT WRITES TO, WHICH IS NOT THE SAME QUESTION AS WHERE IT SITS

A claim is a record about campaign work, so the guard owns a change that lands
on campaign work: a target inside a base tree, or inside a campaign
directory at the root. A target in neither -- `/tmp`, `$HOME`, another
checkout entirely -- is allowed whatever claim the session holds, because
refusing it enforces nothing about a sub-issue and stops every scratch write a
session in the base makes.

The target is read from the tool: the path field for a file tool, and for
`Bash` the OPERANDS OF THE CHANGING FORMS THAT MATCHED -- the word a redirect
writes to, the files of `tee` and `sed -i`, the non-option arguments of `mv`,
`rm`, `cp`, `mkdir`, `touch` and `install`, slashless ones included, and an
attached `--flag=value` when the value SAYS it is a path, a value that says
nothing being unread rather than resolved -- resolved against the payload's
cwd. Never the set of words that merely look like paths: a command's slashed
words include its remote, its sed script and the file its stderr goes to, and
none of those is what it changes, so reading them as the target allows `cp
/tmp/x.md AGENTS.md` on the strength of the operand it is not writing to.

Three writes have no filesystem target at all and are never read for one: a
`SERVICE_DOORS` `gh` call, because the campaign plane is GitHub issues; a `git
commit|push|merge|tag|revert|rebase`, whose target is the repository; and an
HTTP `POST|PATCH|PUT|DELETE`. Each falls through to the claim reading whatever
paths it carries, `git push 2>/tmp/err.log` included.

Bash's reading is all-or-nothing and its empty case is NOT an allow. Every
operand of every matched form outside allows; one operand inside, a form whose
operands cannot be read, or NO readable form at all falls through to the claim
reading below. Those causes are printed apart -- the form and why it was
unread, against the operands and what each resolved to -- because a guard that
did not read a target has looked and found nothing, which is not the same as
looking and finding it elsewhere.

WHICH CAMPAIGN, AND WHAT IT DOES WHEN IT CANNOT TELL

The base root is the topmost ancestor of `cwd` holding this repository's
own marker, so a linked worktree under `.claude/worktrees/` and a delegate's
clone under `<campaign>/repos/<repo>/` both resolve to it rather than to
themselves. No base above `cwd` means this session is not in a campaign at
all and the hook exits 0 -- it is installed machine-wide and most sessions on
this machine are nobody's campaign.

Inside a base, the directories searched are: the one campaign directory
`cwd` sits in, if it sits in one; otherwise every campaign directory at the
root. The union is deliberate, and it is what makes the base root
answerable at all: a session there could be working either open campaign, and
the question the guard can actually decide is not "which campaign is this" but
"does this session hold a claim anywhere on this machine". Refusing on the
ambiguity instead would refuse every write in the base whenever two
campaigns are open.

A base with no campaign directory exits 0. A campaign directory with no
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
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent

# What makes a directory this repository's root rather than any checkout with an
# AGENTS.md in it -- and the campaign directory beside it has one of those. The
# marker is a script this repository owns, so a root it names is a base and not
# any tree that happens to carry instructions.
BASE_MARKER = Path("scripts") / "campaign-claim.py"

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

# `sed`'s own long in-place spelling: this script's own, layered on the
# imported pattern the same way SERVICE_DOORS is. `changing_command` only
# knows the short `sed -i`; a takeaway check can tolerate missing the long
# one, but a claim guard that reads its target from exactly this word cannot
# -- `sed --in-place=...` used to bypass it entirely, read as "not a changing
# call" before target_reading ever ran.
IN_PLACE_SED = re.compile(r"\bsed\b[^|;&]*--in-place\b")

# A verb of the imported pattern glued to a hyphen is a name, not a verb:
# `install-hooks.sh` is the file a fresh clone must run, and `\binstall\b`
# matches it because `-` is a word boundary. So the pattern is searched on a
# copy with every hyphenated word blanked. Only the search sees the copy; the
# operands are read from the command as written. `--in-place` and `-i` start
# with a hyphen and are not hyphenated words, so IN_PLACE_SED and `sed -i`
# still read. A word after `git ` is not blanked: `git merge-file` writes its
# first operand in place and `git commit-tree` writes an object, and the
# pattern's `git (commit|merge|...)` alternation must keep reading them.
HYPHENATED_WORD = re.compile(r"(?<!\bgit )\b\w[\w.]*(?:-[\w.]+)+\b")


def verb_match(changing_command, text):
    """The imported pattern's match on `text`, with hyphenated names blanked."""
    return changing_command.search(HYPHENATED_WORD.sub("_", text))


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


def base_root(cwd: Path):
    """The topmost ancestor of cwd that is this repository's root, or None.

    Topmost and not nearest: a linked worktree is itself a checkout of this
    repository and holds the marker, and stopping there would resolve to a tree
    that has no campaign directory under it and read as "not in a campaign"."""
    found = None
    for d in [cwd, *cwd.parents]:
        if (d / BASE_MARKER).is_file():
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


# ------------------------------------------------------------- the record
#
# RELOCATED FROM campaign-claim.py BY #176, AND ONLY UNTIL #177. That script
# no longer knows what a record is: a claim there is the branch on the remote,
# and attribution is read off `git worktree list`. This guard is the last
# reader of `runtime/claims/`, so the record's shape lives here now rather than
# being imported from a script that has stopped writing one. #177 rewrites this
# guard to read the branch and deletes all six of these together with the
# directory they read.


RELEASED = "released"


def is_released(rec):
    """True when this record has been marked released. A released record is
    attribution kept on purpose, never a claim: it licenses no write."""
    return bool(rec) and bool(rec.get(RELEASED, "").strip())


def mark_released(path, rec, by):
    """Append the release mark, keeping every field the record already had."""
    body = "".join(f"{k} {v}\n" for k, v in rec.items() if k != RELEASED)
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    path.write_text(body + f"{RELEASED} {stamp} by {by}\n")
    return stamp


def read_record(path):
    """The record's fields, or None when there is none. A file that will not
    decode is a reading that failed -- reported by the caller through the
    `unreadable` field -- never a traceback."""
    if not path.exists():
        return None
    try:
        text = path.read_text()
    except (OSError, UnicodeDecodeError) as e:
        return {"unreadable": f"{e.__class__.__name__}"}
    return fields_of(text)


def fields_of(text):
    """A record's `key value` lines as a dict. One parser, so `status` and
    `live` cannot disagree about what a record says."""
    fields = {}
    for line in text.splitlines():
        if " " in line:
            k, v = line.split(" ", 1)
            fields[k] = v.strip()
    return fields


def claim_records(claims):
    """Returns (records, unread). A claim this cannot read is named rather than
    dropped, exactly as parse_agents counts a row it cannot identify: the number
    a close gate reads must not shrink because something was skipped.

    `unread` is a check that did not happen, so it denies the clean verdict the
    way a failed herdr read does."""
    recs, odd = {}, []
    for p in sorted(claims.iterdir()):
        if not p.is_file():
            odd.append(f"{p.name} is not a file, so it holds no claim")
            continue
        try:
            text = p.read_text()
        except (OSError, UnicodeDecodeError) as e:
            odd.append(f"{p.name} will not decode ({e.__class__.__name__}), "
                       f"so what it claims is unknown")
            continue
        recs[p.name] = fields_of(text)
    return recs, odd


def claims_of(directory):
    """(records, refusal) for one campaign directory. A missing claims/ is the
    refusal; an empty one is a reading."""
    claims = directory / "runtime" / "claims"
    if not claims.is_dir():
        return None, (f"{claims} does not exist, so no claim here can be "
                      f"enumerated. An empty directory says no claim was "
                      f"taken; a missing one says nothing.")
    recs, unread = claim_records(claims)
    return (recs, unread), None


def held_by(records, session_id, issue=None):
    """The records this session holds, unreleased. `issue` narrows to one.

    The released test is `is_released` above, so what "released" means is
    written once, beside the mark itself."""
    out = []
    for name, rec in sorted(records.items()):
        if issue is not None and name != str(issue):
            continue
        if rec.get("session", "") != session_id:
            continue
        if is_released(rec):
            continue
        out.append((name, rec))
    return out


QUOTED = re.compile(r'"(?:[^"\\]|\\.)*"|\'[^\']*\'')
# The flags whose argument is prose handed to a service, never run: an issue
# or pull request body or title, a commit message, release notes.
# Only in a `gh` segment: `xargs -t '...'` and `-m` on any other program are
# not prose sinks, and blanking after them would hide what they run.
PROSE_SINK = re.compile(r"\bgh\b[^|;&]*(?:--body|--title|--message|--notes|-m|-t)(?:\s*=|\s+)$")
# What the shell still runs inside a double-quoted prose span: the head of a
# command substitution, up to its first newline or closing paren.
SUBST_HEAD = re.compile(r"\$\(([^\n)]*)|`([^\n`]*)")


def outside_quotes(command):
    """The command with its prose spans blanked, so a pattern matched against
    it sees the words the shell runs and not the text a service is handed.
    `gh issue create --body "... git mv a b ..."` files an issue; the `mv` in
    its body is prose, and matching it refused the one step that cannot hold
    a claim yet, since the number is minted there.

    A sink counts only inside a `gh` segment; `xargs -t '...'` is not one.
    Every other quoted span is kept whole, whatever it follows: `eval`, `-c`,
    `ssh host "..."`, a string piped into a shell -- the sinks that execute
    text cannot be listed, so nothing is hidden by default. A prose span is
    blanked except for the head of each `$(...)` or backtick inside a
    double-quoted one, which the shell does run: `--body "$(cat <<'EOF'"` keeps
    `cat <<'EOF'`, `--body "$(git mv a b)"` keeps `git mv a b`. Inside single
    quotes `$(` is literal and the span is blanked whole."""
    # Built left to right, and the sink scan reads the OUTPUT so far: an
    # earlier prose span already blanked cannot hide the `gh` segment with a
    # `&` or `|` of its own (`--title "R&D" --body "..."`).
    out, pos = [], 0
    for m in QUOTED.finditer(command):
        out.append(command[pos:m.start()])
        span = m.group(0)
        if not PROSE_SINK.search("".join(out)):
            out.append(span)
        elif span[0] == "'":
            out.append("''")
        else:
            heads = [a or b for a, b in SUBST_HEAD.findall(span)]
            out.append('"' + " ; ".join(heads) + '"')
        pos = m.end()
    out.append(command[pos:])
    return "".join(out)


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
    if IN_PLACE_SED.search(command):
        return True, "the command runs sed's long in-place spelling"
    if verb_match(changing_command, command):
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


# A shell word: everything the shell's own separators leave standing.
SHELL_WORD = re.compile(r"[^\s;|&<>()]+")
# Where one command ends and the next begins, which is what attributes an
# operand to the command that takes it. `&` is a separator except after `>`,
# where it is a descriptor duplication and not a background job.
SEGMENT = re.compile(r"\|\||&&|[;\n|]|(?<!>)&")
# `2>&1`, `>&-`: a duplication, not a file. Removed before redirects are read.
FD_DUP = re.compile(r"[0-9]*>&[0-9-]+")
# A file redirect and the word it writes to, which may be absent (`>&2` after
# the duplication strip, `> $LOG` with nothing after it).
REDIRECT = re.compile(r"[0-9]*>>?\s*([^\s;|&<>()]*)")
# A word whose value this cannot know: an expansion, a substitution, a glob.
# Reading one as a literal path would resolve a name that never existed.
UNRESOLVABLE = re.compile(r"[$*?\[\]{}`]")

# The three writes with NO filesystem target. Each is a fall-through and never
# an allow: the campaign plane is GitHub issues, a git write's target is the
# repository, and an HTTP write's is a service -- so a path anywhere in such a
# command is a log, a message file or a body, never what the call changes.
GIT_WRITE = re.compile(r"\bgit\b[^|;&]*\b(?:commit|push|merge|tag|revert|rebase)\b")
HTTP_WRITE = re.compile(r"(?:-X|--method)\s*=?\s*[\"\']?(?:POST|PATCH|PUT|DELETE)\b",
                        re.IGNORECASE)

# The changing forms whose write target IS an operand, and can therefore be
# read. Anything else that matched the changing-command pattern -- a package
# install, a chmod, an interpreter running a script -- is not here and falls
# through, because a form this cannot parse is a target it did not read.
FILE_COMMANDS = {"mv", "rm", "cp", "mkdir", "touch", "install"}
OPT_WITH_ARG = {"-e", "-f", "--expression", "--file"}


def is_sed_in_place(word):
    """Whether a `sed` argument is the in-place flag itself: short
    `-i[SUFFIX]` attached, or long `--in-place` bare or `--in-place=SUFFIX`
    attached. Read by both the dispatch in write_targets() and sed_files()
    itself, so the two agree on what the flag looks like."""
    return (word.startswith("-i") or word == "--in-place"
            or word.startswith("--in-place="))


def resolve_target(token, cwd):
    """(absolute path, why_unreadable) for one path token."""
    try:
        p = Path(os.path.expanduser(token))
        p = p if p.is_absolute() else cwd / p
        return p.resolve(), None
    except (OSError, RuntimeError, ValueError) as e:
        return None, f"{token!r} would not resolve ({e.__class__.__name__})"


def lands_outside(target: Path, root: Path, dirs):
    """(True, None) when the target is in no base tree and no campaign
    directory; (False, what it is inside) otherwise.

    `base_root` and not `root` alone: another checkout of this repository
    -- the main one, seen from a worktree -- is a base tree too, and a
    write into it is campaign work read from the wrong side."""
    other = base_root(target)
    if other is not None:
        return False, f"inside the base {other}"
    if target == root or root in target.parents:
        return False, f"inside the base {root}"
    for d in dirs or ():
        if target == d or d in target.parents:
            return False, f"inside the campaign directory {d}"
    return True, None


def looks_like_path(value):
    """Whether an attached option value says on its own that it is a path.

    A value carrying no separator is indistinguishable from a mode, a keyword
    or a name -- `--interactive=never` and `--target-directory=scripts` are the
    same word shape -- so only a value that says it is a path is read as one.
    Bare `.` and `..` and a `~` prefix say it without a separator."""
    return "/" in value or value in (".", "..") or value.startswith("~")


def operands(args):
    """(the non-option words, why one of them could not be read).

    An option's own SEPARATE argument is kept as an operand: reading it as a
    path resolves a word that is not one, and that direction is the refusing
    one. An ATTACHED one on a LONG option is the write target itself in
    `--target-directory=.`, so a `--x=value` word contributes its value -- but
    only a value that looks like a path, because `--interactive=never`
    contributes `never`, and resolving that against the base names a
    location nothing in the command asked for. A value that does not look like
    a path is UNREAD, which still refuses; it just refuses for what was read.

    A SHORT option's attached value cannot be told from a flag cluster without
    a table per command -- `-rf` is two flags and `-t.` is a target -- so a
    short word whose tail is not purely alphabetic is UNREAD rather than
    guessed either way. That keeps `-p`, `-rf`, `-r` and `-a` reading as flags
    and refuses `-t.`, `-m755` and anything else carrying a value, at the cost
    of never allowing those. The `=` split is a LONG-option syntax only: a
    short option has no `=` separator, so GNU tools read `-t=/tmp/d` as `-t`
    with the attached value `=/tmp/d`, `=` included -- splitting on it first
    reads the value as `/tmp/d` instead, one directory level up from the
    target `cp` really writes to. A short word's tail is checked whole, `=`
    included, which is exactly what makes it non-alphabetic and UNREAD. A `--`
    word is never a cluster, so the test does not reach one: `--no-clobber` is
    a flag and contributes no operand."""
    out, rest = [], False
    for word in args:
        if rest or not word.startswith("-"):
            out.append(word)
            continue
        if word == "--":
            rest = True
            continue
        if word.startswith("--"):
            if "=" in word:
                value = word.split("=", 1)[1]
                if not looks_like_path(value):
                    return None, (f"word {word!r} attaches a value that does "
                                  f"not say it is a path, so whether that "
                                  f"value is a write target is not readable")
                out.append(value)
            continue      # never a flag cluster; a value it carried, if any,
                          # was already appended above
        tail = word.lstrip("-")
        if tail and not tail.isalpha():
            return None, (f"word {word!r} may be an option's attached value, "
                          f"which this guard cannot tell from a flag cluster, "
                          f"so its operands are not readable")
    return [w for w in out if w], None


def sed_files(args):
    """(the file operands of `sed -i`, why one of them could not be read).

    The script is a file operand too until an `-e` or `-f` puts it elsewhere
    -- separate (skipped as that option's own following word) or attached
    long (`--expression=script`) -- and BSD's `-i ''` suffix is the empty
    word, dropped below with every other empty one.

    The in-place flag ITSELF, whatever spelling dispatched here
    (`is_sed_in_place`), contributes nothing: `--in-place=SUFFIX` is not a
    `--flag=value` word whose value might be a target, and reading it as one
    would run `looks_like_path` on a backup suffix like `.bak`, refusing the
    call for a value that was never a candidate.

    Every OTHER long option's `=`-attached value follows operands()'s own
    rule: a value that looks like a path is kept as a file operand, one that
    says nothing about being a path is UNREAD, which refuses the whole call
    rather than guess which it is -- EXCEPT `--expression`, whose value is a
    sed SCRIPT and never a file, path-shaped or not: `s/a/b/` has a `/` and
    would otherwise be misread as the write target `looks_like_path` exists
    to recognise. Before the `=`-aware rule existed, none of `--in-place=`,
    `--expression=` or `--file=` were recognised as supplying anything either
    way: the whole word was excluded for starting with `-`, and with no
    signal that a script had been supplied, the guess below took the one
    remaining file operand for the script and dropped it too -- `sed -i
    --expression=foo.sed file.txt` lost `file.txt` silently rather than
    reading it.

    A short word carrying its own `=` -- `-e=text` and the like -- is UNREAD
    for the reason operands() refuses `-t=/tmp/d`: sed has no `=` syntax for
    a short option, so this cannot be told from a flag cluster. Every OTHER
    short word is untouched, `-i.bak`'s attached suffix included: sed's own
    attached-suffix convention for `-i` is not the ambiguity this closes, and
    refusing it would break the ordinary call this function exists to read."""
    files, skip, supplied = [], False, False
    for word in args:
        if skip:
            skip = False
            continue
        if not word.startswith("-"):
            files.append(word)
            continue
        if is_sed_in_place(word):
            continue                            # the flag itself, no value
        if word.startswith("--"):
            if "=" in word:
                flag, value = word.split("=", 1)
                if flag == "--expression":
                    supplied = True             # a script, never a file
                elif not looks_like_path(value):
                    return None, (f"word {word!r} attaches a value that does "
                                  f"not say it is a path, so whether that "
                                  f"value is a write target is not readable")
                else:
                    files.append(value)
                    supplied = supplied or flag in OPT_WITH_ARG
            continue
        tail = word.lstrip("-")
        if "=" in tail:
            return None, (f"word {word!r} may be an option's attached value, "
                          f"which this guard cannot tell from a flag cluster, "
                          f"so its operands are not readable")
        skip = word in OPT_WITH_ARG
        supplied = supplied or skip
    files = [f for f in files if f]
    if not supplied and files:
        files = files[1:]                       # the first word is the script
    return files, None


def write_targets(command, changing_command):
    """([(form, operand)], None), or (None, why it could not be read).

    The targets of the changing forms that MATCHED, never the set of words
    that look like paths: a command's slashed words include its remote, its
    sed script and the file its stderr goes to, none of which is what it
    changes, and reading those as the target lets `cp /tmp/x.md AGENTS.md`
    through on the strength of the operand it is not writing to.

    Every segment answers for itself. A segment that is CHANGING ON ITS OWN --
    read with its redirects stripped, so the redirect cannot be what makes it
    changing -- and yields no readable form is unread for the whole command,
    because otherwise a readable operand elsewhere answers for it and
    `sh -c 'rm -rf scripts' > /tmp/log` reads as a write to /tmp. `echo hi >
    /tmp/x` is what this must not catch: `echo` is not changing on its own, so
    there the redirect genuinely is the write."""
    if SERVICE_DOORS.search(command):
        return None, ("the command writes to the campaign plane through gh, "
                      "which is GitHub issues and has no filesystem target")
    if GIT_WRITE.search(command):
        return None, ("the command is a git write, whose target is the "
                      "repository and not any path in the command")
    if HTTP_WRITE.search(command):
        return None, ("the command makes a writing HTTP request, whose target "
                      "is a service and not any path in the command")
    found = []
    for segment in SEGMENT.split(command):
        seg = FD_DUP.sub(" ", segment)
        for m in REDIRECT.finditer(seg):
            if not m.group(1):
                return None, (f"a redirect in {segment.strip()!r} names no "
                              f"word this guard can read as its target")
            found.append(("redirect", m.group(1)))
        body = REDIRECT.sub(" ", seg)
        words = [w.strip("\"\'") for w in SHELL_WORD.findall(body)]
        while words and re.match(r"^\w+=", words[0]):
            words.pop(0)                        # a leading VAR=value
        if not words:
            continue
        head, args = words[0].rsplit("/", 1)[-1], words[1:]
        unreadable = None
        if head in FILE_COMMANDS:
            form, (ops, unreadable) = head, operands(args)
        elif head == "tee":
            form, (ops, unreadable) = "tee", operands(args)
        elif head == "sed" and any(is_sed_in_place(a) for a in args):
            form, (ops, unreadable) = "sed -i", sed_files(args)
        else:
            if verb_match(changing_command, body):
                return None, (f"the segment {segment.strip()!r} is a changing "
                              f"command on its own, and its target is not an "
                              f"operand this guard can read")
            continue
        if unreadable:
            return None, f"the `{form}` {unreadable}"
        if not ops:
            return None, (f"the `{form}` form in {segment.strip()!r} names no "
                          f"operand this guard can read")
        found += [(form, o) for o in ops]
    # The residual: a changing command in which no segment is changing on its
    # own and none yields a form -- a pattern match spanning a separator. No
    # case here reaches it, and it stays because the alternative to saying so
    # is an empty target set read as "everything it writes is outside".
    if not found:
        return None, ("no changing form whose target is an operand was found "
                      "in the command, so what it writes to is unknown")
    for form, word in found:
        if UNRESOLVABLE.search(word):
            return None, (f"the `{form}` operand {word!r} is an expansion or a "
                          f"glob, so the path it names cannot be read here")
    return found, None


def target_reading(payload, cwd, root, dirs, changing_command):
    """(verdict, line) -- what this call writes to, as far as it can be read.

    "outside" allows on its own; "inside" and "unread" fall through to the
    claim reading, and are named apart so an absent target never reads as one
    found elsewhere."""
    tool = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}
    if tool in FILE_TOOLS:
        raw = next((tool_input[k] for k in PATH_KEYS if tool_input.get(k)), None)
        if not raw:
            return "unread", f"{tool} carries no path field, so no target was read"
        target, why = resolve_target(str(raw), cwd)
        if why:
            return "unread", f"{tool} target {why}"
        outside, where = lands_outside(target, root, dirs)
        if outside:
            return "outside", f"{tool} target {target} is in no base tree " \
                              f"and no campaign directory"
        return "inside", f"{tool} target {target} is {where}"
    if tool != "Bash":
        return "unread", f"{tool} names no path this guard can read"
    targets, why = write_targets(
        outside_quotes(tool_input.get("command") or ""), changing_command)
    if targets is None:
        return "unread", why
    seen = []
    for form, word in targets:
        target, unreadable = resolve_target(word, cwd)
        if unreadable:
            return "unread", f"the `{form}` operand {unreadable}"
        outside, where = lands_outside(target, root, dirs)
        if not outside:
            return "inside", (f"the `{form}` operand {word!r} resolves to "
                              f"{target}, {where}")
        seen.append(f"`{form}` {word!r} -> {target}")
    return "outside", (f"every operand of every changing form read lands in no "
                       f"base tree and no campaign directory: "
                       f"{'; '.join(seen)}")


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
    """(cwd, root, dirs, note, refusal_lines) -- where this session is, or why
    the question could not be answered."""
    cwd = payload.get("cwd") or os.getcwd()
    try:
        cwd = Path(cwd).resolve()
    except OSError as e:
        return None, None, None, None, [f"cwd {cwd!r} would not resolve "
                                        f"({e.__class__.__name__})."]
    root = base_root(cwd)
    if root is None:
        return cwd, None, None, f"no base above {cwd}", None
    dirs, note = campaign_dirs(root, cwd)
    if dirs is None:
        return cwd, root, None, note, [note]
    return cwd, root, dirs, note, None


def pre(payload, changing_command):
    session_id = payload.get("session_id") or ""
    cwd, root, dirs, note, refusal_lines = setting(payload)
    if refusal_lines:
        return refuse(refusal_lines + [
            "This guard could not read where it is, which is not the same as "
            "reading that there is no claim to check."])
    if root is None:
        return 0                       # not a campaign session; not this hook's
    if not dirs:
        return 0                       # a base with no campaign on it

    is_changing, why = changing(payload, changing_command)
    if not is_changing:
        return 0

    verdict, where = target_reading(payload, cwd, root, dirs,
                                    changing_command)
    if verdict == "outside":
        print(f"check-campaign-claim: allowed, target outside. {where}.")
        return 0
    print(f"check-campaign-claim: target read as {verdict} -- {where}; "
          f"reading the claim.")

    if not session_id:
        return refuse([
            "the payload carries no session_id, so no record can be matched to "
            "this session.",
            f"read {root}; {note}",
            "A claim is attributed by session id and by nothing else."])

    command = (payload.get("tool_input") or {}).get("command") or ""
    issue = close_target(outside_quotes(command))

    found, unread, missing = {}, [], []
    for d in dirs:
        result, refusal_line = claims_of(d)
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
               for name, rec in held_by(recs, session_id, issue)]
    if holders:
        return 0

    detail = []
    for d, recs in found.items():
        if not recs:
            detail.append(f"{d.name}/runtime/claims/ is empty: no claim was "
                          f"taken here.")
        for name, rec in sorted(recs.items()):
            mark = " RELEASED" if is_released(rec) else ""
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
        # `--local` and `--dir` went with the record in #176; a refusal naming
        # a command the new argparse rejects sends the reader nowhere. The
        # remedy the RECORD needs is #177's to write, when this reads the
        # branch instead.
        "  scripts/campaign-claim.py take <campaign issue> <issue> <topic>",
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


def released(payload):
    """Mark a closed sub-issue's claim released. Always exits 0."""
    session_id = payload.get("session_id") or ""
    command = (payload.get("tool_input") or {}).get("command") or ""
    issue = close_target(outside_quotes(command))
    if not issue:
        return 0
    _cwd, root, dirs, note, refusal_lines = setting(payload)
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
        path = d / "runtime" / "claims" / str(issue)
        rec = read_record(path)
        if not rec or "unreadable" in rec:
            continue
        # Marked here rather than by shelling out to campaign-claim: since #176
        # that script writes no record and its `release` deletes a ref, which is
        # not what closing a sub-issue asks for. The mark is idempotent, so a
        # second close is not a failure.
        if is_released(rec):
            print(f"check-campaign-claim --released: {evidence}; "
                  f"{path} is already marked released.")
            return 0
        stamp = mark_released(path, rec, session_id)
        print(f"check-campaign-claim --released: {evidence}; "
              f"marked {path} released {stamp} by {session_id}")
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

    if post:
        return released(payload)

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
    return pre(payload, pattern)


if __name__ == "__main__":
    sys.exit(main())
