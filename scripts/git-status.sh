#!/usr/bin/env bash
# ============================================================================
#  nachimux · which branch this tab is on
#
#  status-left was the workspace name and 120 reserved columns of nothing. The
#  thing you actually need to know constantly -- what branch the tab you are
#  looking at is on -- lived nowhere.
#
#  It publishes to an option rather than running from #() in the bar, for the
#  same reason the attention badge does: #() re-runs every status-interval
#  forever, and `git status` is not something to run on a timer. This runs when
#  you move -- switching tab, switching workspace, focusing a pane, attaching --
#  which is exactly when the answer can have changed out from under you.
#
#  The trade that buys: commit without leaving the pane and the marker is stale
#  until you move. That is the right way round. The bar matters when you are
#  scanning tabs, and by then you have moved.
#
#  Deliberately NOT cached. The obvious key -- .git/index's mtime -- is wrong:
#  it moves on stage, commit and checkout, but NOT when you edit a tracked file,
#  which is precisely when the dirty marker is supposed to appear. A cache that
#  is stale for the common case is worse than no cache, and since this only runs
#  on movement rather than on a timer, it was buying about 50ms nobody can see.
# ============================================================================
set -uo pipefail

dir="${1:-}"
[[ -z "$dir" ]] && dir="$(tmux display -p '#{pane_current_path}' 2>/dev/null)"
[[ -d "$dir" ]] || { tmux set -g @nachimux_git "" 2>/dev/null; exit 0; }

command -v git >/dev/null 2>&1 || { tmux set -g @nachimux_git "" 2>/dev/null; exit 0; }

# --no-optional-locks: never write to someone else's repo just by looking at it.
top="$(cd "$dir" 2>/dev/null && git --no-optional-locks rev-parse --show-toplevel 2>/dev/null)"
[[ -z "$top" ]] && { tmux set -g @nachimux_git "" 2>/dev/null; exit 0; }

branch="$(cd "$top" && git --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)"
[[ "$branch" == HEAD ]] && branch="$(cd "$top" && git --no-optional-locks rev-parse --short HEAD 2>/dev/null)"
[[ -z "$branch" ]] && { tmux set -g @nachimux_git "" 2>/dev/null; exit 0; }

# -uno: untracked files are not "dirty" for this purpose, and counting them is
# the expensive half of git status on a big tree.
dirty=""
if ! (cd "$top" && git --no-optional-locks diff --quiet --ignore-submodules -- 2>/dev/null) \
   || ! (cd "$top" && git --no-optional-locks diff --cached --quiet --ignore-submodules -- 2>/dev/null); then
  dirty="*"
fi

tmux set -g @nachimux_git "${branch}${dirty}" 2>/dev/null || true
