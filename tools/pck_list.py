#!/usr/bin/env python3
"""List (and optionally extract files from) a Godot 4 .pck or an executable
with an embedded .pck.

    python tools/pck_list.py game.exe                 # list paths and sizes
    python tools/pck_list.py game.exe --grep assets   # filter
    python tools/pck_list.py game.exe --extract out/ # extract everything

Godot 4 pack layout (core/io/file_access_pack.cpp, editor_export_platform.cpp):
  header : magic 'GDPC', version (2..4), ver major/minor/patch, flags,
           file_base u64, dir_offset u64 (V3/V4)
  dir    : u32 file_count, then per entry
  entry  : u32 name_len (padded to 4), name, u64 ofs, u64 size, md5[16], u32 flags
  data   : at file_base + ofs  (file_base is relative to the header unless
           the PACK_REL_FILEBASE flag is clear)
An embedded pack ends with a 12-byte trailer: magic + absolute pack offset.
"""

from __future__ import annotations

import argparse
import os
import struct

MAGIC = b"GDPC"


def pe_pck_section(data: bytes) -> int | None:
    """File offset of the PE section named 'pck' (embedded pack, Godot 4.3+)."""
    if data[:2] != b"MZ":
        return None
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe : pe + 4] != b"PE\0\0":
        return None
    nsec = struct.unpack_from("<H", data, pe + 6)[0]
    opt = struct.unpack_from("<H", data, pe + 20)[0]
    off = pe + 24 + opt
    for i in range(nsec):
        s = off + i * 40
        name = data[s : s + 8].rstrip(b"\0")
        if name == b"pck":
            return struct.unpack_from("<I", data, s + 20)[0]
    return None


def find_pack(data: bytes) -> tuple[int, bool]:
    if data[:4] == MAGIC:
        return 0, False
    section = pe_pck_section(data)
    if section is not None:
        for i in range(8):  # header may be aligned inside the section
            if data[section + i : section + i + 4] == MAGIC:
                return section + i, True
    if len(data) >= 12 and data[-12:-8] == MAGIC:
        (start,) = struct.unpack_from("<Q", data, len(data) - 8)
        return start, True
    pos = data.find(MAGIC)  # last resort: pck section inside the exe
    if pos < 0:
        raise SystemExit("no Godot pack found")
    return pos, True


def parse(data: bytes, start: int):
    if data[start : start + 4] != MAGIC:
        raise SystemExit("bad pack magic")
    version, vmaj, vmin, vpat, flags = struct.unpack_from("<5I", data, start + 4)
    if not 2 <= version <= 4:
        raise SystemExit(f"unsupported pack version {version}")
    (file_base, dir_base) = struct.unpack_from("<QQ", data, start + 24)
    if version >= 3 or flags & 1:  # PACK_REL_FILEBASE
        file_base += start
    if version >= 3:
        pos = start + dir_base
    else:
        pos = start + 52  # v2: directory follows the 52-byte header + 64 reserved
    (count,) = struct.unpack_from("<I", data, pos)
    pos += 4
    entries = []
    for _ in range(count):
        (nlen,) = struct.unpack_from("<I", data, pos)
        name = data[pos + 4 : pos + 4 + nlen].decode("utf-8", "replace").rstrip("\x00")
        p = pos + 4 + nlen
        ofs, size = struct.unpack_from("<QQ", data, p)
        md5 = data[p + 16 : p + 32]
        (eflags,) = struct.unpack_from("<I", data, p + 32)
        entries.append((name, file_base + ofs, size, eflags, md5))
        pos = p + 36
    return version, flags, entries


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("pack")
    ap.add_argument("--grep", default=None)
    ap.add_argument("--extract", default=None, metavar="DIR")
    ap.add_argument("--long", action="store_true", help="show sizes in bytes")
    args = ap.parse_args()

    data = open(args.pack, "rb").read()
    start, embedded = find_pack(data)
    version, flags, entries = parse(data, start)
    print(
        f"{args.pack}: embedded={embedded} pack@{start} v{version} "
        f"flags={flags} entries={len(entries)}"
    )
    total = 0
    for name, pos, size, eflags, md5 in entries:
        if args.grep and args.grep not in name:
            continue
        total += size
        shown = str(size) if args.long else f"{size / 1024:.1f} KiB"
        print(f"{shown:>12}  {name}{'  [encrypted]' if eflags & 1 else ''}")
        if args.extract:
            out_path = os.path.join(args.extract, name.replace("res://", "").lstrip("/"))
            os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
            with open(out_path, "wb") as fh:
                fh.write(data[pos : pos + size])
    print(f"total {total / 1048576:.1f} MiB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
