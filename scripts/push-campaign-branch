#!/usr/bin/env sh
# Push a campaign branch the moment it has a commit, and say what happened.
#
# Moved out of the post-commit hook's heredoc so it can be linted, tested, and
# listed in the scripts inventory a session is shown at start-up.
set -u

branch=$(git symbolic-ref --quiet --short HEAD) || exit 0
case "$branch" in
	campaign-*/*) ;;
	*) exit 0 ;;
esac

# mktemp, not /tmp/$$: /tmp is world-writable and a pid is guessable, so a
# pre-planted symlink there is truncated and overwritten by the redirect.
if ! err=$(mktemp); then
	echo "push-campaign-branch: mktemp failed; NOT pushing $branch." >&2
	echo "  The commit is local only. Push it yourself." >&2
	exit 0
fi
trap 'rm -f "$err"' EXIT INT TERM

# No force flag and no --no-verify: a rejected push is news, not something to
# overrule. An amend or a rebase lands here too, and the right answer for those
# is to be told, not to have the remote rewritten.
if git push --quiet origin "$branch" 2>"$err"; then
	echo "push-campaign-branch: pushed $branch"
else
	echo "push-campaign-branch: could NOT push $branch -- the commit is local only." >&2
	sed 's/^/  /' "$err" >&2
	echo "  Push it yourself before anything reads this branch as landed." >&2
fi
exit 0
