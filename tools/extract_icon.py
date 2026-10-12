#!/usr/bin/env python3
"""Extract the icon group embedded in a Windows PE file (e.g. FiberTwig.exe).

Reads the RT_GROUP_ICON / RT_ICON resources and writes a standard multi-size
.ico, which Godot uses as the Windows application icon.

    python tools/extract_icon.py FiberTwig/FiberTwig.exe build/fibertwig.ico
"""

from __future__ import annotations

import struct
import sys


def u16(b, o):
    return struct.unpack_from("<H", b, o)[0]


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def rva_to_offset(sections, rva):
    for va, vsize, raw, rawsize in sections:
        if va <= rva < va + max(vsize, rawsize):
            return raw + (rva - va)
    raise ValueError(f"rva {rva:#x} not in any section")


def iter_resource_dir(data, sections, base, offset):
    """Yield (id_or_none, is_dir, entry_offset_name, sub_offset)."""
    root = rva_to_offset(sections, base) + offset
    named, ids = u16(data, root + 12), u16(data, root + 14)
    for i in range(named + ids):
        e = root + 16 + i * 8
        name = u32(data, e)
        sub = u32(data, e + 4)
        yield name, bool(sub & 0x80000000), sub & 0x7FFFFFFF


def main() -> int:
    src, dst = sys.argv[1], sys.argv[2]
    data = open(src, "rb").read()
    pe = u32(data, 0x3C)
    if data[pe : pe + 4] != b"PE\0\0":
        raise SystemExit("not a PE file")
    nsections = u16(data, pe + 6)
    opt_size = u16(data, pe + 20)
    magic = u16(data, pe + 24)
    dd_offset = pe + 24 + (112 if magic == 0x20B else 96)
    rsrc_rva, rsrc_size = u32(data, dd_offset + 2 * 8), u32(data, dd_offset + 2 * 8 + 4)
    sec_off = pe + 24 + opt_size
    sections = []
    for i in range(nsections):
        s = sec_off + i * 40
        vsize, va, rawsize, raw = u32(data, s + 8), u32(data, s + 12), u32(data, s + 16), u32(data, s + 20)
        sections.append((va, vsize, raw, rawsize))

    groups, icons = {}, {}
    for type_id, is_dir, sub in iter_resource_dir(data, sections, rsrc_rva, 0):
        if not is_dir:
            continue
        for name_id, is_dir2, sub2 in iter_resource_dir(data, sections, rsrc_rva, sub):
            if not is_dir2:
                continue
            for lang_id, is_dir3, sub3 in iter_resource_dir(data, sections, rsrc_rva, sub2):
                if is_dir3:
                    continue
                entry = rva_to_offset(sections, rsrc_rva) + sub3
                rva, size = u32(data, entry), u32(data, entry + 4)
                blob = data[rva_to_offset(sections, rva) : rva_to_offset(sections, rva) + size]
                if type_id == 14:
                    groups[name_id] = blob
                elif type_id == 3:
                    icons[name_id] = blob
    if not groups:
        raise SystemExit("no RT_GROUP_ICON resource found")

    # Use the first icon group; rebuild a GRPICONDIR + image data .ico file.
    grp = next(iter(groups.values()))
    count = u16(grp, 4)
    out = bytearray(struct.pack("<HHH", 0, 1, count))
    images = []
    for i in range(count):
        e = 6 + i * 14
        w, h, colors, _res, planes, bits, size, iid = struct.unpack_from("<BBBBHHIH", grp, e)
        images.append((w, h, colors, planes, bits, size, icons[iid]))
    offset = 6 + 16 * count
    for w, h, colors, planes, bits, size, blob in images:
        out += struct.pack("<BBBBHHII", w, h, colors, 0, planes, bits, len(blob), offset)
        offset += len(blob)
    for *_, blob in images:
        out += blob
    with open(dst, "wb") as fh:
        fh.write(out)
    print(f"{dst}: {count} image(s), sizes: " + ", ".join(f"{w or 256}x{h or 256}@{bits}bpp" for w, h, _, _, bits, _, _ in images))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
