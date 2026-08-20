#!/usr/bin/env bash
# ============================================================================
#  nachimux · how many rows of tabs, and which tab goes on which
#
#  tmux draws the whole window list in one #{W:} loop on one row and hides the
#  overflow behind < > markers, so a busy workspace silently loses tabs off the
#  right edge. Two rows fix that. The question is where to cut.
#
#  It used to cut by decade: 1-9 on top, 10+ below, which made the row a tab sat
#  on equal the key that reached it. Lovely property, lopsided result -- eleven
#  tabs rendered as a row of nine and a row of two.
#
#  So it cuts for balance now, by rendered WIDTH rather than by count: tab
#  names run from very short to very long, and an even split by count would
#  still look nothing like even. Row 0 also has less room than row 1,
#  because the workspace name sits on it, and the split accounts for that.
#
#  Two rows only when one will not do. Most workspaces never need the second,
#  and an always-on empty row costs a terminal line for nothing.
#
#  Assignment is a per-window option, @nachimux_row, because a tmux format
#  cannot work this out for itself: the #{W:} loop exposes no ordinal position,
#  so a format cannot know a tab is "the sixth of eleven", and #{>=:9,10} is
#  TRUE because those operators compare strings. Deciding here and leaving the
#  formats a flat equality test avoids both traps.
#
#  Run with no argument to fix every workspace, or pass one session id.
# ============================================================================
set -uo pipefail

# Width a tab occupies: " <index>/<name> " plus the one-column gap after it.
tab_width() { printf '%s' $(( ${#1} + ${#2} + 4 )); }

apply_one() {
  local s="$1" width left avail0 avail1 total idx name wid n=0
  local -a wids=() widths=()

  # The widest attached client wins: a narrow client would otherwise force a
  # second row on everyone looking at the same workspace.
  width="$(tmux list-clients -t "$s" -F '#{client_width}' 2>/dev/null | sort -rn | head -1)"
  [[ -z "$width" ]] && width=200

  left="$(tmux display -p -t "$s" '#{E:status-left}' 2>/dev/null \
            | sed $'s/#\\[[^]]*\\]//g' | awk '{print length}')"
  [[ -z "$left" ]] && left=0

  total=0
  while IFS=$'\t' read -r wid idx name; do
    [[ -z "$wid" ]] && continue
    wids+=("$wid"); widths+=("$(tab_width "$idx" "$name")")
    total=$(( total + widths[n] )); n=$(( n + 1 ))
  done < <(tmux list-windows -t "$s" -F '#{window_id}	#{window_index}	#{window_name}' 2>/dev/null)
  (( n == 0 )) && return 0

  avail0=$(( width - left - 2 )); (( avail0 < 20 )) && avail0=20
  avail1=$(( width - 2 ));        (( avail1 < 20 )) && avail1=20

  local i split=0
  if (( total <= avail0 )); then
    split=$n                       # it all fits on one row
  else
    # Balance first: pick the cut that leaves the two rows closest in width.
    local run=0 best=-1 diff rest
    for (( i = 0; i < n; i++ )); do
      run=$(( run + widths[i] ))
      rest=$(( total - run ))
      diff=$(( run - rest )); (( diff < 0 )) && diff=$(( -diff ))
      if (( best < 0 || diff < best )); then best=$diff; split=$(( i + 1 )); fi
    done
    # Then respect row 0's smaller budget -- it carries the workspace name --
    # walking the cut back until it fits. When the tabs cannot fit two rows at
    # all this still splits them evenly rather than packing one row full and
    # letting the other run off the edge.
    run=0; for (( i = 0; i < split; i++ )); do run=$(( run + widths[i] )); done
    while (( split > 1 && run > avail0 )); do
      split=$(( split - 1 )); run=$(( run - widths[split] ))
    done
    (( split == 0 )) && split=1    # one tab wider than the row; still show it
  fi

  for (( i = 0; i < n; i++ )); do
    if (( i < split )); then tmux set -w -t "${wids[i]}" @nachimux_row 1 2>/dev/null || true
    else                     tmux set -w -t "${wids[i]}" @nachimux_row 2 2>/dev/null || true
    fi
  done

  # Every row a session wants has to be set ON that session. tmux array options
  # do NOT merge: the moment a session gets its own status-format[1] it stops
  # inheriting the global status-format[0] and that row draws blank -- no error,
  # just an empty line. So row 0 is re-stated here even though it never changes.
  if (( split < n )); then
    tmux set -t "$s" status 3                                        2>/dev/null || return 0
    tmux set -t "$s" 'status-format[0]' '#{E:@nachimux_row_main}'    2>/dev/null || true
    tmux set -t "$s" 'status-format[1]' '#{E:@nachimux_row_tabs2}'   2>/dev/null || true
    tmux set -t "$s" 'status-format[2]' '#{E:@nachimux_row_hints}'   2>/dev/null || true
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
