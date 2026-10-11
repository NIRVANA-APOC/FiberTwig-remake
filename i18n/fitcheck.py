#!/usr/bin/env python3
"""Check every Chinese caption of a .lng against the geometry of FiberTwig.li.

The remake draws captions inside the original widget boxes (see
remake/src/OriginalUI.gd: wrapped() over Width - TShiftX, 18 px per line).
A translation is therefore only usable if it fits the box the original authored
for it.  This harness reproduces that rule from the extracted interface data and
reports, per widget:

    chars/line budget   how many CJK glyphs fit next to the radio/checkbox glyph
    lines               how many 18 px lines the box can show
    required            lines the text really needs (per-character wrap)
    flag                OK / TIGHT / OVERFLOW

Usage:
    python i18n/fitcheck.py [--lng remake/assets/lng/chs_105.lng]
                                 [--json i18n/zh_<block>.json ...]
                                 [--cjk-size 14] [--line 18]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]  # the repository root
REMAKE = ROOT / "remake"
INTERFACE = REMAKE / "assets" / "data" / "interface.json"
DEFAULT_LNG = REMAKE / "assets" / "lng" / "chs_105.lng"

# widgets whose picture[0] is a glyph drawn left of the caption (radio/checkbox)
GLYPH_WIDTH = {"TLabRadioButton": 16, "TLabCheckBox": 16}


def load_nodes() -> dict[str, dict]:
    data = json.loads(INTERFACE.read_text(encoding="utf-8"))
    return {n["Name"]: n for n in data["nodes"]}


def load_lng(path: pathlib.Path) -> dict[str, str]:
    if path.suffix == ".json":
        return json.loads(path.read_text(encoding="utf-8"))
    text = path.read_text(encoding="utf-8")
    out: dict[str, str] = {}
    for block in re.findall(r"<o\b.*?</o>", text, flags=re.S):
        m = re.search(r'<p n="Name">(.*?)</p>', block, flags=re.S)
        if not m:
            continue
        name = m.group(1).strip()
        cm = re.search(r'<p n="Caption">(.*?)</p>', block, flags=re.S)
        if cm:
            cap = cm.group(1)
            for ent, ch in (("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">")):
                cap = cap.replace(ent, ch)
            out[name] = cap
    return out


def text_width(s: str, cjk: float) -> float:
    """Chinese glyph = cjk px; ASCII/space measured with the bitmap metrics."""
    w = 0.0
    for ch in s:
        w += cjk if ord(ch) > 0x2E80 else cjk * 0.55
    return w


def wrap_lines(text: str, width: float, cjk: float) -> list[str]:
    """Per-character wrap, the way OriginalUI.gd wraps Chinese text."""
    out: list[str] = []
    for para in text.split("\n"):
        if not para.strip():
            out.append("")
            continue
        line = ""
        for ch in para:
            if line and text_width(line + ch, cjk) > width:
                out.append(line)
                line = ""
            line += ch
        out.append(line)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--lng", type=pathlib.Path, default=DEFAULT_LNG)
    ap.add_argument("--json", type=pathlib.Path, action="append", default=[],
                    help="extra {id: caption} JSON files to include")
    ap.add_argument("--cjk-size", type=float, default=14.0)
    ap.add_argument("--line", type=float, default=18.0)
    ap.add_argument("--all", action="store_true", help="list every widget, not just problems")
    args = ap.parse_args()

    nodes = load_nodes()
    # Drafts win over the shipped file: with --json only the drafts are read, so
    # the report describes the new text and not the old localization it replaces.
    sources: list[pathlib.Path] = list(args.json)
    if not sources and args.lng.is_file():
        sources = [args.lng]
    captions: dict[str, str] = {}
    for src in sources:
        if src.is_file():
            captions.update(load_lng(src))

    rows = []
    unknown = []
    for name, text in captions.items():
        n = nodes.get(name)
        if n is None:
            unknown.append(name)
            continue
        cls = n.get("Class", "")
        width = float(n.get("Width") or 0)
        height = float(n.get("Height") or 0)
        shift_x = float(n.get("TShiftX") or 0)
        shift_y = float(n.get("TShiftY") or 0)
        # OriginalUI.gd only yields the glyph width when Picture[0] is non-empty
        # (the start-bonus radios have Picture ";FrameSqr.png", i.e. no glyph).
        pic0 = str(n.get("Picture", "")).split(";", 1)[0]
        if cls in GLYPH_WIDTH and pic0 != "":
            shift_x = max(shift_x, GLYPH_WIDTH[cls] + 4)
        avail_w = max(width - shift_x, 20.0)
        avail_h = max(height - shift_y, 0.0)
        wrapped = wrap_lines(text, avail_w, args.cjk_size)
        lines = len(wrapped)
        widest = max((text_width(ln, args.cjk_size) for ln in wrapped), default=0.0)
        rows_avail = max(int(avail_h // args.line), 1)
        flat = text.replace("\n", "")
        slack = avail_w - widest
        # Chinese text is laid out in whole glyphs, so a paragraph line of a wide
        # pane always sits within one glyph of the edge (35 glyphs fill 490 of
        # the 495 px help pane).  That is the design width, not a defect.
        #   OVERFLOW  the text needs more rows than the box has
        #   TIGHT     it does not fit the box but the line breaker can absorb it
        #             (closing punctuation or a balanced tail), or it fills the
        #             box so completely that a later edit has no room at all
        over_by = widest - avail_w
        if lines > rows_avail:
            flag = "OVERFLOW"
        elif over_by > 1.0 or (slack < args.cjk_size and lines == rows_avail):
            flag = "TIGHT"
        else:
            flag = "OK"
        rows.append({
            "id": name, "class": cls, "chars": len(flat),
            "box": f"{int(width)}x{int(height)}", "avail": f"{int(avail_w)}x{int(avail_h)}",
            "slack": round(slack, 1), "lines": lines, "rows": rows_avail,
            "flag": flag, "text": text.replace("\n", " / "),
        })

    order = {"OVERFLOW": 0, "TIGHT": 1, "OK": 2}
    rows.sort(key=lambda r: (order[r["flag"]], -r["chars"]))
    problems = [r for r in rows if r["flag"] != "OK"]
    show = rows if args.all else problems
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    for r in show:
        print(f"{r['flag']:9s} {r['id']:34s} {r['class']:16s} box {r['box']:>8s} "
              f"avail {r['avail']:>8s} {r['lines']}/{r['rows']} lines  slack {r['slack']:>6.1f}px")
        print(f"          {r['text'][:150]}")
    print()
    print(f"{len(rows)} captions checked, "
          f"{sum(1 for r in rows if r['flag'] == 'OVERFLOW')} overflow, "
          f"{sum(1 for r in rows if r['flag'] == 'TIGHT')} tight")
    if unknown:
        print(f"WARNING: {len(unknown)} id(s) not in interface.json: {sorted(unknown)}")
    return 1 if any(r["flag"] == "OVERFLOW" for r in rows) else 0


if __name__ == "__main__":
    sys.exit(main())
