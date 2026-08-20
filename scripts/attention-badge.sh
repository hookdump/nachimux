#!/usr/bin/env bash
# ============================================================================
#  nachimux · how many tabs are asking for you
#
#  Counts every tab, in every workspace, currently flagged -- by the Claude
#  hook (@attention) or a terminal bell -- and publishes it to an option the
#  status bar reads.
#
#  It used to be the other way round: the bar called this from #(), so it ran
#  every status-interval, forever, shelling out to `tmux list-windows -a` and
#  printing nothing in the overwhelming majority of runs. That is polling to
#  discover something we are told about.
#
#  We ARE told. The flag is raised in exactly two places (the Claude hook, and
#  a bell) and dropped in two more (focusing the tab, selecting it). Those four
#  moments now run this, and nothing runs it in between.
#
#  Prints nothing and paints nothing -- the pill lives in the config with the
#  rest of the bar, so it uses the theme palette instead of its own hexes.
# ============================================================================
set -uo pipefail

n=$(tmux list-windows -a -f '#{||:#{@attention},#{window_bell_flag}}' -F x 2>/dev/null \
      | grep -c . || true)

# Empty rather than 0, so the bar's #{?...} reads it as false and the badge
# simply is not there.
if [[ "${n:-0}" -gt 0 ]]; then
  tmux set -g @nachimux_attn_count "$n" 2>/dev/null || true
else
  tmux set -g @nachimux_attn_count "" 2>/dev/null || true
fi
