#!/usr/bin/env bash
# Switch monitors on and off for the Control drawer, for this session only:
# monitors.lua is never written, so logging in again or `hyprctl reload`
# brings every display back.
#
#   displays.sh on   "<monitor description>"   back on, with its monitors.lua line
#   displays.sh off  "<monitor description>"   off (refuses the last display on)
#   displays.sh only "<monitor description>"   this one on, every other one off
#
# Monitors are named by description ("desc:..."), the way monitors.lua names
# them, so switching one back on replaces the rule that switched it off.
# DRY_RUN=1 prints the hyprctl commands instead of running them.
set -euo pipefail

conf="$HOME/.config/hypr/monitors.lua"

quote() { local s=${1//\\/\\\\}; printf '"%s"' "${s//\"/\\\"}"; }

run() {
  if [[ -n ${DRY_RUN:-} ]]; then printf 'hyprctl eval %q\n' "$1"; else hyprctl eval "$1" >/dev/null; fi
}

# The monitor's own line in monitors.lua, which carries its mode, position
# and scale. Without one it comes back on Hyprland's preferred settings.
rule_for() {
  grep -E '^[[:space:]]*hl\.monitor\(' "$conf" 2>/dev/null | grep -F "\"desc:$1\"" | head -1 || true
}

on() {
  local line
  line=$(rule_for "$1")
  [[ -n $line ]] || line="hl.monitor({ output = $(quote "desc:$1"), disabled = false, mode = \"preferred\", position = \"auto\", scale = \"auto\" })"
  run "$line"
}

off() { run "hl.monitor({ output = $(quote "desc:$1"), disabled = true })"; }

enabled() { hyprctl monitors -j | jq -r '.[].description'; }

[[ $# -eq 2 && -n $2 ]] || { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

case "$1" in
  on) on "$2" ;;
  off)
    others=$(enabled | grep -vxF -- "$2" | wc -l)
    (( others > 0 )) || { echo "displays.sh: not turning off the last display" >&2; exit 1; }
    off "$2"
    ;;
  only)
    on "$2"
    hyprctl monitors all -j | jq -r --arg d "$2" '.[] | select(.description != $d) | .description' |
      while IFS= read -r other; do off "$other"; done
    ;;
  *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
