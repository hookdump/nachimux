#!/usr/bin/env bash
# ============================================================================
#  nachimux · global "needs you" badge for the status bar
#
#  Counts every tab (in every workspace) currently flagged for attention —
#  either by the Claude hook (@attention) or a terminal bell (window_bell_flag)
#  — and prints a compact yellow  🔔 N  pill. Prints NOTHING when the count is
#  zero, so the badge simply disappears when nothing needs you.
#
#  Invoked from the status bar via #(...), so it re-runs every status-interval
#  (see `status-interval` in tmux.spanish.conf). tmux re-parses the #[...] style
#  codes in our output, which is how the pill gets its colors.
# ============================================================================
set -eo pipefail

n=$(tmux list-windows -a -f '#{||:#{@attention},#{window_bell_flag}}' -F x 2>/dev/null \
      | grep -c . || true)

[ "${n:-0}" -gt 0 ] || exit 0

# Yellow pill (matches the attention tab colors: #f9e2af on #11111b).
printf '#[fg=#f9e2af,bg=default]#[fg=#11111b,bold,bg=#f9e2af] 🔔 %s #[fg=#f9e2af,bg=default]#[default]' "$n"
