# Why the close is shaped this way

One section per step of `SKILL.md`. Read a section when a guard there looks
arbitrary, or when you are about to change it.

## Step 0 — binding

`$CAMPAIGN_DIR` is bound once, absolute, because two later steps fail silently on
a relative value: step 1 compares it against herdr's absolute `cwd`, so a
relative value matches nothing and the refusal passes having found nothing; step
5 then deletes relative to whatever directory the session happens to hold.

It is bound on both paths, the no-directory one binding the empty string
explicitly, because step 5 has to tell three states apart and *unset* is not one
of them. Unset means nobody ran this step, which is a different problem from a
campaign this machine holds no cache of.

## Step 1 — holder and agents

A live PID that is some other `claude` reads as held. That is the safe direction
to be wrong in here: refusing to take over costs a question, taking over a live
session's directory costs its work.

**Do not match `ListAgents` names against the branch.** An executor session keeps
whatever name its harness gave it and cannot rename itself, so a prefix test on
`campaign-<N>-` finds the delegates and misses exactly what `runtime/executors/`
exists to catch. `AGENTS.md` § Who is a campaign session states the rule; this is
where it bites.

## Step 2 — work only on this machine

Step 1's two unenumerable cases land here: an agent herdr has forgotten and an
executor nothing recorded both still leave their work in a checkout. The delete
spares the container checkout, but step 5 closes the anchor indexing it, so it is
read here too.

**The `[ -d ]` wrapper is what tells "no member repository" from "cannot look".**
A campaign with no member repository has no `repos/` at all, and that is
legitimate. A `repos/` that exists but cannot be read is not, and the two looked
identical while `find` carried `2>/dev/null`: an `EACCES` printed nothing, the
loop ran zero times, and the close read a repo-less campaign where there were
checkouts it was not allowed to see.

**The enumeration goes to a file, not through a pipe.** A pipeline's exit status
is its last command's, so `find | while read` discards whatever `find` said;
writing to `/tmp/checkouts-$N` puts `find`'s own failure back where a `||` can
catch it.

`find` rather than a `repos/*/` glob is a portability fix; `references/gotchas.md`
says what each shell does with an unmatched one.

## Step 4 — validate, compare, write

**`.tmp` then `mv`, and both files removed first.** A refusal that has already
truncated `/tmp/repos-before` leaves a zero-length file, and zero-length is what
a legitimate `- none` leaves — so a failed read reads as a repo-less campaign,
the one shape whose index is *meant* to be empty. Worse, the read-back compares
the two files: two failures leave two empty files and `cmp -s` prints "index
survived" over a body nobody managed to read. Absent files make `cmp -s` exit 2,
and the pre-emptive `rm -f` stops a leftover from an earlier run standing in for
either of them.

**Why the compare survives one campaign, one machine.** The body has a single
structural writer now, so the ceremony is no longer the everyday guard it was
written as. It is demoted to catching the two things the principle does not
cover, which from here look identical: a person editing the charter straight on
GitHub, which is theirs to do, and a session writing from a machine the anchor is
not `BOUND` to, which is the principle broken. Both are silent, and without the
compare one silently discards the other — modelled and witnessed. The loss is
worse than it looks, because a body write cannot touch a sub-issue link: the
index goes on naming work in a repository the `## Repos` list has dropped, and
the close then deletes that list's last copy.

## Step 5 — announce, close, delete

**Why announce at all.** Step 1's gate is local, and under one campaign, one
machine that covers everything legitimate: every agent and every executor session
is on the bound machine, step 1 saw every one that announced, and step 2 read the
container and `repos/` for the work of one that did not. A machine working this
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
