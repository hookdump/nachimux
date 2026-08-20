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
DEFAULT_PINS=(newtab workspaces tabs tabs10 split actions)

# Category headers are rendered in this order; only non-empty ones appear.
CATEGORY_ORDER=(TABS WS SPLIT COPY MISC)

# A category can also carry a CONDITION: a tmux format deciding whether it is
# worth showing right now. The split keys are noise in a tab with no splits,
# and that is most tabs most of the time.
#
# The group is stashed in its own option and referenced from inside the
# conditional rather than inlined, because a label containing a comma would
# otherwise split the #{?a,b,c} it sits in -- the same trap that has bitten
# every other format in this config.
#
# #{!=:...,1} rather than #{>:...,1}: those operators compare STRINGS, so
# "2" > "1" is true by luck and "10" > "1" is false. window_panes is never
# below 1, so "not exactly one" is the honest test.
cat_condition() {
  case "$1" in
    SPLIT) printf '#{!=:#{window_panes},1}' ;;
    *)     printf '' ;;
  esac
}

# Pill caps in the theme's prefix accent. These are tmux FORMATS, not literal
# hexes: the option is expanded at draw time, so a light/dark flip repaints the
# bar without this script having to know a single colour. scripts/theme.sh owns
# the values and rebuilds this bar after a flip.
CAP_L='#[fg=#{@nachimux_c_accent}]#[bg=default]#[fg=#{@nachimux_c_accentink}]#[bg=#{@nachimux_c_accent}]#[bold]'
CAP_R='#[fg=#{@nachimux_c_accent}]#[bg=default]#[default]'

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
    local rendered="#[bold]${cat}#[nobold] ${group}"
    local cond; cond="$(cat_condition "$cat")"
    if [[ -n "$cond" ]]; then
      # Stash the group, reference it conditionally. The leading gap goes inside
      # the conditional too, so a hidden group leaves no double space behind.
      tmux set -g "@nachimux_hint_${cat}" "${content:+   }${rendered}" 2>/dev/null || true
      content+="#{?${cond},#{E:@nachimux_hint_${cat}},}"
    else
      [[ -n "$content" ]] && content+="   "
      content+="$rendered"
    fi
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
