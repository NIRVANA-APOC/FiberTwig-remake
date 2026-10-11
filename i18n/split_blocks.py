#!/usr/bin/env python3
"""Split the English source strings into the translation work packages.

Reads i18n/en_source.json (from extract_en.py) and writes, for every
translation block, one Markdown brief that a translator can read on its own:

    i18n/en_<block>.md     id, widget, size, parent, source text

Blocks are disjoint sets of widget ids; the glossary (i18n/glossary.md) is
shared by all of them.
"""

from __future__ import annotations

import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]  # the repository root
I18N = ROOT / "work" / "i18n"


def block_of(r: dict) -> str:
    name: str = r["id"]
    if re.match(r"^(LLevel|TLevel)\d", name):
        return "levels"
    if name.endswith("WHelp"):
        return "help"
    return "ui"


BLOCKS = {
    "help": "Help pages (game manual) + help tab labels + credits",
    "ui": "Menus, dialogs, buttons, options, tooltips, HUD captions",
    "levels": "Level names / between-level descriptions",
}

TITLES = {
    "help": "BLOCK A — Help pages (the in-game manual), tab labels and credits",
    "ui": "BLOCK B — Menus, dialogs, buttons, options and HUD captions",
    "levels": "BLOCK C — Level names and between-level descriptions",
}


def main() -> int:
    data = json.loads((I18N / "en_source.json").read_text(encoding="utf-8"))
    groups: dict[str, list[dict]] = {k: [] for k in BLOCKS}
    for r in data["records"]:
        groups[block_of(r)].append(r)

    for key, recs in groups.items():
        out = [f"# {TITLES[key]}", ""]
        out.append(f"{len(recs)} strings. Source: FiberTwig.li + lng/enu_10.lng "
                   "(the original game's own captions).")
        out.append("")
        out.append("Every entry shows the widget id, its class, its size in the "
                   "800x600 client, its parent form, and the English text.")
        out.append("")
        for r in recs:
            out.append(f"## `{r['id']}`")
            bits = [f"widget `{r['class']}`", f"size `{r['size'][0]}x{r['size'][1]}`"]
            if r.get("parent"):
                bits.append(f"form `{r['parent']}`")
            if r.get("level") is not None:
                bits.append(f"level {r['level']}")
            out.append("_" + " · ".join(bits) + "_")
            out.append("")
            for ln in r["text"].split("\n"):
                out.append(ln if ln.strip() else "")
            out.append("")
        (I18N / f"en_{key}.md").write_text("\n".join(out), encoding="utf-8")
        print(f"{key:8s} {len(recs):3d} strings -> i18n/en_{key}.md")

    # level file context, shared by block C
    ctx = ["# Level file context (assets/levels/LevelN.txt)", ""]
    ctx.append("The level files drive the artwork, music and effects of each level. "
               "Use this to make the level descriptions concrete.")
    ctx.append("")
    for i, d in sorted(data["levels"].items(), key=lambda kv: int(kv[0])):
        ctx.append(f"## level {i}")
        ctx.append("```json")
        ctx.append(json.dumps(d, ensure_ascii=False, indent=2))
        ctx.append("```")
        ctx.append("")
    (I18N / "level_context.md").write_text("\n".join(ctx), encoding="utf-8")
    print(f"levels   {len(data['levels']):3d} level files -> i18n/level_context.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
