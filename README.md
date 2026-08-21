# nachimux

A tmux config built to feel like a browser: projects are **workspaces**, windows are
**tabs**, panes are **splits**. It uses the standard tmux prefix: **`Ctrl-b`**.

Built for a Spanish keyboard — no binding needs AltGr, which on that layout is where
`[ ] { } | \ ~` live — but nothing about it is Spanish-only, and it works the same on
any other layout.

The full visual guide is in [tmux-guide.html](./tmux-guide.html).

## Getting started

```sh
# Main dependencies (macOS)
brew install tmux gum fzf zoxide

# From this directory
./nachimux setup
nachimux doctor
nachimux docs
```

`setup` links the command into `~/.local/bin`, adds this profile to `~/.tmux.conf`,
installs [TPM](https://github.com/tmux-plugins/tpm) and its plugins, and reloads tmux
if it is already running. It finishes with a working status bar. It never replaces a
file or a link it does not recognise.

If the plugin step does not finish, it says so: open tmux, press `Ctrl-b`, let go,
then press `I`.

To undo it:

```sh
nachimux uninstall           # removes the link and the block in ~/.tmux.conf
nachimux uninstall --purge   # also drops pins, recent lists and the mute state
```

`uninstall` only touches what `setup` created. A link pointing somewhere else, or
config you wrote by hand, is left alone — as are TPM, the plugins and this repo.

## The one concept that matters

Shortcuts are written as `prefix p`. That means:

1. Press `Ctrl-b`.
2. Let go of both keys.
3. Press `p`.

`prefix p` opens a searchable palette that **runs** actions. `prefix /` opens
`nachimux` in another popup to **look things up and learn** them. Both read the same
registry, so the keys and their descriptions cannot drift apart.

## The `nachimux` command

```text
nachimux                  search every shortcut
nachimux split            open the search pre-filtered by "split"
nachimux category         browse by category
nachimux all              print the whole cheatsheet
nachimux prefix           explain how to use Ctrl-b
nachimux docs             open the visual guide
nachimux doctor           check the install, dependencies and live prefix
nachimux doctor --keys    check the cheatsheet against the real bindings
nachimux setup            install the link, activate the profile, install plugins
nachimux uninstall        undo setup (--purge also drops saved state)
nachimux help             show the help
```

The existing short options still work: `-c`, `-a`, `-p` and `-h`.

## Enough shortcuts to survive the first day

| Action | Keys |
| --- | --- |
| Open the palette | `prefix p` |
| Look up every shortcut | `prefix /` |
| Find any tab, anywhere | `prefix g` |
| Switch or create a workspace | `prefix w` |
| Recent workspaces | `prefix W` |
| New tab | `prefix t` |
| Split side by side | `prefix =` |
| Split top and bottom | `prefix -` |
| Move between splits | `prefix h/j/k/l` |
| Zoom a split | `prefix z` |
| Reload the config | `prefix r` |
| Leave without closing anything | `prefix d` |

`prefix g` is the finder. It opens on every tab in every workspace, and `ctrl-a` /
`ctrl-r` / `ctrl-n` / `ctrl-w` switch it between all tabs, recent tabs, tabs asking
for your attention, and workspaces — after it is open, so a wrong guess costs a
keystroke instead of a reopen. `prefix f`, `prefix B` and `prefix n` are the same
finder opened on a different filter.

## Files

- `nachimux.conf`: the main config.
- `data/cheatsheet.tsv`: the single registry of shortcuts, actions and confirmations.
- `scripts/`: the palette, the finder, the sounds and the status bar.
- `test/smoke.sh`: boots the config on a throwaway socket with a real attached client
  and checks the bar actually draws something. tmux does not fail loudly — a broken
  format renders as nothing at all.
- `tmux-guide.html`: self-contained visual documentation.

The profile resolves its scripts from wherever the repo actually lives, so it does not
care which directory you cloned it into.

The registry's columns are `category`, `mode`, `keys`, `description`, `command` and
`confirm`. A row with a `command` also shows up in the runnable palette. If it also
has a `confirm`, tmux asks before running a destructive action — and
`nachimux doctor --keys` fails if a row promises a prompt the binding does not honour.

The profile, the CLI and all the documentation use the standard `C-b`, so there are
never two different sources of truth.
