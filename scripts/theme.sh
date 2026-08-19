#!/usr/bin/env bash
# ============================================================================
#  nachimux · the whole palette, per light or dark terminal theme
#
#  Dimming only works if the dim colour actually recedes against the terminal
#  background. A light grey on a dark background reads as dim; the SAME grey on
#  a light background reads as MORE focused. So the palette has to flip with the
#  terminal, and every colour that carries meaning has to flip together — panes
#  AND the status bar, or half the bar ends up arguing with the other half.
#
#  This file owns the colours. The config owns the shapes: it renders tabs as
#  #[fg=#{@nachimux_c_tabdim}]…, so adding a colour here changes the bar without
#  touching a single format string, and no format string hardcodes a hex.
#
#  Usage:  theme.sh [light|dark]
#          no argument → detect from the attached client's #{client_theme}
#
#  Runs on config load and from the client-light-theme / client-dark-theme
#  hooks, so it tracks the terminal live.
# ============================================================================
set -euo pipefail

theme="${1:-}"
[[ -z "$theme" ]] && theme="$(tmux display -p '#{client_theme}' 2>/dev/null || true)"

set_colors() {
  # $1..$17 in the order documented below
  tmux set -g @nachimux_c_tabbg     "$1"   # inactive tab block
  tmux set -g @nachimux_c_tabdim    "$2"   # its index + slash
  tmux set -g @nachimux_c_tabname   "$3"   # its name
  tmux set -g @nachimux_c_numhot    "$4"   # "this digit is live" highlight
  tmux set -g @nachimux_c_numoff    "$5"   # index greyed out (out of reach)
  tmux set -g @nachimux_c_curbg     "$6"   # active tab block
  tmux set -g @nachimux_c_curidx    "$7"   # active tab index
  tmux set -g @nachimux_c_curink    "$8"   # active tab name
  tmux set -g @nachimux_c_attnbg    "$9"   # "needs you" block
  tmux set -g @nachimux_c_attndim   "${10}"
  tmux set -g @nachimux_c_attnink   "${11}"
  tmux set -g @nachimux_c_attnhot   "${12}"
  tmux set -g @nachimux_c_attnoff   "${13}"
  tmux set -g @nachimux_c_accent    "${14}" # prefix / mode pills
  tmux set -g @nachimux_c_accentink "${15}"
  tmux set -g @nachimux_c_mauve     "${16}" # the switcher's own accent
  tmux set -g @nachimux_c_mauveink  "${17}"
}

case "$theme" in
  light)
    # Catppuccin Latte. The accent is latte green, NOT #00ff00 -- pure lime on a
    # light bar is close to invisible, and it is the one colour the whole
    # "what can I press" language depends on.
    tmux set -g window-style             "fg=#8c8fa1"
    tmux set -g window-active-style      "fg=#4c4f69,bg=default"
    tmux set -g pane-border-style        "fg=#bcc0cc"
    tmux set -g pane-active-border-style "fg=#8839ef,bold"
    set_colors \
      "#ccd0da" "#8c8fa1" "#4c4f69" \
      "#2f9e00" "#acb0be" \
      "#40a02b" "#d4eccd" "#eff1f5" \
      "#f9e2af" "#8a6d1f" "#4c4f69" "#2f7d1f" "#c9b78a" \
      "#40a02b" "#eff1f5" \
      "#8839ef" "#eff1f5"
    ;;
  *)
    # Catppuccin Mocha — the default when the theme is dark or unknown.
    tmux set -g window-style             "fg=#6c7086"
    tmux set -g window-active-style      "fg=#cdd6f4,bg=default"
    tmux set -g pane-border-style        "fg=#45475a"
    tmux set -g pane-active-border-style "fg=#cba6f7,bold"
    set_colors \
      "#313244" "#585b70" "#a6adc8" \
      "#00ff00" "#45475a" \
      "#00ff00" "#45475a" "#11111b" \
      "#f9e2af" "#7f6c3f" "#11111b" "#0b4d0b" "#b5a274" \
      "#00ff00" "#11111b" \
      "#cba6f7" "#11111b"
    ;;
esac

# Nothing to rebuild: every consumer stores #{@nachimux_c_*} as a FORMAT and
# resolves it at draw time, so setting the options above is the whole flip.
# A repaint is all that is left.
tmux refresh-client -S 2>/dev/null || true
