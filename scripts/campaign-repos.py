#!/usr/bin/env python3
"""Read the `## Repos` list of a campaign README or campaign issue body.

    scripts/campaign-repos.py <path>

The one reader of that list, and the one statement of what it refuses. AGENTS.md
used to enumerate these and no longer does, which left the enumeration alive only
as exit strings in the code below.

  no `## Repos` heading       the list is not there at all, and a missing list is
                              not an empty one.
  a malformed line under it   anything that is not `- owner/repo` or `- none`,
                              which is also what a surviving `<owner/repo>`
                              placeholder is. Skipping it silently made a list
                              written `* owner/repo` read as empty.
  an empty list               indistinguishable from a list a bad write dropped,
                              and this list is the only copy of the repository
                              index the close does not delete.
  a mixed list                `- none` beside a repository. Nothing in it says
                              whether `none` is a sentinel somebody forgot or a
                              repository the list means to name, and neither
                              reading can be acted on.
  colliding checkouts         two entries whose checkout directory `repos/<name>/`
                              is the same, so the second acquire overwrites the
                              first without a word.
  the base                    `## Repos` lists the MEMBER repositories a campaign
                              clones; the base reaches its campaign directory by
                              its own route, so a list naming it would acquire a
                              second checkout. Prose said so in three files and
                              no reader enforced it (#205).

`slug`, `key` and `BASE_REPO` are exported for `scripts/campaign-claim.py`, which
compares a sub-issue's `Repository:` line to this list: one reader of what makes
two spellings the same repository, rather than two that agree by both being exact.

scripts/check-rule-readers.py is the second reader that keeps this claim true: it
refuses a commit that stages a `grep`, `sed`, `awk`, `rg`, `jq` or Python
line-reading parse naming `## Repos` or `owner/repo` -- as code in any tracked
markdown outside scripts/, inside a fence or a four-space indent, reading the
index rather than the working tree. A parse naming no tool, a bare `while read`
with a `case`, is outside the claim. It
catches a pasted copy, not a re-implementation that names nothing; see its
header. Removing the guard returns this line to being a hope.

The contract callers hold it to:

  exit 0, one `owner/repo` per line   the list names repositories
  exit 0, no output                   the list is exactly `- none`, so the
                                      campaign has no member repository and a
                                      caller loops zero times without a special
                                      case
  exit 1, one line on stderr          the list is wrong, and the line says how

opening-campaign step 4 runs it and writes `runtime/repos`; step 5 reads that
file. Its passage on adding a repository runs it again before the sync, and
closing-campaign step 4 runs it over the README and over the body GitHub stored.
"""
import re
import sys

HEADING = re.compile(r"^## Repos\s*$")
NEXT_SECTION = re.compile(r"^## ")
COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)
ITEM = re.compile(r"^- (\S.*)$")
# An entry is `owner/repo` or the sentinel, and the sentinel is spelled exactly.
ENTRY = re.compile(r"^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$")
NONE = "none"

# THE BASE'S OWN SLUG LIVES HERE because this is the reader that has to refuse
# it, and `scripts/campaign-claim.py` imports it from here rather than keeping a
# second spelling: that file is the only other reader that compares a slug to
# the base, and two copies of a name would drift on the first rename. It cannot
# go the other way -- campaign-claim.py already reads this file, and the pair
# would import in a circle.
BASE_REPO = "kalaluthien/campaign-base"

# WHAT A SLUG IS ALLOWED TO ARRIVE WRAPPED IN. `## Repos` is authored from a
# template and stays strict: `ENTRY` above admits `owner/repo` and nothing else,
# and a list written any other way is refused where it is written. A
# `Repository:` line on a sub-issue is prose a person types, and the same
# repository arrives there as `owner/repo`, in backticks, in angle brackets,
# with a trailing slash, with a `.git`, or in another case. Those are one
# repository, and comparing them raw made a scope refusal say "this campaign is
# not for that repository" when the truth was "that line was not read as a slug"
# (kalaluthien/campaign-base#205). `slug` and `key` are the ONE reader of that,
# used by the base check here and by campaign-claim.py's `Repository:` reading.
#
# ANGLE BRACKETS ARE NOT A WRAPPER, and this is the one entry that has to be
# argued rather than listed: `<owner/repo>` is the sub-issue template's
# PLACEHOLDER, so stripping the brackets would read an unfilled template as a
# repository literally named `owner/repo` and cut a ref for it. A placeholder is
# an absent answer, and it stays one.
WRAPPERS = "`'\" \t"
DOT_GIT = ".git"


def slug(text):
    """The repository this text names, wrappers and a `.git` removed and the
    CASE LEFT ALONE, or None when it names none.

    None is a REFUSAL and never a pass-through: a caller that fell back to the
    raw text on None would restore exactly the raw comparison this replaces.
    Case is left alone because this is what gets printed and passed to `gh` --
    `key` below is the thing to compare with, and the two are separate so that
    a case-folded slug never reaches a reader as the repository's name."""
    s = (text or "").strip().strip(WRAPPERS).rstrip("/")
    if s.lower().endswith(DOT_GIT):
        s = s[:-len(DOT_GIT)]
    s = s.strip("/")
    return s if ENTRY.match(s) else None


def key(text):
    """The comparison key: `slug` case-folded, because GitHub does not tell
    `Web` from `web` and two readers that disagree about that refuse each
    other's repositories. None when the text names no repository."""
    s = slug(text)
    return None if s is None else s.casefold()


def is_base(text):
    """Whether this text names the base, however it was spelled."""
    return key(text) is not None and key(text) == key(BASE_REPO)


def section(text):
    """The non-blank lines under `## Repos`, or None when there is no heading."""
    out, inside = [], False
    for line in COMMENT.sub("", text).splitlines():
        if HEADING.match(line):
            inside = True
            continue
        if inside:
            if NEXT_SECTION.match(line):
                break
            if line.strip():
                out.append(line.rstrip())
    return out if inside else None


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    path = sys.argv[1]
    try:
        with open(path, encoding="utf-8") as f:
            lines = section(f.read())
    except OSError as e:
        sys.exit(f"campaign-repos: cannot read {path}: {e.strerror}")

    if lines is None:
        sys.exit(f"campaign-repos: no `## Repos` heading in {path}")

    items = []
    for line in lines:
        m = ITEM.match(line)
        if not m:
            sys.exit(f"campaign-repos: malformed line under ## Repos: {line}")
        entry = m.group(1).strip()
        if entry != NONE and not ENTRY.match(entry):
            # `<owner/repo>` from the template lands here too, and reads as what
            # it is: a line that is neither a repository nor the sentinel.
            sys.exit(f"campaign-repos: malformed line under ## Repos: - {entry}")
        # THE BASE IS NEVER A MEMBER OF THIS LIST, and until #205 that was
        # prose in three files with no reader. `## Repos` says which
        # repositories to CLONE when a campaign opens; the base reaches
        # `<campaign>/repos/campaign-base/` by its own route, so a list naming
        # it would have step 5 acquire it a second time. The claim path is
        # unaffected either way -- `campaign-claim.py` exempts the base before
        # it reads the list -- so this refusal is the structural gap being
        # closed, not a live break being fixed.
        if is_base(entry):
            sys.exit(f"campaign-repos: `## Repos` names the base ({entry}); it "
                     f"lists the MEMBER repositories a campaign clones, and the"
                     f" base is a member of its own campaign by another route")
        items.append(entry)

    if not items:
        sys.exit(f"campaign-repos: the ## Repos list is empty in {path}")

    repos = [i for i in items if i != NONE]
    if len(repos) != len(items):
        if repos:
            plural = "y" if len(repos) == 1 else "ies"
            sys.exit(f"campaign-repos: `- none` is mixed with {len(repos)} repository"
                     f" entr{plural}; the list is `- none` alone or repositories,"
                     " never both")
        return                     # `- none` alone: no repositories, and that is fine

    # Every entry becomes a checkout at repos/<name>/, so two entries ending in
    # the same name are one directory and the second acquire overwrites the
    # first. Case-folded: the filesystem here does not tell `Web` from `web`.
    # `where` and not `key`: `key` is this module's exported reader, and a local
    # of that name shadowed it inside the one function that might come to need
    # it. Latent when a review found it, and a rename is cheaper than the day it
    # is not.
    seen = {}
    for i in repos:
        where = i.rsplit("/", 1)[-1].casefold()
        if where in seen:
            if seen[where] == i:
                sys.exit(f"campaign-repos: duplicate entry under ## Repos: {i}")
            sys.exit("campaign-repos: two entries share the checkout directory"
                     f" repos/{i.rsplit('/', 1)[-1]}/: {seen[where]} and {i}")
        seen[where] = i

    print("\n".join(repos))


# GUARDED, so campaign-claim.py can import `slug`, `key` and `BASE_REPO` without
# running the reader. It used to call `main()` at import time, which is why that
# file ran this one as a subprocess; it still does for the LIST, because the
# refusals above are exit strings and reading them back as a verdict is what
# keeps one reader rather than two.
if __name__ == "__main__":
    main()
