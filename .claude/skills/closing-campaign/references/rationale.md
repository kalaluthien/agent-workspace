# Why the close is shaped this way

One section per step of `SKILL.md`. Read a section when a guard there looks
arbitrary, or when you are about to change it.

## Step 0 — binding

`$CAMPAIGN_DIR` is bound once, absolute, because two later steps fail silently on
a relative value: step 1 compares it against herdr's absolute `cwd`, so a
relative value matches nothing and the refusal passes having found nothing; step
5 then deletes relative to whatever directory the session happens to hold.

It is always bound to a real directory. A campaign bound here with no directory
is scaffolded first — `opening-campaign` steps 2 and 4, step 2 being where the
slug and kind step 4 needs are chosen — because `runtime/claims/` has no other
home (#52, "The claim records need a directory"). The
empty-string path that once stood here, with steps 1, 2 and 4 skipped, is
retired: it skipped exactly the gates that protect the delete. Unset or empty now
means step 0 never ran, which is the wrong-cwd hazard the guard in step 5 exists
for.

**What the gates are worth on that path, which is not what "restored" would
claim.** When step 0 creates the tree, step 1 and step 2 then read a directory
seconds old: no herdr `cwd` can be under it, `runtime/claims/` is empty
because it was just copied, and there is nothing uncommitted in it. They cannot
fail, so they must not be reported as passed. The soundness argument is that
they have nothing to find: an agent of this campaign is launched into
`<campaign>/repos/<repo>/` and a session working one of its subtasks is recorded
in `<campaign>/runtime/claims/`, and both need a directory that did not exist —
so a campaign never worked on this machine can have no local executor to miss.
The residue is the one case that breaks the premise: a directory that existed
here and was deleted by hand without a close, leaving agents alive with their
tree gone. Nothing local can see that, and step 5's announcement on the anchor
is what covers it. Step 1 reports "not applicable" on this path rather than
"passed", so a reader is never told a vacuous gate held.

## Step 1 — the agents

There is no holder to read. The holding session is retired (`AGENTS.md` § Who is
a campaign session), so this step asks only what is live under the tree, and it
asks it of both records because either alone is blind to half the executors.

A live PID that is some other `claude` reads as held. That is the safe direction
to be wrong in here: leaving a claim standing costs a question, deleting a live
session's tree costs its work.

**Do not match `ListAgents` names against the branch.** A name and a branch are
two strings on purpose (`AGENTS.md` § Naming a session): a session is named
`campaign-<anchor>-<role>-<n>`, which carries no subtask at all, and it can be
changed while the claim cannot. So a test built on the
branch string finds whatever happens to match and misses what
`runtime/claims/` exists to catch. `AGENTS.md` § Who is a campaign session states the rule; this is
where it bites.

## Step 2 — work only on this machine

Step 1's two unenumerable cases land here: an agent herdr has forgotten and an
executor nothing recorded both still leave their work in a checkout. The delete
spares the container checkout, but step 5 closes the anchor indexing it, so it is
read here too.

**Why the reading is a script and not the nine commands it replaced.** Absent
`repos/` and unreadable `repos/`, a pipeline swallowing the enumeration's own
exit status, and a portable enumeration are four things a gate written in prose
has to get right in whatever shell the person is in — and each of them fails by
reporting nothing, which reads as a pass. `scripts/campaign-local-work` owns all
four, its exit status separates "the reading failed" from the verdict, and its
docstring carries the evidence. This step keeps only what a reader must decide:
which rows are blockers.

## Step 4 — validate, compare, write

**`.tmp` then `mv`, and both files removed first.** A refusal that has already
truncated `/tmp/repos-before` leaves a zero-length file, and zero-length is what
a legitimate `- none` leaves — so a failed read reads as a repo-less campaign,
the one shape whose index is *meant* to be empty. Worse, the read-back compares
the two files: two failures leave two empty files and `cmp -s` prints "index
survived" over a body nobody managed to read. Absent files make `cmp -s` exit 2,
and the pre-emptive `rm -f` stops a leftover from an earlier run standing in for
either of them.

**Why the compare is the everyday guard under one campaign, one machine** — the
three causes of a silent overwrite it catches, and why the loss is worse than
it looks — is
`AGENTS.md` § Compare then write the anchor issue body, which states it in full
and is the copy to correct.

## Step 5 — announce, close, delete

**Why announce at all.** Step 1's gate is local, and under one campaign, one
machine that covers everything legitimate: every agent and every executor session
is on the bound machine, step 1 enumerates `runtime/claims/` and so sees every
one that wrote a record, and step 2 read the container and `repos/` for the work
of one that did not. A machine working this
campaign against the binding is what neither can see, and no cheap local check
fixes it. Announcing narrows that window rather than closing it — a session that
never comments is invisible either way — and what keeps it survivable is that a
delegate pushes as soon as it has one commit, so a tree deleted underneath it
costs uncommitted work and nothing more.

**`-prune` on the two exact paths, not a `*/runtime*` pattern.** A pattern also
hides `scripts/repos-helper.sh` and anything else whose name merely contains
`repos` or `runtime` — an omission from a listing whose whole job is to omit
nothing (probed: the pattern form drops exactly that file).

**`grep . || echo` rather than a `${LEFTOVERS:-...}` default**, so the words are
written by a listing that really ran rather than by an assignment that never
happened. That branch fires only for a directory whose scaffold was taken out by
hand: an intact one always lists at least `AGENTS.md`, `CLAUDE.md`, `README.md`
and `scripts/`.

**What makes the claim-ref release sighted is step 3, not step 1.** Every subtask
is settled or disposed of by then, so no claim ref can be an executor's live
workspace — and step 3 runs on the no-directory path too, where step 1 was
skipped, and it sees hands and subagent executors that no `herdr agent list` row
would. `AGENTS.md` forbids deleting a claim ref while an agent on your machine
works it; this is the one place where that has been established for every ref at
once. Reaching into a member repository's refs from a close would be the
cross-repository sweep this container forbids.

**Ancestry, not equality**, in numbers: a zero-commit claim compared against
today's `main` sha reads unequal and would be refused as holding work — exactly
the ref the step exists to release. Probed: a claim four commits behind reads
`ahead_by=0 behind_by=4 status=behind`. `matching-refs` returns an empty array
rather than a 404 when a campaign claimed nothing (probed), so the loop runs zero
times and says nothing.

**A machine the campaign was `BOUND` to before a migration may still hold a
directory of its own**: a stale cache, untouched by this delete, with nothing
durable in it.
