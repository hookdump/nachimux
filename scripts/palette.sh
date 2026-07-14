#!/usr/bin/env bash
# ============================================================================
#  nachimux · executable command palette   (prefix p)
#
#  This UI and the `nachimux` cheatsheet share data/cheatsheet.tsv. Rows with
#  a command are executable here; rows without one remain useful documentation.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${NACHIMUX_ROOT:-$(cd -P "$SCRIPT_DIR/.." && pwd)}"
DATA="$ROOT/data/cheatsheet.tsv"
FZF="$(command -v fzf || true)"
CONFIRM_SOUND_PLAYER="$ROOT/scripts/play-confirm-sound.sh"

if [[ ! -f "$DATA" ]]; then
  tmux display-message "palette: action registry not found — $DATA"
  exit 0
fi

if [[ -z "$FZF" ]]; then
  tmux display-message "palette: fzf not found — brew install fzf"
  exit 0
fi

MODE="${1:-palette}"

# ── Pin manager: prefix hint bar ─────────────────────────────────────────────
# Reached from the "nachimux-pins" palette action. Enter pins/unpins the
# shortcut under the cursor and the list reloads in place; the real top-right
# bar updates live (prefix-hint.sh rewrites @nachimux_prefix_hint). Esc closes.
# No tmux overlay is involved, so this runs happily inside the palette popup.
pins_menu() {
  local hint_script="$ROOT/scripts/prefix-hint.sh"
  local colors="bg+:#313244,bg:#1e1e2e,fg:#cdd6f4,fg+:#cdd6f4,hl:#f38ba8,hl+:#f38ba8"
  colors="$colors,header:#f38ba8,info:#cba6f7,pointer:#f5c2e7,prompt:#cba6f7,border:#585b70"
  bash "$hint_script" list-fzf \
    | "$FZF" --ansi \
        --delimiter=$'\t' --with-nth=1 \
        --prompt='  bar › ' --pointer='▶' \
        --reverse --no-multi --no-info --cycle \
        --border=rounded --margin=0 --padding=0 \
        --header='Enter pins/unpins · Esc closes · this is the strip you see when you tap the prefix' \
        --color="$colors" \
        --bind "enter:execute-silent(bash \"$hint_script\" toggle {2})+reload(bash \"$hint_script\" list-fzf)" \
    >/dev/null 2>&1 || true
  exit 0
}

if [[ "$MODE" == "pins" ]]; then
  pins_menu
fi

# Catppuccin-ish terminal colors.
KEYCOL=$'\033[38;5;183m'   # mauve
CATCOL=$'\033[38;5;110m'   # blue
DIM=$'\033[38;5;102m'      # overlay grey
RST=$'\033[0m'

render_hint() {
  local mode="$1" keys="$2"
  case "$mode" in
    prefix)  printf 'prefix %s' "$keys" ;;
    palette) printf 'palette' ;;
    copy)    printf 'copy %s' "$keys" ;;
    shell)   printf '$ %s' "$keys" ;;
    *)       printf '%s' "$keys" ;;
  esac
}

play_confirmation_sound() {
  local player_command
  [[ -f "$CONFIRM_SOUND_PLAYER" ]] || return 0

  # Let tmux own the background process so the palette can close immediately
  # without interrupting the sound or delaying the selected action.
  printf -v player_command '%q %q' /bin/bash "$CONFIRM_SOUND_PLAYER"
  tmux run-shell -b "$player_command" >/dev/null 2>&1 || true
}

# This script runs *inside* `display-popup -E`, and a popup owns its client's
# single overlay slot. Any command that opens another overlay — a prompt
# (command-prompt), a confirmation (confirm-before), or a tree/menu/popup
# (choose-tree, display-menu, …) — is torn down the instant this popup closes,
# so firing it inline does nothing: you see the prompt flash up and vanish, and
# the action never takes effect (e.g. "Rename tab" shows the prompt but never
# renames). The fix is to defer such commands just past the popup teardown so
# the overlay lands on the real client. run-shell -b hands the job to the tmux
# server; the short sleep lets this popup finish closing first.
POPUP_SETTLE_DELAY="0.25"
run_after_popup() {
  local tmux_command="$1"
  tmux run-shell -b "sleep $POPUP_SETTLE_DELAY; tmux $tmux_command" >/dev/null 2>&1 || true
}

# True when a command opens a client overlay and so must be deferred until the
# popup is gone. Everything else runs inline for an instant, snappy feel.
opens_overlay() {
  case "$1" in
    command-prompt*|confirm-before*|choose-tree*|choose-client*|choose-buffer*|display-menu*|display-popup*) return 0 ;;
    *) return 1 ;;
  esac
}

# Visible field + hidden tmux command + hidden confirmation prompt.
build() {
  local category mode keys description command confirm hint hint_pad cat_pad hint_color
  while IFS=$'\t' read -r category mode keys description command confirm; do
    [[ "$category" == "category" ]] && continue
    [[ -z "$category" || -z "$command" ]] && continue

    hint="$(render_hint "$mode" "$keys")"
    hint_pad="$(printf '%-13s' "$hint")"
    cat_pad="$(printf '%-13s' "$category")"
    if [[ "$mode" == "palette" ]]; then
      hint_color="$DIM"
    else
      hint_color="$KEYCOL"
    fi

    printf '%s%s%s %s│%s %s%s%s │ %s\t%s\t%s\n' \
      "$hint_color" "$hint_pad" "$RST" "$DIM" "$RST" \
      "$CATCOL" "$cat_pad" "$RST" "$description" "$command" "$confirm"
  done < "$DATA"
}

COLORS="bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8,fg:#cdd6f4"
COLORS="$COLORS,header:#f38ba8,info:#cba6f7,pointer:#f5c2e7,marker:#b4befe"
COLORS="$COLORS,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8,border:#585b70"

choice="$(build \
  | "$FZF" --ansi \
      --delimiter=$'\t' --with-nth=1 \
      --prompt='  do › ' \
      --pointer='▶' --marker='✓' \
      --reverse --no-multi --no-info --cycle \
      --border=rounded --margin=0 --padding=0 \
      --header='search an action · Enter runs it · the key is shown on the left' \
      --color="$COLORS" \
  || true)"

[[ -z "$choice" ]] && exit 0

command="$(printf '%s' "$choice" | cut -f2)"
confirm="$(printf '%s' "$choice" | cut -f3-)"
[[ -z "$command" ]] && exit 0

play_confirmation_sound

# A popup cannot open a second popup reliably. Reuse the palette process and
# turn the current panel into the searchable cheatsheet instead.
if [[ "$command" == "nachimux-help" ]]; then
  exec /bin/bash "$ROOT/nachimux"
fi

# Same trick: reuse this popup process to become the prefix-bar pin manager.
if [[ "$command" == "nachimux-pins" ]]; then
  exec /bin/bash "$ROOT/scripts/palette.sh" pins
fi

# Destructive rows stay in the shared registry but require native tmux
# confirmation after the palette closes. confirm-before is itself an overlay,
# so it must be deferred until this popup is gone (see run_after_popup).
if [[ -n "$confirm" ]]; then
  run_after_popup "confirm-before -p \"$confirm (y/n)\" $command"
  exit 0
fi

# Toggle actions need to inspect current state rather than set a fixed value.
if [[ "$command" == "set -g mouse" ]]; then
  if [[ "$(tmux show -gv mouse)" == "on" ]]; then
    tmux set -g mouse off \; display-message "mouse: off"
  else
    tmux set -g mouse on \; display-message "mouse: on"
  fi
  exit 0
fi

# Commands come from the trusted local registry. Overlay commands (prompts,
# trees, menus) are deferred until the popup closes so they land on the real
# client; everything else runs inline. eval preserves quoted tmux formats and
# expands NACHIMUX_ROOT for helper actions.
if opens_overlay "$command"; then
  run_after_popup "$command"
else
  eval "tmux $command"
fi
