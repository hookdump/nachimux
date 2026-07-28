#!/usr/bin/env bash
# ============================================================================
#  nachimux · prefix hint bar
#
#  The green cheat strip that appears top-right while you hold the prefix is
#  data-driven, not hardcoded. This script is its engine:
#
#    build          render the pinned shortcuts into @nachimux_prefix_hint
#    toggle <id>    pin / unpin one shortcut, then rebuild
#    list-fzf       emit the pin manager's rows (see palette.sh `pins` mode)
#
#  The universe of pinnable shortcuts lives in data/prefix-hints.tsv; your
#  personal selection is a state file that survives tmux server restarts.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${NACHIMUX_ROOT:-$(cd -P "$SCRIPT_DIR/.." && pwd)}"
HINTS="$ROOT/data/prefix-hints.tsv"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/nachimux"
PINS_FILE="$STATE_DIR/prefix-pins"

# Matches the current bar exactly, so nothing changes until you customize.
DEFAULT_PINS=(newtab workspaces tabs split actions)

# Category headers are rendered in this order; only non-empty ones appear.
CATEGORY_ORDER=(TABS WS SPLIT COPY MISC)

# Green pill caps (identical to the theme's prefix accent). The content between
# them is bold keys + nobold labels joined by " · ".
CAP_L='#[fg=#00ff00]#[bg=default]#[fg=#11111b]#[bg=#00ff00]#[bold]'
CAP_R='#[fg=#00ff00]#[bg=default]#[default]'

ensure_state() {
  mkdir -p "$STATE_DIR"
  if [[ ! -f "$PINS_FILE" ]]; then
    printf '%s\n' "${DEFAULT_PINS[@]}" > "$PINS_FILE"
  fi
}

is_pinned() { grep -qxF "$1" "$PINS_FILE" 2>/dev/null; }

# Render the pinned shortcuts into the tmux option the status bar reads, GROUPED
# by category (TABS / WS / SPLIT / …). Each category shows a bold header, then its
# pinned items as compact "key=label" joined by " · ". Categories appear in
# CATEGORY_ORDER; within one, items follow pins-file order. Stale ids are skipped.
build() {
  ensure_state
  # Resolve each pinned id -> cat/key/label once (bash 3.2: no assoc arrays).
  local ids_cat=() ids_key=() ids_lbl=() id line
  while IFS= read -r id || [[ -n "$id" ]]; do
    [[ -z "$id" ]] && continue
    line="$(awk -F'\t' -v id="$id" '$1==id {print; exit}' "$HINTS")"
    [[ -z "$line" ]] && continue
    ids_cat+=("$(printf '%s' "$line" | cut -f2)")
    ids_key+=("$(printf '%s' "$line" | cut -f3)")
    ids_lbl+=("$(printf '%s' "$line" | cut -f4)")
  done < "$PINS_FILE"

  local content="" cat i group gn
  for cat in "${CATEGORY_ORDER[@]}"; do
    group=""; gn=0
    for i in "${!ids_cat[@]}"; do
      [[ "${ids_cat[$i]}" != "$cat" ]] && continue
      if (( gn == 0 )); then
        group="${ids_key[$i]}=${ids_lbl[$i]}"
      else
        group+=" · ${ids_key[$i]}=${ids_lbl[$i]}"
      fi
      gn=$((gn + 1))
    done
    (( gn == 0 )) && continue
    [[ -n "$content" ]] && content+="   "
    content+="#[bold]${cat}#[nobold] ${group}"
  done

  local hint=""
  [[ -n "$content" ]] && hint="${CAP_L} ${content} ${CAP_R}"

  tmux set -g @nachimux_prefix_hint "$hint" 2>/dev/null || true
  tmux refresh-client -S 2>/dev/null || true
}

toggle() {
  ensure_state
  local id="$1"
  if is_pinned "$id"; then
    grep -vxF "$id" "$PINS_FILE" > "$PINS_FILE.tmp" 2>/dev/null || : > "$PINS_FILE.tmp"
    mv "$PINS_FILE.tmp" "$PINS_FILE"
  else
    printf '%s\n' "$id" >> "$PINS_FILE"
  fi
  build
}

# Rows for the fzf pin manager: visible field (state glyph + key + label) then
# a hidden id field. --ansi colors: green ✓ when pinned, dim ○ when not.
list_fzf() {
  ensure_state
  local id key label mark keycol
  local GREEN=$'\033[38;5;120m' MAUVE=$'\033[38;5;183m'
  local DIM=$'\033[38;5;102m'   RST=$'\033[0m'
  local cat catcol
  while IFS=$'\t' read -r id cat key label; do
    [[ "$id" == "id" || -z "$id" ]] && continue
    if is_pinned "$id"; then
      mark="${GREEN}✓${RST}"
    else
      mark="${DIM}○${RST}"
    fi
    catcol="$(printf '%-6s' "$cat")"
    keycol="$(printf '%-5s' "$key")"
    printf '%s  %s%s%s %s%s%s %s\t%s\n' \
      "$mark" "$DIM" "$catcol" "$RST" "$MAUVE" "$keycol" "$RST" "$label" "$id"
  done < "$HINTS"
}

case "${1:-build}" in
  build)    build ;;
  toggle)   toggle "${2:?toggle needs an id}" ;;
  list-fzf) list_fzf ;;
  *) echo "usage: prefix-hint.sh {build|toggle <id>|list-fzf}" >&2; exit 2 ;;
esac
