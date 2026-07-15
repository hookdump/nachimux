#!/usr/bin/env bash
# ============================================================================
#  nachimux · pane active/inactive styling, per light or dark terminal theme
#
#  The "dim the inactive pane" trick only works if the dim colour actually
#  recedes against the terminal background. A light grey on a dark background
#  reads as dim; the SAME light grey on a light background reads as MORE
#  focused. So the palette must flip with the terminal theme.
#
#  Usage:  pane-theme.sh [light|dark]
#          no argument → detect from the attached client's #{client_theme}
#
#  Called on config load and re-run by the client-light-theme /
#  client-dark-theme hooks, so it tracks the terminal live.
# ============================================================================
set -euo pipefail

theme="${1:-}"
[[ -z "$theme" ]] && theme="$(tmux display -p '#{client_theme}' 2>/dev/null || true)"

case "$theme" in
  light)
    # Catppuccin Latte: dark crisp active text, faded grey inactive.
    tmux set -g window-style             "fg=#8c8fa1"            # inactive: faded
    tmux set -g window-active-style      "fg=#4c4f69,bg=default" # active: dark, crisp
    tmux set -g pane-border-style        "fg=#bcc0cc"            # inactive border: light grey
    tmux set -g pane-active-border-style "fg=#8839ef,bold"       # active border: latte mauve
    ;;
  *)
    # Catppuccin Mocha (dark) — the default when theme is dark or unknown.
    tmux set -g window-style             "fg=#6c7086"            # inactive: muted
    tmux set -g window-active-style      "fg=#cdd6f4,bg=default" # active: bright, crisp
    tmux set -g pane-border-style        "fg=#45475a"            # inactive border: dim grey
    tmux set -g pane-active-border-style "fg=#cba6f7,bold"       # active border: mocha mauve
    ;;
esac

tmux refresh-client -S 2>/dev/null || true
