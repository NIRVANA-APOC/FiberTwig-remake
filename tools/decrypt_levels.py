#!/usr/bin/env python3
"""Decrypt Fiber Twig level files (Level4.txt .. Level17.txt).

Reverse engineered from FiberTwig.exe (Puzzle Lab, 2004).

Cipher
------
A home made 64 bit block cipher consisting of

    C = T(P xor K8) xor K8

where ``K8`` is an 8 byte key and ``T`` is the 8x8 bit transpose

    T(x)[k] bit b  =  x[b] bit k          (for k, b in 0..7)

The cipher is applied to every aligned 8 byte block; a trailing partial
block is only XORed with the key.  Levels 0..3 ship in plain text (trial
content), levels 4..17 are encrypted.

Key derivation
--------------
The key comes from the fixed serial number string
``"007173307790020009386587"`` found in the executable:

1. filter the string down to its decimal digits,
2. apply the permutation
   ``out[(2*i) mod (n+1) - 1] = in[i-1]``  (i = 1..n),
3. drop the first three characters,
4. strip leading zeroes and parse the remainder as a 64 bit integer,
5. keep the bytes of that integer (little endian), clear bit 7 of every
   byte and drop zero bytes -> ASCII key string "Zp1meWKa",
6. expand/truncate to 8 bytes -> 0x5A 0x70 0x31 0x6D 0x65 0x57 0x4B 0x61.

Usage:
    python3 decrypt_levels.py <squares.zxc|extracted_dir> <out_dir>
"""
import os
import struct
import sys

DEFAULT_SERIAL = "007173307790020009386587"


def derive_key(serial: str = DEFAULT_SERIAL) -> bytes:
    digits = "".join(c for c in serial if c.isdigit())
    n = len(digits)
    out = list(digits)
    for i in range(1, n + 1):
        out[(2 * i) % (n + 1) - 1] = digits[i - 1]
    s = "".join(out)[3:].lstrip("0")
    value = int(s)
    raw = value.to_bytes(8, "little")
    key = bytes(b for b in (x & 0x7F for x in raw) if b)
    return key


def key8(key: bytes) -> bytes:
    return bytes(key[i % len(key)] for i in range(8))


def transpose8(block: bytes) -> bytes:
    out = bytearray(8)
    for k in range(8):
        for b in range(8):
            if (block[b] >> k) & 1:
                out[k] |= 1 << b
    return bytes(out)


def decrypt(data: bytes, key: bytes) -> bytes:
    k8 = key8(key)
    full = len(data) // 8 * 8
    out = bytearray()
    for i in range(0, full, 8):
        block = bytes(x ^ y for x, y in zip(data[i:i + 8], k8))
        out += bytes(x ^ y for x, y in zip(transpose8(block), k8))
    tail = data[full:]
    out += bytes(x ^ y for x, y in zip(tail, k8))
    return bytes(out)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    key = derive_key()
    print("key: %s (0x%s)" % (key.decode(), key8(key).hex()))
    if src.endswith(".zxc"):
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from zxc import read_archive
        _count, _sum, entries = read_archive(src)
        files = {name: payload for name, payload in entries}
    else:
        files = {f: open(os.path.join(src, f), "rb").read() for f in os.listdir(src)}
    for name in sorted(files):
        if not (name.startswith("Level") and name.endswith(".txt")):
            continue
        raw = files[name]
        pt = raw if raw[:8] == b"<Level n" else decrypt(raw, key)
        if not pt.startswith(b"<Level n"):
            print("WARNING: %s did not decrypt to XML" % name)
        open(os.path.join(dst, name), "wb").write(pt)
        print("%-14s %7d bytes  %s" % (name, len(pt), pt.split(b"\n")[0][:60].decode("latin-1")))


if __name__ == "__main__":
    main()
