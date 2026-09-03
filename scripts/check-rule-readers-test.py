#!/usr/bin/env python3
"""Prove check-rule-readers fires where it must and stays quiet where it must not.

A guard is trusted only once it has been watched to fail. Every case below is a
fixture written to a temporary tree and run through the real script, so what is
tested is the shipped behaviour rather than a re-implementation of it -- which
would be the second reader the guard itself exists to forbid.

Usage: scripts/check-rule-readers-test.py
"""
import subprocess
import sys
import tempfile
from pathlib import Path

GUARD = Path(__file__).resolve().parent / "check-rule-readers.py"

def fence(body, lang="sh"):
    return f"# t\n\n```{lang}\n{body}\n```\n"


# One per FORM, in the shape a competent person actually writes it -- the flag
# order the owning script itself uses, and the sibling command that answers the
# same question.
FORM_CASES = [
    ("session-alive: the script's own flag order", fence('ps -p "$PID" -o ucomm='), 1),
    ("session-alive: comm instead of ucomm", fence("ps -o comm= -p 1"), 1),
    ("session-alive: pgrep answers the same question", fence("pgrep -x claude"), 1),
    ("session-alive: no `=` on the selector", fence("ps -o comm -p 1"), 1),
    # One case per alternation of the regex, so a revert of any one
    # alternation fails here instead of shipping quietly.
    ("session-alive: the selector combined with other flags", fence("ps -axo ucomm="), 1),
    ("session-alive: a quoted selector", fence('ps -o "ucomm" -p 1'), 1),
    # Synthetic, and deliberately so: `\B` is what stops `-o` matching when a
    # word character precedes the dash, and no realistic line exercises it.
    # Drop `\B` and this fires. It must hold no `|`, `;` or `&`, since the form
    # cannot cross one and a piped fixture would pin nothing.
    ("session-alive: a dash inside a word is not the selector flag",
     fence("ps -p 1 --color-o ucomm="), 0),
    # Each of the next two is matched by exactly one alternation: the list-pair
    # spelling carries no `=`, so only the list form sees it, and the bare
    # selector names no `ps`, so only the quoted-constant form does. A fixture
    # matched by both would pin neither.
    ("session-alive: a Python copy passing the selector as a list element",
     fence('subprocess.run(["ps", "-o", "comm", "-p", pid])'), 1),
    ("session-alive: the selector held in a constant",
     fence('SELECTOR = "ucomm="'), 1),
    # ...and the boundary the narrowed claim now names, so widening the form
    # later has to move this row rather than pass silently.
    ("session-alive: another field first is outside the claim", fence("ps -o pid,ucomm -p 1"), 0),
    # Two spellings of the open-campaign issue survey campaign-anchors owns.
    ("campaign issues: the open-campaign issue survey by label",
     fence("gh issue list -R o/r --label campaign --state open --limit 200"), 1),
    ("campaign issues: the same survey by the parent field",
     fence("gh issue list -R o/r --state open --json number,title,parent"), 1),
    # The wrapped form: a continuation line a line-at-a-time scan would read past.
    ("campaign issues: the survey wrapped across a backslash continuation",
     fence("gh issue list -R o/r --state open \\\n  --json number,title,parent"), 1),
    ("campaign issues: the short flag spelling", fence("gh issue list -l campaign -R o/r"), 1),
    ("campaign issues: the quoted label spelling", fence('gh issue list --label "campaign" -R o/r'), 1),
    ("campaign issues: a continuation that never completes the form stays quiet",
     fence("gh issue list -R o/r \\\n  --state closed"), 0),
    # A backslash on the last line of a block is a typo, not an exemption: the
    # carried text is scanned when the run ends rather than dropped unread.
    ("campaign issues: a continuation left open at the end of a fence is still scanned",
     fence("gh issue list -R o/r --state open --json number,title,parent \\"), 1),
    ("campaign issues: a continuation left open when prose resumes is still scanned",
     "# t\n\n    gh issue list -R o/r --state open --json number,title,parent \\\n\nprose.\n", 1),
    # ...and it does not reach across the close into the next block, which would
    # let two harmless blocks report a form neither of them holds.
    ("campaign issues: a continuation does not join across a fence close",
     fence("gh issue list -R o/r --state open \\") + fence("--json number,title,parent"), 0),
    ("campaign issues: an issue list that reads neither is outside the claim",
     fence("gh issue list -R o/r --state closed --json number,title"), 0),
    ("sub-issues: the index read", fence("gh api --paginate repos/o/r/issues/1/sub_issues"), 1),
    ("sub-issues: the endpoint named in prose is a mention",
     "# t\n\nRead it back from `sub_issues`.\n", 0),
    # The binding reading: the campaign issue's comments filtered for BOUND, and the
    # machine comparison. One case per alternation, and then the two shapes
    # that are the *write* of a binding rather than a reading of one -- both
    # already in this tree, both of which a bare `hostname` form would refuse.
    ("bound: the comments endpoint the reading walks",
     fence("gh api --paginate --slurp repos/o/r/issues/1/comments"), 1),
    ("bound: the comment bodies filtered for the marker",
     fence("gh issue view 1 -R o/r --json comments -q '.comments[].body' | grep '^BOUND'"), 1),
    ("bound: a jq that names the marker",
     fence("""jq -r '.[] | select(.body | startswith("BOUND"))' comments.json"""), 1),
    ("bound: the machine comparison in shell",
     fence('[ "$M" = "$(hostname -s)" ] && echo here'), 1),
    ("bound: ...and the same comparison written the other way round",
     fence('[ "$(hostname -s)" = "$M" ] && echo here'), 1),
    ("bound: the machine comparison in Python",
     fence("here = machine == socket.gethostname()", lang="python"), 1),
    ("bound: posting a binding is a write, not a reading",
     fence('gh issue comment 1 -R o/r --body "BOUND $(hostname -s)"'), 0),
    ("bound: naming this host in a comment body is a write too",
     fence("HOST=$(hostname -s)"), 0),
    ("repos: a shell parse of the list", fence("grep '^- ' README.md | grep owner/repo"), 1),
    ("repos: the heading named in an error message", fence('echo "REFUSE: the ## Repos list did not read"'), 0),
    ("repos: a parse naming no tool is outside the claim",
     fence("""while read -r l; do case $l in '## Repos') f=1;; esac; done < README.md"""), 0),
    ("settlement: a jq read of the verdict field", fence("gh issue view 1 --json stateReason | jq -r .stateReason"), 1),
    ("settlement: the REST spelling", fence("gh api issues/1 --jq .merged_at"), 1),
    ("settlement: `not planned` as a disposition, not a verdict", fence('gh issue close 1 --reason "not planned"'), 0),
    ("local-work: short porcelain", fence("git status -s"), 1),
    ("local-work: the long spelling", fence("git status --porcelain"), 1),
    ("local-work: diff --quiet asks the same thing", fence("git diff --quiet"), 1),
    ("local-work: unmerged branches", fence("git branch --no-merged main"), 1),
    ("local-work: for-each-ref over campaign refs", fence("git for-each-ref refs/heads/campaign-1/"), 1),
    ("name-session: the herdr pane call", fence("herdr agent rename p1 campaign-1-executor-1"), 1),
    ("name-session: the harness call", fence('herdr agent prompt p1 "/rename campaign-1-executor-1"'), 1),
]

# How far the pinning goes, stated because a reader would otherwise infer more:
# every *form* is pinned by at least one case, and within `campaign-session-alive`
# every alternation is pinned individually. Alternations of the other four forms
# are not -- an exhaustive per-alternation sweep found roughly fourteen deletable
# with the suite green, including `mergedAt` and the `## Repos` half of
# campaign-repos'. That is known scope, not full coverage.

# The parser decides what counts as code. Each of these was an unsafe silence:
# the guard exited 0 on a violation that renders as code.
PARSER_CASES = [
    ("prose mentioning a retired form", "# t\n\n`ps -o comm=` is wrong, and here is why.\n", 0),
    ("a four-space indented code block", "# t\n\nLike so:\n\n    ps -o comm= -p 1\n", 1),
    ("a tab-indented code block", "# t\n\nLike so:\n\n\tps -o comm= -p 1\n", 1),
    # The violation sits *after* the impostor closer and before the real one,
    # so a parser that ends the block early stops scanning and reports clean.
    # With the violation in a later fence both parsers catch it and the case
    # proves nothing.
    ("a ``` run does not close a ```` fence",
     "# t\n\n````sh\n```\nps -o comm= -p 1\n````\n", 1),
    ("a ~~~ run does not close a ``` fence",
     "# t\n\n```sh\n~~~\nps -o comm= -p 1\n```\n", 1),
    ("a ~~~ opener closed by ~~~", "# t\n\n~~~sh\nps -o comm= -p 1\n~~~\n", 1),
    ("`~~~ text` is not a closer", "# t\n\n~~~\n~~~ still open\nps -o comm= -p 1\n~~~\n", 1),
    ("an unclosed fence keeps scanning", "# t\n\n```sh\nps -o comm= -p 1\n", 1),
    ("CRLF line endings", "# t\r\n\r\n```sh\r\nps -o comm= -p 1\r\n```\r\n", 1),
]

# The exemption is the one way to say "this fence must hold the form". Every
# way it could silently exempt more than it names is a hole in the guard.
EXEMPTION_CASES = [
    ("a fence exempted by the line above it",
     "# t\n\n<!-- unguarded: campaign-session-alive -- on purpose -->\n\n```sh\nps -o comm= -p 1\n```\n", 0),
    ("an exemption separated from the fence by prose",
     "# t\n\n<!-- unguarded: campaign-session-alive -- x -->\n\nProse intervenes.\n\n```sh\nps -o comm= -p 1\n```\n", 1),
    ("an exemption naming a different owner",
     "# t\n\n<!-- unguarded: campaign-repos -- x -->\n\n```sh\nps -o comm= -p 1\n```\n", 1),
    ("two exemptions in a row both apply",
     "# t\n\n<!-- unguarded: campaign-repos -- x -->\n<!-- unguarded: campaign-session-alive -- y -->\n\n"
     "```sh\nps -o comm= -p 1\ngrep '^- ' r.md | grep owner/repo\n```\n", 0),
    ("an exemption does not survive to the next fence",
     "# t\n\n<!-- unguarded: campaign-session-alive -- x -->\n\n```sh\nps -o comm= -p 1\n```\n\n"
     "```sh\nps -o comm= -p 1\n```\n", 1),
    # An indented block after an exempted fence is the one path on which a
    # stale `exempted` is reachable: every fence opener reassigns it, so a
    # fence-only fixture cannot tell a leak from a reset.
    ("an exemption does not reach a later indented block",
     "# t\n\n<!-- unguarded: campaign-session-alive -- x -->\n\n```sh\nps -o comm= -p 1\n```\n\n"
     "Then:\n\n    ps -o comm= -p 1\n", 1),
    # A malformed exemption must be reported, never skipped. The strict owner
    # token matches nothing in a prose owner, so without a loose detector the
    # line is simply not an exemption and nothing says it was rejected.
    ("an exemption naming a prose owner is reported",
     "# t\n\n<!-- unguarded: AGENTS.md \u00a7 Naming a session -- x -->\n\n```sh\nps -o comm= -p 1\n```\n", 1,
     "an exemption naming no script"),
    ("an exemption naming a misspelled script is reported",
     "# t\n\n<!-- unguarded: campaign-typo-session -- x -->\n\n```sh\nps -o comm= -p 1\n```\n", 1,
     "an exemption naming no script"),
    ("an exemption reaches a following indented block",
     "# t\n\n<!-- unguarded: campaign-session-alive -- on purpose -->\n\n    ps -o comm= -p 1\n", 0),
    ("an exemption spent on an indented block does not reach the next one",
     "# t\n\n<!-- unguarded: campaign-session-alive -- x -->\n\n    ps -o comm= -p 1\n\n"
     "Then:\n\n    ps -o comm= -p 1\n", 1),
    ("an exemption inside an indented block exempts nothing",
     "# t\n\n    <!-- unguarded: campaign-session-alive -- x -->\n    ps -o comm= -p 1\n", 1),
    # No prose between the fence and the indent: a prose line resets the
    # exemption too, so this alone would not expose a missing fence-close reset.
    ("an exemption does not survive a closed fence into an indented block",
     "# t\n\n<!-- unguarded: campaign-session-alive -- x -->\n\n```sh\nps -o comm= -p 1\n```\n\n"
     "    ps -o comm= -p 1\n", 1),
    ("an exemption inside an open fence exempts nothing",
     "# t\n\n```sh\n<!-- unguarded: campaign-session-alive -- x -->\nps -o comm= -p 1\n```\n", 1),
]

# Three forms now live in one script, `campaign-tracker`. `EXEMPT` takes
# `[\w-]+` with no spaces, so had the exemption token been merged along with the
# scripts, one `<!-- unguarded: campaign-tracker -->` would silence the campaign issue
# survey, the index read and the settlement verdict at once -- two more forms
# than the author named, with nothing reporting it. Each case below holds two
# forms of that one script in a single fence and exempts one; the surviving
# finding is what a collapsed token would have swallowed.
#
# The `forbid` field is what makes these bite. Exit 1 alone passes under the
# collapsed design too: `campaign-anchors` would not be an owner there, so the
# run reports "an exemption naming no script" and both forms fire -- also
# exit 1, for the opposite reason.
BOTH_TRACKER_FORMS = ("gh issue list -R o/r --state open --json number,title,parent\n"
                      "gh api --paginate repos/o/r/issues/1/sub_issues")

GRANULARITY_CASES = [
    ("tracker: exempting the campaign issue survey leaves the index read reported",
     f"# t\n\n<!-- unguarded: campaign-anchors -- x -->\n\n```sh\n{BOTH_TRACKER_FORMS}\n```\n",
     1, "the sub-issue index read", "the open-campaign issue survey"),
    ("tracker: ...and exempting the index read leaves the campaign issue survey reported",
     f"# t\n\n<!-- unguarded: campaign-subtasks -- x -->\n\n```sh\n{BOTH_TRACKER_FORMS}\n```\n",
     1, "the open-campaign issue survey", "the sub-issue index read"),
    # Named separately, both are silenced -- so the split did not simply make
    # the exemption unusable.
    ("tracker: two tokens of one script, named separately, silence both",
     "# t\n\n<!-- unguarded: campaign-anchors -- x -->\n"
     f"<!-- unguarded: campaign-subtasks -- y -->\n\n```sh\n{BOTH_TRACKER_FORMS}\n```\n",
     0, None, None),
    # The script's own name is not a token, and saying so is the report a
    # collapsed design could not make.
    ("tracker: the merged script's name is not an exemption token",
     f"# t\n\n<!-- unguarded: campaign-tracker -- x -->\n\n```sh\n{BOTH_TRACKER_FORMS}\n```\n",
     1, "an exemption naming no script", None),
    # The finding says which script to call as well as which token to exempt:
    # a reader told only the token cannot find the code.
    ("tracker: a finding names the script to call and the token to exempt",
     fence("gh api --paginate repos/o/r/issues/1/sub_issues"),
     1, "scripts/campaign-tracker.py (exempt with `campaign-subtasks`)", None),
    # The same split, on the other merge.
    ("claim: the liveness form is exempted by its own token, not the script's",
     "# t\n\n<!-- unguarded: campaign-claim -- x -->\n\n```sh\nps -o comm= -p 1\n```\n",
     1, "an exemption naming no script", None),
]

CASES = FORM_CASES + PARSER_CASES + EXEMPTION_CASES + GRANULARITY_CASES


def staged_case():
    """The index branch has no other reader: exercise it through a real repo.

    No fixture above passes --staged, so this is the only case that fails if
    the guard falls back to reading the working tree instead of the index.
    """
    with tempfile.TemporaryDirectory() as d:
        run_git = lambda *a: subprocess.run(
            ["git", "-C", d, *a], capture_output=True, text=True, check=True)
        run_git("init", "-q")
        f = Path(d) / "doc.md"
        f.write_text("# t\n\n```sh\nps -o comm= -p 1\n```\n")
        run_git("add", "doc.md")
        f.write_text("# t\n\nnothing to see\n")     # reverted on disk, still staged
        out = subprocess.run([str(GUARD), "--staged"], cwd=d,
                             capture_output=True, text=True)
        clean = subprocess.run([str(GUARD)], cwd=d, capture_output=True, text=True)
        return out.returncode, clean.returncode, out.stdout


def announce_case():
    """A clean run must not print the same nothing as a run that read nothing.

    Two readings, because the count alone cannot tell them apart: the guard says
    how many files it examined, and it names separately every tracked path it
    could not read. A file staged for deletion is tracked, is globbed, and has
    no content in the working tree -- so it must appear as unread and must not
    be counted among the files examined.
    """
    with tempfile.TemporaryDirectory() as d:
        run_git = lambda *a: subprocess.run(
            ["git", "-C", d, *a], capture_output=True, text=True, check=True)
        run_git("init", "-q")
        (Path(d) / "kept.md").write_text("# t\n\nnothing to see\n")
        (Path(d) / "gone.md").write_text("# t\n\nnor here\n")
        run_git("add", "kept.md", "gone.md")
        (Path(d) / "gone.md").unlink()          # tracked, no content on disk
        out = subprocess.run([str(GUARD)], cwd=d, capture_output=True, text=True)

        # A file with content the run cannot read is the other answer: it may
        # hold the very copy this guard looks for, so it must refuse rather
        # than join either the examined files or the empty ones.
        bad = Path(d) / "locked.md"
        bad.write_text("# t\n\nstill prose\n")
        run_git("add", "locked.md")
        bad.chmod(0o000)
        blocked = subprocess.run([str(GUARD)], cwd=d,
                                 capture_output=True, text=True)
        bad.chmod(0o644)
        return (out.returncode, out.stdout,
                blocked.returncode, blocked.stdout, blocked.stderr)


def run(body):
    with tempfile.TemporaryDirectory() as d:
        f = Path(d) / "fixture.md"
        f.write_text(body)
        out = subprocess.run(
            [str(GUARD), str(f)], capture_output=True, text=True
        )
        return out.returncode, out.stdout


def main():
    failures = 0
    for case in CASES:
        name, body, want = case[0], case[1], case[2]
        expect = case[3] if len(case) > 3 else None
        forbid = case[4] if len(case) > 4 else None
        code, out = run(body)
        # An exit code alone lets a case pass for the wrong reason: a fixture
        # aimed at the exemption reporter is satisfied by the fence violation it
        # also contains. Where a case names the text it expects, that is checked
        # too -- and `forbid` names the finding that must be *absent*, which is
        # the only way to pin an exemption that silenced exactly one form.
        ok = (code == want and (expect is None or expect in out)
              and (forbid is None or forbid not in out))
        print(f"{'ok  ' if ok else 'FAIL'}  {name}  (exit {code}, wanted {want})")
        if not ok:
            failures += 1
            print("".join(f"        {l}\n" for l in out.splitlines()))
    code, out, blocked_code, blocked_out, blocked_err = announce_case()
    checks = [
        ("a clean run says how many files it examined",
         "check-rule-readers: 1 markdown file(s)" in out),
        ("a clean run says which of the two sources it read",
         "read from the working tree" in out),
        ("a tracked path with no content is named as unread",
         "unread: gone.md" in out),
        ("a clean run still exits 0", code == 0),
        ("a file that could not be read is named as unreadable",
         "unreadable: locked.md" in blocked_out),
        ("a file that could not be read still gets the announcement",
         "check-rule-readers: 1 markdown file(s)" in blocked_out),
        ("a file that could not be read refuses on its own", blocked_code == 1),
        ("a file that could not be read is diagnosed, not raised",
         "Traceback" not in blocked_err),
    ]
    for label, ok in checks:
        print(f"{'ok  ' if ok else 'FAIL'}  {label}")
        if not ok:
            failures += 1
            print("".join(f"        {l}\n" for l in out.splitlines()))

    staged, worktree, staged_out = staged_case()
    # The announcement names its source, and only a --staged run can pin the
    # other half of that sentence: hardcoding "the working tree" passes every
    # working-tree case there is.
    said = "read from the index" in staged_out
    print(f"{'ok  ' if said else 'FAIL'}  a --staged run says it read the index")
    if not said:
        failures += 1
        print("".join(f"        {l}\n" for l in staged_out.splitlines()))
    ok = staged == 1 and worktree == 0
    print(f"{'ok  ' if ok else 'FAIL'}  a staged violation reverted on disk "
          f"(--staged exit {staged}, wanted 1; working-tree exit {worktree}, wanted 0)")
    if not ok:
        failures += 1

    if failures:
        print(f"\n{failures} of {len(CASES) + 10} cases failed.", file=sys.stderr)
        return 1
    print(f"\nall {len(CASES) + 10} cases pass.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
