#!/usr/bin/env python3
"""Take and release a sub-issue's claim, and say who is standing in one.

    campaign-claim.py take <N> <issue> <topic> [--repo owner/repo]
    campaign-claim.py release <N> <issue> [--branch B] [--repo owner/repo]
    campaign-claim.py live <N> [--repo owner/repo]

THE CLAIM IS THE BRANCH, AND NOTHING ELSE

A claim used to be two things that had to agree: a branch on the remote, and a
`runtime/claims/<issue>` record on this machine saying which session held it.
The record answered attribution -- which session -- and liveness -- which pid.
Both answers are now read off facts that were already there:

  attribution   the WORKSPACE a claim branch is checked out in, read from
                `git worktree list`. Neither a harness restart nor a rename
                touches a checkout, which is exactly the pair the record's
                `session` field existed to survive.
  liveness      the herdr row itself.

So there is nothing to write, nothing to keep in step, and nothing that dies
with a directory. `spec/campaign/orchestration/system.als`'s `holder` is this
reading, and `AttributionIsSound` is what it costs: three events move a
checkout out from under a live agent -- an acquire, a directory delete, and a
sub-issue moved out of its campaign -- and after any of them the agent is live,
listed, and no longer the holder. `live` prints that state as its own group
rather than resolving it.

A WORKSPACE, NOT A SESSION, AND WHY THAT IS THE STRONGEST HONEST READING

The obvious join is a session's own directory: `herdr agent list` prints a
`cwd`, and `git -C <cwd> branch --show-current` prints a branch. Measured
against this machine on 2026-09-04 it found nothing, for two reasons that are
the ordinary case and not an edge:

  * herdr reports where a session was STARTED, not where it is working. An
    executor on the base works in a worktree (AGENTS.md, Execution mode) and
    its herdr `cwd` stays at the clone it launched from, on `main`.
  * that worktree belongs to the BASE ROOT's repository, while the clone the
    session sits in is a different repository with its own `.git`, so
    `git -C <cwd> worktree list` cannot see the branch at all.

Nothing else on disk ties a session to a worktree, and the name may not be
tested against the branch -- they are two strings on purpose (AGENTS.md, The
session name). So per-session attribution is not derivable, and this does not
pretend otherwise: it answers WHERE a claim is checked out, which is what both
of its readers actually ask. `release` needs to know somebody is sitting in the
ref before it deletes it, and a close needs to know whether any claim is still
occupied; neither needs a session id. Addressing a holder is `ListAgents` and
the four messages, which is where it already was.

EVERY CLAIM CUTS A REF, REPO-LESS WORK INCLUDED

`take --local` used to write the record and cut nothing, for work that lands no
commit -- a scaffold, a sweep, a decision written into the campaign issue. With
no record there is nothing for it to write, and the atomicity it had moved onto
`O_EXCL` goes back where it belongs: create-ref's server-side refusal, which
serialises every machine and not just this one. A repo-less campaign cuts its
ref on the base, which is what `R4_RepolessCampaign` in
`spec/campaign/github/system.als` already required.

`release` FINDS THE BRANCH RATHER THAN BEING TOLD IT

The record used to carry the branch, so `release <issue>` knew which ref to
delete. The remote carries it too: refs under `campaign-<N>/` whose segment
after the slash opens with the sub-issue number. Two refs matching one
sub-issue is a refusal, not a guess. `--branch` names one directly, for the
case where the naming rule was broken and the sweep finds nothing.

A GONE REF WITH A MERGED PULL REQUEST IS NOTHING BEYOND MAIN

The normal end of a branch claim is a merged pull request and a deleted ref,
and the comparison `release` asks for then answers 404. A comparison that did
not happen is not an empty branch, so that used to refuse -- on the one path
every finished sub-issue takes. The 404 is read apart from every other failure,
and it is not trusted alone: the compare 404s identically for a gone ref, a
missing base and an unreachable repository, so `release` then asks the ref's own
endpoint and goes on only when that says 404 too. Then it asks GitHub for a
merged pull request whose head was this branch, and one found is the durable
record that everything the branch held is on main. No ref and no merged pull
request is still a refusal, because a branch that vanished without merging is
reported, never released.

A REF AHEAD OF MAIN IS KEPT, AND SO IS ONE SOMEBODY IS SITTING IN

Two refusals guard the delete, and they answer different questions. A branch
still ahead of main is the pull request's head, and deleting it would take
commits with it. A branch a live session has checked out is somebody's
workspace, and deleting the ref under it strands them -- that one is only
readable now that attribution is derived, and it is the reading the record
could not make: a record said who CLAIMED a sub-issue, never who is standing in
it. Both are reported, never resolved, and nothing is deleted when either bites.

THE BINDING IS READ BEFORE A REF IS CUT

`take` runs campaign-tracker `bound <N>` and cuts a ref only on `here`:
`elsewhere`, `unbound` and a failed read each refuse by name. That makes the
claim one of the binding's mechanically gated writes.

`live` MAKES BOTH READINGS AND CONCLUDES FROM NEITHER

    remote refs under campaign-<N>/      every claim, readable from anywhere
    git worktree list                    where each one is checked out, here
    herdr agent list                     what is still running, here

The first two join on the branch name and on nothing else. Three groups come
out -- claims checked out on this machine, claims checked out nowhere on it,
and every live session of this campaign -- and `live` reaches no verdict; a
close reads the counts.

WHICH REPOSITORIES ARE SWEPT

The base root always, resolved the way AGENTS.md resolves it, because
`<campaign>/worktrees/` hangs off it. Then the repository root of every live
session's `cwd`, which picks up each member clone without this script being
told where the clones are. A root git will not answer for is named, never
skipped: a repository that could not be swept is a reading that failed, and its
claims are not evidence of an empty machine.

WHAT IT REFUSES TO GUESS

A worktree listing this cannot make is reported and denies the clean verdict,
the same way a failed herdr read does. A detached worktree is a real answer --
it holds no branch -- because git answered.

WHAT WENT WITH THE RECORD, AND IS GONE

`take --name` checked a session's name against
`scripts/campaign-name-session.py`'s rule and refused one belonging to another
campaign, because a stale name written into a record sent every later reader to
the wrong session. There is no record to write a name into, so there is no
longer a reader that catches a session working under another campaign's name.
The rule in AGENTS.md 'The session name' stands; nothing enforces it at the
claim any more, and this paragraph is the only record of that.

EXIT

take     0 claimed, 3 already claimed, 1 the claim was refused or failed.
release  0 released, 1 refused or the reading failed.
live     0 every reading made, 1 one of them did not happen.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

DEFAULT_REPO = "kalaluthien/campaign-base"
SHA = re.compile(r"^[0-9a-f]{40}$")

HERE = Path(__file__).resolve().parent


def run(*args, **kw):
    """A command that is not installed comes back as a failed run, not a
    traceback: `gh` absent, or `herdr` absent, or `git` absent, is the "I could
    not look" case this script is written to report, and a stack trace loses
    the reason."""
    try:
        return subprocess.run(args, capture_output=True, text=True, **kw)
    except (FileNotFoundError, PermissionError) as e:
        return subprocess.CompletedProcess(
            args, 127, "", f"{args[0]}: {e.__class__.__name__}: {e}")


# --------------------------------------------------------------- the binding


def binding_verdict(word):
    """Why the binding refuses a ref cut, or None. `word` is the first token
    campaign-tracker `bound` printed: `here` admits; `elsewhere` and `unbound`
    refuse by name; anything else is a reading that failed, which refuses too,
    because a binding that could not be read is not a binding here."""
    if word == "here":
        return None
    if word == "elsewhere":
        return ("the campaign is bound elsewhere; a claim is a write only its "
                "machine makes (AGENTS.md, The binding)")
    if word == "unbound":
        return ("the campaign is not bound to any machine; only a person's "
                "word binds it, and a claim comes after")
    return f"the binding could not be read (campaign-tracker bound said {word!r})"


def binding_refusal(campaign_issue):
    """Read the binding through its one reader and say why it refuses, or
    None."""
    b = run(sys.executable, str(HERE / "campaign-tracker.py"), "bound",
            str(campaign_issue))
    word = (b.stdout.strip().split() or [""])[0]
    # Whole, on one line: the tracker's prefix is over a hundred characters and
    # gh's auth failure is several lines with the cause on the first, so
    # neither a prefix cut nor a last-line keep carries both ends.
    why = " ".join(b.stderr.split()) or b.stdout.strip() or "no message"
    return binding_verdict(word if b.returncode == 0 else
                           f"exit {b.returncode}: {why}")


# ---------------------------------------------------------- branches as claims


def branch_name(campaign_issue, issue, topic):
    return f"campaign-{campaign_issue}/{issue}-{topic}"


def issue_of_branch(branch, campaign_issue):
    """The sub-issue number a claim branch names, or None. Pure.

    `campaign-<N>/<issue>-<topic>`: the number is what stands between the slash
    and the first hyphen after it. A branch whose second segment does not open
    with digits and a hyphen claims no sub-issue this can name, and it comes
    back None rather than guessed at."""
    prefix = f"campaign-{campaign_issue}/"
    if not branch.startswith(prefix):
        return None
    m = re.match(r"(\d+)-", branch[len(prefix):])
    return m.group(1) if m else None


def parse_refs(text):
    """(branches, why_unreadable) from the matching-refs listing. Pure."""
    try:
        refs = json.loads(text or "[]")
    except json.JSONDecodeError as e:
        return None, f"the ref listing did not parse ({e.__class__.__name__})"
    if not isinstance(refs, list):
        return None, "the ref listing was not a list"
    return sorted(x[len("refs/heads/"):] for x in refs
                  if isinstance(x, str) and x.startswith("refs/heads/")), None


def matching_refs(repo, campaign_issue):
    """Every claim branch of this campaign on the remote.

    `git/matching-refs/` answers a prefix in one request and 200s with an empty
    array when nothing matches, so an empty campaign and an unreachable
    repository do not come back looking the same."""
    r = run("gh", "api", f"repos/{repo}/git/matching-refs/heads/"
            f"campaign-{campaign_issue}/", "--jq", "[.[].ref]")
    if r.returncode != 0:
        return None, (f"could not list {repo}'s campaign-{campaign_issue}/ "
                      f"refs: {' '.join(r.stderr.split())[:160]}")
    return parse_refs(r.stdout)


def refs_for_issue(branches, campaign_issue, issue):
    """The claim branches of one sub-issue. Pure, so none, one and two each
    have a case; two is what `release` refuses on rather than picking."""
    return [b for b in branches
            if issue_of_branch(b, campaign_issue) == str(issue)]


# ------------------------------------------------------------------------ take


def cmd_take(args):
    branch = branch_name(args.campaign_issue, args.issue, args.topic)
    # The binding, read before a ref is cut: a claim is one of the writes only
    # the bound machine makes. Read from the one reader, never re-derived.
    refusal = binding_refusal(args.campaign_issue)
    if refusal:
        print(f"refusing: {refusal}", file=sys.stderr)
        return 1
    print("bound here, so the claim may be cut")

    # Resolved and checked before the create, never written inline: a read that
    # fails and still prints goes up as the sha and comes back as the 422 that
    # means "already claimed", so the sub-issue reads as taken and is abandoned.
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
            print("  create-ref refuses an existing ref server-side, so this "
                  "is the claim working.")
            print("  Read who is standing in it before doing anything else:")
            print(f"    {sys.argv[0]} live {args.campaign_issue}")
            return 3
        print(f"refusing: create-ref failed.\n  {r.stderr.strip()}",
              file=sys.stderr)
        return 1
    print(f"claimed {branch}")
    print(f"  The ref IS the claim: nothing else was written, and "
          f"`{sys.argv[0]} live {args.campaign_issue}` reads it back.")
    return 0


# --------------------------------------------- the herdr half of the reading


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
        return None, (f"herdr agent list exited {r.returncode}: "
                      f"{r.stderr.strip()[:120]}")
    return parse_agents(r.stdout)


def parse_worktrees(text):
    """{branch: [path, ...]} from `git worktree list --porcelain`. Pure.

    The porcelain form is paragraphs of `key value` lines: `worktree <path>`
    opens one, `branch refs/heads/<name>` names its branch, and a detached
    worktree simply has no `branch` line -- a real answer, not a failure, so it
    is dropped rather than counted as unreadable."""
    out, path = {}, None
    for line in (text or "").splitlines():
        if line.startswith("worktree "):
            path = line[len("worktree "):].strip()
        elif line.startswith("branch refs/heads/") and path:
            out.setdefault(line[len("branch refs/heads/"):].strip(),
                           []).append(path)
        elif not line.strip():
            path = None
    return out


def base_root():
    """The base checkout this script belongs to, resolved AGENTS.md's one way:
    the parent of the common git dir, which is the MAIN checkout even when this
    file is read through a linked worktree -- and the campaign worktrees hang
    off exactly there."""
    r = run("git", "-C", str(HERE), "rev-parse", "--path-format=absolute",
            "--git-common-dir")
    if r.returncode != 0:
        return None, (f"could not resolve the base root from {HERE}: "
                      f"{' '.join(r.stderr.split())[:120]}")
    return str(Path(r.stdout.strip()).parent), None


def repo_root(cwd):
    """The repository root of one session's directory, or why not. A `cwd` that
    is not in a repository is not a failure -- a session may sit anywhere -- so
    it comes back as (None, None)."""
    if not cwd or cwd == "?":
        return None, None
    r = run("git", "-C", cwd, "rev-parse", "--path-format=absolute",
            "--git-common-dir")
    if r.returncode != 0:
        return None, None
    return str(Path(r.stdout.strip()).parent), None


def sweep_roots(sessions):
    """(roots, why_unreadable) -- every repository to enumerate worktrees in.

    The base root is unconditional, because a campaign's worktrees hang off it
    whether or not any session happens to be sitting there. A failure to
    resolve it is a refusal: not knowing where to look is not the same as
    looking and finding nothing."""
    root, why = base_root()
    if why:
        return None, why
    roots = {root}
    for row in sessions.values():
        r, _ = repo_root(row.get("cwd", ""))
        if r:
            roots.add(r)
    return sorted(roots), None


def checkouts(roots):
    """({branch: [path, ...]}, unread) across every root. A root git will not
    answer for is named, never skipped, because a repository that could not be
    swept is not an empty one."""
    out, unread = {}, []
    for root in roots:
        r = run("git", "-C", root, "worktree", "list", "--porcelain")
        if r.returncode != 0:
            unread.append(f"{root}: git worktree list exited {r.returncode}: "
                          f"{' '.join(r.stderr.split())[:120]}")
            continue
        for branch, paths in parse_worktrees(r.stdout).items():
            out.setdefault(branch, []).extend(paths)
    return {b: sorted(set(p)) for b, p in out.items()}, unread


def classify(branches, where, sessions, campaign_issue):
    """(occupied, vacant, ours) -- the join, on the branch name and on nothing
    else.

    Pure, so it can be tested against recorded inputs. `ours` is every live
    session named for this campaign, which is what a close sweeps; it is
    deliberately not filtered by whether the session holds anything, because
    which session holds which claim is the question this cannot answer and
    says so."""
    name_prefix = f"campaign-{campaign_issue}-"
    occupied, vacant = [], []
    for b in branches:
        paths = where.get(b, [])
        (occupied if paths else vacant).append((b, paths))
    ours = [(sid, row) for sid, row in sorted(sessions.items())
            if row.get("name", "").startswith(name_prefix)]
    return occupied, vacant, ours


def cmd_live(args):
    branches, why1 = matching_refs(args.repo, args.campaign_issue)
    print(f"reading 1  {args.repo} refs under campaign-{args.campaign_issue}/ "
          f"-- {'FAILED: ' + why1 if why1 else str(len(branches)) + ' claim(s)'}")
    sessions, why2 = herdr_sessions()
    print(f"reading 2  herdr agent list -- "
          f"{'FAILED: ' + why2 if why2 else str(len(sessions)) + ' session(s) on this machine'}")
    roots, why3 = sweep_roots(sessions or {})
    where, unread = ({}, []) if why3 else checkouts(roots)
    print(f"reading 3  git worktree list -- "
          f"{'FAILED: ' + why3 if why3 else f'{len(roots)} repo(s) swept, {len(unread)} unread'}")
    for root in (roots or []):
        print(f"           {root}")
    for note in unread:
        print(f"           !! {note}")
    if why1 or why2 or why3:
        print("\nOne of the three readings did not happen, so no count below "
              "is safe to act on.", file=sys.stderr)
        return 1

    occupied, vacant, ours = classify(branches, where, sessions,
                                      args.campaign_issue)

    print(f"\nclaims checked out on this machine ({len(occupied)}) -- joined "
          f"on the branch name, which a restart and a rename both leave alone")
    for b, paths in occupied:
        for path in paths:
            print(f"  {b:<34} {path}")

    print(f"\nclaims checked out nowhere on this machine ({len(vacant)})")
    for b, _ in vacant:
        print(f"  {b}")
    if vacant:
        print("  Each is one of: a delegate that exited, a checkout on another "
              "machine, or work\n  finished and waiting on a merge. Ask before "
              "treating any of them as free.")

    print(f"\nlive sessions of campaign-{args.campaign_issue} ({len(ours)})")
    for sid, row in ours:
        print(f"  {row['name']:<24} {row['status']:<8} {row['pane']:<10} "
              f"{row['cwd']}")
    if ours:
        print("  WHICH of these holds which claim above is not derivable: "
              "herdr reports where a\n  session started, not the worktree it "
              "is working in. Ask them; the four messages\n  are the address, "
              "and this list is who to ask.")

    if unread:
        print(f"\n{len(unread)} repositor(y/ies) could not be swept, so the "
              f"claims above are of what\nwas readable and not of what is "
              f"here.", file=sys.stderr)

    print(f"\nall three readings were made. {len(occupied)} occupied, "
          f"{len(vacant)} vacant, {len(ours)} live session(s) of this campaign.")
    print("No verdict: a close reads these counts, it does not get one from "
          "here.")
    return 1 if unread else 0


# --------------------------------------------------------------------- release


def compare_path(repo, branch):
    """Where to ask how far a branch is ahead of main."""
    return f"repos/{repo}/compare/main...{branch}"


def delete_path(repo, branch):
    """Where the ref is deleted. Same repo argument as compare_path, and that
    is the whole point: a claim branch has the same name in every member
    repository, so asking local git instead of the named remote could delete a
    different repository's ref holding a delegate's commits."""
    return f"repos/{repo}/git/refs/heads/{branch}"


def which_branch(branches, campaign_issue, issue, branch_arg):
    """(branch, refusal) -- which ref this release is about. Pure.

    `--branch` wins, because it is the caller naming one directly for the case
    the naming rule was broken. Otherwise the remote's own refs answer, and TWO
    matching one sub-issue is a refusal: nothing here can tell which of them
    holds the work, and deleting the wrong one costs a branch."""
    if branch_arg:
        return branch_arg, None
    found = refs_for_issue(branches, campaign_issue, issue)
    if not found:
        return None, (f"no ref under campaign-{campaign_issue}/ names sub-issue "
                      f"#{issue}, so there is no claim here to release. Pass "
                      f"--branch if the branch was named some other way.")
    if len(found) > 1:
        return None, (f"{len(found)} refs name sub-issue #{issue} "
                      f"({', '.join(found)}). Nothing here can tell which holds "
                      f"the work; pass --branch to name one.")
    return found[0], None


def occupants(where, branch):
    """The workspaces this branch is checked out in. Pure -- the reading the
    record could not make: it said who CLAIMED a sub-issue, never whether
    anything is standing in it right now."""
    return where.get(branch, [])


def ahead_count(returncode, out):
    """The comparison's ahead_by as an int, or None when the question was not
    answered. Split out so a known N is distinguishable from a comparison that
    did not happen; only the first is safe to act on."""
    ahead = (out or "").strip()
    if returncode != 0 or not ahead.isdigit():
        return None
    return int(ahead)


def ahead_verdict(n, out, err, repo, branch):
    """Read the comparison, already reduced to `n` by ahead_count so the caller
    parses it once and passes it through. Returns (ok, refusal)."""
    if n is None:
        ahead = (out or "").strip()
        return False, (f"could not ask {repo} how far {branch} is ahead of "
                       f"main; got {ahead!r}; {(err or '').strip()[:200]}. "
                       f"A comparison that did not happen is not an empty "
                       f"branch.")
    if n != 0:
        return False, (f"{repo} says {branch} is {n} commit(s) ahead of main. "
                       f"A ref holding commits is reported, never deleted.")
    return True, None


def ref_gone(returncode, err):
    """Did the comparison answer 404, meaning the ref is not there? Every other
    non-zero is a question that was not answered, and stays one."""
    return returncode != 0 and "HTTP 404" in (err or "")


def ref_probe(returncode, err):
    """What `git/ref/heads/<branch>` said: `present`, `gone`, or `unanswered`.
    Asked only after the comparison answered 404, because that 404 is the same
    bytes for a gone ref, a missing base, and an unreachable repository; only
    the ref's own endpoint separates the first from the other two."""
    if returncode == 0:
        return "present"
    if "HTTP 404" in (err or ""):
        return "gone"
    return "unanswered"


def merged_head_verdict(returncode, out, repo, branch):
    """Read `gh pr list --head <branch> --state merged`. Returns (ok, text):
    the merged pull request's number when ok, the refusal otherwise."""
    if returncode != 0:
        return False, (f"could not ask {repo} for a merged pull request whose "
                       f"head was {branch}. A question that did not get "
                       f"answered is not an absence.")
    try:
        prs = json.loads(out or "[]")
    except json.JSONDecodeError:
        return False, (f"{repo} answered the pull request question with "
                       f"something that is not JSON: {(out or '')[:120]!r}")
    if not prs:
        return False, (f"{repo} has no ref {branch} and no merged pull request "
                       f"whose head was it. A branch that vanished without "
                       f"merging is reported, never released.")
    return True, f"merged as #{prs[0].get('number', '?')}"


def cmd_release(args):
    branches, why = matching_refs(args.repo, args.campaign_issue)
    if why and not args.branch:
        print(f"refusing: {why}\n  A ref listing that did not happen is not an "
              f"absence of claims.", file=sys.stderr)
        return 1
    branch, refusal = which_branch(branches or [], args.campaign_issue,
                                   args.issue, args.branch)
    if refusal:
        print(f"refusing: {refusal}", file=sys.stderr)
        return 1
    print(f"releasing {branch} on {args.repo}")

    # What is standing in it, read before anything is deleted. A sweep that
    # failed refuses: not knowing whether a workspace holds the branch is not
    # the same as knowing none does.
    sessions, why2 = herdr_sessions()
    if why2:
        print(f"refusing: {why2}\n  The repositories to sweep are derived from "
              f"the live sessions, so an unread\n  listing leaves an occupant "
              f"unread too.", file=sys.stderr)
        return 1
    roots, why3 = sweep_roots(sessions)
    if why3:
        print(f"refusing: {why3}", file=sys.stderr)
        return 1
    where, unread = checkouts(roots)
    if unread:
        print(f"refusing: {len(unread)} repositor(y/ies) could not be swept, "
              f"so whether a workspace\n  holds {branch} is unknown:",
              file=sys.stderr)
        for note in unread:
            print(f"  {note}", file=sys.stderr)
        return 1
    here = occupants(where, branch)
    if here:
        print(f"refusing: {branch} is checked out in {len(here)} workspace(s):",
              file=sys.stderr)
        for path in here:
            print(f"  {path}", file=sys.stderr)
        print("  Deleting the ref under a workspace strands its work. Remove "
              "the worktree first.", file=sys.stderr)
        return 1
    print(f"{branch} is checked out in no workspace on this machine "
          f"({len(roots)} repo(s) swept)")

    r = run("gh", "api", compare_path(args.repo, branch), "--jq", ".ahead_by")
    if ref_gone(r.returncode, r.stderr):
        q = run("gh", "api", f"repos/{args.repo}/git/ref/heads/{branch}")
        state = ref_probe(q.returncode, q.stderr)
        if state != "gone":
            print(f"refusing: the comparison against main answered 404 but the "
                  f"ref {branch} is {state} on {args.repo}"
                  f"{'' if state == 'present' else ': ' + q.stderr.strip()[:120]}. "
                  f"A comparison that did not happen is not an empty branch.",
                  file=sys.stderr)
            return 1
        p = run("gh", "pr", "list", "-R", args.repo, "--head", branch,
                "--state", "merged", "--json", "number")
        ok, text = merged_head_verdict(p.returncode, p.stdout, args.repo, branch)
        if not ok:
            print(f"refusing: {text}", file=sys.stderr)
            return 1
        print(f"{args.repo} has no ref {branch}, and it was {text}: nothing "
              f"beyond main, and no ref to delete")
        return 0
    n = ahead_count(r.returncode, r.stdout)
    ok, refusal = ahead_verdict(n, r.stdout, r.stderr, args.repo, branch)
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
    return 0


# ------------------------------------------------------------------------ main


def main():
    ap = argparse.ArgumentParser(add_help=True,
                                 description=__doc__.splitlines()[0])
    against = argparse.ArgumentParser(add_help=False)
    against.add_argument("--repo", default=DEFAULT_REPO)
    sub = ap.add_subparsers(dest="cmd", required=True)

    # One shape for the campaign issue everywhere: `#1` and `1` are the same
    # campaign in the branch and in `bound`.
    def number(s):
        return s.lstrip("#")

    t = sub.add_parser("take", parents=[against],
                       help="cut the claim branch on the remote")
    t.add_argument("campaign_issue", type=number)
    t.add_argument("issue")
    t.add_argument("topic")
    t.set_defaults(fn=cmd_take)

    r = sub.add_parser("release", parents=[against],
                       help="delete a claim branch holding nothing beyond main")
    r.add_argument("campaign_issue", type=number)
    r.add_argument("issue")
    r.add_argument("--branch", help="name the ref directly, for a branch the "
                                    "naming rule does not describe")
    r.set_defaults(fn=cmd_release)

    v = sub.add_parser("live", parents=[against],
                       help="which claims exist, and who is standing in them")
    v.add_argument("campaign_issue", type=number)
    v.set_defaults(fn=cmd_live)

    args = ap.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
