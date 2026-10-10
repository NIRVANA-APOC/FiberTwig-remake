#!/usr/bin/env python3
"""Build remake/assets/fonts/NotoSansSC-UI.ttf - the CJK font of the remake.

The original interface font is a 12 px bitmap atlas (Arial12lat.png indexed by
CP1252 bytes), which cannot hold Chinese glyphs.  The Simplified Chinese
localization therefore draws its text with a small TrueType font instead.

This script takes a Noto Sans SC variable font (SIL OFL 1.1, see
assets/fonts/OFL.txt), pins it to Regular (the Windows build defaults to
Thin), subsets it to the characters used by lng/chs_105.lng plus ASCII and
saves the result.  The subset keeps the original font name because the
Reserved Font Name of the source is "Source" - derived subsets of the
"Noto Sans SC" family may keep that name.

Usage:
    python tools/make_chs_font.py [--source C:/Windows/Fonts/NotoSansSC-VF.ttf]
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REMAKE = ROOT / "remake"
LNG = REMAKE / "assets" / "lng" / "chs_105.lng"
OUT = REMAKE / "assets" / "fonts" / "NotoSansSC-UI.ttf"
DEFAULT_SOURCES = [
    pathlib.Path(r"C:\Windows\Fonts\NotoSansSC-VF.ttf"),
    pathlib.Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"),
    pathlib.Path("/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc"),
]


def captions() -> list[str]:
    text = LNG.read_text(encoding="utf-8")
    return re.findall(r'<p n="Caption">(.*?)</p>', text, flags=re.S)


def character_set() -> str:
    chars = set()
    # ASCII keeps Latin words ("Fiber Twig", "Puzzle Lab", cheat codes) and
    # digits working in every caption that is drawn with this font.
    for cp in range(0x20, 0x7F):
        chars.add(chr(cp))
    for cap in captions():
        chars.update(cap)
    chars.update("\u00a0\u2018\u2019\u201c\u201d\u2013\u2014\u2026\u3001\u3002\uff01\uff08\uff09\uff0c\uff1a\uff1b\uff1f\u300a\u300b")
    return "".join(sorted(chars))


def find_source(explicit: str | None) -> pathlib.Path:
    if explicit:
        p = pathlib.Path(explicit)
        if not p.is_file():
            sys.exit(f"font not found: {p}")
        return p
    for p in DEFAULT_SOURCES:
        if p.is_file():
            return p
    sys.exit("no Noto Sans SC font found; pass --source <path to NotoSansSC-VF.ttf>")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", help="source Noto Sans SC font")
    ap.add_argument("--weight", type=int, default=400)
    args = ap.parse_args()

    from fontTools import subset
    from fontTools.ttLib import TTFont
    from fontTools.varLib import instancer

    src = find_source(args.source)
    chars = character_set()
    print(f"source : {src}")
    print(f"chars  : {len(chars)}")

    font = TTFont(src)
    if "fvar" in font:
        instancer.instantiateVariableFont(font, {"wght": args.weight}, inplace=True)
        print(f"pinned : wght={args.weight}")
    options = subset.Options()
    options.layout_features = []
    options.hinting = False
    options.desubroutinize = False
    options.recalc_bounds = True
    options.notdef_outline = True
    options.drop_tables += ["DSIG", "vhea", "vmtx", "VORG"]
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(text=chars)
    subsetter.subset(font)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    font.save(OUT)
    print(f"wrote  : {OUT.relative_to(ROOT)} ({OUT.stat().st_size / 1024:.0f} KiB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
