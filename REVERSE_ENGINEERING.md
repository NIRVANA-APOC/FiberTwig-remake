# Fiber Twig — Reverse Engineering Report

Target: **Fiber Twig** v1.0 (Puzzle Lab, 2004, distributed by RealNetworks/RealArcade)
Artifacts analysed: `FiberTwig.exe`, `bass.dll`, `Game/game.zxc`, `levels/squares.zxc`,
`demo.dat`, `saves/*.sav`, `lng/*.lng`, `launch.ini`, `options.cfg`, `fibertwig.udf`.

Everything below was recovered from the shipped artifacts (static analysis of the
Delphi executable with Ghidra + manual disassembly, file-format archaeology and
cryptanalysis). Where a statement is an inference rather than a directly observed
fact it is marked **[inferred]**.

---

## 1. Overview

Fiber Twig is a Pipe-Mania-like puzzle game built on Puzzle Lab's in-house
"Lab" framework:

* The playfield shows an unfinished pattern made of **twigs** (`fishka`).
  Every twig is a 40×40 cell with joints on any of its four edges
  (`1 = up, 2 = right, 4 = down, 8 = left` → 15 possible shapes, type 0 = empty).
* A conveyor at the bottom delivers new twigs; the player picks them up,
  rotates them (right mouse button), places them (left button) and must
  connect every twig of the level into one network that reaches the top.
* Some cells contain **transparent ("ghost") twigs** that have to be covered
  with a twig of the exact same shape.
* Magic tools help: a **hammer** (smash a twig), an **amphora/clipper**
  (create a wanted twig, or cut one away) and the **drop section** (throw a
  twig away). Scores are earned per placed twig and for **combinations**
  (patterns listed in `FishCombinations.dat`), which in turn grant bonuses.

The screen is 800×600, split into a 600×500 play area, a 200 px wide right
panel (HUD + tools + drop section) and a 100 px high belt at the bottom.

---

## 2. Resource containers — `.zxc` archives

`Game/game.zxc` (3.9 MB) and `levels/squares.zxc` (3.5 MB) are uncompressed
archives. Layout (little endian):

```
u32 magic = 12345 (0x3039)
u16 entryCount
u16 checksum
entryCount * 48 byte table entries
concatenated payloads
```

Entry (48 bytes):

```
+0x00  u8   nameLength (1..31)
+0x01  char name[nameLength]
+0x20  u32  reserved (0)
+0x24  u32  payloadOffset      (relative to end of the table)
+0x28  u32  payloadSize
+0x2C  u32  reserved (0)
```

A parser/writer is provided in `tools/zxc.py`. Extracted contents:

* **game.zxc** (97 files): UI art (buttons, cursors, frames), five bitmap
  fonts (`Arial12lat.png`, `Arial12cyr.png`, …), 16 WAV sound effects,
  5 `*.mo3` music modules (BASS compressed modules) and the UI layout
  `FiberTwig.li`.
* **squares.zxc** (319–340 files depending on release): the tile art
  (`brick*.png`, `BigBrick*`, decorations, creatures), the twig sprites
  (`1_1.png`, `12_1.png`, … `1234_1.png`), animation frames (`*_1.pNg`,
  `*_2.pNg`, `*.aim`), 18 level files and the binary lookup tables
  (`Squares_*.dat`).

The `temp/` folder is just the archive copied/re-packed by the launcher
(`launch.ini`, `RealArcade` integration) — `Game\game.zxc → temp\game.zxc`,
`levels\squares.zxc → temp\squares.zxc`.

---

## 3. Binary lookup tables (`squares.zxc`)

| file | size | meaning |
|---|---|---|
| `Squares_Points.dat` | 4016 × u32 | board cell table. Each value packs `x` in the low 16 bits and `y` in the high 16 bits (16 columns × 251 rows, 40 px cells, x = 5+40c, y = 40r). |
| `Squares_Frags.dat` | 4750 × 22 bytes | per-frag record: byte 0 = frag type, then 10 × u16 point indices. `frag i` → `u16 at i*22+2` → index into `Squares_Points.dat`. |
| `Squares_FragsTypes.dat` | 78 bytes | fragment-type table (indexed by the frag type byte, stride 0x4E; the shipped file only contains the zero record). |
| `Squares_FishkasTypes.dat` | 16 × 126 bytes | per twig type, three length-prefixed strings: `(shape, shape rotated 90° CW, "_1")`. This is the type → sprite-name mapping. |
| `Squares_Connects.dat` | u16 pairs | combination/connection lookup used by the engine. |
| `FishCombinations.dat` | XML-ish text | the twig combinations that award bonuses (see §6). |

The twig type index is a bitmask; `Squares_FishkasTypes.dat` gives the
ordering used by the level files:

```
1→"1"   2→"2"   3→"12"  4→"3"   5→"13"  6→"23"  7→"123"
8→"4"   9→"14" 10→"24" 11→"124" 12→"34" 13→"134" 14→"234" 15→"1234"
```

with `1 = up, 2 = right, 4 = down, 8 = left`. Rotating a piece 90° clockwise is
`((t << 1) | (t >> 3)) & 0xF`.

---

## 4. Level files

Levels live inside `squares.zxc` (`levels.dat` lists `Level0.txt … Level17.txt`).
Levels 0–3 are plain XML; levels 4–17 are encrypted with a home-made block
cipher (see §5). After decryption all 18 files are human-readable "Lab" XML
produced by the in-house level editor. A decrypted copy is included in
`remake/assets/levels/`.

### 4.1 Document structure

```xml
<Level name="Level10" fragmentation="Squares_" CurrentY="9760" />
<HeroPicture name="borovik.png">
<FragPicture name="FragPic4.png"/>
<Generator period="3500"/>
<PlayMusic name="Sad Song.mo3"/>
<RainEffect name="Rain"/>
<HidenFishkaPicture name="borovikicon.png" prob="0,1"/>
<FishkaWithBonus prob="0,05"/>
<LevelEffect name="RoundBlicks" x="535" y="9756">

<Fishka frag="3727" type="5" link="1"/>            <!-- the initial twig -->

<Picture name="" x="0" y="5350" z="500">           <!-- background / decoration -->
    <Image name="SkyFone2.jpg"/>
</Picture>
<Picture ... >                                     <!-- animation: <Image t="ms"/> -->
    <Image name="Fonar3on.png" t="4000"/>
    <Image name="Fonar3.png"   t="100"/>
</Picture>
<Picture ...>                                      <!-- moving clouds -->
    <Image name="cloud.png"/>
    <MovingCurve alX="20" beX="0,0007" gaX="0" laX="0" lbX="70"
                 alY="30" beY="0,0008" gaY="1,57" laY="0" lbY="9012" t="2000000"/>
</Picture>

<FishkaProb>                                       <!-- conveyor shape classes -->
  <FProb name="1" prob="5">  <FProb name="12" prob="13"> …
</FishkaProb>
<FishkaScore>0 10 10 10 10 … </FishkaScore>         <!-- points per type 0..15 -->
<FishkaBonusProb> 10 2 10 30 2 2 2 </FishkaBonusProb>       <!-- bonus weights -->
<FishkaCombination>
  <CombSequence> 23 12 3 20 32 </CombSequence>      <!-- 1-based combo indices -->
  <OneCombBonusProb> 10 0 10 0 0 0 0 </OneCombBonusProb>
  <AllCombBonusProb> 10 0 10 0 0 0 0 </AllCombBonusProb>
</FishkaCombination>

<PictureMap x="0" y="5881" z="0" OneWidth="40" OneHeight="40">
  <Images>brick3.png brick3_1.png brick3_2.png …</Images>
  <map> 0 0 0 0 … </map>          <!-- 15 columns per row, 44..126 rows -->
  …
</PictureMap>

<GhostFishka x="145" y="8980" type="7"/>           <!-- transparent twigs -->
…
<Fishka frag="3183" type="5" link="1"/>            <!-- the rest of the pattern -->
…
```

Level 0 additionally carries `<FishTypeSequence>` (the first twigs the
conveyor must produce) and `<RainEffect>`; later levels use
`<BonusElement>` (collectible bonus markers with `Point`, `RemovePicture`,
`ShowPicture`, `StartEffect`), `<Bomb>`, `<FireEffect>`, `<MakeGhostRect>`,
`<PutFishka>` and `<MapMovingCurve>`.

### 4.2 Coordinates

* Board = 15 columns × 251 rows of 40 px cells (`y` grows downward:
  `y = 0` is the top of the world, `y ≈ 10121` the bottom).
* A `<Fishka frag="N">` is positioned through
  `N → Squares_Frags.dat → Squares_Points.dat`; the resulting point is the
  cell anchor, stored as `(5+40*col, 40*row)`.
* A `<GhostFishka x y>` is anchored at `(40*col+25, 40*row+20)`
  (`col = (x-25)/40`, `row = (y-20)/40`).
* `<PictureMap>` bricks are drawn at `map.x + 40*col`, `map.y + 40*row`.
* `CurrentY` relates to the initial camera as `cam_y = CurrentY - 247`
  (**measured**, see §10.1; the 247 offset was recovered by fitting the
  rendered level against the reference screenshots and is confirmed by
  replaying the first placement of `demo.dat` against the `paBorder` rule).

### 4.3 Meaning of the two twig lists (verified)

* **`<Fishka>`** — the twigs that are already on the field when the level
  starts (the hurricane damage). Measuring the joint consistency of every
  pair of adjacent fishkas gives **100 % consistent joints in all 18 levels**;
  the entries form 10–54 disconnected components per level, exactly the
  "damaged pattern" the player has to reconnect.
* **`<GhostFishka>`** — transparent target twigs that must be covered with a
  twig of the same type. They never overlap the pre-placed pieces.

The player wins when **all twigs form one connected network, the network
reaches the top row of the map and every transparent twig has been covered**.

---

## 5. Level encryption (levels 4–17)

### 5.1 The cipher

Static analysis of `FiberTwig.exe` located the routine (`0x46FC64`) that the
level parser calls before loading a file from the `TFileFolder` container.
The transformation is a 64-bit block cipher in ECB mode:

```
C = T(P XOR K8) XOR K8
```

`T` is an 8×8 **bit transpose** (`T(x)[k] bit b = x[b] bit k`), implemented in
the executable as the nested loop at `0x46FBB4`; `K8` is an 8 byte key that is
repeated/truncated from a key string derived from the serial number. A final
partial block (< 8 bytes) is only XORed with the key.

### 5.2 Key derivation

The executable contains the constant serial string
`"007173307790020009386587"`. `0x46F6C0` turns it into the key:

1. keep only decimal digits;
2. permute: `out[(2*i) mod (n+1) - 1] = in[i-1]` for `i = 1..n`
   (n = 24 → `"002007010793338067578970"`);
3. delete the first 3 characters and strip leading zeroes →
   `"7010793338067578970"`;
4. parse as a 64-bit integer (0x614B57656D31705A);
5. take the little-endian bytes, clear bit 7 of each and drop zero bytes →
   the 8-character key string **`Zp1meWKa`**;
6. expand to 8 bytes: `5A 70 31 6D 65 57 4B 61`.

`tools/decrypt_levels.py` performs all of this and decrypts the whole level
set (all 18 files are already decrypted in `remake/assets/levels/`).

Note: the same key string is also used by the executable's "registered
content" check, which is why the trial levels 0–3 are stored in clear text.

---

## 6. Game data

### 6.1 Sounds / music (`game.zxc`)

16 WAV effects referenced by name (`PutFishka.wav`, `RotateFishka.wav`,
`BreakFishka.wav`, `ClosedLink.wav`, `Link.wav`, `GameOver.wav`, `LaBomb.wav`,
`Clipper.wav`, `BonusElement.wav`, `Combination.wav`, `BonusDone*.wav`, …) and
5 BASS modules converted for the remake with `openmpt123` + `oggenc`
(`Natureopt`, `Sad Song`, `Sensetive`, `Be happy!`, `In the lost forest2`).

### 6.2 Combos (`FishCombinations.dat`)

Each `<FishkaCombination>` contains several `<Stamp>` alternatives; a stamp is
a set of relative cells with twig types, e.g.

```xml
<FishkaCombination>
  <Stamp>
    <FishkaInStamp x="0"  y="0"  type="15" />
    <FishkaInStamp x="0"  y="40" type="11" />
  </Stamp>
  … more stamps …
</FishkaCombination>
```

The level's `<CombSequence>` lists which combinations are active (1-based) and
`OneCombBonusProb` / `AllCombBonusProb` weight the seven bonus kinds.

### 6.3 Bonuses (`BonusTypes.dat`)

The file holds seven `<BonusType>` records; the *table order* is what
`FishkaBonusProb` / `OneCombBonusProb` index (the order used by the help
screen is a different, presentation-only order):

```
0  PlusHummers        = 2      extra hammers
1  ClearSteck         = true   empty the conveyor (bomb)
2  PlusCaps           = 2      extra amphoras
3  PlusScore          = 100    points
4  SpeedUpOtb         = 60000  drop section accelerator (ms)
5  MakeFishesWithBonus = true  all conveyor twigs become bonus twigs
6  TimeToNoLose       = 60000  time control, no losing (ms)
```

### 6.4 UI definition

`game.zxc:FiberTwig.li` contains the complete "Lab" interface description
(window positions, captions, fonts, sounds). Selected facts used by the
remake:

* play area 600×500, right panel at x = 600 (200 px wide, height 585),
  belt along the bottom 100 px;
* `BGenerateFishWGame` sits at (768, 506) — the "drop section" button;
* HUD labels: level (710, 100), score (690, 120), hammer/clipper counts
  (634/701, 354), combinations (712, 265), drop section caption (607, 430);
* `lng/enu_10.lng` and `fibertwig.li` give every caption in the five shipped
  languages.

### 6.5 Save files

`saves/*.sav` are short INI files where every byte of a record has 0x33 added;
records are separated by literal CRLF bytes. Decoded example:

```ini
CurrentLevel="0"
TotalScore="99999"
TotalHammerNum="99999"
TotalCapNum="99999"
Experience="99999"
PlusOtb="0" … SkillOtb="99999" …
NoLoose="false"
Easy="false"
Hard="false"
```

`tools/save_codec.py` decodes/encodes them.

### 6.6 Demo recording

`demo.dat` is a plain text recording of a play session (level 3) with
timestamped events: `<NewFishkaInSteck time fishtype quest bonus>`,
`<MoveSteck time incr>`, `<MouseMove x y time>`, `<MouseL/RDown/Up …>` and
`<GiveBonus ind>`. It is useful for validating camera/screen mappings
(the first placement happens at screen y ≈ 261 with the camera at
`CurrentY = 9760`).

---

## 7. Executable structure (Delphi)

The executable is a Borland Delphi PE32 application (no packer, sections
`CODE DATA BSS .idata .tls .rdata .reloc .rsrc`). The most important recovered
routines:

| address | role |
|---|---|
| `0x46EAC0` | `TFileFolder` — `.zxc` archive reader |
| `0x46FC64` | level decryptor (`XOR key → bit transpose → XOR key`) |
| `0x46F6C0` | serial-number → key derivation |
| `0x46FBB4` | 8×8 bit transpose |
| `0x46F844` | key-string permutation |
| `0x49A7E4` | level XML parser (`TStringList` based) |
| `0x484348` | level start / HUD setup |
| `0x48D1E0` | between-level menu |

---

## 8. Reproducing the extraction

```bash
python3 tools/zxc.py extract FiberTwig/Game/game.zxc        work/game
python3 tools/zxc.py extract FiberTwig/temp/squares.zxc     work/squares
python3 tools/decrypt_levels.py work/squares                work/levels
python3 tools/save_codec.py decode FiberTwig/saves/LEVEL_01.sav
```

The remake in `remake/` consumes exactly these extracted assets.

---

## 9. Known unknowns / limitations

* The exact trial/registration logic (`fibertwig.udf`, RealArcade integration)
  was not reconstructed; the remake simply unlocks all 18 levels.
* The two special twig classes `double2/double2a/tripl1/adouble1/skoba1`
  referenced by `<FishkaProb>` are generated as ordinary shapes in the remake.
* `Squares_Connects.dat` was not decoded field-by-field; the remake uses the
  joint bitmask rules instead.
* Particle/weather effects (`RainEffect`, `FireEffect`, `LevelEffect`,
  `MovingCurve` motion equations) are approximated.

---

## 10. 1:1 verification against the shipped screenshots

`assets/*.png` are captures of the original game running in a window. They are
*direct evidence* of the layout and of the runtime behaviour, so the remake was
fitted against them. Measurement method: the panel artwork of
`GamePlay1.jpg` and the twig sprites were located inside the captures with
masked normalized cross-correlation (`tools/artmatch.py`).

### 10.1 Screen geometry of the captures

* The window client area is the original **800×600** design scaled by exactly
  **1.25** (an 1000×750 client, the capture adds a 33 px title bar and desktop
  margin). Fitting `GamePlay1.jpg`'s panel art gives design→capture
  `(x, y) = (1.25·x, 33 + 1.25·y)` — e.g. the panel crop at design (612, 90)
  lands at capture (765, 145.5).
* Therefore every coordinate in `FiberTwig.li` *is* the client coordinate of
  the original screen, and the remake can use them unchanged.

### 10.2 Board lattice (measured)

Matching the twig sprites (`13_1.png`, `1_1.png`, …) and the brick tiles inside
the captures shows:

| item | original position |
|---|---|
| twig sprite (top-left corner) | `(40·col + 5, 40·row)` — exactly the grid stored in `Squares_Points.dat` (x = 5+40c, y = 40r) |
| `<GhostFishka x y>` | sprite centre → origin `(x-20, y-20)` |
| brick tile of `<PictureMap>` | `(map.x + 5 + 40·col, map.y + 40·row)` |
| `<Picture>` with `z = 0` | `(pic.x, pic.y)` (world anchored) |
| `<Picture>` with `z ≥ 100` ("Fone") | screen anchored: at the initial camera the first background sits at screen y = **-88** (measured), so it always covers the play view |
| camera | `cam_y = CurrentY - 247` (measured; the level view is `cam_y … cam_y+500`) |

The camera rule is independently confirmed by `demo.dat`: the first board click
of the recorded session (`Level3.txt`, `MouseLDown x=307 y=261`) maps to cell
(7,244) under `cam_y = 9513`, which is exactly a legal `paBorder` placement
(it touches the pre-placed twig (6,244) = type 7 through its left joint with
the placed type 12), whereas `cam_y = CurrentY` would map it to the isolated
cell (7,250) and violate the placement rule.

### 10.3 Runtime behaviour recovered from `demo.dat`

`demo.dat` is a text recording of a 409 s play session of `Level3.txt`:

```xml
<NewFishkaInSteck time="16" fishtype="3" quest="false" bonus="false"/>
<MoveSteck time="32" incr="1"/>
<MouseLDown x="775" y="514" time="4188"/>
<MouseRDown x="306" y="273" time="5938"/>
<GiveBonus ind="2" time="..."/>
```

* `MoveSteck incr` is a **pixel** step of the belt: 10259 px in 409 s →
  **≈25 px/s** (`incr=2` steps also occur). The remake uses 25 px/s.
* Clicking the conveyor strip (y ≈ 545…585) picks up a twig;
  clicking `BGenerateFishWGame` (design 768,506 — the left arrow in the drop
  panel) pushes a new twig onto the belt (the demo shows a
  `NewFishkaInSteck` within ~120 ms after every click on it).
* `quest`/`bonus` flags confirm the mystery (hidden shape) and bonus twigs.
* `GiveBonus ind` indexes `BonusTypes.dat` (see §6.3).
* `MouseRDown` rotates the twig in hand; `MouseLDown` over the play field
  places it.

### 10.4 UI, hints and effects

* `FiberTwig.li` (extracted as `remake/assets/data/interface.json`) is a full
  widget tree (`TLabForm/Button/RadioButton/CheckBox/Label/Grid/Edit/TabForm`)
  with captions, colours, state pictures and click sounds. The remake renders
  these screens from that data, including the 4 difficulty modes
  (`No Lose / Easy / Normal / Hard`), the pause menu, the between-level
  experience/skill screen, save/load, options, help and the high-score list.
* Text uses the shipped bitmap font `Arial12lat.png` with the metrics from
  `Arial12.xml` (`AddMetric`), which reproduces the original text layout.
* Hints (`LHint*` captions) are shown in the black box at the top-left of the
  play area, exactly like `assets/Game-3.png`.
* The light that escapes from open joints is `Blick1.png` — a 4-frame 8×8
  sparkle sheet, drawn stretched along the joint (30…55 px) — driven by the
  `RoundBlicks` effect in `EffectsType.dat` (`RoundLongYEffect`).
* `RainEffect name="Rain"` uses `RainDrop.png` scaled to `MidRain` (20×40,
  alpha 150) and `SmRain` (13×24, alpha 100) as declared by the `.aim`
  `AutoImage` recipes.
* `EffectsType.dat` defines 38 named effects (visual + sound) such as
  `PutFishka`, `ConnectLink`, `ClosedLink`, `HammerFishka`, `BombFishka`,
  `GiveHammer`, `CombinationSound`; `sounds.dat` lists the 16 WAVs.
* `options.cfg` documents the movement policy: `PutAllow = paAll | paBorder |
  paNearlight` and `TakeAllow = taBorderFish | taDenied`. The shipped
  configuration is `paBorder` + `taDenied`, i.e. a new twig must touch the
  existing pattern and placed twigs cannot be picked up again; closing a loop
  is forbidden (`ClosedLink`).
* The starting tool counts (3 hammers, 3 amphoras — `assets/Game-*.png` show
  *8* and *3* after the "+5 Hammer" starting bonus) and the starting-screen
  bonus values are likewise taken from the captures.

### 10.5 Dialog mechanics taken from the interface file

Every modal (options, language, load/save, confirmations, between-level)
is driven by the `ShowModal / HideModal / ChangeModal / SetProp / RunMethod`
actions stored on the widgets, so the navigation graph is literally the one
authored for the original game:

* `BOptionsWOptions` → `HideModal WOptions`, `BCancelWOptions` →
  `HideModal WOptions` (+ `RunMethod`), `BLanguageWOptions` → `ShowModal
  WLanguage`. `WLanguage` therefore stacks *on top of* `WOptions`, and
  closing it returns to the options dialog, not to the title screen.
* `WOptions` holds two radio groups (`RadioGroup=4` music, `5` sound) with
  `100 / 80 / 60 / 40 / 20 / No Music` and `… / No Sound` — not sliders. The
  shipped `Options.png` capture has `Music60` and `Sound80` checked, which is
  index `2` and `1`. `Cancel` restores the snapshot taken when the dialog
  opened, `OK` writes `options.cfg` (`SoundVolumeIdx`, `MusicVolumeIdx`,
  `TurnOffHint`, `FullScreenMode`, `BitsPerPixel`, `PlayerName`,
  `Language`).
* `TLabGrid` defaults (`.li` `DefLine` records) give the list metrics used by
  the load/save/high-score grids: `RowHeight=20`, `CursorColor=12632256`
  (`0xC0C0C0`, the selected row fill measured in `Load_Game.png`),
  `ColTShiftX=4`, `ColTShiftY=2`, `DivisorHeight=20`, `Grid200x240.png`
  (teal frame, interior `#177786` at alpha 38) and `LineCursor200x24.png`.
  The high-score grid has no picture, i.e. no frame and no cursor row.
* `TLabEdit` uses `Edit200x25.png` + `EditCursor.png` (`TShiftX=5`,
  `MaxLength=19`); its `Color` is the box colour, the text is dark.
* `WLoad`/`WSave` are only reachable from the between-level menu
  (`BSaveWBetweenLevelMenu`), exactly as in the `.li`.

### 10.6 Dynamic widgets and per-level artwork

* `enu_10.lng` **creates** four radio buttons (`RDEU`, `RRUS`, `RFRA`, `RPTB`)
  that the base `.li` does not contain — and declares them as `TLabButton`
  although they are radios. The remake clones the existing
  `R<lang>WLanguage` radio (matched by name suffix), not the declared class,
  and stacks the copies on the 30 px pitch measured in
  `assets/Options-Language.png` (the first one keeps the `Top=32` of the
  `.li`, the glyph rows land on y = 176, 206, 236, 266, 296). The shipped original shows five times the
  first language name (the copies inherit its caption); the remake applies the
  captions from the language file instead.
* Language files are single-byte encoded (CP1251/CP1252). High bytes are
  escaped to numeric character references before parsing and mapped back to
  one codepoint per byte, because the bitmap atlases are indexed by byte
  value. `Arial12.xml` carries one metric table + atlas per charset
  (`EASTEUROPE` → `Arial12lat.png`, `RUSSIAN` → `Arial12cyr.png`).
* The hero portrait of the between-level screen is **not** a table in the
  executable: every level file carries `<HeroPicture name="…">`
  (level 1 `Elf1_2.png`, 2 `fairy.png`, 3 `shunter.png`, 4 `sova.png`,
  5 `elf.png`, 6 `Doggy.png`, 7 `centaur.png`, 8 `driada.png`, 9 `gnom.png`,
  10 `borovik.png`, 11 `harpy.png`, 12 `frog.png`, 13 `mag.png`,
  14 `satyr.png`, 15 `winder.png`, 16 `kalmar.png`, 17 `slon.png`).
  It is drawn at its native size at `LLevelHeroWBetweenLevelMenu`
  (125,20): the `.li` default `elf.png` is exactly the label size 120×360.
* The description tabs are `TLevel1…TLevel17` and belong to `Level1.txt…
  Level17.txt` (1 based; there is no `TLevel0` for the tutorial).

### 10.7 Multi-cell fishkas

`<FishkaProb>` may request pieces that cover several cells. Their names are
also the mask encoding, one digit group per occupied cell in row-major order
(`13_124_34` = up+down, up+right+left, down+left), and the shipped artwork
fixes where those cells sit:

| name | artwork | cells |
|------|---------|-------|
| `double1/2` | `123_134_1.png` (40×80) / `124_234_1.png` (80×40) | 1×2 / 2×1 |
| `tripl1/2` | `13_124_34_1.png` (80×80) | (0,0) (0,1) (1,1) |
| `tripl3` | `123_24_14_1.png` | (0,0) (1,0) (0,1) |
| `tripl4` | `12_234_13_1.png`, `23_24_134_1.png` | (0,0) (1,0) (1,1) / (1,0) (0,1) (1,1) |
| `adouble1/2` | `a123_134_1.png`, `a234_124_1.png` | 2×1 / 1×2 |
| `double1a/2a` | `124_234_1a.png`, `123_134_1a.png` | 2×1 / 1×2 |
| `skoba1/2` | `Skoba1.png`, `Skoba2.png` | closed ring, 2×1 / 1×2 |
| `skoba3/4` | `Skoba3.png`, `Skoba4.png` | arch opening up / right |

The executable stores the same grouping next to the `_Connects.dat` /
`_FishkasTypes.dat` names (`double2`+`double1` → `123_134`, `124_234`;
`tripl1`+`tripl2` → `13_124_34`; `adouble1`+`adouble2` → `a123_134`,
`a234_124`; `skoba1`+`skoba2`/`skoba3`/`skoba4`; `double1a`+`double2a` →
`124_234a`, `123_134a`). The cell masks above were additionally verified
pixel by pixel against the artwork (alpha at the cell borders).

Placement, rotation, the belt and the preview work on whole shapes in the
remake: all cells must be free and legal, the piece must touch the existing
pattern, the closed-loop test runs on the complete placement, every covered
cell scores and clears its ghost. The `skoba` mask interpretation is derived
from the artwork (the ring closes on itself) and is the one part that could
not be cross-checked against the binary.

### 10.8 Still open

* `FragPic4.png` (referenced by `<FragPicture>`) is **not** present in the
  archive; it is generated at runtime (most likely the rendered blueprint of
  the level's pattern shown in the panel, `LCombDoneWGame` "1 / 1" in
  `assets/Game-*.png`). The remake draws the first combination instead.
* Levels with `FlowerFall`/`Rain` and the moving `<Picture>` elements
  (`MovingCurve`) use the plain animation path only.
* Volume defaults are the measured capture state (music 60 %, sound 80 %,
  i.e. index 2 and 1) — the shipped `options.cfg` of the CD image was written
  by a different session (`SoundVolumeIdx=2`, `MusicVolumeIdx=3`).
