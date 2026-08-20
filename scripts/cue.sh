#!/usr/bin/env bash
# ============================================================================
#  nachimux · the confirmation cue, and its off switch
#
#  Every action key plays a short cue. That used to mean every keypress ran a
#  script that re-resolved its own path, looked for a player, and then played
#  something -- 73 call sites of it, including the keys you hold down.
#
#  Measured, the wrapper was never the expensive part: it cost about 0.2ms more
#  than an empty shell, and `run-shell` forks either way. So this does not chase
#  the fork. It does two things that actually matter:
#
#    · resolves the player ONCE, at load, into a ready-to-exec command string
#      that lives in a tmux option -- so 73 bindings shrink to
#      `run-shell -b "#{@nachimux_cue_action}"` and no longer carry a path
#    · makes muting free, by swapping that option to `:`. Muted, the "sound
#      pipeline" is a shell no-op. Nothing to detect, nothing to play.
#
#  Muting is a real state, not a preference buried in the config: it survives a
#  server restart via the state file, and the status bar shows it the whole time
#  it is on, so you can never be muted without knowing.
#
#  Usage:  cue.sh init      resolve the player and publish the options
#          cue.sh toggle    flip muted, republish, say so
#          cue.sh muted     exit 0 if muted (for other scripts to ask)
# ============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${NACHIMUX_ROOT:-$(cd -P "$SCRIPT_DIR/.." && pwd)}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/nachimux"
MUTE_FILE="$STATE_DIR/muted"

ACTION_SOUND="$ROOT/sounds/tmux-action-confirm.mp3"
PREFIX_SOUND="$ROOT/sounds/tmux-prefix-ready.mp3"

is_muted() { [[ -e "$MUTE_FILE" ]]; }

# The first player that exists, as a command prefix. Resolved once per init,
# never per keypress.
player() {
  if   command -v afplay  >/dev/null 2>&1; then printf 'afplay'
  elif command -v ffplay  >/dev/null 2>&1; then printf 'ffplay -nodisp -autoexit -loglevel quiet'
  elif command -v mpg123  >/dev/null 2>&1; then printf 'mpg123 -q'
  fi
}

publish() {
  local p action prefix
  p="$(player)"
  if is_muted || [[ -z "$p" ]]; then
    # `:` is the shell's no-op. run-shell still forks a shell -- it always does
    # -- but there is nothing behind it.
    action=':' ; prefix=':'
  else
    action="exec $p '$ACTION_SOUND' >/dev/null 2>&1"
    prefix="exec $p '$PREFIX_SOUND' >/dev/null 2>&1"
  fi
  tmux set -g @nachimux_cue_action "$action"  2>/dev/null || true
  tmux set -g @nachimux_cue_prefix "$prefix"  2>/dev/null || true
  # Drives the status-bar indicator. Empty (not "0") so #{?...} reads it false.
  if is_muted; then tmux set -g @nachimux_muted 1  2>/dev/null || true
  else              tmux set -g @nachimux_muted "" 2>/dev/null || true
  fi
}

case "${1:-init}" in
  init)   publish ;;
  muted)  is_muted ;;
  toggle)
    mkdir -p "$STATE_DIR"
    if is_muted; then rm -f "$MUTE_FILE"; else : > "$MUTE_FILE"; fi
    publish
    # Cue the unmute with the sound itself -- the most direct possible proof.
    is_muted || { c="$(tmux show -gv @nachimux_cue_action 2>/dev/null)"; [[ -n "$c" && "$c" != ':' ]] && ( sh -c "$c" & ) ; }
    if is_muted; then tmux display-message "  cues muted"; else tmux display-message "  cues on"; fi
    tmux refresh-client -S 2>/dev/null || true
    ;;
  *) echo "usage: cue.sh {init|toggle|muted}" >&2; exit 2 ;;
esac
