#!/usr/bin/env bash
# ============================================================================
#  nachimux · window picker popup   (prefix n = attention, prefix B = recent)
#
#  Runs fzf inside a display-popup — the SAME proven-robust recipe as jump.sh.
#  A plain bash TUI that draws once and blocks gets corrupted when the screen
#  behind the popup keeps redrawing (Claude Code, the status badge, etc.), because
#  it never repaints. fzf continuously redraws, so it self-heals and stays clean.
#
#  Two modes (via env, set by the keybinding):
#    NACHI_PICK_MODE   = attention | recent
#    NACHI_PICK_ORIGIN = window_id you're on now (excluded from the list)
#
#  UX: a letter jumps straight to that tab; ↑/↓ move; Enter opens the highlighted
#  one; Esc closes. Tab name is bold/bright, the workspace dimmed after it.
#  Attention is yellow-themed, recent is blue-themed.
#
#  DRYRUN=1 prints the built rows + letter binds instead of launching fzf.
# ============================================================================
set -o pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${NACHIMUX_ROOT:-$(cd -P "$SCRIPT_DIR/.." && pwd)}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/nachimux"
MRU_FILE="$STATE_DIR/tab-mru"

MODE="${NACHI_PICK_MODE:-recent}"
ORIGIN="${NACHI_PICK_ORIGIN:-}"
KEYS="asdfghjklqwertyuiop"

FZF="$(command -v fzf || true)"
[ -z "$FZF" ] && { tmux display-message "picker: fzf not found — brew install fzf"; exit 0; }

# ── ANSI (truecolor) — tab bold/bright, workspace dim, letter in the accent ──
RST=$'\033[0m'
TAB=$'\033[1;38;2;205;214;244m'    # bold #cdd6f4
WS=$'\033[2;38;2;108;112;134m'     # dim  #6c7086
case "$MODE" in
  attention)
    LETTER=$'\033[1;38;2;249;226;175m'   # yellow #f9e2af
    HDR="🔔 needs you"; PROMPT='  🔔 › '; EMPTY='✓ nothing needs you right now'
    ACCENT="#f9e2af"; MAX=${#KEYS}
    ;;
  *)
    LETTER=$'\033[1;38;2;137;180;250m'   # blue #89b4fa
    HDR="↩ recent tabs"; PROMPT='  ↩ › '; EMPTY='↩ no other recent tabs yet'
    ACCENT="#89b4fa"; MAX=9
    ;;
esac

# ── build "display<TAB>wid" rows in the right order ─────────────────────────
map="$(tmux list-windows -a -F '#{window_id}	#{session_name}	#{window_name}' 2>/dev/null)"
lookup(){ printf '%s\n' "$map" | awk -F'\t' -v w="$1" '$1==w{print $2 "\t" $3; exit}'; }

emit_row(){ # $1=letter $2=window $3=session $4=wid
  printf '%s%s%s  %s%s%s  %s%s%s\t%s\n' "$LETTER" "$1" "$RST" "$TAB" "$2" "$RST" "$WS" "$3" "$RST" "$4"
}

rows=""; n=0
if [ "$MODE" = "attention" ]; then
  while IFS=$'\t' read -r wid sess win; do
    [ -z "$wid" ] && continue
    [ "$wid" = "$ORIGIN" ] && continue
    [ "$n" -ge "$MAX" ] && break
    rows="${rows}$(emit_row "${KEYS:$n:1}" "$win" "$sess" "$wid")"$'\n'
    n=$((n + 1))
  done < <(tmux list-windows -a -f '#{||:#{@attention},#{window_bell_flag}}' \
             -F '#{window_id}	#{session_name}	#{window_name}' 2>/dev/null)
elif [ -f "$MRU_FILE" ]; then
  while IFS= read -r wid; do
    [ -z "$wid" ] && continue
    [ "$wid" = "$ORIGIN" ] && continue
    row="$(lookup "$wid")"; [ -z "$row" ] && continue
    [ "$n" -ge "$MAX" ] && break
    rows="${rows}$(emit_row "${KEYS:$n:1}" "${row#*	}" "${row%%	*}" "$wid")"$'\n'
    n=$((n + 1))
  done < "$MRU_FILE"
fi

# ── letter → jump binds (fzf pos() is 1-based; each assigned letter selects) ──
binds="esc:abort"
i=0
while [ "$i" -lt "$n" ]; do
  binds="${binds},${KEYS:$i:1}:pos($((i + 1)))+accept"
  i=$((i + 1))
done

COLORS="bg+:#313244,bg:#1e1e2e,fg:#cdd6f4,fg+:#cdd6f4,hl:${ACCENT},hl+:${ACCENT}"
COLORS="$COLORS,pointer:${ACCENT},prompt:${ACCENT},header:${ACCENT},border:#585b70,info:#6c7086"

if [ "${DRYRUN:-}" = "1" ]; then
  printf 'ROWS:\n%s\nBINDS: %s\n' "$rows" "$binds"
  exit 0
fi

# ── empty state: a single non-selectable info row (stays in the robust surface)
if [ "$n" -eq 0 ]; then
  printf '%s%s%s\t\n' "$LETTER" "$EMPTY" "$RST" \
    | "$FZF" --ansi --delimiter=$'\t' --with-nth='{1}' \
        --reverse --no-multi --no-info --no-sort --header="$HDR" --prompt="$PROMPT" \
        --border=rounded --margin=0 --padding=0 --color="$COLORS" >/dev/null 2>&1 || true
  exit 0
fi

target="$(printf '%s' "$rows" \
  | "$FZF" --ansi --delimiter=$'\t' --with-nth='{1}' --accept-nth='{2}' \
      --reverse --no-multi --no-info --no-sort --cycle \
      --prompt="$PROMPT" --pointer='▶' \
      --header="$HDR  ·  letter jump · ↑↓ · enter · esc" \
      --border=rounded --margin=0 --padding=0 \
      --bind "$binds" --color="$COLORS" \
  || true)"

[ -z "$target" ] && exit 0
tmux switch-client -t "$target" >/dev/null 2>&1 || true
