#!/bin/bash
# Enumerate Omarchy themes or backgrounds as TSV:
#   key <tab> label <tab> apply-path <tab> thumbnail <tab> current(0|1)
#
# Thumbnails are vipsthumbnail crops in ~/.cache/omarchy/grid-wallpaper-picker, keyed by
# path+mtime+size so a 35MB wallpaper is not decoded by Qt on every open.

set -euo pipefail

mode="${1:-themes}"
USER_THEMES="$HOME/.config/omarchy/themes"
STOCK_THEMES="${OMARCHY_PATH:-/usr/share/omarchy}/themes"
CURRENT_NAME="$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)"
CURRENT_BG="$(readlink -f "$HOME/.local/state/omarchy/current/background" 2>/dev/null || true)"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/grid-wallpaper-picker"
INDEX_FILE="$CACHE_DIR/index.tsv"
PENDING="$CACHE_DIR/pending.$$"

mkdir -p "$CACHE_DIR"
trap 'rm -f "$PENDING"' EXIT
: >"$PENDING"

generate_thumbnail() {
  local image="$1"
  local dest="$2"
  local tmp="$dest.$$.jpg"

  [[ -f $dest ]] && return 0
  if VIPS_CONCURRENCY=1 vipsthumbnail "$image" --size 384x384 --smartcrop=centre --path "$tmp[Q=80,strip]" 2>/dev/null; then
    mv -f "$tmp" "$dest"
  else
    rm -f "$tmp"
  fi
}

thumbnail_for() {
  local image="$1"
  local signature hash dest

  [[ -f $image ]] || return 0
  signature=$(stat -Lc '%s:%Y' "$image") || { printf '%s' "$image"; return 0; }
  hash=$(awk -F '\t' -v path="$image" -v sig="$signature" '$1 == path && $2 == sig { print $3; exit }' "$INDEX_FILE" 2>/dev/null || true)

  if [[ -z $hash ]]; then
    hash=$(printf '%s\t%s' "$image" "$signature" | md5sum | cut -d ' ' -f 1)
    printf '%s\t%s\t%s\n' "$image" "$signature" "$hash" >>"$INDEX_FILE"
  fi

  dest="$CACHE_DIR/$hash.jpg"
  if [[ ! -f $dest ]]; then
    printf '%s\0%s\0' "$image" "$dest" >>"$PENDING"
  fi
  printf '%s' "$dest"
}

drain_pending() {
  [[ -s $PENDING ]] || return 0
  export -f generate_thumbnail
  xargs -0 -n 2 -P "$(nproc)" bash -c 'generate_thumbnail "$1" "$2"' _ <"$PENDING" >/dev/null 2>&1 || true
  : >"$PENDING"
}

resolve_thumb() {
  local image="$1"
  local dest
  dest=$(thumbnail_for "$image")
  if [[ -n $dest && -f $dest ]]; then
    printf '%s' "$dest"
  else
    printf '%s' "$image"
  fi
}

label_from_slug() {
  local s="${1//-/ }" w out=""
  for w in $s; do
    out+="${out:+ }${w^}"
  done
  printf '%s' "$out"
}

find_preview() {
  local theme_path="$1" f ext bg
  for ext in png jpg jpeg webp gif bmp; do
    f="$theme_path/preview.$ext"
    [[ -f $f ]] && { printf '%s' "$f"; return 0; }
  done
  [[ -d $theme_path/backgrounds ]] || return 0
  shopt -s nullglob
  for bg in "$theme_path/backgrounds"/*; do
    [[ -f $bg ]] || continue
    case "${bg,,}" in
      *.jpg|*.jpeg|*.png|*.gif|*.bmp|*.webp)
        printf '%s' "$bg"
        shopt -u nullglob
        return 0
        ;;
    esac
  done
  shopt -u nullglob
}

theme_signature() {
  printf 'v4\ncache:%s\ncurrent:%s\n' "$CACHE_DIR" "$CURRENT_NAME"
  [[ -d $USER_THEMES ]] && stat -Lc 'user:%Y' "$USER_THEMES"
  [[ -d $STOCK_THEMES ]] && stat -Lc 'stock:%Y' "$STOCK_THEMES"
  local d
  for d in "$USER_THEMES"/* "$STOCK_THEMES"/*; do
    [[ -d $d || -L $d ]] || continue
    stat -Lc '%n:%Y' "$d" 2>/dev/null || true
  done
}

background_signature() {
  printf 'v4\ncache:%s\ncurrent:%s\nbg:%s\n' "$CACHE_DIR" "$CURRENT_NAME" "$CURRENT_BG"
  local dir
  for dir in \
    "$HOME/.config/omarchy/backgrounds/$CURRENT_NAME" \
    "$HOME/.local/state/omarchy/current/theme/backgrounds"; do
    [[ -d $dir ]] && stat -Lc '%n:%Y' "$dir"
  done
}

cached_rows() {
  local sigfile="$CACHE_DIR/$mode.sig"
  local rowsfile="$CACHE_DIR/$mode.rows"
  local sig="$1"
  local thumb
  [[ -f $sigfile && -f $rowsfile ]] || return 1
  cmp -s "$sigfile" <(printf '%s' "$sig") || return 1
  # Absolute thumb paths go stale if the cache directory is renamed.
  thumb=$(awk -F '\t' 'NF >= 4 && $4 != "" { print $4; exit }' "$rowsfile")
  if [[ -n $thumb && ! -e $thumb ]]; then
    return 1
  fi
  cat "$rowsfile"
}

emit() {
  local key="$1" label="$2" path="$3" thumb="$4" current="$5" removable="${6:-0}"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$key" "$label" "$path" "$thumb" "$current" "$removable"
}

list_themes() {
  local -A seen=()
  local theme_path theme_name preview current thumb removable
  local tmp
  tmp=$(mktemp)

  for theme_path in "$USER_THEMES"/* "$STOCK_THEMES"/*; do
    [[ -d $theme_path || -L $theme_path ]] || continue
    theme_name=${theme_path##*/}
    [[ -n $theme_name && $theme_name != '*' ]] || continue
    [[ -z ${seen[$theme_name]+x} ]] || continue
    seen[$theme_name]=1

    preview=$(find_preview "$theme_path")
    if [[ -z $preview && -d $STOCK_THEMES/$theme_name ]]; then
      preview=$(find_preview "$STOCK_THEMES/$theme_name")
    fi
    [[ -n $preview ]] || continue

    current=0
    [[ $theme_name == "$CURRENT_NAME" ]] && current=1
    removable=0
    if [[ -d $USER_THEMES/$theme_name && ! -L $USER_THEMES/$theme_name ]]; then
      removable=1
    fi
    thumbnail_for "$preview" >/dev/null
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$theme_name" "$(label_from_slug "$theme_name")" "$theme_name" "$preview" "$current" "$removable" >>"$tmp"
  done

  drain_pending

  while IFS=$'\t' read -r theme_name label path preview current removable; do
    thumb=$(resolve_thumb "$preview")
    emit "$theme_name" "$label" "$path" "$thumb" "$current" "$removable"
  done < <(sort -t $'\t' -k2,2 "$tmp")
  rm -f "$tmp"
}

list_backgrounds() {
  local dir image name current thumb
  local -A seen=()
  local tmp
  tmp=$(mktemp)

  for dir in \
    "$HOME/.config/omarchy/backgrounds/$CURRENT_NAME" \
    "$HOME/.local/state/omarchy/current/theme/backgrounds"; do
    [[ -d $dir ]] || continue
    while IFS= read -r -d '' image; do
      [[ -z ${seen[$image]+x} ]] || continue
      seen[$image]=1
      name=${image##*/}
      name=${name%.*}
      current=0
      if [[ -n $CURRENT_BG && $(readlink -f "$image" 2>/dev/null) == "$CURRENT_BG" ]]; then
        current=1
      fi
      thumbnail_for "$image" >/dev/null
      printf '%s\t%s\t%s\t%s\t%s\n' "$image" "$name" "$image" "$image" "$current" >>"$tmp"
    done < <(find -L "$dir" -maxdepth 1 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' \) \
      -print0 2>/dev/null | sort -z)
  done

  drain_pending

  while IFS=$'\t' read -r key label path preview current; do
    [[ -n $key ]] || continue
    thumb=$(resolve_thumb "$preview")
    emit "$key" "$label" "$path" "$thumb" "$current"
  done <"$tmp"
  rm -f "$tmp"
}

case "$mode" in
  themes)
    sig=$(theme_signature)
    if cached_rows "$sig"; then
      exit 0
    fi
    list_themes | tee "$CACHE_DIR/$mode.rows"
    printf '%s' "$sig" >"$CACHE_DIR/$mode.sig"
    ;;
  backgrounds|wallpaper|wallpapers)
    mode=backgrounds
    sig=$(background_signature)
    if cached_rows "$sig"; then
      exit 0
    fi
    list_backgrounds | tee "$CACHE_DIR/$mode.rows"
    printf '%s' "$sig" >"$CACHE_DIR/$mode.sig"
    ;;
  *)
    echo "Usage: list.sh {themes|backgrounds}" >&2
    exit 1
    ;;
esac
