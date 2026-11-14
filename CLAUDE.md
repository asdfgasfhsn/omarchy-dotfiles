# omarchy-dotfiles

A fork of denonmaryland/omarchy-dotfiles (remote `upstream`). `origin` is the
fork. Work directly on `main`.

## Making a change live

This machine uses the linked install (`./install.sh --link`). Most files in
`~/.config` and `~/.local` are symlinks back into this repo, so edits here are
live once reloaded:

- Hyprland (`hypr/*.lua`): `hyprctl reload`, then `hyprctl configerrors`
- Shell plugins (`plugins/`, `omarchy/shell.json`): `omarchy restart shell`
- fastfetch, foot: rerun the program

`hypr/glass.lua` and `hypr/recessed_windows.lua` are **copied**, not linked.
They hold the Glass and Depth drawers' saved slider state. To change their
defaults, edit the repo and the live copy, or move the sliders and copy the
live file back.

The list of what gets linked lives in `lib/linked.sh`. `install.sh` and
`check-links.sh` both read it, so add new top-level paths there.

## After an Omarchy update

Migrations edit user config. Appends and the shell's own saves write through
the links. Migrations that `mv` a new file into place (most `shell.json` ones)
or use `sed -i` replace the link with a plain file without saying anything.
Run:

    ./check-links.sh --fix && git diff

## Duplicated files: change all copies

- `plugins/denon.bar/widgets/` and `plugins/denon.shell/widgets/` are
  identical except `Tray.qml`.
- `indicators/` exists in `denon.bar`, `denon.shell` and `denon.indicators`,
  all identical.
- `Reflection.qml` is identical in `denon.bar` and `denon.shell`.
  `BarModel.js` differs between them.

`plugins/denon.bar/panels/` is the drawer framework that most other plugins
import (`import "../denon.bar/panels"`). `denon.shell` is the bar actually in
use, but don't remove `denon.bar`.

## Gotchas

- Any code here that writes a config file atomically must resolve symlinks
  first (`os.path.realpath`), or it breaks the link. See the `atomic` helpers in
  `local/share/*/control.py`.
- `omarchy plugin validate` refuses symlinks inside a plugin folder. It only
  runs on `omarchy plugin add`/`update` (the four external plugins in
  `install.sh`), which stay as real folders.
- `omarchy plugin list` reports bar-widget plugins as `enabled` only when
  they're placed in the bar, so `denon.menu` shows `false` while working.
- Never edit `~/.config/hypr/monitors.lua`; the installer leaves it alone.
- Never delete `~/.config/omarchy/shell.json` and recreate it while the shell
  runs: the shell watches it, and seeing it vanish left the bar half-drawn and
  rebuilding until `omarchy restart shell`. Swap it in one rename
  (`swap_in_link` in `lib/linked.sh`) or edit it in place.
- `omarchy restart shell` resets world-clock cities you added: Omarchy's
  Elsewhen widget seeds its defaults over them at startup (an Omarchy bug, not
  the links).

## Tests

`tests/multi-monitor-workspaces.sh` runs a nested Hyprland with a virtual
second monitor in a throwaway home and checks the per-monitor workspace chips.
It doesn't touch the live session.
