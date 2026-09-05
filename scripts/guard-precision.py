#!/usr/bin/env python3
"""Read the claim guard's precision off its own verdict log.

    scripts/guard-precision.py [LOG ...] [--minutes N] [--base PATH] [--pairs N]

WHY THIS EXISTS. Every false positive `check-campaign-claim.py` has had was
found by whoever it hit, after the fact, and filed by hand. The guard runs on
every `Bash`, `Edit` and `Write` of every session on this machine, so its
precision is the campaign's running cost, and nothing measured it: a refusal
left no record, the session retried in another shape, and the next session paid
the same refusal again (kalaluthien/campaign-base#196).

THE METHOD, WRITTEN BEFORE ANY NUMBER.

  1. Read every verdict line the guard wrote. With no LOG named, that is every
     `runtime/guard.log` under `--base`: one per campaign directory, plus the
     base's own. A log that is not there is NAMED, not skipped -- "I could not
     look" is not "I looked and found nothing".
  2. For each REFUSED line, look forward in the SAME SESSION for an `allowed`
     line within `--minutes` (default 30) whose target matches. That pair is a
     SUSPECTED false positive: the session wanted the same thing, was refused,
     and got it in another shape.
  3. A refusal with no matching allow after it is counted HELD.

WHAT "THE SAME TARGET" MEANS, and it is three readings because a call has three
kinds of target:

  * the sub-issue numbers the command's `gh` writes name, read through the
    guard's own `issue_target` -- imported, so a change to how the guard reads a
    number moves this with it;
  * the file path, for a file tool;
  * the command's first word, reduced to a basename, and only when neither of
    the other two found anything. This is the loosest of the three and it is
    what catches the shape that keeps happening: `git commit` refused, then
    `git commit` allowed a minute later.

THE COMMAND IT READS IS THE LOGGED ONE, cut at 200 bytes by the guard, so a
`gh` write past that cut is invisible here and the call falls to the basename
reading. Widening the cut would put whole document bodies in a machine-local
log this never deletes; the loss is a pair not made, never a pair invented.

WHAT A NUMBER HERE IS AND IS NOT. A suspected false positive is a PAIR, not a
verdict: a session may legitimately be refused and then legitimately allowed
after taking a claim, and that pair looks identical from the log. So the output
is the pairs themselves, verbatim, for a person to read -- and the rate beside
each refusal sentence is a place to look, not a finding. The refusal sentences
with a rate above zero are what #196 step 3 files as sub-issues, each citing
its pairs.

GROUPED BY THE REFUSAL SENTENCE, with the numbers and paths in it replaced, so
"no claim covering a write to #9" and "...to #11" are one row. The raw sentence
of the first pair is printed under each row.
"""
import argparse
import collections
import datetime
import glob
import importlib.machinery
import importlib.util
import json
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
LOG_NAME = os.path.join("runtime", "guard.log")
# What varies between two instances of one refusal: a number, an absolute path,
# a quoted fragment. Replaced so the grouping is by the SENTENCE and not by the
# call that happened to trigger it.
VARYING = [(re.compile(r"/\S+"), "<path>"), (re.compile(r"#?\b\d+\b"), "N")]


def guard():
    """The guard module, imported. `issue_target` and `segments` are how it
    decides which sub-issue a command names, and this file must agree with it
    rather than keep a second answer (AGENTS.md: no second reader of a rule a
    script owns)."""
    src = HERE / "check-campaign-claim.py"
    spec = importlib.util.spec_from_loader(
        "ccc", importlib.machinery.SourceFileLoader("ccc", str(src)))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def targets(g, row):
    """The set of things this call was about. Empty means nothing to match on,
    and a refusal with an empty set can never be paired -- which is reported
    as its own count rather than folded into HELD."""
    out = set()
    if row.get("target"):
        out.add(("path", row["target"]))
    command = row.get("command") or ""
    if command:
        segs, _why = g.segments(command)
        for seg in segs or []:
            word, rest = g.head(seg)
            if word == "gh":
                n = g.issue_target(rest)
                if n:
                    out.add(("issue", n))
        # THE BASENAME IS A FALLBACK AND ONLY A FALLBACK. Added beside the
        # others it made every `gh` call match every other `gh` call, so a
        # refusal on #9 paired with an allow on #12 and the rate went to 100%
        # over two unrelated lines. It is the reading for the calls the other
        # two cannot see -- `git commit` refused, `git commit` allowed a minute
        # later, which is #193's shape.
        first = command.split()
        if first and not out:
            out.add(("argv0", first[0].rsplit("/", 1)[-1]))
    return out


def when(row):
    try:
        return datetime.datetime.fromisoformat(row["at"])
    except (KeyError, ValueError):
        return None


def normalize(sentence):
    for pat, sub in VARYING:
        sentence = pat.sub(sub, sentence)
    return sentence.strip()


def read_logs(paths):
    """(rows, notes). Every line that parses, in time order, with one note per
    file saying what was read from it -- including the ones that were not
    there, which is the reading a silent skip destroys."""
    rows, notes = [], []
    for p in paths:
        if not os.path.exists(p):
            notes.append(f"{p}: absent, so nothing was read from it")
            continue
        good = bad = 0
        with open(p, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if not line.strip():
                    continue
                try:
                    rows.append(json.loads(line))
                    good += 1
                except ValueError:
                    bad += 1
        notes.append(f"{p}: {good} verdict(s) read"
                     + (f", {bad} line(s) that would not parse" if bad else ""))
    rows.sort(key=lambda r: r.get("at", ""))
    return rows, notes


def pair_up(g, rows, minutes):
    """(pairs, held, unpairable). One pass per session."""
    by_session = collections.defaultdict(list)
    for r in rows:
        by_session[r.get("session", "")].append(r)
    window = datetime.timedelta(minutes=minutes)
    pairs, held, unpairable = [], [], []
    for _sid, seq in by_session.items():
        for i, r in enumerate(seq):
            if r.get("verdict") != "REFUSED":
                continue
            mine = targets(g, r)
            if not mine:
                unpairable.append(r)
                continue
            t0 = when(r)
            match = None
            for later in seq[i + 1:]:
                if later.get("verdict") != "allowed":
                    continue
                t1 = when(later)
                if t0 is not None and t1 is not None and t1 - t0 > window:
                    break
                if mine & targets(g, later):
                    match = later
                    break
            (pairs if match else held).append((r, match) if match else r)
    return pairs, held, unpairable


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("logs", nargs="*", help="verdict logs; default: every "
                                           "runtime/guard.log under --base")
    p.add_argument("--minutes", type=float, default=30.0)
    p.add_argument("--base", default=str(Path.home() / "campaign-base"))
    p.add_argument("--pairs", type=int, default=5,
                   help="how many pairs to print verbatim per refusal sentence")
    a = p.parse_args(argv)

    base = Path(os.path.expanduser(a.base))
    paths = a.logs or sorted(
        {str(base / LOG_NAME)}
        | set(glob.glob(str(base / "*-[0-9][0-9][0-9][0-9][0-9][0-9]" / LOG_NAME))))
    rows, notes = read_logs(paths)
    print(f"guard-precision: read {len(rows)} verdict(s) from "
          f"{len(paths)} log(s), pairing window {a.minutes} minute(s)")
    for n in notes:
        print(f"  {n}")
    if not rows:
        # A REPORT OVER NOTHING IS NOT A CLEAN REPORT. Exiting 0 here would put
        # "0 suspected false positives" in front of a reader who would take it
        # for a measurement.
        print("  nothing to measure: no verdict has been logged yet")
        return 1

    g = guard()
    pairs, held, unpairable = pair_up(g, rows, a.minutes)
    refusals = [r for r in rows if r.get("verdict") == "REFUSED"]
    print(f"  {len(refusals)} refusal(s), {len(rows) - len(refusals)} allow(s)")
    print(f"  {len(pairs)} suspected false positive(s), {len(held)} refusal(s) "
          f"held, {len(unpairable)} with nothing to match on")

    by_sentence = collections.defaultdict(lambda: {"n": 0, "fp": []})
    for r in refusals:
        by_sentence[normalize(r.get("reason", ""))]["n"] += 1
    for r, later in pairs:
        by_sentence[normalize(r.get("reason", ""))]["fp"].append((r, later))

    print("\n  refusals  suspected  rate   sentence")
    for sentence, d in sorted(by_sentence.items(),
                              key=lambda kv: (-len(kv[1]["fp"]), -kv[1]["n"])):
        rate = len(d["fp"]) / d["n"] if d["n"] else 0.0
        print(f"  {d['n']:>8}  {len(d['fp']):>9}  {rate:>4.0%}   "
              f"{sentence[:140]}")

    for sentence, d in sorted(by_sentence.items(), key=lambda kv: -len(kv[1]["fp"])):
        if not d["fp"]:
            continue
        print(f"\n  {sentence[:100]}")
        for r, later in d["fp"][:a.pairs]:
            print(f"    REFUSED {r.get('at', '?')} {r.get('tool', '?')}: "
                  f"{(r.get('command') or r.get('target') or '')[:100]}")
            print(f"    allowed {later.get('at', '?')} "
                  f"{later.get('tool', '?')}: "
                  f"{(later.get('command') or later.get('target') or '')[:100]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
