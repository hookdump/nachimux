#!/usr/bin/env bash
# ============================================================================
#  nachimux · record a tab visit into the MRU stack
#
#  Wired to the pane-focus-in hook: every time a window gains focus (you switch
#  tabs or workspaces), we push its window_id to the front of a small most-
#  recently-used list, de-duplicated and capped. That list powers `prefix B`
#  (recent-tabs.sh) — tmux keeps no visit history of its own, so we keep one.
#
#    $1 = window_id that just got focus  (passed by the hook as #{window_id})
#
#  Deliberately tiny and fire-and-forget (the hook backgrounds it). Writes via a
#  temp file + atomic mv so overlapping focus events can't corrupt the list.
# ============================================================================
# NO `set -e`: on the first-ever call MRU_FILE doesn't exist, so `[ -f ] && grep`
# returns non-zero — under set -e that would abort before the mv and the file
# would never get written. This recorder is fire-and-forget; keep it lenient.

wid="${1:-}"
[ -n "$wid" ] || exit 0

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/nachimux"
MRU_FILE="$STATE_DIR/tab-mru"
CAP=30

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
tmp="$MRU_FILE.$$"
{
  printf '%s\n' "$wid"
  [ -f "$MRU_FILE" ] && grep -vxF "$wid" "$MRU_FILE"
} 2>/dev/null | head -n "$CAP" > "$tmp" 2>/dev/null
mv "$tmp" "$MRU_FILE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
