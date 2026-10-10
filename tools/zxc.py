#!/usr/bin/env python3
"""Fiber Twig .zxc archive tool (list / extract / pack).

The .zxc container used by Puzzle Lab's "Lab" engine is a simple table of
contents:

    offset 0   u32 magic   = 12345 (0x3039)
    offset 4   u16 count   number of entries
    offset 6   u16 checksum
    offset 8   count * 48 byte entries
    ...        concatenated entry payloads

Each 48 byte entry:

    +0x00  u8   name length (1..31)
    +0x01  char name[31]
    +0x20  u32  zero
    +0x24  u32  payload offset (relative to the end of the table)
    +0x28  u32  payload size
    +0x2C  u32  zero

Usage:
    python3 zxc.py list    Game/game.zxc
    python3 zxc.py extract Game/game.zxc out_dir
    python3 zxc.py pack    in_dir out.zxc
"""
import os
import struct
import sys

MAGIC = 12345
HEADER = 8
ENTRY = 48


def read_archive(path):
    data = open(path, "rb").read()
    magic, count, checksum = struct.unpack_from("<IHH", data, 0)
    if magic != MAGIC:
        raise ValueError("not a .zxc archive (magic=%d)" % magic)
    base = HEADER + ENTRY * count
    entries = []
    for i in range(count):
        off = HEADER + ENTRY * i
        n = data[off]
        name = data[off + 1:off + 1 + n].decode("latin-1")
        _zero, payload_off, size, _zero2 = struct.unpack_from("<IIII", data, off + 0x20)
        entries.append((name, data[base + payload_off:base + payload_off + size]))
    return count, checksum, entries


def cmd_list(path):
    count, checksum, entries = read_archive(path)
    print("%s: %d files, checksum=0x%04x" % (path, count, checksum))
    for name, payload in entries:
        print("  %-36s %8d" % (name, len(payload)))


def cmd_extract(path, outdir):
    count, checksum, entries = read_archive(path)
    for name, payload in entries:
        target = os.path.join(outdir, name)
        os.makedirs(os.path.dirname(target) or outdir, exist_ok=True)
        with open(target, "wb") as fh:
            fh.write(payload)
    print("extracted %d files to %s" % (count, outdir))


def cmd_pack(indir, outpath):
    names = []
    for root, _dirs, files in os.walk(indir):
        for f in files:
            full = os.path.join(root, f)
            names.append(os.path.relpath(full, indir).replace(os.sep, "/"))
    names.sort(key=str.lower)
    table = bytearray()
    payloads = bytearray()
    for name in names:
        raw = open(os.path.join(indir, name), "rb").read()
        nb = name.encode("latin-1")
        entry = bytearray(ENTRY)
        entry[0] = len(nb)
        entry[1:1 + len(nb)] = nb
        struct.pack_into("<IIII", entry, 0x20, 0, len(payloads), len(raw), 0)
        table += entry
        payloads += raw
    with open(outpath, "wb") as fh:
        fh.write(struct.pack("<IHH", MAGIC, len(names), 0))
        fh.write(table)
        fh.write(payloads)
    print("packed %d files -> %s" % (len(names), outpath))


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    cmd = sys.argv[1]
    if cmd == "list":
        cmd_list(sys.argv[2])
    elif cmd == "extract":
        cmd_extract(sys.argv[2], sys.argv[3])
    elif cmd == "pack":
        cmd_pack(sys.argv[2], sys.argv[3])
    else:
        print(__doc__)
        sys.exit(1)
