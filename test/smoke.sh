#!/usr/bin/env bash
# ============================================================================
#  nachimux · smoke test
#
#  tmux does not fail loudly. A broken format renders as nothing at all: no
#  error, no warning, just an empty strip of status bar that looks like a
#  design choice. Every one of these has happened here:
#
#    · a session-local status-format[1] silently stopped inheriting the global
#      status-format[0], and the entire top row went blank
#    · a comma inside #[fg=X,bg=Y] split an enclosing #{?a,b,c}
#    · #{>=:9,10} is TRUE, because those operators compare strings
#    · module colours set after tpm were baked too late to apply, so a cold
#      boot and a reloaded server wore different colours
#
#  None of those are catchable by reading the config, and only the first is
#  even visible without looking closely. So this boots the real config on a
#  throwaway socket, attaches a REAL client -- the blank-row bug does not
#  reproduce without one -- and asserts the bar actually has pixels in it.
#
#  Usage:  test/smoke.sh          run everything
#  Exit:   0 all passed · 1 something failed
# ============================================================================
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$ROOT/tmux.spanish.conf"
IN=nachi-smoke-in; OUT=nachi-smoke-out
PASS=0; FAIL=0

green() { printf '\033[32m%s\033[0m' "$1"; }
red()   { printf '\033[31m%s\033[0m' "$1"; }

ok()   { PASS=$((PASS+1)); printf '  %s %s\n' "$(green '✓')" "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  %s %s\n' "$(red '✗')" "$1"; [[ -n "${2:-}" ]] && printf '      %s\n' "$2"; }
check(){ if [[ -n "${2:-}" ]]; then ok "$1"; else bad "$1" "${3:-got nothing}"; fi; }

cleanup(){ tmux -L $OUT kill-server 2>/dev/null; tmux -L $IN kill-server 2>/dev/null; }
trap cleanup EXIT

boot() { # boot <windows>  — real config, real attached client
  cleanup; sleep 0.3
  tmux -L $IN -f "$CONF" new-session -d -s s -n w1 2>/dev/null || return 1
  sleep 1.5
  local i; for ((i=2;i<=$1;i++)); do tmux -L $IN new-window -d -t s -n "w$i" 2>/dev/null; done
  tmux -L $IN select-window -t s:=1 2>/dev/null
  tmux -L $OUT -f /dev/null new-session -d -s host -x 164 -y 24 2>/dev/null || return 1
  tmux -L $OUT set -g status off >/dev/null 2>&1
  tmux -L $OUT send-keys -t host "TERM=xterm-256color tmux -L $IN attach -t s" Enter 2>/dev/null
  sleep 3
}
screen(){ tmux -L $OUT capture-pane -p -t host 2>/dev/null | head -"${1:-4}"; }
t(){ tmux -L $IN "$@" 2>/dev/null; }

printf '\nnachimux smoke test\n\n'

# ── the config loads at all ────────────────────────────────────────────────
printf 'load\n'
err="$(tmux -L $IN -f "$CONF" new-session -d -s probe 2>&1; tmux -L $IN kill-server 2>/dev/null)"
if [[ -z "$err" ]]; then ok "config sources with no errors"; else bad "config sources with no errors" "$err"; fi

# ── a small workspace: one row of tabs ─────────────────────────────────────
printf '\nsmall workspace (5 tabs)\n'
if boot 5; then
  check "status is 2 rows"            "$( [[ "$(t show -t s -v status)" == 2 ]] && echo y )" "status=$(t show -t s -v status)"
  check "messages avoid the tab row"  "$( [[ "$(t show -t s -v message-line)" == 1 ]] && echo y )"
  S="$(screen 1)"
  check "row 0 has tabs on it"        "$(printf '%s' "$S" | grep -o 'w1')" "row 0 was: '$S'"
  check "row 0 has the workspace name" "$(printf '%s' "$S" | grep -o ' s ')"
  for r in 0 1; do
    check "status-format[$r] renders"  "$(t display -p -t s "#{E:status-format[$r]}" | tr -d ' ')"
  done
else bad "could not boot a 5-tab server"; fi

# ── a big workspace: the second tab row ────────────────────────────────────
printf '\nbig workspace (12 tabs)\n'
if boot 12; then
  check "status grew to 3 rows"       "$( [[ "$(t show -t s -v status)" == 3 ]] && echo y )" "status=$(t show -t s -v status)"
  check "messages moved to row 2"     "$( [[ "$(t show -t s -v message-line)" == 2 ]] && echo y )"
  L0="$(screen 3 | sed -n 1p)"; L1="$(screen 3 | sed -n 2p)"
  check "row 0 carries tabs 1-9"      "$(printf '%s' "$L0" | grep -o 'w9')"  "row 0 was: '$L0'"
  check "row 0 does NOT carry tab 10" "$( printf '%s' "$L0" | grep -q 'w10' || echo y )"
  check "row 1 carries tabs 10+"      "$(printf '%s' "$L1" | grep -o 'w12')" "row 1 was: '$L1'"
  for r in 0 1 2; do
    check "status-format[$r] renders"  "$(t display -p -t s "#{E:status-format[$r]}" | tr -d ' ')"
  done
  for w in 1 9 10 12; do
    check "tab $w renders a label"     "$(t display -p -t s:=$w '#{E:@nachimux_tab_normal}' | grep -o "w$w")"
  done
fi

# ── key tables ─────────────────────────────────────────────────────────────
printf '\nkey tables\n'
check "prefix table is populated"     "$( [[ "$(t list-keys -T prefix | wc -l)" -gt 40 ]] && echo y )"
check "tabsN follow-up table exists"  "$( [[ "$(t list-keys -T tabsN | wc -l)" -ge 15 ]] && echo y )" "tabsN has $(t list-keys -T tabsN | wc -l | tr -d ' ') binds"
check "retired tabs10 table is gone"  "$( [[ "$(t list-keys -T tabs10 2>/dev/null | wc -l)" -eq 0 ]] && echo y )"
check "destructive keys confirm"      "$(t list-keys -T prefix | grep -E ' (X|x) ' | grep -c confirm-before | grep -x 2)" \
                                      "expected both X and x to use confirm-before"

# ── the palette flips ──────────────────────────────────────────────────────
printf '\ntheme\n'
t run-shell "$ROOT/scripts/theme.sh dark" >/dev/null; sleep 0.6
D="$(t show -gv @nachimux_c_curbg)"
t run-shell "$ROOT/scripts/theme.sh light" >/dev/null; sleep 0.6
L="$(t show -gv @nachimux_c_curbg)"
check "accent differs between themes" "$( [[ -n "$D" && -n "$L" && "$D" != "$L" ]] && echo y )" "dark=$D light=$L"
check "light accent is not pure lime" "$( [[ "$L" != "#00ff00" ]] && echo y )" "light accent is $L — invisible on a light bar"
t run-shell "$ROOT/scripts/theme.sh dark" >/dev/null

# ── the sheet still describes reality ──────────────────────────────────────
printf '\ncheatsheet\n'
K="$("$ROOT/nachimux" doctor --keys 2>/dev/null)"
check "doctor --keys reports clean"   "$(printf '%s' "$K" | grep -o '\[ok\]')" "$(printf '%s' "$K" | grep '\[fail\]' | head -3)"

printf '\n%s passed, %s failed\n\n' "$(green "$PASS")" "$( ((FAIL)) && red "$FAIL" || echo 0 )"
(( FAIL == 0 ))
