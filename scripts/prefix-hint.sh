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

# Render the pinned shortcuts into the tmux option the status bar reads, in the
# order you pinned them (pins-file order), resolving each id's key+label from
# the universe. Unknown/stale ids are skipped. Empty option when none pinned.
build() {
  ensure_state
  local id line key label content="" n=0
  while IFS= read -r id || [[ -n "$id" ]]; do
    [[ -z "$id" ]] && continue
    line="$(awk -F'\t' -v id="$id" '$1==id {print; exit}' "$HINTS")"
    [[ -z "$line" ]] && continue
    key="$(printf '%s' "$line" | cut -f2)"
    label="$(printf '%s' "$line" | cut -f3)"
    if (( n == 0 )); then
      content+=" ${key} #[nobold]${label}"
    else
      content+=" · #[bold]${key} #[nobold]${label}"
    fi
    n=$((n + 1))
  done < "$PINS_FILE"

  local hint=""
  (( n > 0 )) && hint="${CAP_L}${content} ${CAP_R}"

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
  while IFS=$'\t' read -r id key label; do
    [[ "$id" == "id" || -z "$id" ]] && continue
    if is_pinned "$id"; then
      mark="${GREEN}✓${RST}"
    else
      mark="${DIM}○${RST}"
    fi
    keycol="$(printf '%-5s' "$key")"
    printf '%s  %s%s%s %s\t%s\n' "$mark" "$MAUVE" "$keycol" "$RST" "$label" "$id"
  done < "$HINTS"
}

case "${1:-build}" in
  build)    build ;;
  toggle)   toggle "${2:?toggle needs an id}" ;;
  list-fzf) list_fzf ;;
  *) echo "usage: prefix-hint.sh {build|toggle <id>|list-fzf}" >&2; exit 2 ;;
esac
