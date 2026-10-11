#!/usr/bin/env python3
"""Build the CJK UI font of the remake: remake/assets/fonts/<face>-UI.ttf.

Why this font
-------------
The interface of the original game is a 12 px bitmap atlas (``Arial12lat.png``
indexed by CP1252 bytes) and cannot hold Chinese glyphs, so the Simplified
Chinese localization draws its captions with a TrueType font at 14 px
(``CJK_FONT_SIZE`` in ``remake/src/OriginalUI.gd``).  The art of Fiber Twig is a
hand painted enchanted garden: gnarled golden twig lettering, mossy green
painted panels, a 2004 storybook fantasy.  A neutral geometric sans reads as a
modern web interface on those panels, so the shipped face is **LXGW WenKai
Screen** - a Kai (楷体) whose brush entry and exit strokes come from FONTWORKS
Klee One, in the stroke weight that was tuned for screen reading, which is what
survives 14 px.  ``--list`` shows every face this script knows; the comparison
that chose this one (seven candidates, rendered on real screens) was made in a
working directory and only its outcome is kept here.

What the script does
--------------------
1. collects the character set from ``remake/assets/lng/chs_105.lng`` (every
   ``<p n="Caption">``) plus ASCII and the punctuation the interface uses,
2. loads the documented source font (one of the redistributable open-licence
   faces in ``FACES``, downloaded on demand with ``--download``),
3. pins a variable weight if the source has a ``wght`` axis,
4. subsets to that character set,
5. pins the vertical metrics to the 14 px / 3 px line box the 18 px line grid of
   ``OriginalUI.gd`` was laid out with (``--keep-metrics`` keeps the source box),
6. checks that the result really contains every requested character,
7. writes ``remake/assets/fonts/<face>-UI.ttf`` and the matching OFL file
   (``remake/assets/fonts/OFL.txt``, upstream text verbatim plus a provenance
   header), and prints the resulting size.

The localization file is rewritten by the translators from time to time, so the
subset is always driven by the file on disk - just run the script again.

Usage
-----
    python tools/make_chs_font.py --list
    python tools/make_chs_font.py                     # the shipped face
    python tools/make_chs_font.py --face noto-sans-sc  # reproduce the old file
    python tools/make_chs_font.py --out work/tmp/x.ttf --face wenkai --weight 500
    python tools/make_chs_font.py --extra-text i18n/glossary.md \\
        --extra-text i18n/zh_ui.json              # cover the pending text too

Only SIL OFL (or equivalent) fonts may be added to ``FACES``; the Windows
system faces (simkai/simhei/simsun/DengXian) are proprietary and must never be
shipped.
"""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import pathlib
import re
import sys
import urllib.request
import zipfile
from dataclasses import dataclass, field

ROOT = pathlib.Path(__file__).resolve().parent.parent
REMAKE = ROOT / "remake"
FONT_DIR = REMAKE / "assets" / "fonts"
LNG = REMAKE / "assets" / "lng" / "chs_105.lng"
CACHE = ROOT / "work" / "i18n" / "font" / "src"

# Characters the interface draws with the CJK font that do not have to appear
# in the .lng: the language radio button of the Chinese localization is always
# its native name (OriginalUI.LANG_NAMES), and the Latin product names keep
# their dashes/quotes.
EXTRA_CHARS = "简体中文"

# The 18 px line grid of the bitmap font is laid out around a 14 px line box
# with a 14 px ascent (see OriginalUI.gd: draw_text() centres get_height() on
# the grid and then adds get_ascent()).  A face with a different line box would
# move every Chinese caption up or down by a pixel, so the subset pins the
# vertical metrics to exactly that box - the glyph outlines are untouched.
REF_SIZE_PX = 14.0  # CJK_FONT_SIZE
REF_ASCENT_PX = 14.0
REF_DESCENT_PX = 3.0


@dataclass(frozen=True)
class Face:
    """One redistributable source font."""

    key: str
    label: str
    out: str  # shipped file name inside remake/assets/fonts
    family: str  # family name written into the subset's name table
    url: str  # documented download of the source font
    licence_url: str  # upstream OFL / licence text
    weight: int = 400
    archive: str = ""  # member pattern for zip sources
    local: tuple = field(default_factory=tuple)  # extra local source paths
    note: str = ""


# Every face below is SIL OFL 1.1 or equivalent.  The subsets are renamed to
# "Fiber Twig ..." because all of these licences declare Reserved Font Names
# ('LXGW'/'霞鹜', 'YOz', 'ChillMovableType', 'Source') that a modified font must
# not carry: a game font embedded in a download is an installable desktop font,
# which the LXGW additional permission explicitly excludes from name reuse.
FACES: dict[str, Face] = {
    "wenkai-screen": Face(
        key="wenkai-screen",
        label="LXGW WenKai Screen / 霞鹜文楷屏幕阅读版",
        out="LXGWWenKaiScreen-UI.ttf",
        family="Fiber Twig Kai UI",
        url="https://github.com/lxgw/LxgwWenKai-Screen/releases/download/v1.522/LXGWWenKaiScreen.ttf",
        licence_url="https://raw.githubusercontent.com/lxgw/LxgwWenKai-Screen/main/OFL.txt",
        weight=400,
        note="Kai (楷体) with brush shaped strokes and a stroke weight raised "
        "for screen reading; based on FONTWORKS Klee One.",
    ),
    "wenkai": Face(
        key="wenkai",
        label="LXGW WenKai / 霞鹜文楷",
        out="LXGWWenKai-UI.ttf",
        family="Fiber Twig Kai Text UI",
        url="https://github.com/lxgw/LxgwWenKai/releases/download/v1.522/LXGWWenKai-Regular.ttf",
        licence_url="https://raw.githubusercontent.com/lxgw/LxgwWenKai/main/OFL.txt",
        weight=400,
    ),
    "yozai": Face(
        key="yozai",
        label="Yozai / 悠哉字体",
        out="Yozai-UI.ttf",
        family="Fiber Twig Brush UI",
        url="https://github.com/lxgw/yozai-font/releases/download/v0.868/Yozai-Regular.ttf",
        licence_url="https://raw.githubusercontent.com/lxgw/yozai-font/master/OFL.txt",
        weight=400,
    ),
    "zhuque": Face(
        key="zhuque",
        label="Zhuque Fangsong / 朱雀仿宋",
        out="ZhuqueFangsong-UI.ttf",
        family="Fiber Twig Fangsong UI",
        url="https://github.com/trionestype/zhuque/releases/download/v0.212/ZhuqueFangsong-v0.212.zip",
        licence_url="https://raw.githubusercontent.com/trionestype/zhuque/main/LICENSE.txt",
        weight=400,
        archive="zhuquefangsong-regular.ttf",
    ),
    "chill-huokai": Face(
        key="chill-huokai",
        label="Chill HuoKai / 寒蝉活楷体",
        out="ChillHuoKai-UI.ttf",
        family="Fiber Twig HuoKai UI",
        url="https://github.com/Warren2060/ChillMovableType/releases/download/HuoKaiv1.000/ChillHuoKai.zip",
        licence_url="https://raw.githubusercontent.com/Warren2060/ChillMovableType/main/LICENSE",
        weight=400,
        archive="chillhuokai_regular.otf",
    ),
    "noto-serif-sc": Face(
        key="noto-serif-sc",
        label="Noto Serif SC / 思源宋体",
        out="NotoSerifSC-UI.ttf",
        family="Fiber Twig Song UI",
        url="https://github.com/notofonts/noto-cjk/raw/main/Serif/Variable/OTF/Subset/NotoSerifSC-VF.otf",
        licence_url="https://raw.githubusercontent.com/notofonts/noto-cjk/main/Serif/LICENSE",
        weight=500,
        local=(pathlib.Path(r"C:\Windows\Fonts\NotoSerifSC-VF.ttf"),),
    ),
    "noto-sans-sc": Face(
        key="noto-sans-sc",
        label="Noto Sans SC (the face this task replaces)",
        out="NotoSansSC-UI.ttf",
        family="Fiber Twig Sans UI",
        url="https://github.com/notofonts/noto-cjk/raw/main/Sans/Variable/OTF/Subset/NotoSansSC-VF.otf",
        licence_url="https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/LICENSE",
        weight=400,
        local=(pathlib.Path(r"C:\Windows\Fonts\NotoSansSC-VF.ttf"),),
    ),
}

DEFAULT_FACE = "wenkai-screen"

# Punctuation that is not guaranteed to appear in the .lng but is used by the
# interface (the curated list of the original script).
EXTRA_PUNCT = "\u00a0\u00b7\u2018\u2019\u201c\u201d\u2013\u2014\u2026\u3001\u3002\u300a\u300b\uff01\uff08\uff09\uff0c\uff1a\uff1b\uff1f"


def captions(text: str) -> list[str]:
    return re.findall(r'<p n="Caption">(.*?)</p>', text, flags=re.S)


def character_set(paths: list[pathlib.Path]) -> str:
    """ASCII + every caption of the localization + any extra text source.

    A file without ``<p n="Caption">`` records (a glossary, a JSON dump of the
    translations, a plain text list) contributes its whole content, so the same
    pipeline can be pointed at whatever the translators are working on.
    """
    chars = set(chr(cp) for cp in range(0x20, 0x7F))
    for path in paths:
        text = path.read_text(encoding="utf-8")
        caps = captions(text)
        for cap in (caps or [text]):
            chars.update(cap)
    chars.update(EXTRA_PUNCT)
    chars.update(EXTRA_CHARS)
    chars.discard("\n")
    chars.discard("\r")
    chars.discard("\t")
    return "".join(sorted(chars))


def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def download(url: str, dest: pathlib.Path) -> pathlib.Path:
    dest.parent.mkdir(parents=True, exist_ok=True)
    print(f"download: {url}")
    with urllib.request.urlopen(url, timeout=300) as resp, dest.open("wb") as fh:
        while True:
            block = resp.read(1 << 20)
            if not block:
                break
            fh.write(block)
    return dest


def ensure_source(face: Face, explicit: str | None, allow_download: bool) -> pathlib.Path:
    """Return a local source font, downloading the documented file if needed."""
    for cand in ([pathlib.Path(explicit)] if explicit else []) + [
        CACHE / pathlib.Path(face.url).name,
        *face.local,
    ]:
        if cand and cand.is_file():
            return cand
    if not allow_download:
        sys.exit(
            f"source font for '{face.key}' not found.\n"
            f"  download it from: {face.url}\n"
            f"  or pass --source <file>, or run with --download"
        )
    raw = download(face.url, CACHE / pathlib.Path(face.url).name)
    return unpack(raw, face)


def unpack(archive: pathlib.Path, face: Face) -> pathlib.Path:
    """Extract the wanted font out of a zip source."""
    if archive.suffix.lower() != ".zip":
        return archive
    out_dir = archive.with_suffix("")
    out_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as zf:
        names = [n for n in zf.namelist()
                 if n.lower().endswith((".ttf", ".otf")) and "__MACOSX" not in n]
        if not names:
            sys.exit(f"no font inside {archive}")
        chosen = names[0]
        if face.archive:
            hits = [n for n in names if fnmatch.fnmatch(pathlib.Path(n).name.lower(), face.archive.lower())]
            if not hits:
                sys.exit(f"no {face.archive} inside {archive}: {names}")
            chosen = hits[0]
        zf.extract(chosen, out_dir)
    return out_dir / chosen


def pin_metrics(font, upem: int) -> tuple[int, int]:
    """Pin the vertical metrics to the 14 px / 3 px line box of the 18 px grid."""
    asc = round(upem * REF_ASCENT_PX / REF_SIZE_PX)
    desc = round(upem * REF_DESCENT_PX / REF_SIZE_PX)
    hhea = font["hhea"]
    hhea.ascent, hhea.descent, hhea.lineGap = asc, -desc, 0
    if "OS/2" in font:
        os2 = font["OS/2"]
        os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap = asc, -desc, 0
        os2.usWinAscent, os2.usWinDescent = asc, desc
    return asc, desc


def rename(font, family: str) -> None:
    """Give the subset its own family name (OFL: a modified font must not use
    a Reserved Font Name, and a subset should be recognisable as such)."""
    name = font["name"]
    for rec in name.names:
        if rec.nameID in (1, 3, 4, 16):
            rec.string = family
        elif rec.nameID == 6:
            rec.string = family.replace(" ", "")
        elif rec.nameID == 17:
            rec.string = "Regular"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--face", default=DEFAULT_FACE, choices=sorted(FACES),
                    help=f"source face (default {DEFAULT_FACE})")
    ap.add_argument("--source", help="explicit source font file")
    ap.add_argument("--weight", type=int, help="pin a variable font to this weight")
    ap.add_argument("--out", help="output .ttf (default remake/assets/fonts/<face>-UI.ttf)")
    ap.add_argument("--text-file", default=str(LNG), help="localization file to subset for")
    ap.add_argument("--extra-text", action="append", default=[],
                    help="additional text source whose characters must be covered "
                         "(a glossary, a JSON dump of the pending translation, ...); repeatable")
    ap.add_argument("--licence-out", help="write the shipped OFL here")
    ap.add_argument("--download", action="store_true", help="fetch the source if it is missing")
    ap.add_argument("--keep-name", action="store_true", help="keep the source family name")
    ap.add_argument("--keep-metrics", action="store_true",
                    help="keep the source line box instead of pinning the 14/3 px one")
    ap.add_argument("--list", action="store_true", help="list the known faces and exit")
    args = ap.parse_args()

    if args.list:
        for face in FACES.values():
            print(f"{face.key:16} {face.label}\n{'':16} {face.url}")
        print(f"\ndefault face: {DEFAULT_FACE}")
        return 0

    from fontTools import subset
    from fontTools.ttLib import TTFont
    from fontTools.varLib import instancer

    face = FACES[args.face]
    src = unpack(ensure_source(face, args.source, args.download), face)
    out = pathlib.Path(args.out) if args.out else FONT_DIR / face.out
    texts = [pathlib.Path(args.text_file)] + [pathlib.Path(p) for p in args.extra_text]
    for t in texts:
        if not t.is_file():
            sys.exit(f"text source not found: {t}")
    chars = character_set(texts)
    weight = args.weight if args.weight is not None else face.weight

    print(f"face   : {face.key} ({face.label})")
    print(f"source : {src}  sha256={sha256(src)[:16]}  {src.stat().st_size / 1048576:.1f} MiB")
    print(f"text   : {', '.join(t.name for t in texts)}  chars={len(chars)}")

    # recalcTimestamp=False keeps head.modified from the source font, so two
    # runs of this script produce a byte identical subset (the SHA-256 in the
    # licence header stays meaningful).
    font = TTFont(src, recalcTimestamp=False)
    upem = font["head"].unitsPerEm
    if "fvar" in font:
        axes = {a.axisTag: weight for a in font["fvar"].axes if a.axisTag == "wght"}
        if axes:
            instancer.instantiateVariableFont(font, axes, inplace=True)
            print(f"pinned : wght={weight}")
    if not args.keep_name:
        rename(font, face.family)
        print(f"family : {face.family}")
    if not args.keep_metrics:
        asc, desc = pin_metrics(font, upem)
        print(f"linebox: pinned to ascent {REF_ASCENT_PX:.0f} px / descent {REF_DESCENT_PX:.0f} px "
              f"({asc}/-{desc} at upem {upem})")

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

    # The .lng is rewritten from time to time; never ship a subset that cannot
    # draw a caption - a missing glyph silently falls back to a system face,
    # i.e. to the look this font was chosen to replace.
    have = set(font.getBestCmap())
    missing = [c for c in chars if ord(c) not in have]
    if missing:
        print(f"WARNING: the face has no glyph for {len(missing)} of the {len(chars)} requested "
              f"characters - they would fall back to a system face:")
        print(f"         {''.join(missing)}")

    out.parent.mkdir(parents=True, exist_ok=True)
    font.save(out)
    hhea = font["hhea"]
    cmap = font.getBestCmap()
    ideograph = next((c for c in chars if ord(c) > 0x2E80 and ord(c) in cmap), "一")
    adv = font["hmtx"][cmap[ord(ideograph)]][0] if ord(ideograph) in cmap else 0
    latin = font["hmtx"][cmap[ord("x")]][0] if ord("x") in cmap else 0
    scale = 14.0 / upem  # CJK_FONT_SIZE in OriginalUI.gd
    print(f"metrics: upem={upem} hhea={hhea.ascent}/{hhea.descent}/{hhea.lineGap} "
          f"ideograph<{ideograph}>={adv} latin-x={latin}")
    print(f"        at 14 px -> height={(hhea.ascent - hhea.descent + hhea.lineGap) * scale:.2f} "
          f"ascent={hhea.ascent * scale:.2f} ideograph-advance={adv * scale:.2f} x={latin * scale:.2f}")
    print(f"wrote  : {out.relative_to(ROOT) if str(out).startswith(str(ROOT)) else out} "
          f"({out.stat().st_size / 1024:.0f} KiB)")

    # The shipped licence lives next to the font as assets/fonts/OFL.txt (that
    # is the path the README points at); --licence-out overrides it.
    lic_out = pathlib.Path(args.licence_out) if args.licence_out else FONT_DIR / "OFL.txt"
    # A candidate build (explicit --out, e.g. into work/) does not touch the
    # shipped licence; the shipped build (no --out) always refreshes it.
    if not args.out or args.licence_out:
        write_licence(face, src, out, lic_out, chars)
    return 0


def write_licence(face: Face, src: pathlib.Path, out: pathlib.Path, lic_out: pathlib.Path,
                  chars: str) -> None:
    """Ship the upstream OFL next to the subset, with a provenance header."""
    text = ""
    cached = CACHE / (pathlib.Path(face.licence_url).name + "." + face.key)
    if cached.is_file():
        text = cached.read_text(encoding="utf-8", errors="replace")
    else:
        try:
            with urllib.request.urlopen(face.licence_url, timeout=120) as resp:
                text = resp.read().decode("utf-8", errors="replace")
            cached.write_text(text, encoding="utf-8")
        except Exception as exc:  # offline builds keep the old licence file
            if lic_out.is_file():
                print(f"licence: keeping existing {lic_out.name} ({exc})")
                return
            sys.exit(f"cannot fetch {face.licence_url}: {exc}\n"
                     f"save it as {cached} and run again")
    header = (
        f"{out.name} is a subset of {face.label}\n"
        f"    source : {face.url}\n"
        f"    sha256 : {sha256(src)}\n"
        f"    built by tools/make_chs_font.py ({len(chars)} glyphs, "
        f"wght {face.weight})\n\n"
        "The upstream licence follows verbatim.\n\n"
    )
    lic_out.parent.mkdir(parents=True, exist_ok=True)
    lic_out.write_text(header + text, encoding="utf-8")
    print(f"licence: {lic_out.relative_to(ROOT) if str(lic_out).startswith(str(ROOT)) else lic_out}")


if __name__ == "__main__":
    sys.exit(main())
