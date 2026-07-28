#!/usr/bin/env bash
# ============================================================================
#  nachimux · fuzzy jump to any tab in any workspace   (bound to a prefix key)
#
#  Shows every workspace with its tabs nested below (name + number). Type to
#  fuzzy-filter across BOTH workspace and tab names; ↑/↓ to move; Enter jumps
#  straight into the chosen tab — or, on a workspace row, into that workspace's
#  active tab. Runs inside `display-popup -E`, same as the palette.
#
#  Origin (set by the keybinding via `display-popup -e`, so the popup can mark
#  where you are). Passed as env vars, NOT shell args: a session_id like "$25"
#  passed as an argument would be eaten by the popup shell's positional-parameter
#  expansion, so JUMP_SESSION/JUMP_WINDOW carry them intact instead.
#    JUMP_SESSION = session_id of the pane that opened us  (marks current workspace)
#    JUMP_WINDOW  = window_id  of the pane that opened us   (marks current tab)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${NACHIMUX_ROOT:-$(cd -P "$SCRIPT_DIR/.." && pwd)}"
FZF="$(command -v fzf || true)"
CONFIRM_SOUND_PLAYER="$ROOT/scripts/play-confirm-sound.sh"

CUR_SESSION="${JUMP_SESSION:-}"
CUR_WINDOW="${JUMP_WINDOW:-}"

if [[ -z "$FZF" ]]; then
  tmux display-message "jump: fzf not found — brew install fzf"
  exit 0
fi

# Catppuccin-ish terminal colors (match palette.sh).
WSCOL=$'\033[38;5;183m'    # mauve  — workspace names (header rows)
IDXCOL=$'\033[38;5;102m'   # overlay grey — tab numbers
CURCOL=$'\033[38;5;150m'   # green  — the workspace/tab you're on now
WSTAG=$'\033[38;5;239m'    # dark grey — faint workspace tag on tab rows
YELLOW=$'\033[1;38;5;220m' # bold yellow — a tab/workspace asking for attention
RST=$'\033[0m'

# Each emitted line has two tab-separated fields:
#   1) what fzf DISPLAYS and searches (tree row, with color) — via --with-nth='{1}'
#   2) hidden jump target (session_id or window_id)          — read back on accept
# fzf 0.74 searches the --with-nth field, so all searchable text lives in field 1:
# workspace rows carry the workspace name; tab rows carry the tab index + name PLUS
# a faint (dark-grey) workspace tag, so a combined query like "churn edit" narrows
# to that workspace's tab. Workspace rows target the session (its active tab); tab
# rows target the window.
build() {
  local last_sid="" sid sname wid widx wname wactive attn pointer namecol mark
  # sessions holding at least one attention/bell window — so we can flag the
  # workspace header too, even though its rows stream one at a time.
  local flagged_sessions
  flagged_sessions=" $(tmux list-windows -a -f '#{||:#{@attention},#{window_bell_flag}}' \
                        -F '#{session_id}' 2>/dev/null | sort -u | tr '\n' ' ') "
  while IFS=$'\t' read -r sid sname wid widx wname wactive attn; do
    if [[ "$sid" != "$last_sid" ]]; then
      last_sid="$sid"
      mark=""
      [[ "$sid" == "$CUR_SESSION" ]] && mark=" ${CURCOL}●${RST}"
      if [[ "$flagged_sessions" == *" $sid "* ]]; then
        printf '%s🔔 %s%s%s\t%s\n' "$YELLOW" "$sname" "$RST" "$mark" "$sid"
      else
        printf '%s%s%s%s\t%s\n' "$WSCOL" "$sname" "$RST" "$mark" "$sid"
      fi
    fi
    pointer="  "
    namecol="$RST"
    if [[ "$attn" == "1" ]]; then
      pointer=" ${YELLOW}🔔${RST}"
      namecol="$YELLOW"
    elif [[ "$wid" == "$CUR_WINDOW" ]]; then
      pointer=" ${CURCOL}▶${RST}"
      namecol="$CURCOL"
    fi
    printf '   %s %s%2s%s  %s%s%s   %s%s%s\t%s\n' \
      "$pointer" "$IDXCOL" "$widx" "$RST" "$namecol" "$wname" "$RST" \
      "$WSTAG" "$sname" "$RST" "$wid"
  done < <(tmux list-windows -a \
    -F '#{session_id}	#{session_name}	#{window_id}	#{window_index}	#{window_name}	#{window_active}	#{||:#{@attention},#{window_bell_flag}}')
}

COLORS="bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8,fg:#cdd6f4"
COLORS="$COLORS,header:#f38ba8,info:#cba6f7,pointer:#f5c2e7,marker:#b4befe"
COLORS="$COLORS,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8,border:#585b70"

target="$(build \
  | "$FZF" --ansi \
      --delimiter=$'\t' --with-nth='{1}' --accept-nth='{2}' \
      --prompt='  jump › ' --pointer='▶' \
      --reverse --no-multi --no-info --cycle \
      --border=rounded --margin=0 --padding=0 \
      --header='type to fuzzy-match a tab (or workspace) · ↑↓ move · Enter jumps' \
      --color="$COLORS" \
  || true)"

[[ -z "$target" ]] && exit 0

# Same quiet cue as a palette selection; let tmux own the background process so
# the popup can close immediately.
if [[ -f "$CONFIRM_SOUND_PLAYER" ]]; then
  tmux run-shell -b "$(printf '%q %q' /bin/bash "$CONFIRM_SOUND_PLAYER")" >/dev/null 2>&1 || true
fi

tmux switch-client -t "$target"
