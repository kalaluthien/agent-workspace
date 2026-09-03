#!/usr/bin/env python3
"""Take, read and release a subtask's claim, and say who is alive holding one.

    campaign-claim.py take <N> <issue> <topic> [--local] [--repo owner/repo]
                           [--name NAME] [--session SID]
    campaign-claim.py status <issue>
    campaign-claim.py list
    campaign-claim.py release <issue> [--branch B] [--confirmed-absent WHO]
                              [--session SID]
    campaign-claim.py live <N> [--dir CAMPAIGN]
    campaign-claim.py alive <pid>

A claim is two things that must agree: a branch on the remote, which is what
actually stops two executors working one subtask, and a record on this machine
saying which session holds it. AGENTS.md says the record's shape is written in
exactly one place; this is that place. One script owns both halves, so there is
nothing to copy: a delegate runs `take`, a close or a sweep runs `list`,
`status` and `live`.

`--local`: THE RECORD ALONE, AND WHY IT IS STILL ATOMIC

Work that lands nothing in any repository -- a scaffold under `<campaign>/`, a
sweep, a decision written into the anchor -- has no commits for a branch to
carry, and cutting one costs a create-ref, a compare and a delete for a ref that
only ever held `main`. `take --local` writes the record and cuts nothing.

That moves the atomicity from create-ref's server-side refusal onto `O_EXCL`,
which is the same shape one filesystem down: the second taker's `open` fails and
it is told who holds the claim, exit 3. The record still names the branch the
work *would* have used, so `live`'s stray-branch reading keeps working, and
carries `local yes` so `release` knows there is no ref to delete.

The narrower guarantee is stated rather than hidden: `O_EXCL` serialises the two
takers on ONE machine, where create-ref serialises them across all of them. That
is the same ceiling the binding already sets -- one campaign, one machine -- so
`--local` gives up nothing a repo-less campaign had.

RELEASED IS A MARK, NOT A DELETION

A local claim is released by marking the record `released <timestamp>`, not by
removing it: the record is the only thing that ever attributed the subtask to a
session, and a close reads it afterwards. A released record licenses no write
and does not block a re-take -- an idempotency key naming what was asked for
rather than which attempt is the shape that refuses a repeat of work that has
returned to its starting state.

`--name` FROM ANOTHER CAMPAIGN IS REFUSED

A session that moved from one campaign to another keeps its old name unless
something sets it, and the record is where a stale name does lasting damage:
`list` prints `name` as the address to reach the holder. So `take` compares the
`campaign-<M>-` a name carries against the anchor and refuses when they differ,
naming both numbers. opening-campaign step 3 is the step that sets the name;
this is its second reader.


`--session` ON `take` IS THE LAUNCH-TIME PATH

A launcher must claim the branch before the delegate exists and must hold no
record of its own, and `take --session <the delegate's session id> --name
<its name>` is both at once: the ref is cut now, the record is attributed to
the delegate by the one field every join reads. The pid is written `unknown`
whenever `--session` names a session other than the caller's, because the
caller's pid would be a lie that `status` reads as the delegate's liveness.

`--session` ON `release` IS THE HOLDER'S OWN PROOF

`--confirmed-absent` exists because a THIRD party cannot tell a dead session
from a restarted one. The holder itself has no such problem: a caller whose
session id equals the record's `session` is the claimant, and its release needs
no absence established by anyone. `--session` is that proof, and it is also how
scripts/check-campaign-claim.py releases a claim on the holder's behalf, since a
hook is handed the `session_id` and has no environment to read it from.

The campaign directory comes from --dir or $CAMPAIGN. There is no default and no
search: guessing which directory is this campaign's is how a record lands in
another campaign's tree, and the caller always knows.

WHAT IT REFUSES TO GUESS

`name` is the harness name, which only the calling session can read (ListAgents'
first line). Left out, the record says so rather than carrying an invented name:
a wrong address sends a later reader to the wrong session, which is worse than
no address, because they will believe it.

`dead` is not proof of an absence. A harness restart gives a live session a new
pid, so its record reads dead while the session works on. `status` says so
whenever it can see the evidence -- a claude process that started after the
record was written -- and downgrades its verdict to `stale?`. A caller that
treats `dead` as "free to take" without reading that line takes a live claim.

`live` MAKES BOTH READINGS AND CONCLUDES FROM NEITHER

AGENTS.md says to make them both, every time, and they answer different
questions:

  herdr agent list       liveness, for every session on this machine, delegate
                         or not. It says nothing about which subtask a row holds.
  runtime/claims/        attribution, for every claim. Its pid reads dead after
                         a harness restart the session survived, so it locates a
                         session rather than proving one.

The join is by session id and by nothing else: `agent_session.value` is the same
value a record's `session` field holds, and the only field on either side that
survives both a harness restart and a rename. Never the name, which can change
while the claim it belongs to cannot -- one peer answered to three names in an
hour. Never the pid, which changes at a restart, the case this is trying to see.
`live` prints three groups and their counts and reaches no verdict; a close reads
the counts.

`alive` IS THE PID READING, AND ITS `dead` DELETES TREES

    stdout   exit  meaning                              may the caller take over?
    alive    0     a process holds the pid and its      no
                   name is one this install runs
    other    0     a process holds the pid and the      NO -- and not because the
                   name is not recognised               session is there; because
                                                        nothing here can tell a
                                                        recycled pid from an
                                                        install whose binary is
                                                        named differently
    dead     0     no process holds the pid             yes
    (stderr) 2     the reading itself failed            no

**Exit status is about the reading, never the verdict.** A failed read that
exited like `dead` deletes a tree under a live session, so a caller compares the
printed word and treats anything else, exit 2 included, as a refusal.

`kill -0` decides existence: a syscall against the caller's own process table, so
it cannot fail transiently the way running `ps` can. Safe about the *process*,
though, and not about the session -- a harness restart leaves a surviving session
holding a new pid, so a record written before one reads `dead`.

The name is read from `ucomm`, not `comm`. `ps -o comm=` reports how a process
was invoked, so one build can answer `claude` through a wrapper and its full path
when exec'd by path; comparing that against the literal calls a live executor
dead, which is the direction that deletes a working tree. `ucomm` is invariant
across *how* a process was started.

`ucomm` is NOT identity: it is the basename of the exec'd file, symlinks
resolved, truncated to MAXCOMLEN -- probed by copying a binary to a new name and
reading the new name back. So NAMES is a fact about this install, not about
claude, and it is why an unrecognised name is `other` rather than `dead`: the
literal is allowed to be wrong without a tree being deleted for it.

Two residuals stay, and stay stated here rather than in a caller:

  * A pid recycled onto a DIFFERENT claude session reads `alive`, and a pid
    recycled onto anything else reads `other`. Either way a caller refuses a
    takeover it should have been allowed, which is the safe direction. This
    paragraph is the only record of either form: the Alloy verdict that held
    the first was retired with the holder role, and no model in `spec/alloy/`
    represents a pid at all, so there is no longer a spec to defer to.
  * `alive` means a claude holds this pid, not that it is *this campaign's*
    session. The record carries a `session` name that nothing here compares,
    because a pid is all a record is guaranteed to carry.

A zombie -- exited, unreaped -- still answers `alive`: `kill -0` succeeds and
`ucomm` is unchanged. A caller sees a live executor it cannot retire.

scripts/check-rule-readers.py is the second reader that keeps the `alive` claim
true: it refuses a commit that stages a `ps` whose `-o` selector *opens* with
`comm`/`ucomm`, that selector passed as a Python list element, a bare quoted
`ucomm=`, or a `pgrep` -- as code in any tracked markdown outside scripts/. A
selector that puts another field first, `-o pid,ucomm`, is outside the claim.

EXIT

0 for a completed action or a clean read; 1 for a refusal or a half-made reading;
2 for an `alive` whose reading failed; 3 for `take` when the subtask is already
claimed, which is news rather than an error. Every verdict is on stdout, and the
reading that produced it is printed beside it.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

DEFAULT_REPO = "kalaluthien/agent-workspace"
SHA = re.compile(r"^[0-9a-f]{40}$")

# What the exec'd binary is called on this install. Not a property of claude.
NAMES = frozenset({"claude", "claude.exe"})


def run(*args, **kw):
    """A command that is not installed comes back as a failed run, not a
    traceback: `gh` absent, or `herdr` absent, is the "I could not look" case
    this script is written to report, and a stack trace loses the reason."""
    try:
        return subprocess.run(args, capture_output=True, text=True, **kw)
    except (FileNotFoundError, PermissionError) as e:
        return subprocess.CompletedProcess(
            args, 127, "", f"{args[0]}: {e.__class__.__name__}: {e}")


# ----------------------------------------------------------- the pid reading


def holds(pid: int) -> bool:
    """Is any process holding this pid? A syscall, so it cannot fail loosely.

    Returns None when the question itself could not be asked."""
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True                     # held by another user, so it is held
    except (OSError, OverflowError):
        return None
    return True


def name_of(pid):
    """(name, why_unreadable) for a pid `holds` says exists."""
    out = run("ps", "-o", "ucomm=", "-p", str(pid))
    if out.returncode != 0:
        return None, (f"ps -o ucomm= -p {pid} exited {out.returncode}: "
                      f"{out.stderr.strip() or 'no message'}")
    # `.strip()` is load-bearing, not tidying. `ps -o ucomm=` pads to a fixed
    # width -- `claude.exe` comes back as 16 characters -- and command
    # substitution strips trailing newlines but not spaces. Comparing the padded
    # form against a literal reads a live session as dead, which is this
    # reading's own bug one field over. Do not remove it as noise.
    name = out.stdout.strip()
    if not name:
        # The process existed a moment ago and does not now. Do not call that
        # `dead`: it is a read that lost its race, and `dead` licenses a delete.
        return None, f"ps reported no name for pid {pid}, which kill -0 says exists"
    return name, None


def liveness(pid_text):
    """(verdict, why_unreadable) for one pid, as a string.

    Pure of exits on purpose: `status`, `list` and `release` all read this and
    none of them may be killed by a pid a record happens to carry."""
    arg = str(pid_text)
    if not arg.isascii() or not arg.isdigit() or int(arg) <= 0:
        return None, f"not a pid: {arg!r}"
    pid = int(arg)
    held = holds(pid)
    if held is None:
        return None, f"kill -0 {pid} could not be asked"
    if not held:
        return "dead", None
    name, why = name_of(pid)
    if why:
        return None, why
    return ("alive" if name in NAMES else "other"), None


def alive(pid):
    """The liveness word a record's reader prints, or why there is none."""
    v, why = liveness(pid)
    return v if v else f"unreadable ({why})"


def cmd_alive(args):
    v, why = liveness(args.pid)
    if why:
        print(f"campaign-claim alive: {why}", file=sys.stderr)
        return 2
    print(v)
    return 0


# ---------------------------------------------------------------- the records


def campaign_dir(arg):
    d = arg or os.environ.get("CAMPAIGN")
    if not d:
        sys.exit("campaign-claim: no campaign directory. Pass --dir or set "
                 "$CAMPAIGN. This script does not search for one.")
    p = Path(d).expanduser().resolve()
    claims = p / "runtime" / "claims"
    if not claims.is_dir():
        sys.exit(f"campaign-claim: {claims} does not exist.\n"
                 f"  A claim record has no home but the campaign directory, so "
                 f"scaffold it first\n"
                 f"  (opening-campaign steps 2 and 4). A missing directory is "
                 f"not an empty one:\n"
                 f"  an empty directory says no claim was taken, a missing one "
                 f"says nothing.")
    return p, claims


def record_path(claims, issue):
    return claims / str(issue)


RELEASED = "released"


def is_released(rec):
    """True when this record has been marked released. A released record is
    attribution kept on purpose, never a claim: it licenses no write."""
    return bool(rec) and bool(rec.get(RELEASED, "").strip())


def holder_line(path, rec):
    """What a second taker is told. It names the session, because the only
    useful next move is to go and ask it."""
    return (f"already claimed: {path} exists and is not released.\n"
            f"  session {rec.get('session', '<absent>')}  "
            f"name {rec.get('name', '<absent>')}  "
            f"pid {rec.get('pid', '<absent>')}\n"
            f"  branch {rec.get('branch', '<absent>')}\n"
            f"  Read who holds it before doing anything else:\n"
            f"    {sys.argv[0]} status {path.name} --dir <campaign>")


def write_record(path, name, branch, local=False, session_arg=None,
                 replacing=False):
    """Create the record, and refuse to overwrite a live one.

    `O_EXCL` and not `path.exists()`: the check-then-write it replaces has a
    window between the two in which a peer's take lands, and the window is
    exactly the collision the claim exists to stop. Returns (body, refusal);
    a refusal means nothing was written."""
    own = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    session = session_arg or own
    # Another session's record must not carry this process's pid: `status`
    # would read the launcher's liveness as the delegate's.
    pid = os.environ.get("CLAUDE_PID", "") if session == own else ""
    missing = [k for k, v in (("CLAUDE_CODE_SESSION_ID", session),
                              ("CLAUDE_PID", pid if session == own else "n/a"))
               if not v]
    if missing:
        print(f"!! {' and '.join(missing)} not set; the record will carry "
              f"'unknown' there.\n"
              f"   session identifies this session across a restart and a "
              f"rename; pid is what\n"
              f"   makes liveness a local check. Without them a later reader "
              f"can neither reach\n"
              f"   nor test this claim.", file=sys.stderr)
    body = (f"session {session or 'unknown'}\n"
            f"name {name or 'unknown'}\n"
            f"pid {pid or 'unknown'}\n"
            f"branch {branch}\n"
            + ("local yes\n" if local else ""))
    if replacing:
        # The caller has already read this record and found it released, so
        # there is nothing here O_EXCL would be protecting.
        path.write_text(body)
        return body, None
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    except FileExistsError:
        return None, "exists"
    except OSError as e:
        return None, f"could not write {path}: {e.__class__.__name__}: {e}"
    with os.fdopen(fd, "w") as handle:
        handle.write(body)
    return body, None


def mark_released(path, rec, by):
    """Append the release mark, keeping every field the record already had."""
    body = "".join(f"{k} {v}\n" for k, v in rec.items() if k != RELEASED)
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    path.write_text(body + f"{RELEASED} {stamp} by {by}\n")
    return stamp


def liveness_of(rec):
    """The record's liveness, or why it has none. Split out because the whole
    release gate hangs off this one value and nothing pinned the wire: replacing
    it with the constant "dead" left the suite green and made a live claim
    deletable."""
    if not rec:
        return None
    if "unreadable" in rec:
        return f"unreadable ({rec['unreadable']}: the record itself would not read)"
    pid = rec.get("pid", "")
    if not pid or pid == "unknown":
        return "unreadable (no pid)"
    return alive(pid)


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


def count_newer(ps_text, names, mtime):
    """How many claude sessions in a recorded `ps` listing started after mtime.

    Pure, and split out so a test of it does not depend on whether a claude
    happens to be running on the machine the suite runs on.

    Returns (count, why_unreadable); a `why` means the count is unknown, which
    is not the same as zero and must never be printed as one."""
    newer = 0
    for line in ps_text.splitlines():
        stamp, _, comm = line.strip().rpartition(" ")
        if comm not in names:
            continue
        try:
            started = time.mktime(time.strptime(stamp.strip()))
        except ValueError:
            return None, f"could not parse a process start time ({stamp!r})"
        if started > mtime:
            newer += 1
    return newer, None


def restarted_since(mtime):
    """Evidence that a `dead` pid may name a session that is still working: a
    claude session that started after this record was written."""
    r = run("ps", "-axo", "lstart=,ucomm=")
    if r.returncode != 0:
        return None, "could not read the process table"
    return count_newer(r.stdout, NAMES, mtime)


def cmd_status(args):
    _, claims = campaign_dir(args.dir)
    path = record_path(claims, args.issue)
    print(f"read {path}")
    rec = read_record(path)
    if rec is None:
        print("verdict none -- no record was ever written here")
        return 0
    if "unreadable" in rec:
        print(f"verdict unreadable -- the file is there but will not decode "
              f"({rec['unreadable']}). This is not an absence.")
        return 0
    for k in ("session", "name", "pid", "branch"):
        print(f"  {k} {rec.get(k, '<absent>')}")
    pid = rec.get("pid", "")
    if not pid or pid == "unknown":
        print("verdict unreadable -- the record carries no pid to test")
        return 0
    v = alive(pid)
    if v == "dead":
        newer, why = restarted_since(path.stat().st_mtime)
        if why:
            print(f"verdict dead -- but {why}, so a restart cannot be ruled out")
        elif newer:
            print(f"verdict stale? -- pid {pid} is held by nobody, and {newer} "
                  f"claude process(es) started after this record was written.")
            print("  A harness restart gives a live session a new pid. Ask the "
                  "session named above\n  before taking this claim; do not read "
                  "this as free.")
        else:
            print(f"verdict dead -- pid {pid} is held by nobody, and no claude "
                  f"process started after this record was written")
    else:
        print(f"verdict {v}")
    return 0


def cmd_list(args):
    _, claims = campaign_dir(args.dir)
    entries = sorted(claims.iterdir())
    files = [p for p in entries if p.is_file()]
    odd = [p for p in entries if not p.is_file()]
    print(f"read {claims} -- {len(files)} claim(s)")
    for p in odd:
        print(f"  !! {p.name} is not a file, so it holds no claim this can "
              f"read -- counted apart, never dropped")
    if not files:
        print("  (empty: no claim was taken here. This is a reading, not a "
              "missing directory.)")
    for p in files:
        rec = read_record(p) or {}
        v = liveness_of(rec) or "unreadable (empty record)"
        # Printed beside the liveness rather than instead of it: they answer
        # different questions, and a released record whose session is still
        # alive is an ordinary state, not a contradiction.
        mark = "  RELEASED" if is_released(rec) else ""
        print(f"  {p.name:8} {v:12} {rec.get('branch', '<no branch>'):40} "
              f"{rec.get('name', '<no name>')}{mark}")
    return 0


def foreign_name(name, anchor):
    """The campaign number a `campaign-<M>-...` name carries when it is not
    this campaign's, else None. Pure, so the refusal has a case. A name of any
    other shape is not judged here: campaign-name-session.py owns the shape,
    and a record may honestly carry `unknown`."""
    m = re.match(r"campaign-([0-9]+)-", name or "")
    if m and m.group(1) != str(anchor):
        return m.group(1)
    return None


def cmd_take(args):
    _, claims = campaign_dir(args.dir)
    branch = f"campaign-{args.anchor}/{args.issue}-{args.topic}"
    other = foreign_name(args.name, args.anchor)
    if other:
        print(f"refusing: --name {args.name} belongs to campaign {other}, and "
              f"this claim is on campaign {args.anchor}. A stale name written "
              f"into a record sends every later reader to the wrong session; "
              f"rename first with scripts/campaign-name-session.py.",
              file=sys.stderr)
        return 1
    path = record_path(claims, args.issue)
    existing = read_record(path)
    if existing and "unreadable" in existing:
        print(f"refusing: {path} is there and will not decode "
              f"({existing['unreadable']}). That is a reading that failed, not "
              f"a free subtask.", file=sys.stderr)
        return 1
    replacing = False
    if existing:
        if not is_released(existing):
            print(holder_line(path, existing), file=sys.stderr)
            return 3
        print(f"{path} is marked released ({existing[RELEASED]}), so it is "
              f"free to re-take.")
        replacing = True

    if args.local:
        print(f"--local: no ref is cut for {branch}; the record is the whole "
              f"claim.")
        body, refusal = write_record(path, args.name, branch, local=True,
                                     session_arg=args.session,
                                     replacing=replacing)
        if refusal == "exists":
            # Between the read above and this open, a peer took it. That window
            # is what O_EXCL closes, and this is the branch that says so.
            print(holder_line(path, read_record(path) or {}), file=sys.stderr)
            return 3
        if refusal:
            print(f"refusing: {refusal}", file=sys.stderr)
            return 1
        print(f"wrote {path}")
        print("".join(f"  {l}\n" for l in body.splitlines()))
        return 0

    # Resolved and checked before the create, never written inline: a read that
    # fails and still prints goes up as the sha and comes back as the 422 that
    # means "already claimed", so the subtask reads as taken and is abandoned.
    r = run("gh", "api", f"repos/{args.repo}/commits/main", "--jq", ".sha")
    sha = r.stdout.strip()
    if r.returncode != 0 or not SHA.match(sha):
        print(f"refusing: could not resolve {args.repo}'s main sha.\n"
              f"  got {sha!r}; {r.stderr.strip()}", file=sys.stderr)
        return 1
    print(f"cut from {args.repo}@main {sha}")

    r = run("gh", "api", f"repos/{args.repo}/git/refs",
            "-f", f"ref=refs/heads/{branch}", "-f", f"sha={sha}")
    if r.returncode != 0:
        if "already exists" in r.stderr.lower():
            print(f"already claimed: {branch} exists on {args.repo}.")
            print("  create-ref refuses an existing ref server-side, so this is "
                  "the claim working.")
            print("  Read who holds it before doing anything else:")
            print(f"    {sys.argv[0]} list --dir <campaign>")
            return 3
        print(f"refusing: create-ref failed.\n  {r.stderr.strip()}",
              file=sys.stderr)
        return 1
    print(f"claimed {branch}")
    body, refusal = write_record(path, args.name, branch,
                                 session_arg=args.session, replacing=replacing)
    if refusal == "exists":
        print(holder_line(path, read_record(path) or {}), file=sys.stderr)
        return 3
    if refusal:
        print(f"refusing: {refusal}\n  The ref {branch} WAS cut and is not "
              f"released by this failure.", file=sys.stderr)
        return 1
    print(f"wrote {path}")
    print("".join(f"  {l}\n" for l in body.splitlines()))
    return 0


def compare_path(repo, branch):
    """Where to ask how far a branch is ahead of main."""
    return f"repos/{repo}/compare/main...{branch}"


def delete_path(repo, branch):
    """Where the ref is deleted. Same repo argument as compare_path, and that
    is the whole point: a claim branch has the same name in every member
    repository, so asking local git instead of the named remote could delete a
    different repository's ref holding a delegate's commits."""
    return f"repos/{repo}/git/refs/heads/{branch}"


def holder_proof(rec, session_arg):
    """Is the caller the claimant itself? Returns (yes, why_not).

    Pure, and split out because it is the one thing that makes a release safe
    without an absence: a session releasing ITS OWN claim needs nobody to
    establish that anyone is gone. The comparison is on the session id and on
    nothing else -- the field that survives a restart and a rename, and the same
    join `live` makes."""
    if not session_arg:
        return False, "no --session was passed"
    if not rec:
        return False, "there is no record here to match a session against"
    held = rec.get("session", "")
    if not held or held == "unknown":
        return False, "the record carries no session id to match"
    if held != session_arg:
        return False, (f"the record is held by session {held}, not by "
                       f"{session_arg}")
    return True, None


def release_gate(rec, branch_arg, confirmed, liveness_word, mine=False):
    """Decide whether a release may proceed, and say no with a reason.

    Pure, because this is the destructive path and the effects around it reach
    GitHub -- so a suite that respects "no case may touch the network" could
    otherwise not cover the decision at all. Returns (branch, refusal); a
    refusal is a string and means nothing is deleted.

    Both branches need a confirmed absence. A record can at least be tested; no
    record is the *weaker* evidence, not the stronger, because it may be a
    session that claimed and died before writing, or a delegate on a machine
    this tree knows nothing about.

    `mine` is the one way PAST the liveness test rather than through it: the
    test asks whether the holder is gone, and a holder releasing its own claim
    has made the question moot. Nothing else may skip it, which is why it is a
    parameter of this calculation and not a condition at the call site."""
    if rec:
        if mine:
            return rec.get("branch", ""), None
        if liveness_word != "dead":
            return None, (f"the record reads {liveness_word}. Only a confirmed "
                          f"absence is safe to act on.")
        if not confirmed:
            return None, ("the pid is held by nobody, which is not proof the "
                          "session is gone. A harness restart renumbers pids. "
                          "Ask, then pass --confirmed-absent.")
        return rec.get("branch", ""), None
    if not branch_arg:
        return None, "no record here, so pass --branch to say which ref to release."
    if not confirmed:
        return None, ("no record means nobody here can say who holds it. Ask "
                      "(campaign-claim live, then the peers), then pass "
                      "--confirmed-absent.")
    return branch_arg, None


def ahead_verdict(returncode, out, err, repo, branch):
    """Read the comparison. Returns (ok, refusal)."""
    ahead = (out or "").strip()
    if returncode != 0 or not ahead.isdigit():
        return False, (f"could not ask {repo} how far {branch} is ahead of "
                       f"main; got {ahead!r}; {(err or '').strip()[:200]}. "
                       f"A comparison that did not happen is not an empty "
                       f"branch.")
    if ahead != "0":
        return False, (f"{repo} says {branch} is {ahead} commit(s) ahead of "
                       f"main. A ref holding commits is reported, never "
                       f"deleted.")
    return True, None


def cmd_release(args):
    _, claims = campaign_dir(args.dir)
    path = record_path(claims, args.issue)
    rec = read_record(path)
    liveness_word = liveness_of(rec)
    mine, why_not_mine = holder_proof(rec, getattr(args, "session", None))
    if rec and "unreadable" not in rec:
        if is_released(rec):
            # Idempotent on purpose: the PostToolUse half fires on every close,
            # and a second one must not read as a failure.
            print(f"{path} is already marked released ({rec[RELEASED]}). "
                  f"Nothing to do.")
            return 0
        if mine:
            print(f"{path} names session {rec.get('session')}, which is the "
                  f"caller. The holder's own release needs no absence.")
        elif getattr(args, "session", None):
            print(f"note: --session did not prove the claim is the caller's "
                  f"({why_not_mine}).")
        if rec.get("local", "") == "yes":
            if not (mine or args.confirmed_absent):
                print(f"refusing: {path} is a local claim held by session "
                      f"{rec.get('session', '<absent>')}. Pass --session with "
                      f"that id, or --confirmed-absent WHO.\n"
                      f"  Deleting a claim costs the one thing keeping two "
                      f"executors off the subtask.", file=sys.stderr)
                return 1
            by = args.session if mine else args.confirmed_absent
            stamp = mark_released(path, rec, by)
            print(f"local claim: no ref was ever cut, so there is none to "
                  f"delete.")
            print(f"marked {path} released {stamp} by {by}")
            return 0
    if rec:
        print(f"{path} reads {liveness_word}")
        if liveness_word == "dead":
            newer, why = restarted_since(path.stat().st_mtime)
            # On stdout with the rest of the trace. Splitting the trace across
            # two streams reordered it under a pipe, and for a script whose
            # contract is "print what was read and which branch was taken" the
            # order is part of the evidence.
            if why:
                print(f"note: the restart check did not run ({why}).")
            elif newer:
                print(f"note: {newer} claude session(s) started after this "
                      f"record was written, so a restart is likely.")
            else:
                print("note: no claude session started after this record was "
                      "written.")
    else:
        print(f"no record at {path}; nothing on this machine attributes a "
              f"claim to a session.")

    # A holder releasing its own claim satisfies the gate the way a confirmed
    # absence does, and for a stronger reason: it is not evidence about where
    # the session went, it IS the session.
    proof = args.session if mine else args.confirmed_absent
    branch, refusal = release_gate(rec, args.branch, proof, liveness_word,
                                   mine=mine)
    if refusal:
        sys.stdout.flush()
        print(f"refusing: {refusal}\n  Deleting a claim costs the one thing "
              f"keeping two executors off the subtask.", file=sys.stderr)
        return 1
    print("released by its own holder, session " + proof if mine
          else f"absence confirmed by: {proof}")

    r = run("gh", "api", compare_path(args.repo, branch), "--jq", ".ahead_by")
    ok, refusal = ahead_verdict(r.returncode, r.stdout, r.stderr, args.repo,
                                branch)
    if not ok:
        print(f"refusing: {refusal}", file=sys.stderr)
        return 1
    print(f"{args.repo} says {branch} holds nothing beyond main")

    r = run("gh", "api", "-X", "DELETE", delete_path(args.repo, branch))
    if r.returncode != 0:
        print(f"refusing: could not delete the ref.\n  {r.stderr.strip()}",
              file=sys.stderr)
        return 1
    print(f"deleted {branch}")
    if rec:
        path.unlink()
        print(f"deleted {path}")
    return 0


# ------------------------------------------------------- the two-sided reading


def parse_agents(text):
    """The herdr reading, with no process in it, so it can be tested against a
    recorded listing instead of against whatever happens to be running."""
    try:
        agents = json.loads(text)["result"]["agents"]
    except (ValueError, KeyError, TypeError) as e:
        return None, f"could not parse herdr's output ({e.__class__.__name__})"
    out = {}
    for a in agents:
        sid = (a.get("agent_session") or {}).get("value")
        if sid is None:
            # A row herdr lists but cannot identify. Counted, never dropped:
            # silently skipping it would shrink "sessions on this machine",
            # which is the number a close gate reads.
            sid = f"<unidentified:{a.get('pane_id', '?')}>"
        out[sid] = {
            "name": a.get("name") or "<unnamed>",
            "status": a.get("agent_status", "?"),
            "cwd": a.get("cwd", "?"),
            "pane": a.get("pane_id", "?"),
        }
    return out, None


def herdr_sessions():
    """Every session on this machine. Listing needs no HERDR_ENV guard: that
    guard is against acting on somebody else's session, never against reading,
    and `agent list` answers the same from outside a pane as from inside."""
    r = run("herdr", "agent", "list")
    if r.returncode != 0:
        return None, f"herdr agent list exited {r.returncode}: {r.stderr.strip()[:120]}"
    return parse_agents(r.stdout)


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


def classify(recs, sessions):
    """Split both readings into the three groups, joining on the session id and
    on nothing else. Pure, so the join can be tested against recorded inputs --
    it is the one line where reaching for the name instead would look right and
    be wrong every time a session is renamed."""
    answered, orphan = [], []
    for issue, rec in sorted(recs.items()):
        sid = rec.get("session", "")
        s = sessions.get(sid)
        (answered if s else orphan).append((issue, rec, s))
    held = {r.get("session") for r in recs.values()}
    idle = [(sid, s) for sid, s in sessions.items() if sid not in held]
    return answered, orphan, idle


def stray_branches(recs, anchor):
    """Records in this directory naming a branch outside this campaign. Pure,
    so the check has a case; a record with no branch counts as stray, since a
    record that cannot say what it claims is not evidence that it claims
    something of ours."""
    return [(i, r) for i, r in sorted(recs.items())
            if not r.get("branch", "").startswith(f"campaign-{anchor}/")]


def cmd_live(args):
    d = args.dir or os.environ.get("CAMPAIGN")
    if not d:
        print("campaign-claim live: no campaign directory. Pass --dir or set "
              "$CAMPAIGN.", file=sys.stderr)
        return 1
    claims = Path(d).expanduser().resolve() / "runtime" / "claims"
    if not claims.is_dir():
        print(f"campaign-claim live: {claims} does not exist, so claims cannot "
              f"be enumerated.\n  A missing directory says nothing; an empty "
              f"one says no claim was taken. This is\n  the first, and it is a "
              f"refusal rather than a clean reading.", file=sys.stderr)
        return 1

    sessions, why = herdr_sessions()
    print(f"reading 1  herdr agent list -- "
          f"{'FAILED: ' + why if why else str(len(sessions)) + ' session(s) on this machine'}")
    recs, odd = claim_records(claims)
    print(f"reading 2  {claims} -- {len(recs)} claim(s) read, "
          f"{len(odd)} unread")
    for note in odd:
        print(f"           !! {note}")
    # Before the herdr gate: a record naming another campaign's branch is a
    # defect in this directory, and surfacing it must not depend on the other
    # reading having worked.
    stray = stray_branches(recs, args.anchor)
    if stray:
        print(f"\n!! {len(stray)} record(s) here name a branch outside "
              f"campaign-{args.anchor}:")
        for i, r in stray:
            print(f"  #{i:<6} {r.get('branch', '<no branch>')}")
        print("  Either this directory is holding another campaign's records, "
              "or a branch was\n  named wrongly. Neither is this script's to "
              "fix.")

    if why or odd:
        if odd and not why:
            print(f"\n{len(odd)} claim(s) could not be read, so the counts "
                  f"below are of what was\nreadable and not of what is here.",
                  file=sys.stderr)
        else:
            print("\nOne of the two readings did not happen, so no count below "
                  "is safe to act on.", file=sys.stderr)
        return 1

    answered, orphan, idle = classify(recs, sessions)
    print(f"\nclaims answered by a live session ({len(answered)}) -- "
          f"joined on the session id, the one field a restart and a rename "
          f"both leave alone")
    for issue, rec, s in answered:
        print(f"  #{issue:<6} {s['status']:<8} {s['name']:<24} "
              f"{rec.get('branch', '<no branch>')}")

    print(f"\nclaims no live session on this machine answers ({len(orphan)})")
    for issue, rec, _ in orphan:
        pid = rec.get("pid", "")
        v = alive(pid) if pid and pid != "unknown" else "unreadable (no pid)"
        print(f"  #{issue:<6} pid {pid or '<absent>'} reads {v}; "
              f"session {rec.get('session', '<absent>')}")
    if orphan:
        print("  Each of these is one of: a session that exited, a session the "
              "harness restarted\n  under a new id, or a record written by a "
              "session that never registered with herdr.\n  Ask before "
              "treating any of them as free.")

    print(f"\nlive sessions holding no claim recorded here ({len(idle)})")
    for sid, s in idle:
        print(f"  {s['name']:<24} {s['status']:<8} {s['pane']:<10} {s['cwd']}")
    if idle:
        print("  A session with no claim may still be working -- a launcher, a "
              "session between\n  subtasks, or one on another campaign. This "
              "list is not a list of idle panes.")

    print(f"\nboth readings were made. {len(answered)} answered, "
          f"{len(orphan)} unanswered, {len(idle)} unattributed.")
    print("No verdict: a close reads these counts, it does not get one from "
          "here.")
    return 0


# ------------------------------------------------------------------------ main


def main():
    ap = argparse.ArgumentParser(add_help=True, description=__doc__.splitlines()[0])
    # On every subcommand rather than only before it: `list --dir X` is what a
    # person types, and argparse would otherwise reject it with a usage line
    # that does not say why.
    where = argparse.ArgumentParser(add_help=False)
    where.add_argument("--dir", help="the campaign directory (or set $CAMPAIGN)")
    # Only on the two subcommands that reach a repository. `status` and `list`
    # read nothing but this machine's records, and accepting a flag they ignore
    # reads as though naming a repository changed what they answer.
    against = argparse.ArgumentParser(add_help=False)
    against.add_argument("--repo", default=DEFAULT_REPO)
    sub = ap.add_subparsers(dest="cmd", required=True)

    t = sub.add_parser("take", parents=[where, against])
    t.add_argument("anchor")
    t.add_argument("issue")
    t.add_argument("topic")
    t.add_argument("--name", help="this session's ListAgents name")
    t.add_argument("--local", action="store_true",
                   help="the record alone: cut no ref, for work that lands no "
                        "commit in any repository")
    t.add_argument("--session", metavar="SID",
                   help="the session id to record (default "
                        "$CLAUDE_CODE_SESSION_ID); a hook is handed one and "
                        "has no environment to read it from")
    t.set_defaults(fn=cmd_take)

    s = sub.add_parser("status", parents=[where])
    s.add_argument("issue")
    s.set_defaults(fn=cmd_status)

    l = sub.add_parser("list", parents=[where])
    l.set_defaults(fn=cmd_list)

    r = sub.add_parser("release", parents=[where, against])
    r.add_argument("issue")
    r.add_argument("--branch")
    r.add_argument("--confirmed-absent", metavar="WHO",
                   help="who established the session is gone. `dead` alone "
                        "never releases a claim.")
    r.add_argument("--session", metavar="SID",
                   help="the caller's own session id. Matching the record's "
                        "`session` proves the caller IS the holder, which "
                        "needs no absence established by anybody.")
    r.set_defaults(fn=cmd_release)

    v = sub.add_parser("live", parents=[where])
    v.add_argument("anchor")
    v.set_defaults(fn=cmd_live)

    a = sub.add_parser("alive")
    a.add_argument("pid")
    a.set_defaults(fn=cmd_alive)

    args = ap.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
