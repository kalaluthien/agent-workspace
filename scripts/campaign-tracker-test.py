#!/usr/bin/env python3
"""Prove campaign-tracker reads the whole thing, and says when it could not.

All four subcommands replace a `gh` line that once lived in prose, and all four
carry the rule that made the prose fragile: a listing that stops early reads
exactly like a complete one, and a reading that did not happen reads exactly
like an empty tracker.

`campaign-issues`, `bound` and `index` are covered as pure readings plus a shimmed `gh`;
no case reaches the network. `settlement` runs the installed script behind a `gh`
on PATH that answers from a fixture, so the request shapes and the exit codes are
the ones a person gets. The case that matters most there is the one with no
verdict at all: an index that did not read must refuse, because printing "the
index is empty" at exit 0 reads exactly like a campaign with no sub-issues and
closes it.

Usage: scripts/campaign-tracker-test.py
"""
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
TRACKER = HERE / "campaign-tracker.py"


def load():
    spec = importlib.util.spec_from_loader(
        "campaign_tracker",
        importlib.machinery.SourceFileLoader("campaign_tracker", str(TRACKER)))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def tracker(*args, env=None):
    return subprocess.run([sys.executable, str(TRACKER), *args],
                          capture_output=True, text=True, env=env)


# The `gh` a settlement case answers from. One fixture file, keyed by the shape
# of the call, so a change to how the script asks shows up as a missing fixture
# rather than as a silently different answer.
SHIM = '''#!/usr/bin/env python3
import json, os, sys
data = json.load(open(os.environ["SHIM_DATA"]))
a = sys.argv[1:]
if a[0] == "api":
    key = "index"
elif a[0] == "pr":
    key = f"pr:{a[4]}#{a[2]}"
elif "labels" in a[-1]:
    key = "head"
else:
    key = f"issue:{a[4]}#{a[2]}"
v = data.get(key)
if v is None:
    print(f"no fixture for {key}", file=sys.stderr); sys.exit(3)
if isinstance(v, dict) and "exit" in v:
    print(v.get("stderr", ""), file=sys.stderr); sys.exit(v["exit"])
sys.stdout.write(v if isinstance(v, str) else json.dumps(v))
'''


def head(state="OPEN", labels=("campaign",), parent=None):
    return {"state": state, "title": "a campaign",
            "labels": [{"name": n} for n in labels], "parent": parent}


def sub(n, repo="kalaluthien/campaign-base", nested=0):
    return {"number": n, "sub_issues_summary": {"total": nested},
            "repository_url": f"https://api.github.com/repos/{repo}"}


def issue(state, reason=None, prs=(), title="a sub-issue", homeless=False):
    """`homeless` is the shape GitHub returns for a pull request it will not
    place -- its repository deleted, or moved out of this account's reach."""
    return {"state": state, "stateReason": reason, "title": title,
            "closedByPullRequestsReferences": [
                {"number": n, "url": f"https://x/{n}",
                 "repository": None if homeless else
                 {"owner": {"login": "kalaluthien"},
                  "name": "campaign-base"}} for n in prs]}


def settlement(fixture, tmp):
    bin_dir = Path(tmp) / "bin"
    bin_dir.mkdir(exist_ok=True)
    gh = bin_dir / "gh"
    gh.write_text(SHIM)
    gh.chmod(0o755)
    data = Path(tmp) / "data.json"
    data.write_text(json.dumps(fixture))
    env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}",
               SHIM_DATA=str(data))
    r = tracker("settlement", "1", env=env)
    return r.returncode, r.stdout, r.stderr


def main():
    m = load()
    ran, fails = [], []

    def check(name, cond):
        ran.append(name)
        if not cond:
            fails.append(name)

    # ------------------------------------------------- campaign issues: two readings
    def iss(n, label=False, parent=False):
        return {"number": n, "title": f"t{n}",
                "labels": [{"name": "campaign"}] if label else [],
                "parent": {"number": 1} if parent else None}

    listing = [iss(1, label=True), iss(9, label=True, parent=True),
               iss(7), iss(8, parent=True)]
    campaign_issues, stray, bare = m.classify(listing)
    check("a campaign issue is labelled and parentless",
          [i["number"] for i in campaign_issues] == [1])
    check("a labelled issue with a parent is a sub-issue wearing the label",
          [i["number"] for i in stray] == [9])
    check("an unlabelled issue with no parent is reported, not silently a campaign issue",
          [i["number"] for i in bare] == [7])
    check("an ordinary sub-issue is in no list",
          8 not in [i["number"] for i in campaign_issues + stray + bare])
    check("the three lists partition nothing twice",
          len(campaign_issues) + len(stray) + len(bare) == 3)

    # The blocking defect and its sibling: every row must be decided by what the
    # issue itself carries. Deriving either reading from membership in a second
    # `gh` call made *absence* read as a property, so a truncated listing or an
    # issue created between the calls produced a wrong row rather than none.
    check("the label reading comes from the issue, not from a filtered listing",
          [i["number"] for i in m.classify([iss(1, label=True)])[0]] == [1])
    check("...and an unlabelled issue is not promoted by being alone",
          m.classify([iss(1)])[0] == [])
    check("an empty tracker yields empty lists rather than an error",
          m.classify([]) == ([], [], []))

    # ------------------------------------------------------ index: the parse
    one = json.dumps([{"number": 1}, {"number": 2}])
    items, why = m.parse_index(one)
    check("an array of sub-issues reads", why is None and len(items) == 2)
    items, why = m.parse_index("")
    check("an empty response is an empty index, not a failure",
          why is None and items == [])
    items, why = m.parse_index("[{]")
    check("malformed output is a why, not an empty index", items is None and why)
    items, why = m.parse_index(json.dumps({"message": "Not Found"}))
    check("an object where an array was expected is a why, not zero sub-issues",
          items is None and why)
    items, why = m.parse_index(json.dumps([{"number": 1}]) + json.dumps([{"number": 2}]))
    check("concatenated pages are a why rather than a silently short index",
          items is None and why)

    # ---------------------------------------------------- bound: the binding
    # Three ways the jq pipeline this replaced was wrong, each testable without
    # a network because the comparison is a calculation.
    check("no BOUND comment is unbound, not a machine",
          m.binding_of(["hello", "BOUNDARY issues"]) is None)
    check("the LAST BOUND wins, since a migration appends",
          m.binding_of(["BOUND alpha", "chat", "BOUND beta"]) == "beta")
    check("only the first line of an annotated binding is the machine",
          m.binding_of(["BOUND beta\nmigrated because alpha died"]) == "beta")
    check("a CRLF body does not leave a carriage return on the name",
          m.binding_of(["BOUND beta\r\nwhy"]) == "beta")
    check("an empty machine name is unbound rather than the empty string",
          m.binding_of(["BOUND "]) is None)
    # The three printed words are the whole contract; a caller reads the word.
    r = tracker("bound", "not-a-number")
    check("bound refuses a malformed campaign issue with exit 2, never a verdict",
          r.returncode == 2 and "not an issue number" in r.stderr
          and r.stdout.strip() == "")

    # ----------------------------------- the flags, which are why this exists
    # Nothing pinned them: the pure functions above pass whatever `gh` was asked
    # for, so deleting `--paginate` or `--limit` left the suite green while the
    # readings silently went back to a truncated first page.
    with tempfile.TemporaryDirectory() as d:
        shim, log = Path(d) / "bin", Path(d) / "argv"
        shim.mkdir()
        (shim / "gh").write_text(
            "#!/bin/sh\nprintf '%s\\n' \"$@\" >> " + str(log) + "\n"
            "case \"$*\" in *sub_issues*) echo '[]' ;; *) echo '[]' ;; esac\n")
        (shim / "gh").chmod(0o755)
        env = {"PATH": f"{shim}:/usr/bin:/bin", "HOME": str(d)}
        tracker("campaign-issues", env=env)
        argv = log.read_text()
        check("campaign issues passes --limit, since gh's default is thirty",
              "--limit" in argv)
        check("...and reads labels and parent from the one listing",
              "number,title,labels,parent" in argv)
        check("...and does not make a second, label-filtered call",
              argv.count("--state") == 1)
        check("...and raises it well past the default",
              any(x.isdigit() and int(x) >= 100 for x in argv.split()))
        # A listing that came back *at* the limit is a reading not made in
        # full, and the rows it would print are actively wrong rather than
        # merely short. It must refuse, not print a note and exit 0.
        (shim / "gh").write_text(
            "#!/bin/sh\necho '[{\"number\":1,\"title\":\"t\",\"labels\":[],"
            "\"parent\":null}]'\n")
        (shim / "gh").chmod(0o755)
        r = tracker("campaign-issues", "--limit", "1", env=env)
        check("a listing at the limit refuses rather than printing wrong rows",
              r.returncode == 1 and "REFUSING" in r.stdout + r.stderr)
        r = tracker("campaign-issues", "--limit", "9", env=env)
        check("...and a listing under the limit does not", r.returncode == 0)

        (shim / "gh").write_text(
            "#!/bin/sh\nprintf '%s\\n' \"$@\" >> " + str(log) + "\necho '[]'\n")
        (shim / "gh").chmod(0o755)
        log.write_text("")
        tracker("index", "1", env=env)
        argv = log.read_text()
        check("index passes --paginate, since the endpoint pages at thirty",
              "--paginate" in argv)
        check("...against the sub_issues endpoint, which is the index",
              "sub_issues" in argv)

        # `bound` is the third pagination seam, and its own: a campaign migrated
        # after thirty comments would answer with the binding it left.
        log.write_text("")
        (shim / "gh").write_text(
            "#!/bin/sh\nprintf '%s\\n' \"$@\" >> " + str(log) + "\necho '[[]]'\n")
        (shim / "gh").chmod(0o755)
        r = tracker("bound", "1", env=env)
        argv = log.read_text()
        check("bound passes --paginate and --slurp over the comments",
              "--paginate" in argv and "--slurp" in argv and "comments" in argv)
        check("...and no BOUND comment prints `unbound`",
              r.returncode == 0 and r.stdout.strip() == "unbound")

    # ----------------------------------------------- the end-to-end refusals
    # A tracker that cannot be read must never print "open campaign issues (0)".
    with tempfile.TemporaryDirectory() as d:
        shim = Path(d) / "bin"
        shim.mkdir()
        for body, label in ((
                # A non-zero exit that still prints a valid listing. Without the
                # status check the parse succeeds and the failure is invisible;
                # the earlier failing-gh case printed nothing, so the parse
                # branch did the refusing and the status branch was pinned by
                # nothing.
                "#!/bin/sh\necho '[]'\nexit 1\n", "a gh that fails but prints valid output"),
                ("#!/bin/sh\nexit 1\n", "a failing gh"),
                            ("#!/bin/sh\necho 'not json'\n", "unparseable output"),
                            ("#!/bin/sh\necho '{}'\n", "an object instead of a list")):
            (shim / "gh").write_text(body)
            (shim / "gh").chmod(0o755)
            r = tracker("campaign-issues",
                        env={"PATH": f"{shim}:/usr/bin:/bin", "HOME": str(d)})
            out = r.stdout + r.stderr
            check(f"{label} refuses rather than printing an empty tracker",
                  r.returncode == 1 and "open campaign issues" not in out)

    # The same branch on the index reader.
    with tempfile.TemporaryDirectory() as d:
        shim = Path(d) / "bin"
        shim.mkdir()
        (shim / "gh").write_text("#!/bin/sh\necho '[]'\nexit 1\n")
        (shim / "gh").chmod(0o755)
        r = tracker("index", "1",
                    env={"PATH": f"{shim}:/usr/bin:/bin", "HOME": str(d)})
        check("a gh that fails but prints valid output is not an empty index",
              r.returncode == 1 and "0 sub-issue(s)" not in r.stdout)

    for args in (("campaign-issues",), ("index", "1")):
        r = tracker(*args, env={"PATH": "/nonexistent", "HOME": "/tmp"})
        out = r.stdout + r.stderr
        check(f"`{args[0]}` refuses when gh cannot be run",
              r.returncode == 1 and "not" in out.lower() and "Traceback" not in out)
    # `bound` refuses on exit 2, not 1: its status is about the reading, and a
    # caller that read 1 as "unbound" would bind a campaign another machine has.
    r = tracker("bound", "1", env={"PATH": "/nonexistent", "HOME": "/tmp"})
    out = r.stdout + r.stderr
    check("`bound` refuses on exit 2 when gh cannot be run, printing no verdict",
          r.returncode == 2 and "Traceback" not in out
          and out.strip().splitlines()[-1].strip() not in ("here", "unbound"))

    # ----------------------------------------------------------- settlement
    with tempfile.TemporaryDirectory() as tmp:
        merged = {"state": "MERGED"}
        base = {"head": head(),
                "index": [sub(10), sub(11)],
                "issue:kalaluthien/campaign-base#10":
                    issue("CLOSED", "COMPLETED", prs=[90]),
                "issue:kalaluthien/campaign-base#11":
                    issue("CLOSED", "COMPLETED", prs=[91]),
                "pr:kalaluthien/campaign-base#90": merged,
                "pr:kalaluthien/campaign-base#91": merged}

        # The whole reason this section exists: no verdict is not a clean verdict.
        for what, index in (("gh exits non-zero", {"exit": 1, "stderr": "HTTP 404"}),
                            ("the body is not JSON", "<html>not json</html>"),
                            ("the endpoint returns an object", {"total": 2})):
            code, out, err = settlement(dict(base, index=index), tmp)
            check(f"an index that did not read refuses -- {what}",
                  code != 0 and "the index is empty" not in out
                  and "could not read the sub-issue index" in err
                  and "Traceback" not in err)

        code, out, err = settlement(dict(base, index=[]), tmp)
        check("an index that read empty is a campaign with no sub-issues",
              code == 0 and "the index is empty" in out)

        code, out, err = settlement(base, tmp)
        check("every sub-issue settled reads closable",
              code == 0 and "2/2 settled; closable" in out)

        code, out, err = settlement(dict(base, **{
            "issue:kalaluthien/campaign-base#11": issue("OPEN")}), tmp)
        check("one open sub-issue refuses the close",
              code == 0 and "1/2 settled; NOT closable" in out
              and "#11" in out and " open " in out)

        # A sub-issue closed on purpose is settled; the note says which kind, and
        # AGENTS.md tells a reader to quote the note rather than the word.
        code, out, err = settlement(dict(base, **{
            "issue:kalaluthien/campaign-base#11":
                issue("CLOSED", "NOT_PLANNED")}), tmp)
        check("a sub-issue dropped as not planned still settles",
              code == 0 and "2/2 settled; closable" in out
              and "[not planned]" in out)

        code, out, err = settlement(dict(base, **{
            "issue:kalaluthien/campaign-base#11":
                issue("CLOSED", "COMPLETED")}), tmp)
        check("closed as completed with nothing to merge names its note",
              code == 0 and "[completed, no merged pull request]" in out)

        code, out, err = settlement(dict(base, **{
            "pr:kalaluthien/campaign-base#91": {"state": "CLOSED"}}), tmp)
        check("a closing pull request that never merged is dropped, not complete",
              code == 0 and "dropped" in out and "2/2 settled" in out)

        # A reading that could not be made is its own verdict. Every one of
        # these aborted the table before the fourth column existed: the reader
        # asked for a settlement and got a message about `gh`, or a traceback.
        for what, fixture in (
                ("its closing pull request is in a repository gone private",
                 {"pr:kalaluthien/campaign-base#91": {"exit": 1, "stderr": "HTTP 404"}}),
                ("its own issue cannot be read",
                 {"issue:kalaluthien/campaign-base#11": {"exit": 1, "stderr": "HTTP 404"}}),
                ("the API places its pull request in no repository",
                 {"issue:kalaluthien/campaign-base#11":
                  issue("CLOSED", "COMPLETED", prs=[91], homeless=True)})):
            code, out, err = settlement(dict(base, **fixture), tmp)
            check(f"a sub-issue reads unread when {what}",
                  code == 0 and " unread " in out and "Traceback" not in err)
            check(f"...and the count separates it from settled -- {what}",
                  "1/2 settled, 1 unread; NOT closable" in out)
            check(f"...and the refusal names the reading, not open work -- {what}",
                  "could not be read" in out and "open sub-issues remain" not in out)

        # The other end of the same rule: the campaign issue read is one call too, and
        # its failure must not come back as a table with nothing in it.
        code, out, err = settlement(dict(base, head={"exit": 1, "stderr": "HTTP 404"}), tmp)
        check("a campaign issue that did not read refuses, saying no verdict was reached",
              code != 0 and "could not read the campaign issue" in err
              and "No verdict was reached" in err and "Traceback" not in err)

        code, out, err = settlement(dict(base, head=head(labels=())), tmp)
        check("a number with no campaign label is reported as maybe a sub-issue",
              code == 0 and "may be a sub-issue" in out)

        code, out, err = settlement(dict(base, head=head(parent={"number": 7})), tmp)
        check("a campaign issue that is itself a sub-issue is reported",
              code == 0 and "sub-issue of #7" in out)

        code, out, err = settlement(dict(base, index=[sub(10), sub(11, nested=3)]), tmp)
        check("a sub-issue with members of its own is reported, not counted",
              code == 0 and "3 sub-issue(s) of its own" in out)

        code, out, err = settlement(dict(base, head=head(state="CLOSED"), **{
            "issue:kalaluthien/campaign-base#11": issue("OPEN")}), tmp)
        check("a campaign issue closed over an open sub-issue is reported",
              code == 0 and "the campaign issue is closed with sub-issues still open" in out)

        # A sub-issue filed on another repository is read there, not here.
        code, out, err = settlement(dict(base, index=[sub(10), sub(5, repo="o/other")],
                                         **{"issue:o/other#5": issue("OPEN")}), tmp)
        check("a sub-issue in another repository is read against that repository",
              code == 0 and "o/other#5" in out and "1/2 settled" in out)

        # settlement reads the index through the same function `index` prints
        # from. Moving only the parse behind a script once left `--paginate`
        # hand-written on this path, where deleting it silently dropped fourteen
        # sub-issues and turned "NOT closable" into "closable".
        check("settlement and index share one reader of the sub-issue endpoint",
              m.cmd_settlement.__code__.co_names.count("fetch_index") == 1
              and m.cmd_index.__code__.co_names.count("fetch_index") == 1)

    if not ran:
        print("FAIL  the suite ran no case at all")
        return 1
    for f in fails:
        print(f"FAIL  {f}")
    print(f"{len(ran) - len(fails)}/{len(ran)} cases pass")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
