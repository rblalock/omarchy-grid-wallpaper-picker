#!/bin/bash
# Download one gallery thumb into the on-disk cache if missing.
set -euo pipefail

url="${1:-}"
dest="${2:-}"
[[ -n $url && -n $dest ]] || exit 1
[[ -f $dest ]] && exit 0

case "$url" in
  https://wallpapers.hel1.your-objectstorage.com/*) ;;
  https://bjarneo.github.io/*) ;;
  *) exit 1 ;;
esac

mkdir -p "$(dirname -- "$dest")"
tmp="$dest.$$"
if curl -fsSL --max-time 20 --retry 0 -o "$tmp" "$url"; then
  mv -f "$tmp" "$dest"
else
  rm -f "$tmp"
  exit 1
fi
