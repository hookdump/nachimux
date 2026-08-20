#!/usr/bin/env bash
# ============================================================================
#  nachimux · one place to find a tab
#
#  There used to be four ways in, and you had to pick one BEFORE you could see
#  anything: prefix g (fuzzy tree), prefix B (recent), prefix n (needs you),
#  prefix f (find by name). Four layouts, four sets of keys, and the decision
#  demanded exactly the knowledge you opened a finder to get.
#
#  They were never four tools. They were one list with different filters on it,
#  so that is what this is:
#
#      all      every tab in every workspace, grouped under its workspace
#      recent   most-recently-visited tabs first (the global MRU)
#      needs    only the tabs asking for you (@attention or a bell)
#      ws       workspaces, most-recently-visited first
#
#  and you switch between them AFTER it is open -- ctrl-a / ctrl-r / ctrl-n /
#  ctrl-w --
#  so a wrong guess costs a keystroke instead of a reopen. The old keys still
#  work; each one just opens this at its own mode.
#
#  prefix w keeps its own switcher on purpose. choose-tree kills, moves and
#  sorts; it is a manager, not a finder, and folding it in here would lose that.
#
#  Runs fzf inside display-popup, the recipe pick-window.sh proved: a plain TUI
#  that draws once gets shredded when the screen behind the popup repaints,
#  while fzf redraws continuously and self-heals.
#
#  Usage:  find.sh              interactive; mode from $NACHI_FIND_MODE
#          find.sh rows <mode>  emit rows for one mode (fzf calls this to reload)
# ============================================================================
set -o pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${NACHIMUX_ROOT:-$(cd -P "$SCRIPT_DIR/.." && pwd)}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/nachimux"
MRU_FILE="$STATE_DIR/tab-mru"
WS_MRU_FILE="$STATE_DIR/ws-mru"

CUR_SESSION="${NACHI_FIND_SESSION:-}"
CUR_WINDOW="${NACHI_FIND_WINDOW:-}"

RST=$'\033[0m'
WSCOL=$'\033[38;5;183m'    # mauve — workspace headers
IDXCOL=$'\033[38;5;102m'   # grey  — tab index
CURCOL=$'\033[38;5;150m'   # green — where you are now
WSTAG=$'\033[38;5;239m'    # dark  — the faint workspace tag on a tab row
YELLOW=$'\033[1;38;5;220m' # bold  — asking for you
LETTER=$'\033[1;38;5;117m' # blue  — the alt-key shortcut

KEYS="asdfghjkl"

# ── rows ────────────────────────────────────────────────────────────────────
# Every mode emits the same two tab-separated fields, so fzf can swap between
# them with reload() and never learn anything about which mode it is showing:
#   1) what is displayed and searched   2) the hidden jump target
# All searchable text has to live in field 1 -- fzf 0.74 searches --with-nth --
# which is why a tab row carries a dim copy of its workspace name: "churn edit"
# then narrows to that workspace's tab.

rows_all() {
  local last_sid="" sid sname wid widx wname wactive attn pointer namecol mark flagged
  flagged=" $(tmux list-windows -a -f '#{||:#{@attention},#{window_bell_flag}}' \
                -F '#{session_id}' 2>/dev/null | sort -u | tr '\n' ' ') "
  while IFS=$'\t' read -r sid sname wid widx wname wactive attn; do
    if [[ "$sid" != "$last_sid" ]]; then
      last_sid="$sid"; mark=""
      [[ "$sid" == "$CUR_SESSION" ]] && mark=" ${CURCOL}●${RST}"
      if [[ "$flagged" == *" $sid "* ]]; then
        printf '%s🔔 %s%s%s\t%s\n' "$YELLOW" "$sname" "$RST" "$mark" "$sid"
      else
        printf '%s%s%s%s\t%s\n' "$WSCOL" "$sname" "$RST" "$mark" "$sid"
      fi
    fi
    pointer="  "; namecol="$RST"
    if [[ "$attn" == "1" ]]; then pointer=" ${YELLOW}🔔${RST}"; namecol="$YELLOW"
    elif [[ "$wid" == "$CUR_WINDOW" ]]; then pointer=" ${CURCOL}▶${RST}"; namecol="$CURCOL"
    fi
    printf '   %s %s%2s%s  %s%s%s   %s%s%s\t%s\n' \
      "$pointer" "$IDXCOL" "$widx" "$RST" "$namecol" "$wname" "$RST" "$WSTAG" "$sname" "$RST" "$wid"
  done < <(tmux list-windows -a -F \
    '#{session_id}	#{session_name}	#{window_id}	#{window_index}	#{window_name}	#{window_active}	#{||:#{@attention},#{window_bell_flag}}' 2>/dev/null)
}

# Flat modes get an alt-<letter> shortcut per row. Plain letters cannot be used
# here the way the old lettered popups used them -- those surfaces had no search
# box to compete with -- so the letter moved to alt and typing stays typing.
emit_flat() { # $1=n $2=name $3=session $4=wid $5=mark
  local l=""
  [[ "$1" -lt ${#KEYS} ]] && l="${LETTER}${KEYS:$1:1}${RST}" || l=" "
  printf ' %s  %s%s%s%s   %s%s%s\t%s\n' "$l" "${5}" "$2" "$RST" "$RST" "$WSTAG" "$3" "$RST" "$4"
}

rows_recent() {
  local n=0 wid row map
  map="$(tmux list-windows -a -F '#{window_id}	#{session_name}	#{window_name}' 2>/dev/null)"
  [[ -f "$MRU_FILE" ]] || return 0
  while IFS= read -r wid; do
    [[ -z "$wid" || "$wid" == "$CUR_WINDOW" ]] && continue
    row="$(printf '%s\n' "$map" | awk -F'\t' -v w="$wid" '$1==w{print $2 "\t" $3; exit}')"
    [[ -z "$row" ]] && continue
    emit_flat "$n" "${row#*	}" "${row%%	*}" "$wid" ""
    n=$((n + 1))
  done < "$MRU_FILE"
}

rows_needs() {
  local n=0 wid sess win
  while IFS=$'\t' read -r wid sess win; do
    [[ -z "$wid" ]] && continue
    emit_flat "$n" "$win" "$sess" "$wid" "$YELLOW"
    n=$((n + 1))
  done < <(tmux list-windows -a -f '#{||:#{@attention},#{window_bell_flag}}' \
             -F '#{window_id}	#{session_name}	#{window_name}' 2>/dev/null)
}

# Workspaces by recency rather than by position. Kept separate from the tab MRU
# because bouncing around four tabs of one project should not evict every other
# project from the workspace list.
#
# Recency ORDERS the list, it does not filter it: a workspace you have not
# touched since the MRU started still has to be reachable, so anything missing
# from the list gets appended after it. Stale ids (a workspace that has since
# been killed) are dropped on the way through.
rows_ws() {
  local n=0 sid name windows cur map seen=""
  map="$(tmux list-sessions -F '#{session_id}	#{session_name}	#{session_windows}' 2>/dev/null)"

  emit_ws() { # emit_ws <session_id>
    cur="$(printf '%s\n' "$map" | awk -F'	' -v s="$1" '$1==s{print $2 "	" $3; exit}')"
    [[ -z "$cur" ]] && return 1
    name="${cur%%	*}"; windows="${cur#*	}"
    [[ "$1" == "$CUR_SESSION" ]] && name="${CURCOL}${name}${RST}"
    emit_flat "$n" "$name" "$windows tabs" "$1" ""
    n=$((n + 1)); seen="$seen $1 "
    return 0
  }

  if [[ -f "$WS_MRU_FILE" ]]; then
    while IFS= read -r sid; do
      [[ -z "$sid" ]] && continue
      emit_ws "$sid" || true
    done < "$WS_MRU_FILE"
  fi
  while IFS=$'	' read -r sid name windows; do
    [[ -z "$sid" || "$seen" == *" $sid "* ]] && continue
    emit_ws "$sid" || true
  done <<< "$map"
}

rows() {
  case "$1" in
    recent) rows_recent ;;
    needs)  rows_needs ;;
    ws)     rows_ws ;;
    *)      rows_all ;;
  esac
}

# fzf calls back into this to swap modes without reopening the popup.
if [[ "${1:-}" == "rows" ]]; then rows "${2:-all}"; exit 0; fi

FZF="$(command -v fzf || true)"
[[ -z "$FZF" ]] && { tmux display-message "find: fzf not found — brew install fzf"; exit 0; }

MODE="${NACHI_FIND_MODE:-all}"
SELF="$(printf '%q' "$SCRIPT_DIR/find.sh")"

prompt_for() { case "$1" in
  recent) printf '  ↩ recent › ';;
  needs)  printf '  🔔 needs you › ';;
  ws)     printf '  ▤ workspaces › ';;
  *)      printf '  ⌕ all tabs › ';;
esac; }

HDR='ctrl-a all · ctrl-r recent · ctrl-n needs · ctrl-w workspaces   ·   alt-a…l · ↑↓ · enter · esc'

COLORS="bg+:#313244,bg:#1e1e2e,fg:#cdd6f4,fg+:#cdd6f4,hl:#f9e2af,hl+:#f9e2af"
COLORS="$COLORS,pointer:#cba6f7,prompt:#cba6f7,header:#6c7086,border:#585b70,info:#6c7086"

# alt-<letter> selects the Nth row outright. Meaningful in the flat modes, where
# position is stable; harmless in the tree, where it just moves the cursor.
binds="esc:abort,ctrl-j:down,ctrl-k:up"
i=0; while [[ $i -lt ${#KEYS} ]]; do
  binds="${binds},alt-${KEYS:$i:1}:pos($((i + 1)))+accept"; i=$((i + 1))
done
for m in all recent needs ws; do
  binds="${binds},ctrl-${m:0:1}:change-prompt($(prompt_for "$m"))+reload($SELF rows $m)"
done

target="$(rows "$MODE" | "$FZF" --ansi \
    --delimiter=$'\t' --with-nth='{1}' --accept-nth='{2}' \
    --prompt="$(prompt_for "$MODE")" --pointer='▶' \
    --reverse --no-multi --no-info --no-sort --cycle \
    --border=rounded --margin=0 --padding=0 \
    --header="$HDR" --bind "$binds" --color="$COLORS" || true)"

[[ -z "$target" ]] && exit 0
"$ROOT/scripts/play-confirm-sound.sh" >/dev/null 2>&1 &
tmux switch-client -t "$target" >/dev/null 2>&1 || true
