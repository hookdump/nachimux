#!/usr/bin/env bash
# ============================================================================
#  nachimux · "needs you" menu   (bound to a prefix key)
#
#  Pops a tmux menu listing every tab that is asking for attention — i.e. any
#  window flagged @attention (set by the Claude Code hook) OR carrying tmux's
#  native bell flag (any program that rang the bell). Each entry gets a letter;
#  press it to jump straight there. Switching in clears the flag (focus-in hook
#  + tmux clears the bell on select). The tab you're already on is excluded.
#
#  Args (from the keybinding, expanded by run-shell):
#    $1 = client name that pressed the key   (so the menu lands on the right one)
#    $2 = window_id you're on now             (excluded from the list)
#
#  DRYRUN=1 prints the tmux command instead of running it (for testing).
# ============================================================================
# no `set -u`: macOS bash 3.2 errors on empty-array expansion under nounset
set -eo pipefail

CLIENT="${1:-}"
ORIGIN="${2:-}"

# letters offered, in a comfortable home-row-first order
KEYS="asdfjklghqwertyuiop"

items=()
n=0
while IFS=$'\t' read -r wid disp; do
  [ "$wid" = "$ORIGIN" ] && continue
  [ "$n" -ge "${#KEYS}" ] && break
  k="${KEYS:$n:1}"
  n=$((n + 1))
  items+=( "$disp" "$k" "switch-client -t '$wid'" )
done < <(tmux list-windows -a \
           -f '#{||:#{@attention},#{window_bell_flag}}' \
           -F '#{window_id}	#{session_name} / #{window_name}')

client_arg=()
[ -n "$CLIENT" ] && client_arg=( -c "$CLIENT" )

if [ "$n" -eq 0 ]; then
  tmux display-message "${client_arg[@]}" "#[fg=#00ff00,bold]  ✓ nothing needs you right now  "
  exit 0
fi

if [ "${DRYRUN:-}" = "1" ]; then
  printf 'tmux display-menu %s -T " needs you " -x R -y S\n' "${client_arg[*]}"
  printf '  [%s]\n' "${items[@]}"
  exit 0
fi

tmux display-menu "${client_arg[@]}" -T " 🔔 needs you " -x R -y S "${items[@]}"
