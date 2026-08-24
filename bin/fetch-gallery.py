#!/usr/bin/env python3
"""Fetch bjarneo/omarchy-themes index and write a compact gallery cache.

Source: https://bjarneo.github.io/omarchy-themes/wallpapers.js
If gotar.omarchy-themes already cached a slim manifest, reuse it.

Writes ~/.cache/omarchy/hex-picker/gallery.json
Prints {"ok":true,"path":"...","count":N} (or {"ok":false,"error":"..."}).
"""
import json
import os
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _sec

SOURCE = "https://bjarneo.github.io/omarchy-themes/wallpapers.js"
CACHE_DIR = os.path.expanduser("~/.cache/omarchy/hex-picker")
GALLERY = os.path.join(CACHE_DIR, "gallery.json")
GOTAR = os.path.expanduser("~/.cache/gotar.omarchy-themes/manifest.json")
TTL = 24 * 3600
VARIANT_ORDER = ["palette", "gruvbox", "nord", "material", "aether"]
GALLERY_FORMAT = 2


def fail(msg):
    print(json.dumps({"ok": False, "error": str(msg)}, separators=(",", ":")))
    sys.exit(1)


def variants_of(th):
    if not isinstance(th, dict):
        return []
    out = []
    for key in VARIANT_ORDER:
        t = th.get(key)
        if not isinstance(t, dict):
            continue
        n = t.get("n") or ""
        ct = t.get("ct") or ""
        bg = t.get("bg") or ""
        if not _sec.safe_slug(n) or not ct or not _sec.safe_relpath(ct):
            continue
        if bg and not _sec.safe_relpath(bg):
            bg = ""
        out.append({"k": key, "n": n, "ct": ct, "bg": bg})
    return out


def compact_entry(e):
    if not isinstance(e, dict):
        return None
    variants = variants_of(e.get("th"))
    if not variants:
        return None
    variant = variants[0]
    p = e.get("p") or ""
    if not _sec.safe_relpath(p):
        return None
    thumb = e.get("thumb") or e.get("med") or p
    if thumb and not _sec.safe_relpath(thumb):
        thumb = p
    tags = e.get("tags") if isinstance(e.get("tags"), list) else []
    tags = [t for t in tags if isinstance(t, str) and len(t) <= 128][:16]
    title = e.get("t") if isinstance(e.get("t"), str) and e.get("t") else p.rsplit("/", 1)[-1]
    return {
        "t": title[:256],
        "p": p,
        "thumb": thumb,
        "tags": tags,
        "n": variant["n"],
        "ct": variant["ct"],
        "bg": variant["bg"],
        "vs": variants,
    }


def compact_from_slim(slim):
    if not isinstance(slim, dict):
        raise ValueError("bad slim manifest")
    base = slim.get("base")
    if not _sec.is_allowed_url(base):
        raise ValueError("bad base url")
    entries = slim.get("entries")
    if not isinstance(entries, list):
        raise ValueError("bad entries")
    out = []
    for e in entries:
        item = compact_entry(e)
        if item:
            out.append(item)
    return {
        "format": GALLERY_FORMAT,
        "base": base.rstrip("/"),
        "fetchedAt": int(slim.get("fetchedAt") or time.time()),
        "count": len(out),
        "entries": out,
    }


def load_json_file(path, max_bytes):
    try:
        raw = _sec.read_file_capped(path, max_bytes)
        return json.loads(raw.decode("utf-8"))
    except Exception:
        return None


def cache_fresh(obj):
    if not isinstance(obj, dict) or "entries" not in obj:
        return False
    if obj.get("format") != GALLERY_FORMAT:
        return False
    try:
        fetched = int(obj.get("fetchedAt", 0))
    except Exception:
        return False
    now = int(time.time())
    return fetched <= now + 60 and now - fetched < TTL


def write_gallery(obj):
    os.makedirs(CACHE_DIR, exist_ok=True)
    payload = json.dumps(obj, separators=(",", ":"))
    fd, tmp = tempfile.mkstemp(dir=CACHE_DIR, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(payload)
        os.replace(tmp, GALLERY)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def succeed(obj, persist=True):
    if persist:
        write_gallery(obj)
    print(json.dumps({"ok": True, "path": GALLERY, "count": obj["count"]}, separators=(",", ":")))


def fetch_from_source():
    raw = _sec.http_get(SOURCE, _sec.BYTE_LIMIT_RAW_JS)
    rawtext = raw.decode("utf-8", "replace")
    marker = 'window.WALLPAPERS_BASE_URL = "'
    m = rawtext.find(marker)
    if m == -1:
        raise ValueError("missing WALLPAPERS_BASE_URL")
    start = m + len(marker)
    end = rawtext.index('"', start)
    base = rawtext[start:end].rstrip("/")
    if not _sec.is_allowed_url(base):
        raise ValueError("base URL not allowed")
    start = rawtext.index("window.WALLPAPERS = ")
    start = rawtext.index("{", start)
    end = rawtext.rindex("}")
    data = json.loads(rawtext[start:end + 1])
    if not isinstance(data, dict) or len(data) > _sec.MAX_ENTRIES:
        raise ValueError("unexpected wallpapers map")
    entries = []
    for path, e in data.items():
        if not isinstance(path, str) or not _sec.safe_relpath(path) or not isinstance(e, dict):
            continue
        th_all = e.get("themes") if isinstance(e.get("themes"), dict) else {}
        slim_th = {}
        for v in VARIANT_ORDER:
            t = th_all.get(v)
            if not isinstance(t, dict):
                continue
            n = t.get("name") if isinstance(t.get("name"), str) else ""
            if not _sec.safe_slug(n):
                continue
            ct = t.get("colors_toml") if isinstance(t.get("colors_toml"), str) else ""
            bg = t.get("background") if isinstance(t.get("background"), str) else ""
            slim_th[v] = {"n": n, "ct": ct, "bg": bg}
        item = compact_entry({
            "p": path,
            "t": e.get("title") if isinstance(e.get("title"), str) else "",
            "thumb": e.get("thumb_path") if isinstance(e.get("thumb_path"), str) else "",
            "med": e.get("medium_path") if isinstance(e.get("medium_path"), str) else "",
            "tags": e.get("tags") if isinstance(e.get("tags"), list) else [],
            "th": slim_th,
        })
        if item:
            entries.append(item)
    return {
        "format": GALLERY_FORMAT,
        "base": base,
        "fetchedAt": int(time.time()),
        "count": len(entries),
        "entries": entries,
    }


def main():
    force = "--force" in sys.argv[1:]
    cached = load_json_file(GALLERY, _sec.BYTE_LIMIT_MANIFEST)
    if not force and cache_fresh(cached):
        succeed(cached, persist=False)
        return

    gotar = load_json_file(GOTAR, _sec.BYTE_LIMIT_MANIFEST)
    if not force and cache_fresh(gotar):
        try:
            succeed(compact_from_slim(gotar))
            return
        except Exception:
            pass

    try:
        succeed(fetch_from_source())
    except Exception as ex:
        if cached and isinstance(cached.get("entries"), list):
            succeed(cached)
            return
        fail(ex)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as ex:
        fail(ex)
