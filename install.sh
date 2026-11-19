#!/usr/bin/env bash
# Install these dots on top of a working Omarchy install.
# Everything it replaces is copied to ~/.config/omarchy-dotfiles-backup/<time>-<id>/ first.
#
#   ./install.sh          install, asking once before changing anything
#   ./install.sh --yes    install without asking
#   ./install.sh --link   symlink files to this repo instead of copying them,
#                         so edits here are live (see check-links.sh)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config="$HOME/.config"
# shellcheck source=lib/linked.sh
source "$here/lib/linked.sh"

assume_yes=0
link=0
for arg in "$@"; do
  case "$arg" in
    --yes) assume_yes=1 ;;
    --link) link=1 ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 1 ;;
  esac
done

if ! command -v omarchy >/dev/null 2>&1; then
  echo "omarchy not found. These dots need Omarchy (https://omarchy.org)." >&2
  exit 1
fi

# Omarchy and these plugins read ~/.config directly, so a different
# XDG_CONFIG_HOME would split the install across two places.
if [[ -n "${XDG_CONFIG_HOME:-}" && "$(realpath -m "$XDG_CONFIG_HOME")" != "$(realpath -m "$config")" ]]; then
  echo "XDG_CONFIG_HOME is set to $XDG_CONFIG_HOME. These dots only support ~/.config." >&2
  exit 1
fi

# Plugins installed from their own repos: "<git url> <plugin id>".
external=(
  "https://github.com/denonmaryland/hello-lock hello-lock"
  "https://github.com/denonmaryland/omarchy-theme-studio io.github.denonmaryland.theme-studio"
  "https://github.com/denonmaryland/omarchy-tricky-tiles io.github.denonmaryland.tricky-tiles"
  "https://github.com/denonmaryland/omarchy-softly io.github.denonmaryland.softly"
)

if (( link )); then
  how="symlinked to $here"
else
  how="copied"
fi

if (( ! assume_yes )); then
  cat <<EOF
This will install into your home folder:
  - 26 shell plugins       -> ~/.config/omarchy/plugins/
  - bar layout             -> ~/.config/omarchy/shell.json
  - Hyprland look and keys -> ~/.config/hypr/ (monitors.lua is left alone)
  - fastfetch and foot     -> ~/.config/fastfetch/, ~/.config/foot/
  - helper scripts         -> ~/.local/share/, ~/.local/bin/
  - Hello Lock, Theme Studio, Tricky Tiles and Softly from their own GitHub repos
  - one system package if missing: qt6-5compat (asks for your password)

Files are $how. Anything it replaces is backed up to a new folder in
~/.config/omarchy-dotfiles-backup/.
EOF
  read -r -p "Continue? [y/N] " answer || answer=""
  [[ "$answer" == [yY]* ]] || { echo "Nothing changed."; exit 0; }
fi

# The rail, Workspaces and the floating bar draw their edges with
# Qt5Compat.GraphicalEffects. A fresh Omarchy install doesn't ship it, and
# without it the bar falls back to Omarchy's own.
if ! pacman -Q qt6-5compat >/dev/null 2>&1; then
  echo "Installing qt6-5compat (needs your password)..."
  omarchy-pkg-add qt6-5compat || { echo "Couldn't install qt6-5compat; nothing changed." >&2; exit 1; }
fi

# A fresh, unique backup folder for this run.
mkdir -p "$config/omarchy-dotfiles-backup"
backup="$(mktemp -d "$config/omarchy-dotfiles-backup/$(date +%Y%m%d-%H%M%S)-XXXX")"

# Save a copy of a path (if it exists) into the backup, keeping its place
# relative to $HOME. Only the first copy of each path is kept.
save() {
  local dest="$1" rel="${1#"$HOME"/}"
  [[ -e "$dest" && ! -e "$backup/$rel" ]] || return 0
  # Already a link into this repo: git has the contents, nothing to save.
  [[ -L "$dest" && "$(realpath -m "$dest")" == "$here"/* ]] && return 0
  mkdir -p "$backup/$(dirname "$rel")"
  cp -a "$dest" "$backup/$rel"
}

# Replace a file or folder with ours, after saving the original.
place() {
  local src="$1" dest="$2"
  save "$dest"
  rm -rf -- "$dest"
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
}

# Replace a file or folder with a symlink to ours, after saving the original.
link_to() {
  local src="$1" dest="$2"
  save "$dest"
  swap_in_link "$src" "$dest"
}

# Copy or link, depending on the mode.
put() {
  if (( link )); then link_to "$@"; else place "$@"; fi
}

# The original bar layout, before `omarchy plugin add --enable` changes it.
save "$config/omarchy/shell.json"

echo "Installing plugins, helpers, and Hyprland, fastfetch and foot config ($how)..."
# The bar layout (shell.json) is left for the end: it names the external plugins.
while IFS=$'\t' read -r src dest; do
  [[ $src == "$here/omarchy/shell.json" ]] && continue
  put "$src" "$dest"
  if [[ $dest == "$HOME/.local/bin/"* ]]; then chmod +x "$dest"; fi
done < <(linked_paths "$here")
# Saved drawer state: always copied.
while IFS=$'\t' read -r src dest; do
  place "$src" "$dest"
done < <(copied_paths "$here")

# Touchpad drawer: write its settings file once, from the current values.
if [[ ! -e "$config/hypr/touchpad-control.lua" ]] &&
   hyprctl devices -j 2>/dev/null | grep -qi '"name": *"[^"]*touchpad'; then
  python3 "$HOME/.local/share/touchpad-control/control.py" init >/dev/null 2>&1 ||
    echo "  touchpad controls not set up (you can still use the defaults)"
fi

echo "Adding Hello Lock, Theme Studio, Tricky Tiles and Softly..."
missing=()
for entry in "${external[@]}"; do
  read -r repo id <<<"$entry"
  save "$config/omarchy/plugins/$id"
  if [[ -f "$config/omarchy/plugins/$id/manifest.json" ]]; then
    # Already installed (a re-run): update it in place and make sure it's on.
    omarchy plugin update "$id" --yes || echo "  could not update $id; keeping the installed copy"
    omarchy plugin enable "$id" >/dev/null 2>&1 || true
    continue
  fi
  if ! omarchy plugin add "$repo" --enable --yes || [[ ! -f "$config/omarchy/plugins/$id/manifest.json" ]]; then
    echo "  could not add $repo (try later: omarchy plugin add $repo --enable)"
    missing+=("$id")
  fi
done

# The bar layout goes last: it names the plugins above. Anything that failed
# to install is left out, and the stock lock screen stays on without Hello Lock.
if (( link && ! ${#missing[@]} )); then
  link_to "$here/omarchy/shell.json" "$config/omarchy/shell.json"
else
  # With plugins missing, the layout is edited below, so it gets its own copy
  # rather than an edited repo file.
  (( link )) && echo "  shell.json copied, not linked, because some plugins are missing (check-links.sh lists it until you add them and re-run)"
  place "$here/omarchy/shell.json" "$config/omarchy/shell.json"
fi
if (( ${#missing[@]} )); then
  python3 - "$config/omarchy/shell.json" "${missing[@]}" <<'PY'
import json, sys
path, missing = sys.argv[1], set(sys.argv[2:])
d = json.load(open(path))
d["plugins"] = [p for p in d.get("plugins", []) if p.get("id") not in missing]
for side, items in d.get("bar", {}).get("layout", {}).items():
    d["bar"]["layout"][side] = [w for w in items if w.get("id") not in missing]
if "hello-lock" in missing:
    d["disabledPlugins"] = [p for p in d.get("disabledPlugins", []) if p != "omarchy.lock"]
json.dump(d, open(path, "w"), indent=2)
PY
fi

echo "Reloading..."
hyprctl reload >/dev/null 2>&1 || true
omarchy restart shell >/dev/null 2>&1 || true

cat <<EOF

Done. Backups of anything replaced are in:
  $backup
EOF
if (( ${#missing[@]} )); then
  echo "Not installed (left out of the bar): ${missing[*]}"
fi
if (( link )); then
  echo "Linked to $here. After an Omarchy update, run ./check-links.sh to catch files"
  echo "an update replaced instead of editing through the link."
fi
echo 'To put your own name on the menu and fastfetch, see "Make it yours" in the README.'
