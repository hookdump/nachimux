#!/usr/bin/env bash
# Play the action confirmation cue without surfacing player output or errors.

set -u

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${NACHIMUX_ROOT:-$(cd -P "$SCRIPT_DIR/.." && pwd)}"
SOUND="${1:-${NACHIMUX_CONFIRM_SOUND:-$ROOT/sounds/tmux-action-confirm.mp3}}"

[[ -r "$SOUND" ]] || exit 0

if command -v afplay >/dev/null 2>&1; then
  exec afplay "$SOUND" >/dev/null 2>&1
elif command -v ffplay >/dev/null 2>&1; then
  exec ffplay -nodisp -autoexit -loglevel quiet "$SOUND" >/dev/null 2>&1
elif command -v mpg123 >/dev/null 2>&1; then
  exec mpg123 -q "$SOUND" >/dev/null 2>&1
fi

exit 0
