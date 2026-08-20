#!/usr/bin/env bash
# ============================================================================
#  nachimux · record a tab visit into the MRU stack
#
#  Wired to the tab/workspace switch hooks: every time you land somewhere, we
#  push it to the front of a small most-recently-used list, de-duplicated and
#  capped. tmux keeps no visit history of its own, so we keep one.
#
#    $1 = window_id  that just got focus   → tab-mru,  powers the finder's
#                                            "recent" mode (prefix B)
#    $2 = session_id it belongs to         → ws-mru,   powers "workspaces"
#                                            (prefix W)
#
#  Two lists rather than one, because "the tab I was just in" and "the project I
#  was just in" are different questions: bouncing between four tabs of one
#  workspace should not push every other workspace out of the workspace list.
#
#  Deliberately tiny and fire-and-forget (the hook backgrounds it). Writes via a
#  temp file + atomic mv so overlapping focus events can't corrupt the list.
# ============================================================================
# NO `set -e`: on the first-ever call MRU_FILE doesn't exist, so `[ -f ] && grep`
# returns non-zero — under set -e that would abort before the mv and the file
# would never get written. This recorder is fire-and-forget; keep it lenient.

wid="${1:-}"
sid="${2:-}"
[ -n "$wid" ] || [ -n "$sid" ] || exit 0

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/nachimux"
CAP=30

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

push() { # push <file> <value>
  [ -n "$2" ] || return 0
  tmp="$1.$$"
  {
    printf '%s\n' "$2"
    [ -f "$1" ] && grep -vxF "$2" "$1"
  } 2>/dev/null | head -n "$CAP" > "$tmp" 2>/dev/null
  mv "$tmp" "$1" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

push "$STATE_DIR/tab-mru" "$wid"
push "$STATE_DIR/ws-mru"  "$sid"
