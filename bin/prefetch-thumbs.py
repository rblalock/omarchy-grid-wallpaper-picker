#!/usr/bin/env python3
"""Download gallery thumbs in parallel into ~/.cache/omarchy/grid-wallpaper-picker/net/.

Prints each absolute dest path as soon as it is on disk (already cached or
just fetched) so the overlay can reveal hexes incrementally.

Helsinki TTFB is ~0.5s; many workers beat Qt's Image HTTPS loader.
Downloads go through _sec.http_get_bounded (curl --max-time, no redirects,
byte cap) and sniff_image before a file is trusted.
"""
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _sec

GALLERY = os.path.expanduser("~/.cache/omarchy/grid-wallpaper-picker/gallery.json")
CACHE_NET = os.path.expanduser("~/.cache/omarchy/grid-wallpaper-picker/net")
JOBS = 24
FETCH_SECONDS = 20


def dest_for(base, rel):
    url = base.rstrip("/") + "/" + rel.lstrip("/")
    path = url.split("://", 1)[-1]
    path = path.split("/", 1)[-1]  # strip host
    return url, os.path.join(CACHE_NET, path)


def cached_ok(dest):
    return _sec.sniff_image_file(dest)


def fetch_one(url, dest):
    if cached_ok(dest):
        return dest, True
    if os.path.lexists(dest):
        try:
            os.unlink(dest)
        except OSError:
            return dest, False
    if not _sec.is_allowed_url(url):
        return dest, False
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    tmp = dest + ".%d.tmp" % os.getpid()
    try:
        data = _sec.http_get_bounded(url, _sec.BYTE_LIMIT_MEDIA, total_seconds=FETCH_SECONDS)
        _sec.sniff_image(data)
        with open(tmp, "wb") as f:
            f.write(data)
        os.replace(tmp, dest)
        if not cached_ok(dest):
            os.unlink(dest)
            return dest, False
        return dest, False
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        return dest, False


def main():
    try:
        raw = _sec.read_file_capped(GALLERY, _sec.BYTE_LIMIT_MANIFEST)
        obj = json.loads(raw.decode("utf-8"))
    except Exception as ex:
        print(json.dumps({"ok": False, "error": str(ex)}), flush=True)
        sys.exit(1)

    base = obj.get("base") or ""
    if not _sec.is_allowed_url(base):
        print(json.dumps({"ok": False, "error": "bad base"}), flush=True)
        sys.exit(1)

    jobs = []
    for e in obj.get("entries") or []:
        rel = e.get("thumb") or e.get("p") or ""
        if not rel or not _sec.safe_relpath(rel):
            continue
        url, dest = dest_for(base, rel)
        if cached_ok(dest):
            print(dest, flush=True)
            continue
        if os.path.lexists(dest):
            try:
                os.unlink(dest)
            except OSError:
                continue
        jobs.append((url, dest))

    if not jobs:
        return

    with ThreadPoolExecutor(max_workers=JOBS) as pool:
        futs = [pool.submit(fetch_one, url, dest) for url, dest in jobs]
        for fut in as_completed(futs):
            dest, existed = fut.result()
            if dest and cached_ok(dest):
                print(dest, flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as ex:
        print(json.dumps({"ok": False, "error": str(ex)}), flush=True)
        sys.exit(1)
