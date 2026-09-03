#!/usr/bin/env python3
"""Read the campaign plane: its anchors, its binding, its index, its settlement.

    campaign-tracker.py anchors [--repo owner/repo] [--limit N]
    campaign-tracker.py bound <N> [owner/repo]
    campaign-tracker.py index <N> [owner/repo]
    campaign-tracker.py settlement <N> [owner/repo] [--dir CAMPAIGN]

Four readings of one plane -- GitHub issues, plus `hostname -s` for `bound`.
They were four scripts, and every one of them carried the same lesson in its own
words: a listing that stopped early reads exactly like a complete one, and a
reading that did not happen reads exactly like an empty tracker. One script means
one place that gets it right.

**Read the printed word, never the exit status.** The status is about the
reading; the verdict is on stdout. `bound` in particular prints `here`,
`elsewhere <machine>`, or `unbound`, and only `here` licenses a campaign-wide
write -- a failed read that exited like `unbound` would invite a session to bind
a campaign another machine is working.

WHAT EACH SUBCOMMAND OWNS

anchors     The open-anchor survey, and the two ways its readings disagree.
            Both readings come off ONE listing: an earlier version made two `gh`
            calls and inferred a property from *absence* in the other, which
            denounced a real anchor as a sub-issue wearing the label. `--limit` is
            raised past `gh`'s default of thirty because anchors are the oldest
            issues here, and a listing that comes back *at* the limit refuses
            rather than printing rows that are wrong rather than merely short.

bound       The one reader of the `BOUND` comment. Four things the jq pipeline
            it replaced had to get right, each a way to be wrong: `--paginate`,
            because comments page at thirty and a campaign migrated after thirty
            comments would answer with the binding it left; oldest-first, so the
            LAST match is the current binding; the first line only, because a
            binding may be annotated; and `\\r`, since a body stored with CRLF
            leaves a carriage return on the machine name. The comparison against
            this machine is folded in, because every caller ran `hostname -s` on
            its next line and compared by eye.

index       The sub-issue index -- the whole of it. `gh issue create --parent` is
            the only write that records a campaign's membership and this endpoint
            is the only read. It pages at thirty, and the close is the one place
            the index is read before a directory is deleted.

settlement  The observable spec/alloy/ scenarios are judged by. Verdicts match
            spec/alloy/ledger.als: `complete` (closed, and a pull request that
            closed it is merged), `dropped` (closed with no merged pull request),
            `open`. Settled is "the issue is closed", both verdicts alike; the
            merged pull request only says which kind.

            Each OPEN row also carries who holds its claim, read from
            `<campaign>/runtime/claims/` through campaign-claim's own reader:
            `claimed by <name> [<liveness>]`, or `unclaimed`. That column is
            what an open sub-issue nobody had started was missing -- it read
            exactly like one somebody was three hours into. Without a campaign
            directory the column is EMPTY and a note says which reading did not
            happen, because printing `unclaimed` for a directory nobody read is
            the absence dressed as a reading that this exists to end.

`settlement` reads the index through `index`'s own reader rather than issuing its
own request. Moving only the parse behind a script once left `--paginate`
hand-written in the settlement path, where deleting it turned a live campaign's
verdict from "NOT closable" into "closable" with fourteen sub-issues silently gone
and nothing red.

scripts/check-rule-readers.py is the second reader that keeps these claims true: it
refuses a commit that stages a hand-rolled copy of the anchor survey, the index
read, or the settlement verdict as code in any tracked markdown outside scripts/.
It catches a pasted copy, not a re-implementation that names nothing.

EXIT

anchors, index, settlement  0 when the reading was made, 1 when it was not.
bound                       0 for any verdict, 2 when the reading itself failed.
"""
import argparse
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

DEFAULT_REPO = "kalaluthien/agent-workspace"
CAMPAIGN_LABEL = "campaign"
BOUND_PREFIX = "BOUND "

NOT_EMPTY = "An index that did not read is not an empty campaign."


def gh_read(cmd):
    """Run a `gh` invocation for its stdout. Returns (text, why_unreadable).

    A `gh` that is not installed comes back as a failed run rather than a
    traceback: "I could not look" is the case every reader here is written to
    report, and a stack trace loses the reason the caller was about to print."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True)
    except (FileNotFoundError, PermissionError) as e:
        return None, f"could not run gh ({e.__class__.__name__})"
    if r.returncode != 0:
        return None, f"gh exited {r.returncode}: {r.stderr.strip()[:200]}"
    return r.stdout, None


# --------------------------------------------------------------------- anchors


def listing(repo, limit):
    cmd = ["gh", "issue", "list", "-R", repo, "--state", "open",
           "--limit", str(limit), "--json", "number,title,labels,parent"]
    text, why = gh_read(cmd)
    if why:
        return None, why
    try:
        data = json.loads(text)
    except ValueError as e:
        return None, f"could not parse gh's output ({e.__class__.__name__})"
    if not isinstance(data, list):
        return None, f"gh returned {type(data).__name__}, not a list of issues"
    return data, None


def classify(issues):
    """Split one listing by its two readings. Returns (anchors, stray, bare).

    Every issue carries both properties, so each row is decided by what that
    issue itself says -- never by its absence from somewhere else."""
    def labelled(i):
        return any(l.get("name") == CAMPAIGN_LABEL for l in i.get("labels") or [])
    anchors = [i for i in issues if labelled(i) and not i.get("parent")]
    stray = [i for i in issues if labelled(i) and i.get("parent")]
    bare = [i for i in issues if not labelled(i) and not i.get("parent")]
    return anchors, stray, bare


def rows(title, items, note=""):
    print(f"\n{title} ({len(items)})" + (f" -- {note}" if note else ""))
    for i in sorted(items, key=lambda x: x["number"]):
        print(f"  #{i['number']:<5} {i['title'][:88]}")


def cmd_anchors(args):
    issues, why = listing(args.repo, args.limit)
    if why:
        print(f"campaign-tracker anchors: could not read {args.repo} -- {why}\n"
              f"  A reading that did not happen is not an empty tracker.",
              file=sys.stderr)
        return 1
    print(f"read {args.repo}, limit {args.limit}: {len(issues)} open issue(s)")
    if len(issues) >= args.limit:
        print(f"REFUSING: the listing came back at --limit {args.limit}, so it "
              f"may be truncated,\n  and a truncated listing reads exactly like "
              f"a complete one. Raise --limit and re-run.", file=sys.stderr)
        return 1

    anchors, stray, bare = classify(issues)
    rows("open anchors", anchors, "labelled `campaign`, and with no parent")
    if not anchors:
        print("  (none: this is a reading, not a failed one)")
    if stray:
        rows("!! labelled but has a parent", stray,
             "a sub-issue wearing the label; say so rather than joining it")
    if bare:
        rows("!! no parent and not labelled", bare,
             "an anchor whose label was forgotten, or the third kind of issue "
             "this\n   tracker holds. Read the body against the anchor template")
    return 0


# ----------------------------------------------------------------------- bound


def refuse_bound(message):
    print(f"campaign-tracker bound: {message}", file=sys.stderr)
    raise SystemExit(2)


def run_or_refuse(*args):
    try:
        out = subprocess.run(args, capture_output=True, text=True, check=False)
    except OSError as exc:
        refuse_bound(f"cannot run {args[0]}: {exc}")
    if out.returncode != 0:
        refuse_bound(f"{' '.join(args)} exited {out.returncode}: "
                     f"{out.stderr.strip() or out.stdout.strip() or 'no message'}")
    return out.stdout


def bodies(repo, number):
    """Every comment body on the anchor, oldest first.

    `--paginate --slurp` is what makes one JSON document out of the pages;
    without `--slurp` gh concatenates one array per page and json.loads sees
    trailing data.
    """
    raw = run_or_refuse("gh", "api", "--paginate", "--slurp",
                        f"repos/{repo}/issues/{number}/comments")
    try:
        pages = json.loads(raw)
    except json.JSONDecodeError as exc:
        refuse_bound(f"gh returned something that is not JSON: {exc}")
    out = []
    for page in pages:
        if not isinstance(page, list):
            refuse_bound("gh returned a shape this script does not know")
        out.extend(c.get("body") or "" for c in page)
    return out


def binding_of(comment_bodies):
    """The machine named by the last BOUND comment, or None. A calculation, so
    the three ways this can be wrong are testable without a network."""
    found = None
    for body in comment_bodies:
        if body.startswith(BOUND_PREFIX):
            # The first line is the binding; anything after it is prose.
            found = body.split("\n", 1)[0][len(BOUND_PREFIX):].strip()
    return found or None


def this_machine():
    name = run_or_refuse("hostname", "-s").strip()
    if not name:
        refuse_bound("hostname -s printed nothing")
    return name


def cmd_bound(args):
    machine = binding_of(bodies(args.repo, args.anchor))
    if machine is None:
        print("unbound")
    elif machine == this_machine():
        print("here")
    else:
        print(f"elsewhere {machine}")
    return 0


# ----------------------------------------------------------------------- index


def parse_index(text):
    """Returns (items, why_unreadable).

    `gh api --paginate` behaves by the response's own shape: an endpoint
    returning a JSON **array** has its pages merged into one array, while an
    object endpoint has its page objects concatenated and needs a streaming
    decode. This endpoint returns an array, so a plain decode is right."""
    text = text.strip()
    if not text:
        return [], None
    try:
        items = json.loads(text)
    except ValueError as e:
        return None, (f"could not parse the index ({e.__class__.__name__}: "
                      f"{str(e)[:60]})")
    if not isinstance(items, list):
        return None, (f"the endpoint returned {type(items).__name__}, not a "
                      f"list; --paginate concatenates object pages, so this "
                      f"needs a streaming decode rather than a plain one")
    return items, None


def fetch_index(repo, anchor):
    """Ask GitHub for a campaign's members. Returns (items, why_unreadable).

    The request and the parse are one call on purpose: a caller that got only
    the parse would hand-write `--paginate`, and dropping it there is invisible.
    `settlement` below is that caller."""
    text, why = gh_read(["gh", "api", "--paginate",
                         f"repos/{repo}/issues/{anchor}/sub_issues"])
    if why:
        return None, why
    return parse_index(text)


def cmd_index(args):
    print(f"read repos/{args.repo}/issues/{args.anchor}/sub_issues --paginate")
    items, why = fetch_index(args.repo, args.anchor)
    if why:
        print(f"FAILED -- {why}. {NOT_EMPTY}", file=sys.stderr)
        return 1

    for it in items:
        repo = (it.get("repository") or {}).get("full_name", "?")
        print(f"  {repo}#{it.get('number', '?'):<6} {it.get('state', '?'):<7} "
              f"{(it.get('title') or '')[:70]}")
    print(f"{len(items)} sub-issue(s)"
          + ("  (an empty index is a reading, not a failure)" if not items else ""))
    return 0


# ------------------------------------------------------------------ settlement


def gh_json(*args):
    """(parsed, why_unreadable). Never raises on a reading it could not make.

    This is the shape the whole file uses, and settlement is why: one sub-issue
    whose repository went private would otherwise abort the table before the
    reader saw any verdict at all, and a close reads that table."""
    try:
        out = subprocess.run(["gh", *args], capture_output=True, text=True)
    except OSError as exc:
        return None, f"cannot run gh: {exc}"
    if out.returncode != 0:
        return None, (f"gh {' '.join(args)} exited {out.returncode}: "
                      f"{out.stderr.strip().splitlines()[0][:100] if out.stderr.strip() else 'no message'}")
    if not out.stdout.strip():
        return None, f"gh {' '.join(args)} printed nothing"
    try:
        return json.loads(out.stdout), None
    except ValueError as exc:
        return None, (f"gh {' '.join(args)} returned something that is not JSON "
                      f"({exc.__class__.__name__})")


def verdict(repo, number):
    """(verdict, note, title) for one sub-issue.

    Four verdicts, not three. `unread` is a sub-issue whose issue, or whose
    closing pull request, this account cannot see -- a repository since made
    private, transferred, or deleted. It is neither settled nor open: an
    absence is not a pass and it is not a failure, and settlement counts it in
    a column of its own so a close is refused over it with the reason said.
    Before it existed, the failed read raised out of the table and the reader
    got a message about `gh` where it had asked for a settlement."""
    info, why = gh_json("issue", "view", str(number), "-R", repo,
                        "--json", "state,stateReason,closedByPullRequestsReferences,title")
    if why:
        return "unread", f"the issue could not be read -- {why}", ""
    if info["state"] == "OPEN":
        return "open", "", info["title"]
    title = info["title"]
    for ref in info["closedByPullRequestsReferences"]:
        home = ref.get("repository") or {}
        owner = (home.get("owner") or {}).get("login")
        if not owner or not home.get("name"):
            # A pull request the API declined to place: deleted, or moved
            # somewhere this account cannot follow it to.
            return ("unread", f"the pull request at {ref.get('url') or '?'} is in "
                    "a repository the API did not name", title)
        pr, why = gh_json("pr", "view", str(ref["number"]), "-R",
                          f"{owner}/{home['name']}", "--json", "state")
        if why:
            return ("unread", f"the closing pull request could not be read -- {why}",
                    title)
        if pr["state"] == "MERGED":
            return "complete", ref["url"], title
    # The note says which kind of closed, because "dropped" alone reads as
    # abandoned and a completed sub-issue with nothing to merge lands here too.
    note = {"NOT_PLANNED": "not planned",
            "COMPLETED": "completed, no merged pull request",
            "DUPLICATE": "duplicate"}.get(info["stateReason"] or "",
                                          "closed, no reason recorded")
    return "dropped", note, title


def claim_reader():
    """campaign-claim's own record reading, imported rather than rewritten.

    Returns (module, why_unreadable). The record's shape is written in exactly
    one place, and a settlement that parsed `session`/`name`/`released` itself
    would be the second reader AGENTS.md forbids -- and the one that drifts,
    since nothing re-runs it against a record campaign-claim just wrote."""
    path = Path(__file__).resolve().parent / "campaign-claim.py"
    try:
        spec = importlib.util.spec_from_loader(
            "campaign_claim",
            importlib.machinery.SourceFileLoader("campaign_claim", str(path)))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    except Exception as e:                      # noqa: BLE001 -- any of them
        return None, f"{path}: {e.__class__.__name__}: {e}"
    return module, None


def claim_column(directory):
    """(a function issue -> claim word, a note saying what was read).

    The note is not decoration. Without a campaign directory there is nothing
    to read, and printing `unclaimed` for every row would be an absence dressed
    as a reading -- exactly the failure this column was added to end."""
    if not directory:
        return (lambda n: ""), ("no --dir and no $CAMPAIGN, so no claim was "
                                "read; the rows below say nothing about who "
                                "holds what")
    claims = Path(directory).expanduser().resolve() / "runtime" / "claims"
    if not claims.is_dir():
        return (lambda n: ""), (f"{claims} does not exist, so claims could not "
                                f"be enumerated. A missing directory says "
                                f"nothing; an empty one says no claim was taken")
    module, why = claim_reader()
    if why:
        return (lambda n: ""), f"the claim reader would not load -- {why}"
    recs, odd = module.claim_records(claims)
    note = f"read {claims} -- {len(recs)} claim(s), {len(odd)} unread"
    for o in odd:
        note += f"\n     !! {o}"

    def word(number):
        rec = recs.get(str(number))
        if not rec:
            return "unclaimed"
        if module.is_released(rec):
            return "unclaimed (a released record stands as attribution)"
        # `liveness_of` and not a fresh pid test: it is the wire the release
        # gate hangs off, and two readings of one pid may not disagree.
        return (f"claimed by {rec.get('name', '<no name>')} "
                f"[{module.liveness_of(rec)}]")
    return word, note


def anchor_reports(head):
    """What says the number handed in is not an anchor. Costs no extra call.

    The anchor repository is a member of its own campaigns, so the number handed
    in may be a sub-issue and a sub-issue may be an anchor. Neither is visible in a
    settlement table. These reports read labels and the parent relation, never
    the body: prose is editable and the parent relation is not."""
    if CAMPAIGN_LABEL not in [l["name"] for l in head["labels"]]:
        yield (f"REPORT: no `{CAMPAIGN_LABEL}` label, so this may be a sub-issue read"
               " as an anchor")
    if head["parent"]:
        yield (f"REPORT: this anchor is itself a sub-issue of #{head['parent']['number']}"
               " -- closing that campaign will not settle this one")


def cmd_settlement(args):
    head, why = gh_json("issue", "view", args.anchor, "-R", args.repo,
                        "--json", "state,title,labels,parent")
    if why:
        sys.exit(f"campaign-tracker settlement: could not read the anchor "
                 f"{args.repo}#{args.anchor} -- {why}\n  No verdict was reached "
                 f"for any sub-issue.")
    subs, why = fetch_index(args.repo, args.anchor)
    if why:
        sys.exit(f"campaign-tracker settlement: could not read the sub-issue "
                 f"index -- {why}\n  {NOT_EMPTY}")

    print(f"anchor {args.repo}#{args.anchor}  [{head['state']}]  {head['title']}")
    for line in anchor_reports(head):
        print(f"  -- {line}")
    if not subs:
        print("  (no sub-issues: the index is empty)")
        return 0

    claim_word, claim_note = claim_column(args.dir or os.environ.get("CAMPAIGN"))
    print(f"  -- claims: {claim_note}")

    rows_out, settled, unread, nested = [], 0, 0, []
    for s in subs:
        repo = "/".join(s["repository_url"].split("/")[-2:])
        v, note, title = verdict(repo, s["number"])
        settled += v in ("complete", "dropped")
        unread += v == "unread"
        # Only an open row: a settled sub-issue's claim answers nothing a reader
        # is about to act on, and printing one invites a release that is not
        # needed.
        held = claim_word(s["number"]) if v == "open" else ""
        rows_out.append((f"{repo}#{s['number']}", v, title[:44],
                         "; ".join(x for x in (note, held) if x)))
        # sub_issues is not recursive (probed), so a sub-issue that is itself an
        # anchor hides its own members from this table.
        if s["sub_issues_summary"]["total"]:
            nested.append((f"{repo}#{s['number']}", s["sub_issues_summary"]["total"]))

    width = max(len(r[0]) for r in rows_out)
    for ref, v, title, note in rows_out:
        print(f"  {ref:<{width}}  {v:<9} {title}" + (f"  [{note}]" if note else ""))

    for ref, total in nested:
        print(f"  -- REPORT: {ref} has {total} sub-issue(s) of its own, not listed"
              " above; run this on it too")

    # Two ways not to be closable, named apart because they want different
    # repairs: an open sub-issue is work to finish, an unread one is a reading to
    # get back -- an account to re-authorise, a repository to ask for.
    blockers = []
    if any(v == "open" for _, v, _, _ in rows_out):
        blockers.append("open sub-issues remain")
    if unread:
        blockers.append(f"{unread} sub-issue(s) could not be read, which settles "
                        "nothing either way")
    closable = not blockers
    print(f"  -- {settled}/{len(rows_out)} settled"
          + (f", {unread} unread" if unread else "") + "; "
          + ("closable" if closable else "NOT closable: " + "; ".join(blockers)))
    if head["state"] == "CLOSED" and not closable:
        print("  -- REPORT: the anchor is closed with sub-issues still open")
    return 0


# ------------------------------------------------------------------------ main


def anchor_number(text):
    """The anchor as `bound` validates it: a bare positive issue number.

    Only `bound` refuses a malformed one before spending a request, because it
    is the reading whose caller acts on a printed word and would otherwise read
    a usage error as a verdict."""
    n = text.lstrip("#")
    if not n.isascii() or not n.isdigit() or int(n) <= 0:
        refuse_bound(f"not an issue number: {text!r}")
    return n


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("anchors", help="the open-anchor survey")
    a.add_argument("--repo", default=DEFAULT_REPO)
    a.add_argument("--limit", type=int, default=200)
    a.set_defaults(fn=cmd_anchors)

    # The optional positional repository is the override seam these three share.
    # One spelling across all three: `anchors` takes `--repo` because it takes
    # `--limit` beside it, and a positional there would read as the anchor.
    for name, fn, help_text in (
            ("bound", cmd_bound, "here | elsewhere <machine> | unbound"),
            ("index", cmd_index, "the sub-issue index"),
            ("settlement", cmd_settlement, "every sub-issue's verdict")):
        p = sub.add_parser(name, help=help_text)
        p.add_argument("anchor")
        p.add_argument("repo", nargs="?", default=DEFAULT_REPO)
        # Only settlement reads it, and only settlement is given it: a flag the
        # other two accept and ignore reads as though naming a directory
        # changed what they answer.
        if name == "settlement":
            p.add_argument("--dir", help="the campaign directory whose "
                                         "runtime/claims/ names the holders "
                                         "(or set $CAMPAIGN)")
        p.set_defaults(fn=fn)

    args = ap.parse_args()
    if args.cmd == "bound":
        args.anchor = anchor_number(args.anchor)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
