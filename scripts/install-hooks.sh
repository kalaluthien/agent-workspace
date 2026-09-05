#!/usr/bin/env sh
# Install this repository's git hooks and its harness hooks. Idempotent; run it
# after a clone.
#
# TWO HOOK SYSTEMS, AND WHY THE SECOND IS NOT IN THIS REPOSITORY'S SETTINGS
#
# check-campaign-claim.py has to fire for a delegate whose cwd is
# <campaign>/repos/<repo>/, and that is a different git repository with its own
# settings. Probed rather than assumed: a PreToolUse hook declared in this
# repository's .claude/settings.json fired for a `claude -p` run at the
# base root and did NOT fire for one whose cwd was
# retire-workspace-board-260902/repos/dotclaude/. So it is registered in
# ~/.claude/settings.json, where every session on this machine reads it, and
# the script no-ops when cwd resolves to no campaign directory -- which is what
# makes a machine-wide registration safe for a repository-scoped rule.
#
# pre-commit chains the machine-wide guard at ~/.claude/git-hooks/no-main-commits
# (if present), then this repository's own: check-rule-readers, check-tree-shape,
# check-cross-references, and check-commit-claim -- the commit half of the
# claim gate, whose pre-tool-use half is the harness hook below.
# post-commit pushes a campaign-*/ branch as soon as it has a commit, so an
# executor never sits on a finished commit unpushed; it touches no other branch.
#
# Refuses rather than overwrites: an existing hook not written by this script, a
# symlinked hook slot (writing through it would edit a file outside this
# repository), or a repository with core.hooksPath set (git would never run what
# gets written to .git/hooks/). One exception, adopted and announced: a
# pre-commit acquire-repo.sh wrote, because the hook written here runs the same
# guard and the same claim gate and is a strict superset of it. Two writers of
# one slot, the second refusing the first's output, left every delegate clone
# with none of this repository's hooks (#178).
#
# THAT SHIM HAS TWO SHAPES. Since #190 it carries the claim gate as well as the
# guard and names itself on line 2; the two-line form written before #190 is
# still on disk in clones acquired then. `is_guard_shim` below recognises both,
# and is the one place either shape is spelled.
#
# `--git-only` installs the two git hooks and leaves ~/.claude/settings.json
# alone. The harness registration is machine-wide and points at ONE checkout;
# a clone that re-ran it would repoint every session's guard at itself, and
# the day the clone is deleted the guard refuses every call on the machine.
# acquire-repo.sh passes it for that reason.

set -e

git_only=0
for arg in "$@"; do
	case "$arg" in
		--git-only) git_only=1 ;;
		*) echo "usage: scripts/install-hooks.sh [--git-only]" >&2; exit 2 ;;
	esac
done

# --git-common-dir, never --show-toplevel: in a linked worktree the latter
# returns the worktree, while hooks live in the main checkout, so the install
# would land where git never looks. AGENTS.md states this form.
common=$(git rev-parse --path-format=absolute --git-common-dir)
root=$(cd "$(dirname "$common")" && pwd -P)
hookdir=$common/hooks
precommit=$hookdir/pre-commit
postcommit=$hookdir/post-commit
ours="$root/scripts/"
marker='# Installed by scripts/install-hooks.sh.'
# What is matched to recognise a hook this script wrote, derived from what is
# written rather than spelled twice. The extension is stripped because the
# installer's path changed with #105: a hook installed under the old name is
# still ours, and refusing it as somebody else's would strand every checkout
# that has one.
marker_match=${marker%.sh.}

# The exit status, not the value: `core.hooksPath=""` is a *set* key that git
# honours -- it runs no hook at all -- and a `-n` test walks straight past it.
if hooks_path=$(git config --get core.hooksPath); then
	if [ -z "$hooks_path" ]; then
		echo "refusing: core.hooksPath is set and empty, which disables" >&2
		echo "every hook. Writing $precommit would install nothing." >&2
		echo "Unset it (git config --unset core.hooksPath) and re-run." >&2
	else
		echo "refusing: core.hooksPath is set to '$hooks_path'." >&2
		echo "git runs hooks from there, so writing $precommit installs nothing." >&2
		echo "Chain $ours from $hooks_path/pre-commit by hand, or unset the" >&2
		echo "config for this repository and re-run." >&2
	fi
	exit 1
fi

# A pre-commit acquire-repo.sh wrote, in either of its two shapes. Anything else
# is somebody's decision this script cannot read, and is refused below.
#
# BOTH ARE PATTERNS FOR WHAT THAT SCRIPT WRITES, and this is their one home --
# the same reader it has always been, with a second shape added, not a second
# reader. It cannot be derived from acquire-repo.sh at run time: this installer
# runs inside whatever repository is being set up, and a member clone holds no
# copy of that script, so a derived read would refuse to adopt in exactly the
# clones the shim is written into.
#
# The pre-#190 form is matched WHOLE -- a shebang and one exec of the
# machine-wide guard by absolute path, two lines and no more -- because it
# carries nothing to name itself by. Clones acquired then still hold it.
# The current form is ten lines, so matching it whole would be a second copy of
# what acquire-repo.sh writes; it is matched by three things instead, and the
# marker alone is NOT enough. A hook is adopted here only if it also opens with
# the shebang and actually calls the guard, because what licenses replacing it
# is that the hook written below is a STRICT SUPERSET of it -- and a comment
# somebody pasted proves nothing about that. The marker text lives in
# acquire-repo.sh's SHIM_MARKER, with a comment pointing back here.
is_guard_shim() {
	if [ "$(wc -l <"$1" | tr -d ' ')" = 2 ]; then
		[ "$(sed -n 1p "$1")" = "#!/usr/bin/env sh" ] &&
			sed -n 2p "$1" | grep -qE '^exec "[^"]*/\.claude/git-hooks/no-main-commits" "\$@"$'
		return
	fi
	[ "$(sed -n 1p "$1")" = "#!/usr/bin/env sh" ] &&
		sed -n 2p "$1" | grep -qF '# Written by acquire-repo.sh.' &&
		grep -q 'no-main-commits' "$1"
}

# Each hook gets the same two refusals, so a second hook cannot arrive with
# weaker checks than the first. Both are about writing over somebody's decision
# this script cannot read.
check_slot() {
	slot=$1
	if [ -L "$slot" ]; then
		echo "refusing: $slot is a symlink to $(readlink "$slot")." >&2
		echo "Writing through it would edit a file outside this repository." >&2
		echo "Move it aside and re-run, or chain $ours from its target by hand." >&2
		exit 1
	fi
	# What it OBSERVED, not what it assumes: two shapes reach this branch and
	# they carry different things, so a message naming only the guard was untrue
	# of the one that also carries the claim gate.
	if [ -e "$slot" ] && is_guard_shim "$slot"; then
		echo "adopting: $slot is a shim acquire-repo.sh wrote -- $(wc -l <"$slot" | tr -d ' ') lines," >&2
		echo "calling the no-main-commits guard. The hook written here runs that" >&2
		echo "guard and this repository's own, so it is a superset; replacing it." >&2
		return 0
	fi
	if [ -e "$slot" ] && ! grep -qF "$marker_match" "$slot"; then
		echo "refusing: $slot exists and was not written by this script." >&2
		echo "Read it, then chain from it or move it aside:" >&2
		echo "  mv '$slot' '$slot.bak' && scripts/install-hooks.sh" >&2
		exit 1
	fi
}

check_slot "$precommit"
check_slot "$postcommit"

hook=$precommit
cat >"$hook" <<HOOK
#!/usr/bin/env sh
$marker Re-run it after changing this file.
#
# The line below is the one list of what this hook runs; campaign-primitives
# reads it too. Add a guard by adding it here.
# runs: check-rule-readers.py check-tree-shape.py check-cross-references.py check-commit-claim.py
set -e
# \`cmd && other\` under \`set -e\` exits 1 when the test is false, so a machine
# without the shared guard would have every commit blocked with no message.
if [ -x "\$HOME/.claude/git-hooks/no-main-commits" ]; then
	"\$HOME/.claude/git-hooks/no-main-commits" "\$@"
fi
# --show-toplevel, not --git-common-dir: the guard judges the checkout making
# the commit, not whatever another worktree happens to hold uncommitted.
#
# A guard that is absent or not executable REFUSES rather than silently
# skipping: a hook that is installed is a promise the check ran.
#
# An EMPTY declaration refuses too, for the same reason -- silence here is
# indistinguishable from nothing to check.
guards=\$(sed -n 's/^# runs: //p' "\$0")
# Word list, not string: \`# runs:\` followed by a space leaves \$guards
# non-empty and the loop running zero times -- a silent skip.
set -- \$guards
if [ \$# -eq 0 ]; then
	echo "pre-commit: REFUSING -- this hook carries no '# runs:' line, so it" >&2
	echo "  cannot tell which guards it is meant to run. Re-run" >&2
	echo "  scripts/install-hooks.sh. To commit anyway: SKIP_REPO_GUARDS=1" >&2
	[ "\${SKIP_REPO_GUARDS:-}" = 1 ] || exit 1
	echo "pre-commit: SKIP_REPO_GUARDS=1 -- committing with NO guard run." >&2
fi
for guard in \$guards; do
	g=\$(git rev-parse --show-toplevel)/scripts/\$guard
	if [ ! -x "\$g" ]; then
		echo "pre-commit: REFUSING -- \$g is missing or not executable." >&2
		echo "  This hook is installed, so the guard is expected to run." >&2
		echo "  chmod +x it, or run scripts/install-hooks.sh from a checkout" >&2
		echo "  that has it. To commit anyway you have to say so out loud:" >&2
		echo "    SKIP_REPO_GUARDS=1 git commit ..." >&2
		[ "\${SKIP_REPO_GUARDS:-}" = 1 ] || exit 1
		echo "pre-commit: SKIP_REPO_GUARDS=1 -- committing with \$guard unrun." >&2
		continue
	fi
	"\$g" --staged || exit 1
done
HOOK

chmod +x "$hook"
echo "installed: $hook"

hook=$postcommit
cat >"$hook" <<'HOOK'
#!/usr/bin/env sh
# Installed by scripts/install-hooks.sh. Re-run it after changing this file.
# runs: push-campaign-branch.sh
for s in $(sed -n 's/^# runs: //p' "$0"); do
	x=$(git rev-parse --show-toplevel)/scripts/$s
	if [ ! -x "$x" ]; then
		echo "post-commit: $x is missing or not executable." >&2
		echo "  This commit was NOT pushed. Push it yourself, or run" >&2
		echo "  scripts/install-hooks.sh from a checkout that has the script." >&2
		continue
	fi
	"$x"
done
exit 0
HOOK

chmod +x "$hook"
echo "installed: $hook"

# ---------------------------------------------------- the harness hooks
#
# Skipped under --git-only; the header says why a clone must not run this half.
if [ "$git_only" = 1 ]; then
	echo "skipped: the harness registration in ~/.claude/settings.json (--git-only)"
	exit 0
fi
#
# Registered in ~/.claude/settings.json for the reason in the header. The merge
# is done in Python because settings.json is JSON with a person's own hooks in
# it: a shell that rewrote the file would have to reproduce every key it did not
# come to change, and the one it drops is silent.
#
# The entry is keyed by the script's basename, so re-running this replaces it
# rather than stacking a second copy on every clone -- and an entry an earlier
# install left on another event (the PostToolUse --released half, gone with
# #176's records) is dropped the same way.
#
# The line below is the one list of what this installs into the harness, in the
# same shape as the `# runs:` lines above and read the same two ways: by the
# assignment under it, and by install-hooks-test, which builds its fixture from
# it. Add a harness hook by adding it here.
# installs: check-campaign-claim.py
guard=$root/scripts/$(sed -n 's/^# installs: //p' "$0")
if [ ! -x "$guard" ]; then
	echo "refusing: $guard is missing or not executable, so the claim guard" >&2
	echo "would be registered as a command that cannot run -- which reads to" >&2
	echo "every session like a rule being enforced." >&2
	exit 1
fi

python3 - "$guard" <<'PY'
import json, os, sys

guard = sys.argv[1]
name = os.path.basename(guard)
path = os.path.join(os.path.expanduser("~"), ".claude", "settings.json")

# The matcher is the tool list the guard has an opinion about. Bash is on it
# because a changing shell command is most of what an executor does; the guard
# itself decides which Bash calls count, so widening the matcher costs a process
# and never a false refusal.
MATCHER = "Edit|Write|NotebookEdit|Bash"
# Through the interpreter, never as a bare path. A bare path that has gone
# missing exits 127 from the shell, which the harness reads as a hook that did
# not block -- so a moved checkout turns the guard into a silent pass. python3
# on a missing file exits 2, the one code that refuses, so the same absence
# refuses every guarded call and says which file it could not read.
WANT = {"PreToolUse": [f'python3 "{guard}"']}
# Every event an earlier install may have registered the guard on is swept,
# so a retired half does not keep running from the slot it kept.
SWEEP = ("PreToolUse", "PostToolUse")

try:
    with open(path) as handle:
        settings = json.load(handle)
except FileNotFoundError:
    print(f"refusing: {path} does not exist. This installs INTO a person's "
          f"settings and will not create one.", file=sys.stderr)
    sys.exit(1)
except (OSError, ValueError) as e:
    print(f"refusing: {path} would not read ({e.__class__.__name__}: {e}). "
          f"Rewriting it now would lose whatever is in it.", file=sys.stderr)
    sys.exit(1)

hooks = settings.setdefault("hooks", {})
for event in SWEEP:
    commands = WANT.get(event, [])
    entries = hooks.setdefault(event, [])
    # Every entry mentioning this script goes, whatever matcher or flags it
    # carried: an old registration left beside a new one runs the guard twice
    # and, if its event moved, enforces nothing from the slot it kept.
    kept = [e for e in entries
            if not any(name in (h.get("command") or "")
                       for h in (e.get("hooks") or []))]
    dropped = len(entries) - len(kept)
    if commands:
        kept.append({"matcher": MATCHER,
                     "hooks": [{"type": "command", "command": c} for c in commands]})
        print(f"installed: {path} {event} {MATCHER} -> {name}"
              + (f" (replaced {dropped} earlier entry/entries)" if dropped else ""))
    elif dropped:
        print(f"removed: {path} {event} -> {name} ({dropped} retired entry/entries)")
    elif not entries:
        del hooks[event]                # nothing to say about this event
        continue
    hooks[event] = kept

with open(path, "w") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")
PY
