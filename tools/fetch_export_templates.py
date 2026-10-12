#!/usr/bin/env python3
"""Fetch individual files out of a Godot export-templates .tpz (zip) archive.

The official archive is ~1.3 GB but a Windows-only export needs two files
(~150 MB).  Zip keeps its central directory at the end of the file, so this
tool reads the directory with HTTP range requests and downloads only the
requested entries.

Examples
--------
    # list every entry in the archive
    python tools/fetch_export_templates.py --list

    # install the Windows release template into the editor's template dir
    python tools/fetch_export_templates.py --version 4.7.2-stable \\
        --dest "$APPDATA/Godot/export_templates/4.7.2.stable" \\
        windows_x86_64_release.exe version.txt
"""

from __future__ import annotations

import argparse
import os
import struct
import sys
import urllib.request
import zlib

RELEASE_URL = (
    "https://github.com/godotengine/godot/releases/download/"
    "{version}/Godot_v{version}_export_templates.tpz"
)

CHUNK = 8 << 20  # 8 MiB
EOCD_SIG = b"PK\x05\x06"
CD_SIG = b"PK\x01\x02"
LFH_SIG = b"PK\x03\x04"


class HttpFile:
    """Random-access reads over an HTTP(S) URL using range requests."""

    def __init__(self, url: str) -> None:
        self.url = url
        self.size = 0
        self.range_ok = True

    def fetch(self, start: int, end: int) -> bytes:
        """Return bytes [start, end] (inclusive)."""
        assert end >= start
        req = urllib.request.Request(
            self.url,
            headers={
                "Range": f"bytes={start}-{end}",
                "User-Agent": "godot-template-fetch/1.0",
                "Accept": "*/*",
            },
        )
        with urllib.request.urlopen(req, timeout=120) as resp:
            if resp.status == 206:
                content_range = resp.headers.get("Content-Range", "")
                total = int(content_range.rsplit("/", 1)[-1])
                if self.size == 0:
                    self.size = total
                return resp.read()
            # Server ignored Range: fall back to reading everything once.
            self.range_ok = False
            data = resp.read()
            self.size = len(data)
            return data[start : end + 1]

    def stream(self, start: int, length: int, sink) -> None:
        """Stream `length` bytes from `start` into `sink`, in CHUNK pieces."""
        pos = start
        remaining = length
        while remaining > 0:
            n = min(CHUNK, remaining)
            sink(self.fetch(pos, pos + n - 1))
            pos += n
            remaining -= n
            if length >= CHUNK:
                done = (length - remaining) / length * 100
                print(f"\r    {done:5.1f}%", end="", flush=True)
        if length >= CHUNK:
            print("\r    100.0%")


class Entry:
    __slots__ = ("name", "method", "csize", "usize", "offset")

    def __init__(self, name, method, csize, usize, offset):
        self.name = name
        self.method = method
        self.csize = csize
        self.usize = usize
        self.offset = offset


def parse_cd(data: bytes) -> list[Entry]:
    entries = []
    pos = 0
    while True:
        pos = data.find(CD_SIG, pos)
        if pos < 0:
            break
        (
            _sig,
            _vmade,
            _vneed,
            _flags,
            method,
            _mt,
            _md,
            _crc,
            csize,
            usize,
            nlen,
            elen,
            clen,
            _disk,
            _iattr,
            _eattr,
            offset,
        ) = struct.unpack_from("<4sHHHHHHIIIHHHHHII", data, pos)
        name = data[pos + 46 : pos + 46 + nlen].decode("utf-8", "replace")
        entries.append(Entry(name, method, csize, usize, offset))
        pos += 46 + nlen + elen + clen
    return entries


def read_zip_directory(http: HttpFile) -> list[Entry]:
    tail = http.fetch(max(0, http.size - (256 << 10)), http.size - 1)
    idx = tail.rfind(EOCD_SIG)
    if idx < 0:
        raise SystemExit("not a zip: end-of-central-directory record not found")
    cd_size, cd_offset = struct.unpack_from("<II", tail, idx + 12)
    if cd_offset == 0xFFFFFFFF or cd_size == 0xFFFFFFFF:
        raise SystemExit("zip64 archives are not supported by this helper")
    cd = http.fetch(cd_offset, cd_offset + cd_size - 1)
    return parse_cd(cd)


def extract(http: HttpFile, entry: Entry, dest_path: str) -> None:
    header = http.fetch(entry.offset, entry.offset + 29)
    if header[:4] != LFH_SIG:
        raise SystemExit(f"{entry.name}: bad local header")
    nlen, elen = struct.unpack_from("<HH", header, 26)
    data_start = entry.offset + 30 + nlen + elen
    print(f"  {entry.name}  ({entry.usize / 1048576:.1f} MiB)")
    raw = bytearray()
    http.stream(data_start, entry.csize, raw.extend)
    data = bytes(raw)
    if entry.method == 0:
        out = data
    elif entry.method == 8:
        out = zlib.decompress(data, -15)
    else:
        raise SystemExit(f"{entry.name}: unsupported compression method {entry.method}")
    if len(out) != entry.usize:
        raise SystemExit(
            f"{entry.name}: size mismatch ({len(out)} != {entry.usize})"
        )
    os.makedirs(os.path.dirname(os.path.abspath(dest_path)), exist_ok=True)
    tmp = dest_path + ".part"
    with open(tmp, "wb") as fh:
        fh.write(out)
    os.replace(tmp, dest_path)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("entries", nargs="*", help="entry names (e.g. version.txt)")
    ap.add_argument("--version", default="4.7.2-stable", help="engine version tag")
    ap.add_argument("--url", default=None, help="override archive URL")
    ap.add_argument("--dest", default=".", help="destination directory")
    ap.add_argument("--list", action="store_true", help="list entries and exit")
    ap.add_argument("--prefix", default="templates/", help="strip this prefix")
    args = ap.parse_args()

    url = args.url or RELEASE_URL.format(version=args.version)
    http = HttpFile(url)
    # A one-byte read resolves the redirect and reports the total size.
    http.fetch(0, 0)
    print(f"archive: {url}")
    print(f"size: {http.size / 1048576:.1f} MiB (range requests only)")
    entries = read_zip_directory(http)

    if args.list:
        for e in entries:
            print(f"{e.usize:>12}  {e.name}")
        return 0

    by_name = {e.name: e for e in entries}
    rc = 0
    for name in args.entries:
        entry = by_name.get(name) or by_name.get(args.prefix + name)
        if entry is None:
            print(f"error: no entry named {name!r}", file=sys.stderr)
            rc = 1
            continue
        out_name = entry.name[len(args.prefix) :] if entry.name.startswith(args.prefix) else entry.name
        extract(http, entry, os.path.join(args.dest, out_name))
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
