#!/usr/bin/env bash
# ============================================================================
#  nachimux · Claude Code → tmux "needs you" flag
#
#  Wired to Claude Code's Stop and Notification hooks (in ~/.claude/settings.json).
#  When a Claude session finishes its turn or asks for input, flag its tmux tab
#  so `prefix n` (and the global 🔔 badge) surface it — UNLESS you're already
#  looking at that pane.
#
#  Runs inside the Claude process, which lives in the tmux pane, so $TMUX and
#  $TMUX_PANE are inherited. Claude passes event JSON on stdin; we ignore it.
#  Always exits 0 so it never blocks Claude.
# ============================================================================

# Not inside tmux (or hook env stripped) → nothing to do.
[ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || exit 0

# Are you actively viewing this pane right now? (client attached to its session,
# and it's the active pane of the active window.) If so, don't nag.
read -r attached wactive pactive <<EOF
$(tmux display-message -p -t "$TMUX_PANE" '#{session_attached} #{window_active} #{pane_active}' 2>/dev/null)
EOF
if [ "${attached:-0}" != "0" ] && [ "${wactive:-0}" = "1" ] && [ "${pactive:-0}" = "1" ]; then
  exit 0
fi

tmux set-option -w -t "$TMUX_PANE" @attention 1 2>/dev/null
exit 0
