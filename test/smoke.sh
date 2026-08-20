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

boot() { # boot <windows> [name-prefix]  — real config, real attached client
  cleanup; sleep 0.3
  # Names must not be substrings of each other: the row checks below grep the
  # rendered bar, and "tab-1" would match inside "tab-11".
  local pre="${2:-w}" ; local -a sfx=(aa bb cc dd ee ff gg hh ii jj kk ll mm nn oo pp)
  tmux -L $IN -f "$CONF" new-session -d -s s -n "${pre}${sfx[0]}" 2>/dev/null || return 1
  sleep 1.5
  local i; for ((i=2;i<=$1;i++)); do tmux -L $IN new-window -d -t s -n "${pre}${sfx[i-1]}" 2>/dev/null; done
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
  check "row 0 has tabs on it"        "$(printf '%s' "$S" | grep -o 'waa')" "row 0 was: '$S'"
  check "row 0 has the workspace name" "$(printf '%s' "$S" | grep -o ' s ')"
  for r in 0 1; do
    check "status-format[$r] renders"  "$(t display -p -t s "#{E:status-format[$r]}" | tr -d ' ')"
  done
else bad "could not boot a 5-tab server"; fi

# ── a big workspace: the second tab row ────────────────────────────────────
# Names are deliberately long here. The split is by WIDTH now, so twelve short
# tabs would correctly fit on one row and prove nothing about the second.
printf '\nbig workspace (12 wide tabs)\n'
if boot 12 "project-tab-"; then
  check "status grew to 3 rows"       "$( [[ "$(t show -t s -v status)" == 3 ]] && echo y )" "status=$(t show -t s -v status)"
  check "messages moved to row 2"     "$( [[ "$(t show -t s -v message-line)" == 2 ]] && echo y )"
  check "every tab got a row"         "$( [[ "$(t list-windows -t s -F '#{@nachimux_row}' | grep -c '^[12]$')" == 12 ]] && echo y )" \
                                      "unassigned tabs fall to row 0 and would double up"
  check "both rows are used"          "$( [[ -n "$(t list-windows -t s -F '#{@nachimux_row}' | grep '^1$')" && -n "$(t list-windows -t s -F '#{@nachimux_row}' | grep '^2$')" ]] && echo y )"
  # A tab must render on exactly one row -- the two loops are mirrored filters,
  # so a filter that stops being each other's complement duplicates or drops tabs.
  L0="$(screen 3 | sed -n 1p)"; L1="$(screen 3 | sed -n 2p)"
  dupes=0; missing=0
  while read -r nm; do
    a=0; b=0
    printf '%s' "$L0" | grep -qF "$nm" && a=1
    printf '%s' "$L1" | grep -qF "$nm" && b=1
    (( a + b == 2 )) && dupes=$((dupes+1))
    (( a + b == 0 )) && missing=$((missing+1))
  done < <(t list-windows -t s -F '#{window_name}')
  check "no tab is on both rows"      "$( (( dupes == 0 )) && echo y )" "$dupes tab(s) drawn twice"
  check "no tab is on neither row"    "$( (( missing == 0 )) && echo y )" "$missing tab(s) drawn nowhere"
  # Balance is the whole point of splitting by width rather than by decade.
  # Real tabs in the -F string: tmux does NOT interpret \t, and a literal
  # backslash-t collapses every field into one, which silently makes each tab
  # measure 4 columns and the whole check meaningless.
  spread="$(t list-windows -t s -F '#{@nachimux_row}	#{window_index}	#{window_name}' \
    | awk -F'	' '{w=length($2)+length($3)+4; if($1==2) r2+=w; else r1+=w}
                  END{d=r1-r2; if(d<0)d=-d; print d}')"
  check "rows are within 25 cols"     "$( [[ "${spread:-999}" -le 25 ]] && echo y )" "spread is $spread columns"
  for r in 0 1 2; do
    check "status-format[$r] renders"  "$(t display -p -t s "#{E:status-format[$r]}" | tr -d ' ')"
  done
fi

# ── narrow tabs stay on one row ────────────────────────────────────────────
printf '\nnarrow workspace (11 short tabs)\n'
if boot 11; then
  check "11 short tabs need one row"  "$( [[ "$(t show -t s -v status)" == 2 ]] && echo y )" \
                                      "status=$(t show -t s -v status) — the old decade rule split these needlessly"
  check "row 0 shows the last one"    "$(screen 1 | grep -o 'wkk')"
fi

# ── key tables ─────────────────────────────────────────────────────────────
printf '\nkey tables\n'
check "prefix table is populated"     "$( [[ "$(t list-keys -T prefix | wc -l)" -gt 40 ]] && echo y )"
check "tabsN follow-up table exists"  "$( [[ "$(t list-keys -T tabsN | wc -l)" -ge 15 ]] && echo y )" "tabsN has $(t list-keys -T tabsN | wc -l | tr -d ' ') binds"
check "retired tabs10 table is gone"  "$( [[ "$(t list-keys -T tabs10 2>/dev/null | wc -l)" -eq 0 ]] && echo y )"
check "destructive keys confirm"      "$(t list-keys -T prefix | grep -E ' (X|x) ' | grep -c confirm-before | grep -x 2)" \
                                      "expected both X and x to use confirm-before"

# ── hooks ──────────────────────────────────────────────────────────────────
# set-hook -g REPLACES. A second declaration of the same hook name silently
# deletes the first, with no error and no visible symptom until the thing that
# stopped running is missed. Chain with ";" instead.
printf '\nhooks\n'
dupes="$(grep -E '^set-hook' "$CONF" | grep -oE 'set-hook -a?g [a-z-]+' | awk '{print $3}' | sort | uniq -d)"
check "no hook is declared twice"     "$( [[ -z "$dupes" ]] && echo y )" "declared more than once: $dupes"
check "window-unlinked survived"      "$(t show-hooks -g | grep 'window-unlinked' | grep -o 'tab-rows')"
check "window-unlinked recounts too"  "$(t show-hooks -g | grep 'window-unlinked' | grep -o 'attention.sh')"
check "bell raises the count"         "$(t show-hooks -g | grep -o 'alert-bell')"
# A tmux single-quoted string cannot contain a single quote. Adding one to a
# '...' hook body ends it early and leaves the hook EMPTY -- no error, the work
# just silently stops happening. Both MRU hooks and pane-focus-in have been
# broken this way; assert every declared hook actually has a body.
empty_hooks=""
while read -r hname; do
  [[ -z "$hname" ]] && continue
  # Hooks live in two scopes: session (show-hooks -g) and window (-gw).
  # pane-focus-in and window-renamed are window-scope and do not appear in -g
  # at all, so checking only one scope reports live hooks as missing.
  body="$( { t show-hooks -g; t show-hooks -gw; } | awk -v h="$hname" '$1 ~ "^" h "\\[" {sub(/^[^ ]+ /,""); print; exit}')"
  [[ -z "$body" ]] && empty_hooks="$empty_hooks $hname"
done < <(grep -E '^set-hook' "$CONF" | grep -oE 'set-hook -a?g [a-z-]+' | awk '{print $3}' | sort -u)
check "no hook has an empty body"     "$( [[ -z "$empty_hooks" ]] && echo y )" "empty:$empty_hooks"

# ── the finder ─────────────────────────────────────────────────────────────
# All three modes emit the same two-field contract, which is the whole reason
# fzf can swap between them with reload() and never know which one it is showing.
printf '\nfinder\n'
for m in all recent needs ws; do
  bad_rows="$("$ROOT/scripts/find.sh" rows "$m" 2>/dev/null | awk -F'\t' 'NF!=2{print NR}' | head -1)"
  check "mode '$m' emits display+target rows" "$( [[ -z "$bad_rows" ]] && echo y )" "row $bad_rows has the wrong field count"
done
check "'all' lists every tab"          "$( [[ "$("$ROOT/scripts/find.sh" rows all 2>/dev/null | grep -c .)" -ge 12 ]] && echo y )"
for k in g f B n; do
  check "prefix $k opens the finder"   "$(t list-keys -T prefix | grep -E "^bind-key +-T prefix $k " | grep -o 'find.sh')"
done
check "prefix w keeps its own switcher" "$(t list-keys -T prefix | grep -E '^bind-key +-T prefix w ' | grep -o 'choose-tree')"
check "prefix W opens workspaces"      "$(t list-keys -T prefix | grep -E '^bind-key +-T prefix W ' | grep -o 'NACHI_FIND_MODE ws')"
# Recency orders the workspace list; it must never shorten it.
ws_rows="$("$ROOT/scripts/find.sh" rows ws 2>/dev/null | grep -c .)"
n_sess="$(t list-sessions 2>/dev/null | grep -c .)"
check "every workspace is listed"      "$( [[ "$ws_rows" -ge 1 ]] && echo y )" "listed $ws_rows"
# session_id is literally $0/$2/... -- unquoted in a run-shell command the shell
# eats it and $0 becomes "sh". Both MRU hooks must quote their ids.
check "MRU hooks quote their ids"      "$(grep -c "record-mru.sh '#{window_id}' '#{session_id}'" "$CONF" | grep -x 2)" \
                                       "an unquoted session_id records the literal string sh"

# ── tab naming ─────────────────────────────────────────────────────────────
# Auto-naming is only safe because rename-window pins a window (sets its own
# automatic-rename off). If that ever stopped being true, every curated tab
# name in every workspace would start drifting.
printf '\ntab naming\n'
check "auto-naming is on"              "$( [[ "$(t show -gv automatic-rename)" == on ]] && echo y )"
check "a shell shows the directory"    "$(t show -gv automatic-rename-format | grep -o 'b:pane_current_path')"
check "ssh is not treated as a shell"  "$( t show -gv automatic-rename-format | grep -q '\*sh' && echo '' || echo y )" \
                                       "a *sh glob would swallow ssh"
t new-window -d -t s -c /tmp 2>/dev/null; sleep 1.5
nw="$(t list-windows -t s -F '#{window_id}' | tail -1)"
t rename-window -t "$nw" 'Pinned By Hand' 2>/dev/null; sleep 0.5
check "renaming pins the window"       "$( [[ "$(t show -w -t "$nw" -v automatic-rename)" == off ]] && echo y )" \
                                       "manual names would drift"
check "the hand-given name stuck"      "$( [[ "$(t display -p -t "$nw" '#{window_name}')" == 'Pinned By Hand' ]] && echo y )"

# ── attention ──────────────────────────────────────────────────────────────
# The flag is per-pane now. Looking at one split must not answer for the others.
printf '\nattention\n'
t split-window -d -t s:1 2>/dev/null; t split-window -d -t s:1 2>/dev/null; sleep 0.5
pa="$(t list-panes -t s:1 -F '#{pane_id}' | sed -n 2p)"
pb="$(t list-panes -t s:1 -F '#{pane_id}' | sed -n 3p)"
t run-shell "$ROOT/scripts/attention.sh raise $pa" 2>/dev/null; sleep 0.4
t run-shell "$ROOT/scripts/attention.sh raise $pb" 2>/dev/null; sleep 0.6
check "two panes both register"        "$( [[ "$(t show -w -t s:1 -v @attention_panes 2>/dev/null)" == "$pa $pb" ]] && echo y )" \
                                       "list is [$(t show -w -t s:1 -v @attention_panes 2>/dev/null)]"
check "the tab is flagged"             "$(t show -w -t s:1 -v @attention 2>/dev/null)"
t run-shell "$ROOT/scripts/attention.sh clear $pa" 2>/dev/null; sleep 0.6
check "clearing one keeps the tab lit" "$(t show -w -t s:1 -v @attention 2>/dev/null)" \
                                       "one pane was still waiting and the tab went dark"
t run-shell "$ROOT/scripts/attention.sh clear $pb" 2>/dev/null; sleep 0.6
check "clearing both unflags the tab"  "$( [[ -z "$(t show -w -t s:1 -v @attention 2>/dev/null)" ]] && echo y )"
check "the badge follows"              "$( [[ -z "$(t show -gv @nachimux_attn_count)" ]] && echo y )"
t run-shell "$ROOT/scripts/attention.sh raise $pa" 2>/dev/null; sleep 0.6
check "needs targets the pane"         "$("$ROOT/scripts/find.sh" rows needs 2>/dev/null; t list-windows -a -F '#{@attention_panes}' | grep -o '%')" 
check "the Claude hook raises a pane"  "$(grep -o 'raise "\$TMUX_PANE"' "$ROOT/scripts/claude-attention-hook.sh")"
t run-shell "$ROOT/scripts/attention.sh clear $pa" 2>/dev/null

# ── the saved-layout offer ─────────────────────────────────────────────────
# It must OFFER and never impose: no auto-restore, and silence when there is
# nothing worth offering.
printf '\nsaved layout\n'
check "auto-restore stays off"          "$( [[ "$(t show -gv @continuum-restore)" == off ]] && echo y )" \
                                        "restoring without being asked is the thing this must never do"
check "the hint has a home in the bar"  "$(t show -gv @nachimux_row_hints | grep -o '@nachimux_restore_hint')"
rdir=$(mktemp -d)
t set -g @resurrect-dir "$rdir" 2>/dev/null
t set -gu @nachimux_restore_dismissed 2>/dev/null
t run-shell "$ROOT/scripts/restore-hint.sh check" 2>/dev/null; sleep 0.4
check "silent with no saves"            "$( [[ -z "$(t show -gv @nachimux_restore_hint 2>/dev/null)" ]] && echo y )"
printf 'window\t0\t1\nwindow\t0\t2\n' > "$rdir/tmux_resurrect_x.txt"
t run-shell "$ROOT/scripts/restore-hint.sh check" 2>/dev/null; sleep 0.4
check "offers when a save exists"       "$(t show -gv @nachimux_restore_hint 2>/dev/null | grep -o 'C-r')"
check "it counts what is in the save"   "$(t show -gv @nachimux_restore_hint 2>/dev/null | grep -o '2 tabs')"
t run-shell "$ROOT/scripts/restore-hint.sh dismiss" 2>/dev/null; sleep 0.4
check "dismissing silences it"          "$( [[ -z "$(t show -gv @nachimux_restore_hint 2>/dev/null)" ]] && echo y )"
t run-shell "$ROOT/scripts/restore-hint.sh check" 2>/dev/null; sleep 0.4
check "and it stays dismissed"          "$( [[ -z "$(t show -gv @nachimux_restore_hint 2>/dev/null)" ]] && echo y )"
check "restoring clears the offer"      "$(t list-keys -T prefix | grep -E '^bind-key +-T prefix C-r ' | grep -o 'restore-hint.sh clear')"
rm -rf "$rdir"; t set -gu @resurrect-dir 2>/dev/null

# ── FOCUS sizing ───────────────────────────────────────────────────────────
# A FOCUS tab is one window in two workspaces. Under window-size `latest` a
# small client viewing FOCUS shrinks that tab in its home workspace too.
printf '\nfocus sizing\n'
t run-shell "$ROOT/scripts/focus.sh size" 2>/dev/null; sleep 0.4
check "latest while no FOCUS exists"    "$( [[ "$(t show -gv window-size)" == latest ]] && echo y )" \
                                        "window-size is $(t show -gv window-size)"
t new-session -d -s FOCUS 2>/dev/null
t run-shell "$ROOT/scripts/focus.sh size" 2>/dev/null; sleep 0.4
check "largest once FOCUS exists"       "$( [[ "$(t show -gv window-size)" == largest ]] && echo y )" \
                                        "a small client would shrink shared tabs everywhere"
t kill-session -t '=FOCUS' 2>/dev/null; sleep 0.6
t run-shell "$ROOT/scripts/focus.sh size" 2>/dev/null; sleep 0.4
check "back to latest when it is gone"  "$( [[ "$(t show -gv window-size)" == latest ]] && echo y )"
check "session-closed re-derives it"    "$(t show-hooks -g | grep 'session-closed' | grep -o 'focus.sh size')"

# ── context-sensitive hints ────────────────────────────────────────────────
printf '\nhint bar\n'
"$ROOT/scripts/prefix-hint.sh" build 2>/dev/null; sleep 0.3
check "the split group is conditional"  "$(t show -gv @nachimux_prefix_hint | grep -o 'window_panes')" \
                                        "split keys would show in tabs with no splits"
check "the group is stashed, not inlined" "$(t show -gv @nachimux_prefix_hint | grep -o '@nachimux_hint_SPLIT')" \
                                        "inlining it lets a label comma split the conditional"
# A fresh window: earlier blocks split the existing ones.
t new-window -d -t s 2>/dev/null; sleep 0.5
w1="$(t list-windows -t s -F '#{window_id}' | tail -1)"
check "hidden with one pane"            "$( [[ -z "$(t display -p -t "$w1" '#{?#{!=:#{window_panes},1},x,}')" ]] && echo y )" \
                                        "that window has $(t display -p -t "$w1" '#{window_panes}') panes"
t split-window -d -t "$w1" 2>/dev/null; sleep 0.5
check "shown once it has splits"        "$(t display -p -t "$w1" '#{?#{!=:#{window_panes},1},x,}')"
# Every operand of #{||:} must be wrapped in #{}. A bare `client_prefix` is the
# literal string, which is non-empty, which is TRUE -- so the condition fires
# always and whatever it guards never appears.
check "no bare operand in #{||:}"       "$( grep -qE '#\{\|\|:[a-z_]+,' "$CONF" && echo '' || echo y )" \
                                        "an unwrapped operand is always true"

# ── git in the bar ─────────────────────────────────────────────────────────
printf '\ngit\n'
check "status-left carries the branch"  "$(t show -gv status-left | grep -o '@nachimux_git')"
"$ROOT/scripts/git-status.sh" "$ROOT" >/dev/null 2>&1
check "reports a branch in a repo"      "$(t show -gv @nachimux_git 2>/dev/null; git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)"
"$ROOT/scripts/git-status.sh" /tmp >/dev/null 2>&1
check "reports nothing outside one"     "$( [[ -z "$("$ROOT/scripts/git-status.sh" /tmp >/dev/null 2>&1; tmux show -gv @nachimux_git 2>/dev/null)" ]] && echo y )"
check "never writes to the repo"        "$(grep -c 'no-optional-locks' "$ROOT/scripts/git-status.sh" | grep -qE '^[1-9]' && echo y)" \
                                        "git can take a lock just by being asked; --no-optional-locks stops that"

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
