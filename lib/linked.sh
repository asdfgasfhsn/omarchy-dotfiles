# Sourced by install.sh and check-links.sh. Not meant to be run.
#
# linked_paths <repo> prints "<source>\t<destination>" for every path that
# `./install.sh --link` symlinks into your home folder instead of copying.
#
# Left out on purpose:
#   hypr/glass.lua, hypr/recessed_windows.lua
#     Saved slider state from the Glass and Depth drawers. Linked, every slider
#     move would show up as a change in git. They stay copied.
linked_paths() {
  local repo="$1" path name
  for path in "$repo"/plugins/*/; do
    name="$(basename "$path")"
    printf '%s\t%s\n' "${path%/}" "$HOME/.config/omarchy/plugins/$name"
  done
  for path in "$repo"/local/share/*/; do
    name="$(basename "$path")"
    printf '%s\t%s\n' "${path%/}" "$HOME/.local/share/$name"
  done
  for path in "$repo"/local/bin/*; do
    printf '%s\t%s\n' "$path" "$HOME/.local/bin/$(basename "$path")"
  done
  for path in "$repo"/hypr/*.lua; do
    name="$(basename "$path")"
    [[ $name == glass.lua || $name == recessed_windows.lua ]] && continue
    printf '%s\t%s\n' "$path" "$HOME/.config/hypr/$name"
  done
  printf '%s\t%s\n' "$repo/fastfetch/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
  printf '%s\t%s\n' "$repo/fastfetch/dashboard.py" "$HOME/.config/fastfetch/dashboard.py"
  printf '%s\t%s\n' "$repo/foot/foot.ini" "$HOME/.config/foot/foot.ini"
  printf '%s\t%s\n' "$repo/omarchy/shell.json" "$HOME/.config/omarchy/shell.json"
}

# Copied in both modes.
copied_paths() {
  local repo="$1"
  printf '%s\t%s\n' "$repo/hypr/glass.lua" "$HOME/.config/hypr/glass.lua"
  printf '%s\t%s\n' "$repo/hypr/recessed_windows.lua" "$HOME/.config/hypr/recessed_windows.lua"
}
