#!/usr/bin/env bash
# ============================================================================
#  nachimux · "is there anything behind this digit?"
#
#  Answers, for one workspace: does a tab exist in decade <d> — that is, any
#  index from d0 to d9?  Exit 0 = yes.
#
#      has-decade.sh 1 '$2'    ->  0 if tabs 10-19 exist in session $2
#
#  This is what makes `prefix 1` two different keys depending on your tabs:
#  with tabs 10-19 around it has to ask which one you meant, and without them
#  there is nothing to ask about, so it jumps straight to tab 1. Checking live
#  rather than caching a flag means renaming, killing, moving or renumbering
#  tabs can never leave the answer stale.
# ============================================================================
set -uo pipefail
d="${1:?need a decade digit}"
s="${2:-}"
if [[ -n "$s" ]]; then
  tmux list-windows -t "$s" -F '#{window_index}' 2>/dev/null | grep -qx "${d}[0-9]"
else
  tmux list-windows -F '#{window_index}' 2>/dev/null | grep -qx "${d}[0-9]"
fi
