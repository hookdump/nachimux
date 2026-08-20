#!/usr/bin/env bash
# ============================================================================
#  nachimux · "there is a saved layout, if you want it"
#
#  continuum autosaves every 15 minutes and @continuum-restore is off, because
#  a clean start is the intended way to open tmux. The gap that leaves: the save
#  exists and never comes back unless you happen to remember prefix C-r, so a
#  crash and a deliberate fresh start look exactly alike -- and the one time you
#  needed the save is the one time you were not thinking about it.
#
#  So the answer is to OFFER, never impose. On a fresh server, if a recent save
#  exists, the bar says so and names the key. Restoring clears it. Dismissing
#  clears it. It never restores anything on its own.
#
#  Deliberately not on a timer: it is checked when a server starts and when you
#  attach, which is when the answer can be new. Dismissal lives in a tmux option
#  so it lasts exactly as long as the server does -- a new server asks again,
#  which is the whole point.
#
#    restore-hint.sh check     look for a save and publish the hint
#    restore-hint.sh dismiss   not now
#    restore-hint.sh clear     restored (or otherwise handled)
# ============================================================================
set -uo pipefail

DIR="$(tmux show -gv @resurrect-dir 2>/dev/null)"
[[ -z "$DIR" ]] && DIR="$HOME/.local/share/tmux/resurrect"
MAX_AGE_HOURS=48

publish() { tmux set -g @nachimux_restore_hint "${1:-}" 2>/dev/null || true; }

case "${1:-check}" in
  dismiss)
    tmux set -g @nachimux_restore_dismissed 1 2>/dev/null || true
    publish ""; tmux display-message "  saved layout dismissed"; ;;
  clear)
    tmux set -g @nachimux_restore_dismissed 1 2>/dev/null || true
    publish "" ;;
  check)
    [[ "$(tmux show -gv @nachimux_restore_dismissed 2>/dev/null)" == 1 ]] && exit 0
    newest="$(ls -t "$DIR"/tmux_resurrect_*.txt 2>/dev/null | head -1)"
    [[ -n "$newest" && -s "$newest" ]] || { publish ""; exit 0; }

    now=$(date +%s)
    mtime="$(stat -f %m "$newest" 2>/dev/null || stat -c %Y "$newest" 2>/dev/null || echo 0)"
    age=$(( (now - mtime) / 60 ))                       # minutes
    (( age < 0 )) && age=0
    (( age > MAX_AGE_HOURS * 60 )) && { publish ""; exit 0; }

    if   (( age < 60 ));   then label="${age}m"
    elif (( age < 1440 )); then label="$(( age / 60 ))h"
    else                        label="$(( age / 1440 ))d"
    fi

    # How many tabs are in it -- "restore 16 tabs" is a decision, "restore" is a
    # dare. The save lists one line per window; count the distinct ones.
    tabs="$(awk -F'\t' '$1=="window"{print $2 "\t" $3}' "$newest" 2>/dev/null | sort -u | grep -c . || true)"
    [[ "${tabs:-0}" -gt 0 ]] && what="${tabs} tabs" || what="a layout"

    publish "#[fg=#{@nachimux_c_accentink}]#[bg=#{@nachimux_c_accent}] ⟲ ${what} saved ${label} ago #[default]#[fg=#{@nachimux_c_tabdim}] prefix C-r restores · prefix D dismisses #[default]"
    ;;
esac
