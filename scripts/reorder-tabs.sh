#!/usr/bin/env bash
# ============================================================================
#  nachimux · reorder tabs   (bound to a prefix key, runs in display-popup -E)
#
#  A pick-up / put-down reorder TUI for the tabs of ONE workspace:
#
#     ↑/↓ (or k/j)   move the cursor
#     Enter / Space  grab the highlighted tab  (press again to drop)
#     ↑/↓ while held move that tab — edges ROTATE (top→bottom shifts the rest),
#                    exactly like prefix < / >  (see scripts/move-tab.sh)
#     m  while held  send that tab to ANOTHER workspace (opens a picker)
#     q / Esc        done  (every move is applied live — nothing to confirm)
#
#  The list scrolls in a fixed viewport, so the title and footer stay pinned no
#  matter how many tabs there are, and we redraw from home (no full-screen clear)
#  to avoid flicker.
#
#  Which workspace: REORDER_SESSION is stashed by the keybinding (a session_id
#  like "$3"); we fall back to the popup's own current session if it's missing.
# ============================================================================
# NOTE: deliberately NO `set -e`. This is an interactive loop, so a single
# failing tmux call (or a `[ ] && …` guard that tests false) must not kill it.
set -o pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${NACHIMUX_ROOT:-$(cd -P "$SCRIPT_DIR/.." && pwd)}"
MOVE="$ROOT/scripts/move-tab.sh"

SESS="${REORDER_SESSION:-}"
case "$SESS" in ""|*'#{'*) SESS="$(tmux display-message -p '#{session_id}' 2>/dev/null)";; esac

# ── truecolor helpers (catppuccin mocha) ────────────────────────────────────
RST=$'\033[0m'; BOLD=$'\033[1m'
fg(){ printf '\033[38;2;%s;%s;%sm' "$1" "$2" "$3"; }
bg(){ printf '\033[48;2;%s;%s;%sm' "$1" "$2" "$3"; }
MAUVE="$(fg 203 166 247)"      # titles / hints
OVERLAY="$(fg 108 112 134)"    # tab numbers / dim text
TEXT="$(fg 205 214 244)"       # normal name
CURSORBG="$(bg 49 50 68)$(fg 205 214 244)"          # surface0 — cursor row
HELDBG="$(bg 166 227 161)$(fg 17 17 27)$BOLD"       # green — grabbed row
WSBG="$(bg 245 194 231)$(fg 17 17 27)$BOLD"         # pink — workspace-picker cursor

CLR=$'\033[K'                  # erase to end of line
term_rows(){ local r; r="${REORDER_ROWS:-$(tput lines 2>/dev/null)}"; [ -n "$r" ] && [ "$r" -gt 0 ] 2>/dev/null && echo "$r" || echo 24; }
term_cols(){ local c; c="${REORDER_COLS:-$(tput cols 2>/dev/null)}"; [ -n "$c" ] && [ "$c" -gt 0 ] 2>/dev/null && echo "$c" || echo 60; }

# ── tab state for SESS ──────────────────────────────────────────────────────
idx=(); wid=(); act=(); name=()
load() {
  idx=(); wid=(); act=(); name=()
  local i w a n
  while IFS=$'\t' read -r i w a n; do
    [ -z "$i" ] && continue
    idx+=("$i"); wid+=("$w"); act+=("$a"); name+=("$n")
  done < <(tmux list-windows -t "$SESS" -F '#{window_index}	#{window_id}	#{window_active}	#{window_name}' 2>/dev/null </dev/null)
}
pos_of() { local target="$1" p; for p in "${!wid[@]}"; do [ "${wid[$p]}" = "$target" ] && { echo "$p"; return; }; done; echo -1; }

# ── other-workspace state (for the picker) ──────────────────────────────────
ws_sid=(); ws_name=()
load_ws() {
  ws_sid=(); ws_name=()
  local s n
  # Include the current workspace too — it's shown as "(CURRENT)" and can't be
  # a target (selecting it is a no-op), so you can see where the tab lives now.
  while IFS=$'\t' read -r s n; do
    [ -z "$s" ] && continue
    ws_sid+=("$s"); ws_name+=("$n")
  done < <(tmux list-sessions -F '#{session_id}	#{session_name}' 2>/dev/null </dev/null)
}

load
[ "${#idx[@]}" -eq 0 ] && { echo "reorder: no tabs here"; exit 0; }

cursor=0
for p in "${!act[@]}"; do [ "${act[$p]}" = "1" ] && { cursor="$p"; break; }; done
held=0; held_wid=""; mode="reorder"; ws_cursor=0

# Truncate a plain string to N display cols (no ANSI inside).
trunc(){ local s="$1" n="$2"; [ "${#s}" -le "$n" ] && { printf '%s' "$s"; return; }; printf '%s…' "${s:0:$((n-1))}"; }

# ── the reorder / hold view, with a scrolling viewport ──────────────────────
draw_reorder() {
  local rows cols avail total start end p namew line pointer
  rows="$(term_rows)"; cols="$(term_cols)"
  avail=$(( rows - 5 )); [ "$avail" -lt 3 ] && avail=3   # title+blank + blank+footer + 1 slack
  total=${#idx[@]}
  namew=$(( cols - 10 )); [ "$namew" -lt 8 ] && namew=8

  if [ "$total" -le "$avail" ]; then start=0
  else
    start=$(( cursor - avail/2 )); [ "$start" -lt 0 ] && start=0
    [ "$start" -gt $(( total - avail )) ] && start=$(( total - avail ))
  fi
  end=$(( start + avail - 1 )); [ "$end" -ge "$total" ] && end=$(( total - 1 ))

  printf '\033[H'
  printf '  %s%sReorder tabs%s  %s%s%s%s\n' "$MAUVE" "$BOLD" "$RST" "$OVERLAY" "$(tmux display-message -p -t "$SESS" '#{session_name}' </dev/null 2>/dev/null)" "$RST" "$CLR"
  if [ "$start" -gt 0 ]; then printf '   %s↑ %d more%s%s\n' "$OVERLAY" "$start" "$RST" "$CLR"; else printf '%s\n' "$CLR"; fi
  for (( p=start; p<=end; p++ )); do
    if [ "$held" = "1" ] && [ "${wid[$p]}" = "$held_wid" ]; then
      printf '   %s ⇕ %2s  %s %s%s\n' "$HELDBG" "${idx[$p]}" "$(trunc "${name[$p]}" "$namew")" "$RST" "$CLR"
    elif [ "$p" = "$cursor" ]; then
      printf '   %s ▸ %2s  %s %s%s\n' "$CURSORBG" "${idx[$p]}" "$(trunc "${name[$p]}" "$namew")" "$RST" "$CLR"
    else
      printf '     %s%2s%s  %s%s%s%s\n' "$OVERLAY" "${idx[$p]}" "$RST" "$TEXT" "$(trunc "${name[$p]}" "$namew")" "$RST" "$CLR"
    fi
  done
  if [ "$end" -lt $(( total - 1 )) ]; then printf '   %s↓ %d more%s%s\n' "$OVERLAY" "$(( total - 1 - end ))" "$RST" "$CLR"; else printf '%s\n' "$CLR"; fi
  if [ "$held" = "1" ]; then
    printf '  %s↑/↓%s move · %sm%s → workspace · %sEnter%s drop · %sq%s done%s' "$MAUVE" "$RST" "$MAUVE" "$RST" "$MAUVE" "$RST" "$MAUVE" "$RST" "$CLR"
  else
    printf '  %s↑/↓%s select · %sEnter%s grab · %sq%s done%s' "$MAUVE" "$RST" "$MAUVE" "$RST" "$MAUVE" "$RST" "$CLR"
  fi
  printf '\033[J'
}

# ── the "send to workspace" picker view ─────────────────────────────────────
draw_ws() {
  local rows cols avail total start end p heldname
  rows="$(term_rows)"; cols="$(term_cols)"
  avail=$(( rows - 5 )); [ "$avail" -lt 3 ] && avail=3
  total=${#ws_sid[@]}
  heldname=""; p="$(pos_of "$held_wid")"; [ "$p" -ge 0 ] && heldname="${name[$p]}"

  if [ "$total" -le "$avail" ]; then start=0
  else
    start=$(( ws_cursor - avail/2 )); [ "$start" -lt 0 ] && start=0
    [ "$start" -gt $(( total - avail )) ] && start=$(( total - avail ))
  fi
  end=$(( start + avail - 1 )); [ "$end" -ge "$total" ] && end=$(( total - 1 ))

  printf '\033[H'
  printf '  %s%sSend%s %s%s%s %sto workspace…%s%s\n' "$MAUVE" "$BOLD" "$RST" "$TEXT" "$heldname" "$RST" "$MAUVE" "$RST" "$CLR"
  if [ "$start" -gt 0 ]; then printf '   %s↑ %d more%s%s\n' "$OVERLAY" "$start" "$RST" "$CLR"; else printf '%s\n' "$CLR"; fi
  for (( p=start; p<=end; p++ )); do
    if [ "${ws_sid[$p]}" = "$SESS" ]; then                    # current — not a target
      printf '     %s%s %s(CURRENT)%s%s\n' "$OVERLAY" "${ws_name[$p]}" "$BOLD" "$RST" "$CLR"
    elif [ "$p" = "$ws_cursor" ]; then
      printf '   %s ▸ %s %s%s\n' "$WSBG" "${ws_name[$p]}" "$RST" "$CLR"
    else
      printf '     %s%s%s%s\n' "$TEXT" "${ws_name[$p]}" "$RST" "$CLR"
    fi
  done
  if [ "$end" -lt $(( total - 1 )) ]; then printf '   %s↓ %d more%s%s\n' "$OVERLAY" "$(( total - 1 - end ))" "$RST" "$CLR"; else printf '%s\n' "$CLR"; fi
  printf '  %s↑/↓%s select · %sEnter%s send · %sEsc%s back%s' "$MAUVE" "$RST" "$MAUVE" "$RST" "$MAUVE" "$RST" "$CLR"
  printf '\033[J'
}

draw(){ if [ "$mode" = "ws" ]; then draw_ws; else draw_reorder; fi; }

move_held() {  # $1 = left|right
  local curidx
  curidx="${idx[$cursor]}"
  "$MOVE" "$SESS" "$curidx" "$1" >/dev/null 2>&1 </dev/null
  load
  cursor="$(pos_of "$held_wid")"
  [ "$cursor" -lt 0 ] && cursor=0
}

enter_ws() {   # only if there's somewhere to send it and we won't empty this ws
  load_ws
  local others=0 p
  for p in "${!ws_sid[@]}"; do [ "${ws_sid[$p]}" != "$SESS" ] && others=$(( others + 1 )); done
  [ "$others" -eq 0 ] && return                # nowhere else to send it
  [ "${#idx[@]}" -le 1 ] && return             # don't empty (and destroy) this workspace
  mode="ws"
  ws_cursor=0                                  # land on the first real target, not (CURRENT)
  for p in "${!ws_sid[@]}"; do [ "${ws_sid[$p]}" != "$SESS" ] && { ws_cursor="$p"; break; }; done
}

# Move the picker cursor by $1 (-1 up / +1 down), skipping the (CURRENT) row.
ws_move() {
  local dir="$1" last="$(( ${#ws_sid[@]} - 1 ))" o="$ws_cursor"
  while :; do
    local n=$(( ws_cursor + dir ))
    [ "$n" -lt 0 ] || [ "$n" -gt "$last" ] && { ws_cursor="$o"; return; }   # ran off the end → stay
    ws_cursor="$n"
    [ "${ws_sid[$ws_cursor]}" != "$SESS" ] && return                        # landed on a real target
  done
}

send_to_ws() {
  local tsid total
  tsid="${ws_sid[$ws_cursor]}"
  [ "$tsid" = "$SESS" ] && return              # (CURRENT) → no-op
  tmux move-window -s "$held_wid" -t "${tsid}:" >/dev/null 2>&1 </dev/null
  held=0; held_wid=""; mode="reorder"
  load
  total=${#idx[@]}
  [ "$cursor" -ge "$total" ] && cursor=$(( total - 1 ))
  [ "$cursor" -lt 0 ] && cursor=0
}

cleanup(){ printf '\033[?25h\033[2J\033[H'; }
trap cleanup EXIT
printf '\033[?25l\033[2J'     # hide cursor, clear once
draw
while true; do
  IFS= read -rsn1 k || break
  if [ "$k" = $'\033' ]; then
    rest=""; IFS= read -rsn2 -t 1 rest || true
    k="ESC$rest"
  fi
  if [ "$mode" = "ws" ]; then
    case "$k" in
      'ESC[A'|k|K) ws_move -1 ;;
      'ESC[B'|j|J) ws_move +1 ;;
      ''|$'\n'|$'\r') send_to_ws ;;
      ESC)         mode="reorder" ;;              # Esc → back to holding
      q|Q)         break ;;
    esac
  else
    case "$k" in
      'ESC[A'|k|K)
        if [ "$held" = "1" ]; then move_held left
        else cursor=$(( cursor > 0 ? cursor - 1 : 0 )); fi ;;
      'ESC[B'|j|J)
        if [ "$held" = "1" ]; then move_held right
        else last=$(( ${#idx[@]} - 1 )); cursor=$(( cursor < last ? cursor + 1 : last )); fi ;;
      'ESC[D'|h) [ "$held" = "1" ] && move_held left ;;
      'ESC[C'|l) [ "$held" = "1" ] && move_held right ;;
      m|M)       [ "$held" = "1" ] && enter_ws ;;
      ''|$'\n'|$'\r'|' ')
        if [ "$held" = "1" ]; then held=0; held_wid=""
        else held=1; held_wid="${wid[$cursor]}"; fi ;;
      q|Q|ESC)   break ;;
    esac
  fi
  draw
done
