#!/usr/bin/env python3
"""Extract every English player-visible string of the remake, in interface order.

The original LabInterface (FiberTwig.li) holds the base captions; lng/enu_10.lng
overrides a few of them and adds the language entries.  Both are merged here,
in the order of the .li widget tree, so a translation pass can read one flat,
ordered, fully-contextualised list.

Output: i18n/en_source.json  (machine readable)
        i18n/en_source.txt   (human/LLM readable)
"""

from __future__ import annotations

import json
import pathlib
import re
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]  # the repository root
REMAKE = ROOT / "remake"
LI = REMAKE / "assets" / "game" / "FiberTwig.li"
ENU = REMAKE / "assets" / "lng" / "enu_10.lng"
LEVELS = REMAKE / "assets" / "levels"
OUT = ROOT / "i18n"


def fix(s: str) -> str:
    """The .li stores runs of 10+ spaces as paragraph breaks (see OriginalUI.gd)."""
    s = re.sub(r" {10,}", "\n\n", s)
    return s.replace("\\n", "\n").strip("\n").rstrip()


def parse_li() -> tuple[dict[str, dict], list[str]]:
    root = ET.parse(LI).getroot()
    nodes: dict[str, dict] = {}
    order: list[str] = []
    for obj in root.findall("o")[1:]:
        cls = obj.get("c", "")
        node: dict = {"Class": cls}
        for p in obj.findall("p"):
            key, value = p.get("n"), p.text or ""
            if key is None:
                continue
            if key.startswith("On"):
                node.setdefault(key, []).append(value)
            else:
                node[key] = value
        name = node.get("Name", "")
        if name:
            nodes[name] = node
            order.append(name)
    return nodes, order


def parse_lng(path: pathlib.Path) -> dict[str, dict]:
    """Regex parsing: the shipped language files are not well-formed XML."""
    text = path.read_text(encoding="cp1252", errors="replace")
    out: dict[str, dict] = {}
    for block in re.findall(r"<o\b.*?</o>", text, flags=re.S | re.I):
        name = ""
        props: dict = {}
        for m in re.finditer(r'<p\s+n="([^"]*)"\s*>(.*?)</p>', block, flags=re.S | re.I):
            key, value = m.group(1), fix(m.group(2))
            if key == "Name":
                name = value.strip()
            else:
                props[key] = value
        if name:
            out[name] = props
    return out


def level_context() -> dict[int, dict]:
    """What the level files say about each level (name, music, hero, effects)."""
    info: dict[int, dict] = {}
    for i in range(18):
        f = LEVELS / f"Level{i}.txt"
        if not f.is_file():
            continue
        text = f.read_text(encoding="utf-8", errors="replace")
        d: dict = {}
        m = re.search(r'<Level\s+name="([^"]*)"', text)
        if m:
            d["name"] = m.group(1)
        m = re.search(r'<HeroPicture\s+name="([^"]*)"', text)
        if m:
            d["hero"] = m.group(1)
        m = re.search(r'<PlayMusic\s+name="([^"]*)"', text)
        if m:
            d["music"] = m.group(1)
        for tag in ("RainEffect", "FireEffect", "LevelEffect", "FragPicture"):
            m = re.search(rf'<{tag}\s+name="([^"]*)"', text)
            if m:
                d[tag] = m.group(1)
        for tag in ("BonusElement", "Bomb", "MakeGhostRect", "HidenFishkaPicture"):
            d[tag] = len(re.findall(rf"<{tag}\b", text))
        d["fishka"] = len(re.findall(r"<Fishka\b", text))
        d["ghost"] = len(re.findall(r"<GhostFishka\b", text))
        info[i] = d
    return info


def main() -> int:
    nodes, order = parse_li()
    enu = parse_lng(ENU)
    # merge: the .lng wins, and widgets it adds (none in enu) are appended
    merged: dict[str, str] = {}
    for name in order:
        cap = nodes[name].get("Caption")
        if cap:
            merged[name] = fix(cap)
    for name, props in enu.items():
        if "Caption" in props:
            merged[name] = props["Caption"]
        if name not in nodes:
            order.append(name)
            nodes[name] = {"Class": "added by enu_10.lng", **props}

    # extra runtime captions that are not in the widget tree
    runtime = {
        "LLevelWGameValue": "the level number drawn next to LLevelWGame",
        "LScoreWGameValue": "the score drawn next to LScoreWGame",
        "LCombDoneWGameValue": 'the combination counter, e.g. "1 / 5"',
        "LHammerCountWGameValue": "the hammer count drawn over the tool icon",
        "LCapsCountWGameValue": "the amphora count drawn over the tool icon",
    }

    records = []
    for name in order:
        if name not in merged:
            continue
        n = nodes[name]
        rec = {
            "id": name,
            "class": n.get("Class", ""),
            "size": [n.get("Width", ""), n.get("Height", "")],
            "text": merged[name],
        }
        if n.get("ParentName"):
            rec["parent"] = n["ParentName"]
        for k in ("Layout", "Alignment", "TShiftX", "TShiftY", "RadioGroup"):
            if k in n:
                rec[k] = n[k]
        if name.startswith(("LLevel", "TLevel")):
            m = re.match(r"(?:LLevel|TLevel)(\d+)", name)
            if m:
                rec["level"] = int(m.group(1))
        records.append(rec)

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "en_source.json").write_text(
        json.dumps(
            {"records": records, "runtime": runtime, "levels": level_context()},
            indent=2,
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    lines = ["=== ENGLISH SOURCE STRINGS (interface order) ===", ""]
    for r in records:
        lines.append(f"--- id: {r['id']}")
        lines.append(f"    widget: {r['class']}  size: {r['size'][0]}x{r['size'][1]}"
                     + (f"  parent: {r.get('parent')}" if r.get("parent") else ""))
        lines.append("    text:")
        for ln in r["text"].split("\n"):
            lines.append("      | " + ln)
        lines.append("")
    lines.append("=== LEVEL FILE CONTEXT (assets/levels/LevelN.txt) ===")
    lines.append("")
    for i, d in sorted(level_context().items()):
        lines.append(f"level {i}: {json.dumps(d, ensure_ascii=False)}")
    lines.append("")
    (OUT / "en_source.txt").write_text("\n".join(lines), encoding="utf-8")

    print(f"{len(records)} captions -> {OUT / 'en_source.json'}")
    print(f"{sum(len(r['text']) for r in records)} chars of source text")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
