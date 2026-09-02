#!/bin/bash
# Download one gallery thumb into the on-disk cache if missing.
set -euo pipefail

url="${1:-}"
dest="${2:-}"
[[ -n $url && -n $dest ]] || exit 1
case "$url" in
  https://wallpapers.hel1.your-objectstorage.com/*) ;;
  https://bjarneo.github.io/*) ;;
  *) exit 1 ;;
esac

# Unused by the overlay (prefetch-thumbs.py is the live path). Keep the same
# allowlist and refuse redirects so a leftover helper cannot follow Location.
mkdir -p "$(dirname -- "$dest")"
tmp="$dest.$$"
if curl -fsS --max-redirs 0 --max-time 20 --retry 0 -o "$tmp" "$url"; then
  mv -f "$tmp" "$dest"
else
  rm -f "$tmp"
  exit 1
fi
