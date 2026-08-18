#!/usr/bin/env bash
# ============================================================================
#  nachimux · the second row of tabs
#
#  Tabs 1-9 live on row 0 and answer to `prefix N`. Tabs 10+ answer to
#  `prefix 0 N`, and they get their own row — so the row a tab sits on tells
#  you which keystroke reaches it.
#
#  That second row is not permanent furniture. Most workspaces never pass 9
#  tabs, and an always-on empty row would cost a terminal line for nothing.
#  So this script decides, per workspace:
#
#    no tab past 9   row0 = session + tabs 1-9      status 2
#                    row1 = hints / cpu / clock
#
#    tabs past 9     row0 = session + tabs 1-9      status 3
#                    row1 = tabs 10+
#                    row2 = hints / cpu / clock
#
#  `status`, `status-format` and `message-line` are all SESSION options, so
#  each workspace answers for itself: your 14-tab workspace gets three rows
#  while a 1-tab scratch workspace stays at two.
#
#  The row CONTENTS live in @nachimux_row_* options (see tmux.spanish.conf).
#  This only ever points the rows at them, so editing a row's look never
#  means touching this file.
#
#  Run with no argument to fix every workspace, or pass one session id.
# ============================================================================
set -euo pipefail

apply_one() {
  local s="$1" idx overflow=0
  while read -r idx; do
    if [[ -n "$idx" ]] && (( idx > 9 )); then overflow=1; break; fi
  done < <(tmux list-windows -t "$s" -F '#{window_index}' 2>/dev/null || true)

  # Every row, every time. tmux array options do NOT merge with the global one:
  # setting status-format[1] on a session gives that session its own array and
  # it stops inheriting global status-format[0] entirely -- row 0 goes blank.
  # So row 0 is re-stated here even though it never changes.
  if (( overflow )); then
    tmux set -t "$s" status 3                                        2>/dev/null || return 0
    tmux set -t "$s" 'status-format[0]' '#{E:@nachimux_row_main}'    2>/dev/null || true
    tmux set -t "$s" 'status-format[1]' '#{E:@nachimux_row_tabs2}'   2>/dev/null || true
    tmux set -t "$s" 'status-format[2]' '#{E:@nachimux_row_hints}'   2>/dev/null || true
    # transient messages land on the LAST row, never over a row of tabs
    tmux set -t "$s" message-line 2                                  2>/dev/null || true
  else
    tmux set -t "$s" status 2                                        2>/dev/null || return 0
    tmux set -t "$s" 'status-format[0]' '#{E:@nachimux_row_main}'    2>/dev/null || true
    tmux set -t "$s" 'status-format[1]' '#{E:@nachimux_row_hints}'   2>/dev/null || true
    tmux set -u -t "$s" 'status-format[2]'                           2>/dev/null || true
    tmux set -t "$s" message-line 1                                  2>/dev/null || true
  fi
}

if (( $# > 0 )) && [[ -n "${1:-}" ]]; then
  apply_one "$1"
else
  while read -r s; do [[ -n "$s" ]] && apply_one "$s"; done \
    < <(tmux list-sessions -F '#{session_id}' 2>/dev/null || true)
fi
tmux refresh-client -S 2>/dev/null || true
