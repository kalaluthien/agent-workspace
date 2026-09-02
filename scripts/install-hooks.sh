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
# container root and did NOT fire for one whose cwd was
# retire-workspace-board-260902/repos/dotclaude/. So it is registered in
# ~/.claude/settings.json, where every session on this machine reads it, and
# the script no-ops when cwd resolves to no campaign directory -- which is what
# makes a machine-wide registration safe for a repository-scoped rule.
#
# pre-commit chains the machine-wide guard at ~/.claude/git-hooks/no-main-commits
# (if present), then this repository's own: check-rule-readers, check-tree-shape,
# check-cross-references.
# post-commit pushes a campaign-*/ branch as soon as it has a commit, so an
# executor never sits on a finished commit unpushed; it touches no other branch.
#
# Refuses rather than overwrites: an existing hook not written by this script, a
# symlinked hook slot (writing through it would edit a file outside this
# repository), or a repository with core.hooksPath set (git would never run what
# gets written to .git/hooks/).

set -e

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
# runs: check-rule-readers.py check-tree-shape.py check-cross-references.py
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
# Registered in ~/.claude/settings.json for the reason in the header. The merge
# is done in Python because settings.json is JSON with a person's own hooks in
# it: a shell that rewrote the file would have to reproduce every key it did not
# come to change, and the one it drops is silent.
#
# The two entries are keyed by the script's basename, so re-running this
# replaces them rather than stacking a second copy on every clone.
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
WANT = {
    "PreToolUse": [f'"{guard}"'],
    "PostToolUse": [f'"{guard}" --released'],
}

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
for event, commands in WANT.items():
    entries = hooks.setdefault(event, [])
    # Every entry mentioning this script goes, whatever matcher or flags it
    # carried: an old registration left beside a new one runs the guard twice
    # and, if its event moved, enforces nothing from the slot it kept.
    kept = [e for e in entries
            if not any(name in (h.get("command") or "")
                       for h in (e.get("hooks") or []))]
    dropped = len(entries) - len(kept)
    kept.append({"matcher": MATCHER,
                 "hooks": [{"type": "command", "command": c} for c in commands]})
    hooks[event] = kept
    print(f"installed: {path} {event} {MATCHER} -> {name}"
          + (f" (replaced {dropped} earlier entry/entries)" if dropped else ""))

with open(path, "w") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")
PY
