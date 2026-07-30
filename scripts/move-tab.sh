#!/usr/bin/env bash
# ============================================================================
#  nachimux · move a tab within its workspace   (used by prefix < / > and the
#  reorder popup)
#
#  Usage:  move-tab.sh <session_id> <window_index> <left|right>
#
#  In the MIDDLE of the list a move is an adjacent swap (A B [C] D → A [C] B D),
#  same as before. At the EDGE we ROTATE instead of swapping the two ends:
#
#     [A B C D], move D right  →  [D A B C]   (D to front, the rest shift right)
#     [A B C D], move A left   →  [B C D A]   (A to back,  the rest shift left)
#
#  i.e. the whole list rotates by one rather than the two ends trading places.
#  Rotation is done by parking the tab just outside the range (index 0, or
#  max+1) and then `move-window -r`, which renumbers the session gaplessly from
#  base-index — so index 0 becomes the new first, etc.
#
#  Prints the moved tab's NEW window index on stdout and leaves it selected, so
#  callers (the reorder popup) can keep following it.
# ============================================================================
set -eo pipefail

sess="${1:?session_id}"
cur="${2:?window_index}"
dir="${3:?left|right}"

idxs="$(tmux list-windows -t "$sess" -F '#{window_index}' 2>/dev/null)"
cnt="$(printf '%s\n' "$idxs" | grep -c .)"
min="$(printf '%s\n' "$idxs" | sort -n | head -1)"
max="$(printf '%s\n' "$idxs" | sort -n | tail -1)"

# Nothing to reorder.
if [ "${cnt:-0}" -le 1 ]; then
  printf '%s\n' "$cur"
  exit 0
fi

new="$cur"
case "$dir" in
  right)
    if [ "$cur" = "$max" ]; then                     # edge → rotate to front
      tmux move-window -s "$sess:$cur" -t "$sess:0"
      tmux move-window -r -t "$sess"
      new="$min"
    else                                             # middle → swap with next
      tmux swap-window -d -s "$sess:$cur" -t "$sess:$((cur + 1))"
      new="$((cur + 1))"
    fi
    ;;
  left)
    if [ "$cur" = "$min" ]; then                     # edge → rotate to back
      tmux move-window -s "$sess:$cur" -t "$sess:$((max + 1))"
      tmux move-window -r -t "$sess"
      new="$max"
    else                                             # middle → swap with prev
      tmux swap-window -d -s "$sess:$cur" -t "$sess:$((cur - 1))"
      new="$((cur - 1))"
    fi
    ;;
  *) echo "usage: move-tab.sh <session_id> <window_index> <left|right>" >&2; exit 2 ;;
esac

tmux select-window -t "$sess:$new" 2>/dev/null || true
printf '%s\n' "$new"
