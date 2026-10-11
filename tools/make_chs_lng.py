#!/usr/bin/env python3
"""Generate remake/assets/lng/chs_105.lng — the Simplified Chinese interface.

The original localization scheme (see ../REVERSE_ENGINEERING.md) keeps every
caption of FiberTwig.li and applies ``lng/<code>_<id>.lng`` files that only
override widget properties (mostly Caption).  The shipped files are 8 bit
(CP1251/CP1252); this one is UTF-8 so the text can hold CJK characters - the
remake's loader detects the encoding and switches to the bundled CJK font.

The translated text is NOT stored in this script.  It is written, per block, by
the translators and reviewed against the glossary, then merged here:

    i18n/zh_ui.json       menus, dialogs, options, HUD, in-game hints
    i18n/zh_help.json     help pages, help tabs, credits
    i18n/zh_levels.json   level descriptions

The English source of every id comes from the original interface data:

    i18n/en_source.json   FiberTwig.li + lng/enu_10.lng, in interface order
                          (rebuild with i18n/extract_en.py)

The term base and style guide every block follows is i18n/glossary.md; the
per-block English briefs are i18n/en_*.md (i18n/split_blocks.py).

Usage:
    python tools/make_chs_lng.py            # validate and write the .lng
    python tools/make_chs_lng.py --check    # report untranslated / stale ids
    python tools/make_chs_lng.py --dump     # print the merged ZH dict
Validation (all of it fails the build):
  * an id that is not a widget of the interface,
  * a widget with English text and no Chinese rendering,
  * a rendering that still contains 10+ consecutive spaces (the engine turns
    those into paragraph breaks; a translation must use real newlines),
  * a rendering that is byte-identical to the English source (a missed string),
  * a Chinese rendering missing from any of the blocks.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REMAKE = ROOT / "remake"
INTERFACE = REMAKE / "assets" / "data" / "interface.json"
I18N = ROOT / "i18n"
SOURCE = I18N / "en_source.json"
BLOCKS = {
    "ui": I18N / "zh_ui.json",
    "help": I18N / "zh_help.json",
    "levels": I18N / "zh_levels.json",
}
OUT = REMAKE / "assets" / "lng" / "chs_105.lng"

# Widgets whose caption is produced by the program at run time (score counters,
# level numbers, the five "+" labels).  They must NOT be written into the .lng.
NUMERIC = re.compile(
    r"^(LLevelNum|LScoreCount|LHammerCount|LClipperCount|LLiveCount|LDropAccelCoun|"
    r"LCombCount|LLuckyTwigCount|LDropAccelCount|LLiveExp|LDropAccelExp|"
    r"LLuckyTwigExp|LAmphoraExp|LHammerExp|LYourScoreCount|LYourHammerCount|"
    r"LYourCapsCount|LTotalScoreCount|LScoreCountW|LabLabel)"
)

# The Chinese entry of the language dialog is added by this localization itself
# (the shipped .lng files only declare the five original languages), so it is a
# widget the interface data does not contain.
EXTRA = {"RCHSWLanguage": "简体中文"}

# Captions that are not prose and are therefore identical in every language.
VERBATIM = re.compile(r"^(https?://|www\.|[\d\s%.,+/-]+)$")


def is_verbatim(text: str) -> bool:
    """True for a caption that has no words to translate (URLs, numbers, '+')."""
    s = text.strip()
    if not s:
        return True
    if "www." in s or s.startswith(("http://", "https://")):
        return True
    return bool(VERBATIM.match(s))


def load_source() -> tuple[dict[str, str], dict[str, str]]:
    """id -> English caption and id -> widget class, in interface order."""
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    caps: dict[str, str] = {}
    classes: dict[str, str] = {}
    for rec in data["records"]:
        caps[rec["id"]] = rec["text"]
        classes[rec["id"]] = rec["class"]
    return caps, classes


def load_blocks() -> tuple[dict[str, str], dict[str, str]]:
    """Merge the three translated blocks; returns (translation, block of id)."""
    merged: dict[str, str] = {}
    where: dict[str, str] = {}
    for name, path in BLOCKS.items():
        if not path.is_file():
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        for wid, text in data.items():
            if wid in merged and merged[wid] != text:
                sys.exit(f"conflict: {wid} is translated twice, in "
                         f"{where[wid]} and {name}")
            merged[wid] = text
            where[wid] = name
    for wid, text in EXTRA.items():
        merged.setdefault(wid, text)
        where.setdefault(wid, "extra")
    return merged, where


def validate(caps: dict[str, str], classes: dict[str, str],
             zh: dict[str, str]) -> list[str]:
    errors: list[str] = []
    known = set(classes) | set(EXTRA)
    for wid in sorted(zh):
        if wid not in known:
            errors.append(f"unknown widget id: {wid}")
    for wid, en in caps.items():
        if NUMERIC.match(wid) or not re.search(r"[A-Za-z]", en):
            continue
        if wid not in zh:
            errors.append(f"no Chinese rendering: {wid} ({en[:50]!r})")
    for wid, text in sorted(zh.items()):
        if re.search(r" {10,}", text):
            errors.append(f"{wid}: contains 10+ consecutive spaces "
                          "(use real newlines for a paragraph break)")
        if text == caps.get(wid) and not is_verbatim(caps.get(wid, "")):
            errors.append(f"{wid}: rendering is identical to the English source")
        if "&#" in text:
            errors.append(f"{wid}: contains an XML entity escape")
    return errors


def xml_escape(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def build(zh: dict[str, str], classes: dict[str, str], caps: dict[str, str]) -> str:
    parts = ['<?xml version="1.0" encoding="UTF-8"?>', "<LabInterface>"]
    for wid in sorted(zh):
        cls = classes.get(wid, "TLabLabel")
        parts.append(f'\t<o c="{cls}">')
        parts.append(f"\t\t<p n=\"Name\">{wid}</p>")
        parts.append("\t\t<p n=\"CharSet\">CHINESE</p>")
        parts.append(f'\t\t<p n="Caption">{xml_escape(zh[wid])}</p>')
        parts.append("\t</o>")
    parts.append("</LabInterface>")
    return "\n".join(parts) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="validate only")
    ap.add_argument("--dump", action="store_true", help="print the merged dict")
    args = ap.parse_args()

    caps, classes = load_source()
    zh, where = load_blocks()

    missing_blocks = [n for n, p in BLOCKS.items() if not p.is_file()]
    if missing_blocks:
        print(f"note: block(s) not written yet: {', '.join(missing_blocks)}")

    errors = validate(caps, classes, zh)
    if args.dump:
        print(json.dumps(zh, ensure_ascii=False, indent=2, sort_keys=True))
        return 1 if errors else 0
    if errors:
        print(f"{len(errors)} problem(s):")
        for e in errors[:60]:
            print("  " + e)
        if len(errors) > 60:
            print(f"  … {len(errors) - 60} more")
        return 1
    if args.check:
        done = sum(1 for w in zh if w in classes)
        print(f"all textual captions translated ({done} widgets)")
        return 0

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(build(zh, classes, caps), encoding="utf-8", newline="\n")
    per_block = {b: sum(1 for w in where.values() if w == b) for b in (*BLOCKS, "extra")}
    detail = ", ".join(f"{k} {v}" for k, v in per_block.items() if v)
    print(f"wrote {OUT.relative_to(ROOT)} ({len(zh)} widgets: {detail})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
