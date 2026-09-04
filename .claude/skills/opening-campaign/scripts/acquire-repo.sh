#!/usr/bin/env bash
# acquire-repo — leave a ready checkout of <owner/repo> at <dest-path>.
#
#   .claude/skills/opening-campaign/scripts/acquire-repo.sh \
#       <owner/repo> <dest-path> [--branch <branch>]
#
# The one interface through which a campaign gets a repository. A caller asks
# for a repository, at a path, on a branch; how it got there is not its
# business.
#
# It lives under the skill because opening-campaign is its only caller: a
# repository is acquired when a campaign is opened or joined, and at no other
# moment. scripts/campaign-primitives.py walks .claude/skills/*/scripts/ as a
# second root so a script parked here is still announced.
#
# Bash, not Python: every step is already a `git` or `gh` invocation, so a
# shell function *is* a strategy with nothing between it and the command a
# person would type by hand.

set -euo pipefail

usage() {
	cat >&2 <<'EOF'
usage: acquire-repo <owner/repo> <dest-path> [--branch <branch>]

Leaves a ready checkout of <owner/repo> at <dest-path>, with <branch> checked
out (created from the default branch if it exists nowhere yet). Safe to re-run:
a second call over the same destination converges instead of failing.
EOF
	exit 2
}

log() { printf 'acquire-repo: %s\n' "$*" >&2; }
die() { printf 'acquire-repo: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- arguments

repo=""
dest=""
branch=""

while [ $# -gt 0 ]; do
	case "$1" in
		--branch)
			[ $# -ge 2 ] || usage
			branch=$2
			shift 2
			;;
		--branch=*)
			branch=${1#--branch=}
			shift
			;;
		-h|--help) usage ;;
		-*) die "unknown option: $1" ;;
		*)
			if   [ -z "$repo" ]; then repo=$1
			elif [ -z "$dest" ]; then dest=$1
			else die "unexpected argument: $1"
			fi
			shift
			;;
	esac
done

[ -n "$repo" ] && [ -n "$dest" ] || usage
case "$repo" in
	*/*/*|/*|*/) die "expected <owner/repo>, got: $repo" ;;
	*/*) ;;
	*) die "expected <owner/repo>, got: $repo" ;;
esac

command -v git >/dev/null 2>&1 || die "git is not installed"

# ------------------------------------------------------------- building it
#
# `clone_into()` builds a checkout that does not exist yet; `acquire()` owns
# everything that is the same however the checkout arrived -- the
# already-acquired test, the wrong-repository refusal, convergence on a re-run,
# and installing the commit guard. So `clone_into()` only ever runs against a
# destination that is absent or empty, and never implements idempotency itself.
#
# `checkout_branch()` and `install_commit_guard()` are shared but *not*
# universal, and another way of producing a checkout would have to face them
# rather than assume them: `checkout_branch()` selects a branch with `git
# switch`, which fails inside a linked worktree when that branch is checked out
# elsewhere. `install_commit_guard()` resolves the hooks directory, which for a
# linked worktree is the *common* directory back in the source checkout, and
# refuses when that path falls outside the destination rather than silently
# guard another campaign's tree.

clone_into() {
	local repo=$1 dest=$2 branch=$3

	mkdir -p "$(dirname "$dest")"
	log "cloning $repo into $dest"
	if command -v gh >/dev/null 2>&1; then
		gh repo clone "$repo" "$dest" -- --quiet
	else
		git clone --quiet "https://github.com/$repo.git" "$dest"
	fi
	checkout_branch "$dest" "$branch"
}

# ------------------------------------------------------------ shared helpers

# Print the owner/repo an existing checkout's origin points at. Reads the last
# two path segments, so ssh, https, and a non-GitHub host all parse, rather than
# only a URL containing the literal "github.com".
remote_slug() {
	local url name rest
	url=$(git -C "$1" remote get-url origin 2>/dev/null) || return 1
	url=${url%.git}
	url=${url%/}
	name=${url##*/}
	rest=${url%/*}
	printf '%s/%s\n' "${rest##*[:/]}" "$name"
}

dir_is_empty() { [ -z "$(ls -A "$1" 2>/dev/null)" ]; }

checkout_branch() {
	local dest=$1 branch=$2
	if [ -z "$branch" ]; then
		log "on branch $(git -C "$dest" branch --show-current)"
		return 0
	fi
	if [ "$(git -C "$dest" branch --show-current)" = "$branch" ]; then
		log "already on branch $branch"
	elif git -C "$dest" show-ref --verify --quiet "refs/heads/$branch"; then
		git -C "$dest" switch --quiet "$branch"
		log "switched to local branch $branch"
	elif git -C "$dest" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
		git -C "$dest" fetch --quiet origin "$branch"
		git -C "$dest" switch --quiet --track "origin/$branch"
		log "checked out remote branch $branch"
	else
		git -C "$dest" switch --quiet -c "$branch"
		log "created branch $branch"
	fi
}

# Git hooks do not clone, so the guard that blocks direct commits to main has to
# be installed into every checkout, whatever strategy produced it. A failure
# here is fatal: a caller reading success over an unguarded checkout is exactly
# the silent case the guard exists to prevent.
#
# One writer per hook slot. A repository that ships scripts/install-hooks.sh
# owns its own hooks, and that installer already chains the guard; so it is run
# here, with --git-only because the harness half is the base checkout's and a
# clone must not repoint it. The two-line shim below is written only into a
# checkout with no installer, and the installer adopts that shim on a re-run --
# which is what lets this function converge over a checkout it already guarded
# either way. Before #178 the shim was written unconditionally and the installer
# refused over it, so no delegate clone ever held the repository's hooks.
install_commit_guard() {
	local dest=$1
	local guard="$HOME/.claude/git-hooks/no-main-commits"
	local hooks hook dest_abs installer

	if [ ! -x "$guard" ]; then
		log "no executable guard at $guard, so $dest would be left unguarded."
		log "Restore it from the checkout that owns it:"
		log "  git -C \"\$HOME/.claude\" checkout -- git-hooks/no-main-commits"
		log "  chmod +x \"$guard\""
		die "refusing to leave $dest unguarded"
	fi

	hooks=$(git -C "$dest" rev-parse --path-format=absolute --git-path hooks)
	dest_abs=$(cd "$dest" && pwd -P)
	case "$hooks" in
		"$dest_abs"/*) ;;
		*) die "hooks for $dest resolve to $hooks, outside the checkout; refusing to guard another tree" ;;
	esac

	installer="$dest/scripts/install-hooks.sh"
	# The execute bit alone must not pick the branch: an installer present but
	# not executable would fall through to the shim and silently restore the
	# state this function exists to end.
	if [ -f "$installer" ] && [ ! -x "$installer" ]; then
		die "$installer exists but is not executable; chmod +x it and re-run"
	fi
	if [ -x "$installer" ]; then
		log "running the repository's own installer: $installer --git-only"
		if ! (cd "$dest" && "$installer" --git-only); then
			die "the repository's install-hooks.sh exited $? -- read what it said above"
		fi
		# The invariant is verified, not trusted: the installer belongs to the
		# repository, and its hook has to chain the guard for success here to
		# mean the same thing it means on the shim path.
		grep -q 'no-main-commits' "$hooks/pre-commit" 2>/dev/null ||
			die "the installer left $hooks/pre-commit without the no-main-commits guard; refusing to call $dest guarded"
		log "installed the repository's git hooks, which chain the no-main-commits guard"
		return 0
	fi

	mkdir -p "$hooks"
	hook="$hooks/pre-commit"

	# `>|` in the printed remediation, not `>`: it is pasted into the operator's
	# shell, where `noclobber` makes a plain `>` refuse over the existing hook.
	if [ -e "$hook" ] && ! grep -q 'no-main-commits' "$hook"; then
		log "$hook exists and does not call the guard. Replace it with:"
		log "  printf '%s\\n' '#!/usr/bin/env sh' 'exec \"\$HOME/.claude/git-hooks/no-main-commits\" \"\$@\"' >| $hook"
		log "  chmod +x $hook"
		die "refusing to overwrite an existing pre-commit hook"
	fi

	printf '%s\n' '#!/usr/bin/env sh' "exec \"$guard\" \"\$@\"" > "$hook"
	chmod +x "$hook"
	log "installed the no-main-commits guard"
}

# ------------------------------------------------------------------- acquire

acquire() {
	local repo=$1 dest=$2 branch=$3 have

	if [ -e "$dest/.git" ]; then
		have=$(remote_slug "$dest") || die "$dest is not a usable git checkout"
		[ "$have" = "$repo" ] ||
			die "$dest already holds $have, not $repo — refusing to touch it"
		log "already present: $dest ($repo)"
		git -C "$dest" fetch --quiet origin
		checkout_branch "$dest" "$branch"
	else
		[ ! -e "$dest" ] || [ -d "$dest" ] ||
			die "$dest exists and is not a directory"
		[ ! -d "$dest" ] || dir_is_empty "$dest" ||
			die "$dest is a non-empty directory that is not a git checkout"

		clone_into "$repo" "$dest" "$branch"
	fi

	install_commit_guard "$dest"
	log "ready: $dest"
}

acquire "$repo" "$dest" "$branch"
