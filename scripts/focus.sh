#!/usr/bin/env bash
# ============================================================================
#  nachimux · FOCUS workspace
#     prefix F    add this tab to FOCUS
#     prefix U    remove this tab from THIS workspace (safe)
#     prefix C-f  picker: build FOCUS from a list
#
#  A FOCUS workspace is a session made of LINKED windows. Linking does not copy
#  a tab — both workspaces show the SAME window: same window_id, same pane PIDs,
#  one set of processes. Type in one and it happens in the other, because there
#  is only one of it. Each session keeps its own current tab, so moving around
#  in FOCUS doesn't drag the real workspace along.
#
#  That sharing is exactly why the removal verb matters:
#
#     kill-window   (prefix X)  kills the tab in EVERY workspace it appears in
#     unlink-window (prefix U)  removes it from THIS workspace only
#
#  So prefix U is bound to the safe one. This script also refuses to unlink a
#  window that is linked nowhere else — tmux would have nothing left holding it,
#  and "remove from view" would silently become "destroy". Killing the FOCUS
#  session itself is always safe: linked tabs survive in their home workspace.
#
#  Subcommands:
#     add    [window_id]                 link that tab into FOCUS (idempotent)
#     unlink <session_id> <index> <n>    remove it here; n = linked_sessions
#     pick                               fzf popup, multi-select
#     go                                 switch to FOCUS
#
#  DRYRUN=1 makes `pick` print its rows instead of launching fzf.
# ============================================================================
set -o pipefail

FOCUS="$(tmux show-options -gqv @focus_session 2>/dev/null)"
[ -z "$FOCUS" ] && FOCUS="FOCUS"

msg() { tmux display-message "$*"; }

has_focus()  { tmux has-session -t "=$FOCUS" 2>/dev/null; }
focus_ids()  { tmux list-windows -t "=$FOCUS" -F '#{window_id}' 2>/dev/null; }
focus_count(){ focus_ids | grep -c . | tr -d ' '; }
win_name()   { tmux display-message -p -t "$1" '#{window_name}' 2>/dev/null; }

# A session can't be created empty, so a brand-new FOCUS is born holding one
# throwaway window that gets dropped as soon as a real tab is linked in.
PLACEHOLDER=""
ensure_focus() {
  has_focus && return 0
  PLACEHOLDER="$(tmux new-session -d -P -F '#{window_id}' -s "$FOCUS" \
                   -n 'focus…' 'sleep 86400' 2>/dev/null)" || return 1
  return 0
}
drop_placeholder() {
  [ -n "$PLACEHOLDER" ] && tmux kill-window -t "$PLACEHOLDER" 2>/dev/null
  PLACEHOLDER=""
}

# tmux happily links the same window into a session twice, which leaves two
# identical tabs that can no longer be told apart by name — so dedupe here.
link_one() { # $1 = window_id  ->  0 linked, 2 already there, 1 failed
  focus_ids | grep -qx "$1" && return 2
  tmux link-window -s "$1" -t "=$FOCUS:" 2>/dev/null || return 1
  return 0
}

# Remove one link, with both guards: never strand a window that lives nowhere
# else, and never leave the client standing on a session about to vanish.
unlink_one() { # $1=session_id $2=window_index $3=window_id $4=linked_sessions
  local sid="$1" idx="$2" wid="$3" linked="${4:-1}"
  [ "$linked" -le 1 ] 2>/dev/null && return 2
  local n home
  n="$(tmux list-windows -t "$sid" -F x 2>/dev/null | grep -c .)"
  if [ "${n:-0}" -le 1 ]; then
    home="$(tmux list-windows -a -F '#{window_id} #{session_id}' 2>/dev/null \
            | awk -v w="$wid" -v s="$sid" '$1==w && $2!=s {print $2; exit}')"
    [ -n "$home" ] && tmux switch-client -t "$home" 2>/dev/null
  fi
  tmux unlink-window -t "$sid:$idx" 2>/dev/null || return 1
  return 0
}

# ── add ─────────────────────────────────────────────────────────────────────
cmd_add() {
  local wid="${1:-$(tmux display-message -p '#{window_id}')}"
  local name; name="$(win_name "$wid")"
  if has_focus && focus_ids | grep -qx "$wid"; then
    msg "◉ '$name' is already in $FOCUS"; return 0
  fi
  ensure_focus || { msg "focus: could not create $FOCUS"; return 1; }
  case "$(link_one "$wid"; echo $?)" in
    0) drop_placeholder; msg "◉ '$name' → $FOCUS  ·  $(focus_count) tabs" ;;
    2) msg "◉ '$name' is already in $FOCUS" ;;
    *) msg "focus: could not link '$name'" ;;
  esac
}

# ── unlink ──────────────────────────────────────────────────────────────────
cmd_unlink() {
  local sid="$1" idx="$2" wid="$3" linked="$4" name sess
  [ -z "$sid" ] && sid="$(tmux display-message -p '#{session_id}')"
  [ -z "$idx" ] && idx="$(tmux display-message -p '#{window_index}')"
  [ -z "$wid" ] && wid="$(tmux display-message -p '#{window_id}')"
  [ -z "$linked" ] && linked="$(tmux display-message -p '#{window_linked_sessions}')"
  name="$(win_name "$wid")"
  sess="$(tmux display-message -p -t "$sid" '#{session_name}' 2>/dev/null)"
  case "$(unlink_one "$sid" "$idx" "$wid" "$linked"; echo $?)" in
    0) msg "◌ '$name' removed from '$sess' — still open elsewhere" ;;
    2) msg "⚠ '$name' is only in '$sess' — nothing else holds it (prefix X kills it)" ;;
    *) msg "focus: could not unlink '$name'" ;;
  esac
}

# ── go ──────────────────────────────────────────────────────────────────────
cmd_go() {
  has_focus || { msg "no $FOCUS workspace yet — prefix F adds this tab to one"; return 0; }
  tmux switch-client -t "=$FOCUS"
}

# ── pick ────────────────────────────────────────────────────────────────────
cmd_pick() {
  local FZF; FZF="$(command -v fzf || true)"
  [ -z "$FZF" ] && { msg "focus: fzf not found — brew install fzf"; return 0; }

  local RST=$'\033[0m'
  local TAB=$'\033[1;38;2;205;214;244m'    # bold #cdd6f4
  local WS=$'\033[2;38;2;108;112;134m'     # dim  #6c7086
  local ON=$'\033[1;38;2;203;166;247m'     # mauve #cba6f7 — already in FOCUS
  local OFF=$'\033[2;38;2;108;112;134m'
  local ACCENT="#cba6f7"

  local current rows="" n=0
  current="$(focus_ids)"

  while IFS=$'\t' read -r wid sess win; do
    [ -z "$wid" ] && continue
    [ "$sess" = "$FOCUS" ] && continue          # FOCUS's own copies aren't choices
    local mark
    if printf '%s\n' "$current" | grep -qx "$wid"; then
      mark="${ON}●${RST}"
    else
      mark="${OFF}○${RST}"
    fi
    rows="${rows}$(printf '%s  %s%s%s  %s%s%s\t%s' \
      "$mark" "$TAB" "$win" "$RST" "$WS" "$sess" "$RST" "$wid")"$'\n'
    n=$((n + 1))
  done < <(tmux list-windows -a -F '#{window_id}	#{session_name}	#{window_name}' 2>/dev/null)

  if [ "${DRYRUN:-}" = "1" ]; then
    printf 'FOCUS=%s  candidates=%s\nin-focus now: %s\n%s' \
      "$FOCUS" "$n" "$(printf '%s' "$current" | tr '\n' ' ')" "$rows"
    return 0
  fi
  [ "$n" -eq 0 ] && { msg "focus: no other tabs to pick"; return 0; }

  local COLORS="bg+:#313244,bg:#1e1e2e,fg:#cdd6f4,fg+:#cdd6f4,hl:${ACCENT},hl+:${ACCENT}"
  COLORS="$COLORS,pointer:${ACCENT},prompt:${ACCENT},header:${ACCENT},border:#585b70"
  COLORS="$COLORS,info:#6c7086,marker:${ACCENT}"

  local out; out="$(printf '%s' "$rows" \
    | "$FZF" --ansi --delimiter=$'\t' --with-nth='{1}' --accept-nth='{2}' \
        --multi --marker='◉' --pointer='▶' --reverse --no-info --no-sort --cycle \
        --prompt='  ◉ › ' --expect=ctrl-x \
        --header="◉ build FOCUS  ·  tab marks  ·  enter adds  ·  ctrl-x replaces  ·  esc" \
        --border=rounded --margin=0 --padding=0 --color="$COLORS" \
    || true)"
  [ -z "$out" ] && return 0

  local key picked
  key="$(printf '%s' "$out" | head -1)"
  picked="$(printf '%s' "$out" | tail -n +2 | grep -v '^$')"
  [ -z "$picked" ] && return 0

  ensure_focus || { msg "focus: could not create $FOCUS"; return 1; }

  # Link the new set BEFORE dropping anything, so FOCUS never momentarily
  # empties out — an empty session is destroyed by tmux, taking the workspace
  # (and any client sitting on it) with it.
  local added=0 wid
  while IFS= read -r wid; do
    [ -z "$wid" ] && continue
    link_one "$wid" && added=$((added + 1))
  done <<< "$picked"
  drop_placeholder

  # Snapshot the current members before removing any, rather than iterating the
  # live list while mutating it. (It also keeps this to POSIX tools — `tac` is
  # GNU-only and simply isn't there on macOS, where it fails silently inside a
  # process substitution and turns "replace" into "add".)
  local removed=0 kept snapshot
  if [ "$key" = "ctrl-x" ]; then
    snapshot="$(tmux list-windows -t "=$FOCUS" \
                  -F '#{window_id}	#{window_index}	#{session_id}	#{window_linked_sessions}' \
                  2>/dev/null)"
    while IFS=$'\t' read -r wid idx sid linked; do
      [ -z "$wid" ] && continue
      printf '%s\n' "$picked" | grep -qx "$wid" && continue
      unlink_one "$sid" "$idx" "$wid" "$linked" && removed=$((removed + 1))
    done <<< "$snapshot"
  fi

  kept="$(focus_count)"
  tmux switch-client -t "=$FOCUS" 2>/dev/null
  if [ "$key" = "ctrl-x" ]; then
    msg "◉ $FOCUS rebuilt — $kept tabs  (+$added, −$removed)"
  else
    msg "◉ $FOCUS — $kept tabs  (+$added)"
  fi
}

case "${1:-pick}" in
  add)    shift; cmd_add "$@" ;;
  unlink) shift; cmd_unlink "$@" ;;
  go)     shift; cmd_go "$@" ;;
  pick)   shift; cmd_pick "$@" ;;
  *)      sed -n '2,30p' "$0" ;;
esac
