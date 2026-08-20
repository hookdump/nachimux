#!/usr/bin/env bash
# ============================================================================
#  nachimux · which tabs are asking for you, and which pane inside them
#
#  A tab "asks for you" when Claude finishes a turn or wants input (the Stop /
#  Notification hooks, via claude-attention-hook.sh) or when something rings the
#  bell. The tab bar turns yellow, a badge counts them, prefix n lists them.
#
#  The flag used to live on the WINDOW only, which is fine until the window has
#  four splits: you would land on the right tab and then have to work out which
#  Claude had actually finished. The hook always knew -- it runs inside the pane
#  and has $TMUX_PANE -- and threw it away.
#
#  So the window keeps the flag the tab bar reads, and gains a list of the panes
#  that raised it. Focusing a pane clears only THAT pane; the tab stays flagged
#  while any other pane in it is still waiting.
#
#    attention.sh raise <pane_id>   something in this pane wants you
#    attention.sh clear <pane_id>   you looked at it
#    attention.sh count             recount the badge (also done by the above)
#
#  Counting is event-driven on purpose: it used to run from #() in the status
#  bar every few seconds forever, to be told "still nothing" almost every time.
# ============================================================================
set -uo pipefail

win_of() { tmux display-message -p -t "$1" '#{window_id}' 2>/dev/null; }

count() {
  local n
  n=$(tmux list-windows -a -f '#{||:#{@attention},#{window_bell_flag}}' -F x 2>/dev/null \
        | grep -c . || true)
  # Empty rather than 0, so the bar's #{?...} reads it false and the badge is
  # simply not there.
  if [[ "${n:-0}" -gt 0 ]]; then tmux set -g @nachimux_attn_count "$n" 2>/dev/null || true
  else                           tmux set -g @nachimux_attn_count "" 2>/dev/null || true
  fi
}

raise() {
  local pane="$1" win list
  [[ -n "$pane" ]] || { count; return 0; }
  win="$(win_of "$pane")"; [[ -n "$win" ]] || { count; return 0; }
  list="$(tmux show -w -t "$win" -v @attention_panes 2>/dev/null)"
  case " $list " in *" $pane "*) : ;; *) list="${list:+$list }$pane" ;; esac
  tmux set -w -t "$win" @attention 1                 2>/dev/null || true
  tmux set -w -t "$win" @attention_panes "$list"     2>/dev/null || true
  count
}

clear_one() {
  local pane="$1" win list out p
  [[ -n "$pane" ]] || { count; return 0; }
  win="$(win_of "$pane")"; [[ -n "$win" ]] || { count; return 0; }
  list="$(tmux show -w -t "$win" -v @attention_panes 2>/dev/null)"
  out=""
  for p in $list; do [[ "$p" == "$pane" ]] || out="${out:+$out }$p"; done
  if [[ -z "$out" ]]; then
    # Nothing left waiting in this tab. Drop both the flag and the list.
    tmux set -uw -t "$win" @attention        2>/dev/null || true
    tmux set -uw -t "$win" @attention_panes  2>/dev/null || true
  else
    tmux set -w -t "$win" @attention_panes "$out" 2>/dev/null || true
  fi
  count
}

case "${1:-count}" in
  raise) raise "${2:-}" ;;
  clear) clear_one "${2:-}" ;;
  count) count ;;
  *)     count ;;
esac
