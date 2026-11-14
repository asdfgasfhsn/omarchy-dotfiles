#!/usr/bin/env bash
# Check a linked install (./install.sh --link) after an Omarchy update.
#
# Some updates edit a file through its link, so the change already shows up in
# `git status` here. Others write a new file and move it into place, which
# replaces the link with a plain file. Nothing warns you when that happens:
# the repo stops seeing changes and the two drift apart. This finds those files.
#
#   ./check-links.sh        report only (exits 1 if anything needs attention)
#   ./check-links.sh --fix  copy each replaced file back into the repo and
#                           link it again; review with `git diff` afterwards
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/linked.sh
source "$here/lib/linked.sh"

fix=0
case "${1:-}" in
  "") ;;
  --fix) fix=1 ;;
  -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
esac

ok=0 linked_any=0 problems=0
replaced=() missing=() elsewhere=()

while IFS=$'\t' read -r src dest; do
  if [[ -L $dest ]]; then
    linked_any=1
    if [[ "$(realpath -m "$dest")" == "$(realpath -m "$src")" ]]; then
      ok=$((ok + 1))
    else
      elsewhere+=("$dest -> $(readlink "$dest")")
    fi
  elif [[ -e $dest ]]; then
    replaced+=("$src"$'\t'"$dest")
  else
    missing+=("$src"$'\t'"$dest")
  fi
done < <(linked_paths "$here")

if (( ! linked_any )); then
  echo "Nothing here is linked to $here. Install with ./install.sh --link first."
  exit 1
fi

echo "$ok linked and fine."

if (( ${#replaced[@]} )); then
  problems=1
  echo
  echo "Replaced by a plain file or folder (an update wrote a new one over the link):"
  for entry in "${replaced[@]}"; do
    IFS=$'\t' read -r src dest <<<"$entry"
    echo "  ${dest/#$HOME/\~}"
    diff -ru --label "repo/${src#"$here"/}" --label "live/${dest#"$HOME"/}" \
      -x __pycache__ "$src" "$dest" | sed 's/^/    /' | head -40 || true
  done
fi

if (( ${#missing[@]} )); then
  problems=1
  echo
  echo "Missing (nothing at the destination):"
  for entry in "${missing[@]}"; do
    IFS=$'\t' read -r src dest <<<"$entry"
    echo "  ${dest/#$HOME/\~}"
  done
fi

if (( ${#elsewhere[@]} )); then
  problems=1
  echo
  echo "Linked somewhere other than this repo (left alone, even with --fix):"
  printf '  %s\n' "${elsewhere[@]}"
fi

(( problems )) || exit 0

if (( ! fix )); then
  echo
  echo "Run ./check-links.sh --fix to copy replaced files back into the repo and link them again."
  exit 1
fi

echo
for entry in "${replaced[@]}"; do
  IFS=$'\t' read -r src dest <<<"$entry"
  # The live copy wins: it's what's running, and it carries the update's change.
  # git still has the old version if you want it back.
  rm -rf -- "$src"
  cp -a "$dest" "$src"
  find "$src" -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true
  rm -rf -- "$dest"
  ln -s "$src" "$dest"
  echo "Took the live copy and linked again: ${dest/#$HOME/\~}"
done
for entry in "${missing[@]}"; do
  IFS=$'\t' read -r src dest <<<"$entry"
  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest"
  echo "Linked: ${dest/#$HOME/\~}"
done
echo
echo "Review what came in with: git -C \"$here\" diff"
