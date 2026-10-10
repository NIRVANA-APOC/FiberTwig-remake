# Fiber Twig — reverse engineering + remake

This repository contains a complete reverse-engineering of Puzzle Lab's 2004
puzzle game **Fiber Twig** (RealArcade release) and a playable remake of the
game built with **Godot 4**.

```
FiberTwig/            original game files (target of the analysis)
REVERSE_ENGINEERING.md  full analysis report: formats, cipher, game rules
tools/                Python tools recovered from the analysis
  zxc.py              .zxc archive list/extract/pack
  decrypt_levels.py   level decryption (cipher + key derivation)
  save_codec.py       save-game encode/decode
  build_ui_data.py    FiberTwig.li + Arial12.xml -> remake/assets/data/interface.json
  artmatch.py         locate original artwork inside the reference screenshots
  make_chs_lng.py     Simplified Chinese localization -> remake/assets/lng/chs_105.lng
  make_chs_font.py    Noto Sans SC subset (CJK font) -> remake/assets/fonts/
remake/               Godot 4 remake (see remake/README.md)
  assets/levels/      all 18 levels, decrypted
  assets/squares/ game/  art, audio, fonts extracted from the original
  assets/lng/         original localizations + Simplified Chinese (chs_105.lng)
  assets/fonts/       Noto Sans SC subset for the Chinese captions (SIL OFL)
  src/                GDScript sources
docs/report...        (see REVERSE_ENGINEERING.md)
```

Reference captures of the original game (`assets/*.png`) were used to verify the
reconstruction: the remake reproduces the original 800x600 client layout, the
board lattice, the conveyor speed and the placement rules measured from them
(see section 10 of the report).

The remake ships with the five original localizations (English, German,
French, Portuguese, Russian) plus a complete **Simplified Chinese** one
(`简体中文`) that can be selected in *Options → Language*; all interface text,
help pages, level names and hints are translated (`tools/make_chs_lng.py`).

## Highlights of the analysis

* **`.zxc` archive format** — a simple 48-byte-entry table; all art, sound,
  fonts, the UI layout and the level set were extracted (`tools/zxc.py`).
* **Level format** — "Lab" XML with a 15×251 board of 40 px cells; the
  `<Fishka>` entries are the damaged twig pattern that is already on the
  board (100 % joint-consistent), `<GhostFishka>` are the transparent target
  twigs that must be covered; `Squares_Frags.dat`/`Squares_Points.dat` map
  frag indices to board coordinates.
* **Level encryption** — levels 4…17 use a home-made 64-bit block cipher
  `C = T(P ⊕ K8) ⊕ K8` (T = 8×8 bit transpose) with a key derived from the
  serial number `007173307790020009386587` → `"Zp1meWKa"`.
  All 18 levels are decrypted in `remake/assets/levels/`.
* **Save games** — INI text with every byte shifted by `+0x33`.
* **UI** — `FiberTwig.li` holds the complete widget tree (captions, colours,
  state pictures, click sounds, bitmap-font metrics). The remake renders every
  screen from that data instead of re-designing it.
* **Placement policy** — `options.cfg` documents `PutAllow=paBorder` and
  `TakeAllow=taDenied`; closing a loop is rejected (`ClosedLink`).
* **Demo recording** (`demo.dat`) — a 409 s session of level 3 that pins down
  the conveyor speed (25 px/s), the pickup/generate clicks, mystery/bonus twigs
  and the bonus indices.
* **Effects** (`EffectsType.dat`) — 38 named visual/audio effects, from the
  joint light streaks to the bonus sparks.
* **Bonus table**, **combinations** and the **sound/music** set were recovered.

## Running the remake

```bash
./play.sh                               # launcher (bundled engine or $GODOT/godot4)
./play.sh --opengl3                     # compatibility rendering driver
./play.sh -- --screen=WGame --level=6   # pass game flags after --

# or directly:
godot --path remake
# or, with the bundled download in tools/:
tools/Godot_v4.7.2-stable_linux.x86_64 --path remake
```

See [`remake/README.md`](remake/README.md) for controls and implementation
notes, and [`REVERSE_ENGINEERING.md`](REVERSE_ENGINEERING.md) for the full
technical report.

## Legal

The original game and its assets are © 2004 Puzzle Lab / RealNetworks.
They are included here only as the subject of the reverse-engineering study
and the resulting non-commercial remake.

## Copies / other machines

`SETUP.md` documents this checkout as delivered to `gem:~/Documents/Games/FiberTwig/`
(what is included, how to run the game and the headless tests there, how to do
the screenshot + pixel-diff loop, and the delivery verification result).
