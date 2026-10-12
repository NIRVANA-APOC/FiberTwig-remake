# MIDDLEWARE.md — what this project is, and the rules that keep it honest

This file records **why** this repository exists and **how** its three phases relate.
It is the one document a new contributor — human or AI — should read *before*
changing anything in `remake/`, because `remake/` is not the product: it is a
deliberately temporary bridge, and the rules below are what stop the next phase
from silently destroying the fidelity work it depends on.

The project's own statement of intent:

> 当前 remake 版本仅为中间件。由于原版游戏过于老旧以至于其无法使用现代化工具进行修改和扩展，
> 因此当前路线为：先使用现代化游戏引擎 Godot 尝试逆向 1:1 复刻原版游戏作为中间件 ->
> 将中间件作为固定参考，尝试借助 AI 自动化重构整个游戏，包括性能优化与扩展性玩法。
> 中间件的目的是架起重构的桥梁，其一定程度上是原版游戏的粗略复刻，另一方面由于有着现代化引擎
> 的加持，在代码阅读和重构方面有着巨大优势。

---

## 1. The problem

The game we are reproducing, **Fiber Twig** (Puzzle Lab, 2004, distributed by
RealNetworks/RealArcade), is a closed binary artifact with every property that
makes extension impractical:

| obstacle | reality |
|---|---|
| Language / toolchain | Borland **Delphi PE32** (`FiberTwig.exe`, 924 672 B, sha256 `f7a15e5e…2137`). No source, no build system, and the toolchain era is over. |
| Scripting layer | **None.** All gameplay is native code; there is no mod hook, no config script, no exposed data layer. |
| Resources | A home-made container format, `.zxc` (magic `12345`), with **no checksum field** and an entry table the engine reads through `TFileFolder`. |
| Levels | An in-house "Lab" XML dialect, and **levels 4–17 are encrypted** with a home-made 64-bit block cipher (`C = T(P ⊕ K8) ⊕ K8`, an 8×8 bit transpose) keyed from a serial string baked into the executable. Levels 0–3 ship in clear text. |
| UI | An in-house "Lab" widget framework driven by a binary-ish `.li` file, interpreted at run time. |

You cannot patch a level, add a mechanic or profile the game without first
recovering all of the above from shipped bytes. That recovery is what
`work/reveng/` contains, and it is the reason this repository exists.

---

## 2. The route: three ordered phases

### Phase 1 — Reverse-engineer and rebuild 1:1 in Godot ("the middleware") — **current phase**

Recover the formats, rules and content from the shipped artifacts, then rebuild the
game in **Godot 4.7.2** as `remake/`. The result is *not* the deliverable; it is a
working, readable, executable stand-in for a game whose source no longer exists.

### Phase 2 — Freeze the middleware, refactor from it with AI assistance

Treat `remake/` as a **FROZEN REFERENCE** and rebuild the game from it using
automated, AI-assisted refactoring. The refactor extracts structure
(architecture, data flow, module boundaries) from the middleware. It is explicitly
allowed to throw the middleware's structure away — but only after the extraction,
and only under the rules in §5.

### Phase 3 — Optimise and extend

On the rebuilt base: performance work and new gameplay. **This is the only phase
where deliberate divergence from the original is a feature rather than a defect**,
and even here it must be labelled (§5.1).

---

## 3. Why the middleware is the right bridge

Stated as properties, not as praise:

1. **It is source, in a live engine.** `remake/src/*.gd` is readable GDScript with
   comments that cite the recovered evidence (`FUN_…`, `DAT_…`, byte offsets,
   `file:line`). A refactor tool can parse, analyse and rewrite it. The original
   cannot be parsed by anything.
2. **It is executable, so behaviour is observable rather than guessed.** The
   middleware runs headless, and the shipped EXE runs natively on the development
   host (see §7.4) — so a discrepancy can be *measured* instead of argued about.
3. **It has an automated equivalence harness.** `--autotest=N`, `--wintest`,
   `--closetest`, `--piecetest`, `--langtest`, `--helptest` and friends load every
   level and exercise the rule set without a display. This is currently the **only**
   automated equivalence check in the project.
4. **It carries the recovered formats with it.** The `.zxc` reader, the level
   cipher and key derivation, the `.dat` table decoders and the level corpus all
   live in `remake/assets/` and `tools/`, so the refactor inherits working data
   access rather than rediscovering it.
5. **It is disposable.** It is a bridge, not a foundation. Once phase 2 has
   extracted the behaviour and the data model, the middleware's own structure may
   be discarded.

### 3.1 Honest limits — the middleware is a *rough* 1:1 in places

The user's own framing is "一定程度上是原版游戏的粗略复刻" — partly a rough
reproduction. That is accurate, and it matters for how the refactor uses it:

| dimension | authoritative source |
|---|---|
| **Data formats** (`.zxc`, level XML, `.dat` tables, `.lng`, saves, `demo.dat`) | the **middleware** — the formats are recovered, documented and byte-verified |
| **Rule structure** (what is a joint, what a placement is, what a win is, how the belt generates, how scoring/bonuses are structured) | the **middleware** — the rule skeleton is faithfully reconstructed |
| **Exact pixel and parameter fidelity** (effect parameters, some UI paths, exact timings) | the **ORIGINAL** — see the split below |

#### What is recovered and implemented

These were previously approximated or unimplemented, and are now derived from the
original and implemented in the middleware:

| item | evidence |
|---|---|
| `<MovingCurve>` / `<MapMovingCurve>` motion (45 + 1 records) | `A5_EFFECTS_RE.md` §1–§3, §6; implemented at `remake/src/BoardWorld.gd:121` (`_curve_offset`) |
| `<FireEffect>` (16 records) and the SparkClone emitters, incl. FlowerFall | `A5_EFFECTS_RE.md` §9, §9.3; `remake/src/EffectEmitters.gd` |
| `<PutFishka>` coordinate rule (Level13, 6 twigs) | `A5_EFFECTS_RE.md` §8 |
| `<MakeGhostRect>` (Level15) | `work/reveng/IMPLEMENTATION_NOTES.md` |
| `<LevelEffect name="RoundBlicks">` `Roundangle` as an angular step | `A5_EFFECTS_RE.md` §10.1–§10.2 |

These are **not** to be treated as proven equivalence, though: `A5_EFFECTS_RE.md`
§4 states plainly that the exact algebraic form of the curve was **not** isolated,
that the `al` vs `ga` role assignment rests on a numeric best-fit rather than an
observed instruction sequence, and that the engine may add an easing layer beyond
`la`/`lb`. The middleware implements the recommended two-axis sinusoid with linear
ramp and exposes the ambiguity as a constant so it can be flipped in one place.
Several further interpretation choices are marked `[CHOICE]` rather than proven in
`A5_EFFECTS_RE.md` — among them `ga` as cosine amplitude, the `runeary` override,
`SparkLongYEffect` as a 2× stretch, `SparkSX`/`SparkSY` as jitter, `followpic` as a
tracked picture, `Roundar`/`Roundbr` as semi-axes, and the rain particle-count
derivation. **A recovered formula is an improvement on an approximation, not a
licence to stop comparing against the original.**

#### What is still a genuine limit

* **Known approximations / omissions**: the run-time `<FragPic4>` blueprint is still
  **not generated** — the panel mini-map substitutes the first combination (§6,
  `DIFF-S8-005`); parts of the rain/particle parameterisation remain local choices.
* **Unresolved in the ledgers**: the spark **mover** (SparkAngle semantics,
  `SparkRandomAngle`'s RNG call, the `GravX`/`GravY` integration, and the unit of
  `SparkVec`), whether `RoundBlicks` instantiates concurrently or in a cycle, the
  full `<MoveSin>` semantics, the `t` slot and the meaning of `be` for
  `<MapMovingCurve>`.
* **One intentional gameplay divergence**: the belt runs at 2× the original speed
  (§5.1). See §6 for the full difference ledger.

**Do not treat a middleware value as the specification for an effect parameter.**
Where the two disagree, the original wins — see §4.

Since the content-restoration work landed, the middleware's own `--contenttest`
**asserts** the restored content (it reports the `<PutFishka>` placements accepted
and the `<MakeGhostRect>` conversions), so these particular items can be *checked*
rather than trusted. That covers content presence, not parameter equivalence.

---

## 4. Authority hierarchy — read this before deciding anything

Ordered, highest authority first:

| # | authority | what it is | how to cite it |
|---|---|---|---|
| **1** | **Shipped original artifacts** | `FiberTwig/` — the EXE, `bass.dll`, the four `.zxc` archives, `demo.dat`, `saves/`, `lng/`, `options.cfg`, `launch.ini`. Also the live capture of the running EXE. | byte offsets, addresses, `FiberTwig/<path>`, sha256 |
| **2** | **Recovered ledgers** | `work/reveng/A1_NATIVE_LEDGER.md` + `A1b_FOLLOWUP.md` (executable), `A2_DATA_LEDGER.md` (formats/content, incl. localisation in §9), `A3_REMAKE_MAP.md` (middleware map), plus `LEAD_CROSSCHECK.md` and `lead/LIVE_EVIDENCE.md` | ledger + section (`A1 §3.3`, `A2 §4`, `LEAD_CROSSCHECK L5`) |
| **3** | **The middleware code** | `remake/` — one *implementation* of the ledgers' conclusions | `remake/src/<file>.gd:<line>` |
| **4** | **Anything produced in the refactor phase** | phase-2/3 code, designs, generated structures | your own references |

### 4.1 How to resolve a disagreement

* **Middleware code vs a ledger → the ledger's evidence decides.** The code is a
  single implementation and can be wrong; the ledger records what the artifact
  actually does, with addresses. Fix the code or record the divergence — never
  "adjust" the ledger to match the code.
* **Ledger vs the artifact → the artifact wins, and the ledger gets corrected.**
  If you can read the original, read it.
* **A ledger item marked `UNRESOLVED` / `PARTIAL` / `NEEDS-EVIDENCE` → the
  discrepancy stays recorded. Do not average it away, do not quietly pick the
  middleware's value, and do not upgrade an inferred statement to observed.**
  The specific unresolved items are collected in `work/reveng/DIFF_REPORT.md` §6
  (24 residual unknowns) and in the trailing unknown sections of each ledger —
  `A1_NATIVE_LEDGER.md` §14, `A2_DATA_LEDGER.md` §14, `A1b_FOLLOWUP.md` U2.6/U4.7/U5,
  and `A3_REMAKE_MAP.md` §23.
* **Two ledgers disagreeing → investigate; do not split the difference.** This has
  already happened three times in this project and each time the resolution was a
  correction, not a compromise (see `DIFF_REPORT.md` §5, 50 corrections).

---

## 5. Rules for the refactor phase (phase 2) and beyond

### 5.1 Never "improve" gameplay while claiming fidelity

If the refactor changes a rule — a win condition, a scoring term, a spawn rate —
that change belongs to **phase 3** and must be:

1. labelled as an **intentional divergence** in code and in the difference ledger, and
2. justified against the original's actual behaviour, so a reader can tell
   *"we chose differently"* from *"we failed to reproduce it"*.

The middleware already sets this precedent: the belt runs at **2×** the original
speed as a deliberate playability choice, marked `FIXED-IN-REMAKE` in
`DIFF_REPORT.md` (`DIFF-S7-001`), with `--beltspeed=25` available to restore the
original rate. Follow that pattern exactly.

### 5.2 Keep the formats and the corpus byte-compatible

The regression oracle is:

* the **same 18 levels** (`remake/assets/levels/Level0.txt … Level17.txt`), and
* the **same `demo.dat`** recording.

A refactor that changes a level file, re-encodes an archive, or drops a data table
destroys the only cross-check the project has. Any format change must be additive
and must keep a reader for the original encoding. §7.2 shows how to verify the
corpus in one command.

### 5.3 Keep the headless harness green

The headless tests are the **only automated equivalence check**. A refactor that
cannot run `--autotest` / `--wintest` on all 18 levels has no evidence that it
still implements the same game. Treat a regression there as a build break.

Note the harness's own limits (§6.1): the tests report *geometry*, and several
self-reported numbers are not trustworthy on their own.

### 5.4 Preserve the difference ledger

`work/reveng/DIFF_REPORT.md` and `work/reveng/evidence/A4_diff_index.json` are the
**fidelity baseline**: 90 differences, 24 residual unknowns, 50 corrections, each
row citing both sides and carrying a severity, status and confidence. The refactor
should *consume* it — not delete differences because they look untidy, and not
close a row without new evidence. A refactor that reports "no differences" while
the ledger lists a BLOCKER has lost the plot.

---

## 6. What the middleware does and does not deliver

The authoritative list is `work/reveng/DIFF_REPORT.md`. The headline items a
refactor must not be surprised by:

| id | severity | what |
|---|---|---|
| `DIFF-S6-001` | **BLOCKER** | The engine's win test is only "no open joint remains" (no top-row test, ghosts skipped); the middleware additionally requires **every transparent target to be covered**. The middleware is *stricter* than the original. |
| `DIFF-S3-001`, `DIFF-S15-002` | HIGH | Level-scoped content loss: Level13 loses 6 `<PutFishka>` pre-placements; Level11/15 lose `<FireEffect>`; Level15 loses `<MakeGhostRect>`; Level14 loses `FlowerFall`; all 18 lose the run-time `FragPic4` blueprint. |
| `DIFF-S5-001` | HIGH | The engine's `ClosedLink` refusal predicate was only partly recovered, so the middleware's loop rule is a model, not a reproduction. |
| `DIFF-S12-001`, `DIFF-S13-001` | HIGH | Volume indices are **1-based** in the engine and 0-based in the middleware, in the *same* `options.cfg` keys; the save encoder has **two** byte offsets in the engine and one in the middleware (they agree only on bytes in `0x20…0xCC`). |
| `DIFF-S7-001` | MEDIUM | Belt speed 2× (intentional, `FIXED-IN-REMAKE`). |

### 6.1 Middleware quirks a refactor will trip over

These are properties of the *middleware*, not of the original:

1. **The `[level] … fishkas=N` diagnostic over-reports by exactly one** on all 18
   levels. It is a **Godot 4.7.2 `XMLParser` artefact** — the parser re-reports the
   final element once when an unclosed root ends with a bare CRLF, which is the
   shape of every level file. The file count is right; the *printed* count is wrong
   by one, and the board is unaffected (`DIFF-S3-008`).
2. **Window size quirk.** The project declares an 800×600 canvas
   (`remake/project.godot`), but on the Windows embedder the window opens at
   640×480 and shows the **top-left crop** of the canvas rather than scaling it.
   `--resolution 800x600` does not work on that embedder; `--screen=<name>` does.
   Any pixel comparison must therefore compare **crop-to-crop** at the window's own
   size (0.79 % error on the title screen) rather than upscaling (7.2 % — a
   measurement artefact, see `LEAD_CROSSCHECK` L6.1).
3. **The self-tests are non-deterministic.** `--autotest` uses unseeded randomness,
   so identical invocations report different scores with identical geometry. Six
   runs of `--autotest=0` gave 5930 / 17230 / 18230 / 21030 / 28930 with the same
   `cells=544 components=2`. **Use counts and geometry as evidence; never a score.**
4. **`--capture` cannot run under `--headless`** (null viewport texture), so the
   documented pixel-diff table is not reproducible that way — take a windowed
   screenshot instead.
5. **The shipped EXE opens `temp\*.zxc`, not `Game\*.zxc` / `levels\*.zxc`.** The
   `.zxc` archives come in two builds: a **full** build
   (`temp/squares.zxc`, 340 entries, includes 68 `.pNg` animation frames) and a
   **download** build (`levels/squares.zxc`, 319 entries, with 94 lossy `._PNG` /
   `._JPG` twins and the frames removed). The corpus in `remake/assets/` is the
   **full** build. The 18 level plaintexts are byte-identical in both builds
   (verified, §7.2) — but the *art* is not, so state which build you are comparing
   against.
6. **A green test suite is not evidence of visual equivalence.** The headless harness
   verifies **structure and presence** — that content parses, that mechanics are bound,
   that levels match the shipped element counts — and it verifies at least one
   **property of output** (`--contenttest`'s rain-spread assertion). It does **not**
   verify appearance, density, timing or parameter fidelity.

   A concrete instance: an early `<RainEffect>` implementation computed the correct
   particle count (120 in flight for `MidRain`) but drew **every particle at the same
   `x`**, so the screen showed a single moving vertical streak instead of rain. It
   passed all 18 level-oracle matches, every test flag **and** `--contenttest`. Only a
   human looking at the running build caught it
   (`work/reveng/IMPLEMENTATION_NOTES.md` §4.1).

   **Why it escaped — the reason is about the harness, not about the layer being
   beyond isolation.** The harness makes **static, structural** assertions, and it runs
   without rendering, so a defect whose signature is **temporal** is invisible to it.
   That is not a claim that rain cannot be separated from the rest of the scene: rain
   and the drifting clouds differ by about **21×** in rate (clouds peak at 14.0 px/s in
   X and 24.0 px/s in Y; `MidRain` runs at 500 px/s, `SmRain` at 300 px/s) *and* by a
   large dwell-time difference — at 60 fps a cloud moves 0.233–0.400 px per frame
   (sub-pixel, so per-pixel intensity changes gradually) while a rain streak crosses a
   pixel at 8.33 px/frame (`MidRain`) or 5.00 (`SmRain`), which is impulse-like.
   A **temporal** detector could separate them; a static or frame-averaged one cannot.
   The gap is a missing capability of the suite, and a missing capability is fixable —
   which is exactly why the next sentence matters.

   **Treat the suite as a regression net for structure, and the reference captures
   (`work/ref/`, `assets/`) plus the original itself as the authority for appearance.**
   When you add an output-producing feature, extend `--contenttest` with an assertion on
   a **property of the output** rather than assuming the existing flags cover it — that
   is where the rain-spread check now lives (`error if the columns collapse below 5`),
   and it is the reason the collapse cannot silently return. An assertion that samples
   the output **over successive frames** is what a temporal property needs; a
   single-frame presence check cannot substitute for it.

---

## 7. Where things live, and how to check fidelity

### 7.1 Layout

| path | what it is |
|---|---|
| `FiberTwig/` | the **shipped original**: `FiberTwig.exe`, `bass.dll`, `Game/game.zxc`, `levels/squares.zxc`, `temp/{game,squares}.zxc`, `demo.dat`, `saves/`, `lng/`, `options.cfg`, `launch.ini`. Authority level 1. |
| `remake/` | the **middleware**: Godot 4.7.2 project. `src/` (GDScript), `assets/` (extracted corpus), `docs/` (screen captures), `README.md` (its own known-differences list). |
| `work/reveng/` | the **ledgers and evidence**: `A1_NATIVE_LEDGER.md`, `A1b_FOLLOWUP.md`, `A2_DATA_LEDGER.md`, `A3_REMAKE_MAP.md`, `DIFF_REPORT.md`, `evidence/` (machine-readable extractions), `lead/` (cross-checks and the live-oracle notes), `scratch/` (the scripts that produced everything). Further ledgers may appear as work continues; treat whatever is present as authority level 2. |
| `tools/` | extraction and codec helpers: `zxc.py` (archive reader/writer), `decrypt_levels.py` (level cipher), `save_codec.py` (save files), `artmatch.py`, `build_ui_data.py`, plus the Godot binaries. |
| `work/ref/` + `assets/` | **validated reference captures**. `work/ref/*.png` are 800×600 client-area crops; they match a live capture of the running original to **1.15 %** mean error, so they are trustworthy ground truth. |
| `REVERSE_ENGINEERING.md`, `INTERACTION_LOGIC.md` | the early analysis documents. Useful background, but they contain statements corrected by the ledgers — treat `DIFF_REPORT.md` §5 as the errata list. |
| `SETUP.md`, `WINDOWS.md`, `start.cmd`, `play.sh` | how to run the middleware and the headless tests on each host. |

### 7.2 Verify the corpus (one command)

```bat
python work\reveng\scratch\a7\corpus_verify.py
```

It re-extracts both `squares.zxc` builds with its own reader, re-derives the level
key from the serial string, checks the cipher is its own inverse, decrypts all 18
levels and compares them byte-for-byte with `remake/assets/levels/`. Expected
result: **plaintext 4 / encrypted 14 in each build, 0 mismatches, 0 drift**. The
last run also confirmed `remake/assets/squares` is byte-identical (340/340 files)
to `work/extracted/squares` and to the **full** build. A non-zero drift count is a
corpus break: stop and fix it before refactoring.

To redo the extraction from scratch without touching `tools/`:

```bat
python tools\zxc.py extract FiberTwig\temp\squares.zxc work\squares
python tools\decrypt_levels.py work\squares work\levels
python tools\save_codec.py decode FiberTwig\saves\LEVEL_01.sav
```

### 7.3 Run the middleware and its equivalence harness

```bat
tools\Godot_v4.7.2-stable_win64_console.exe --headless --path remake -- --autotest=0
tools\Godot_v4.7.2-stable_win64_console.exe --headless --path remake -- --wintest
tools\Godot_v4.7.2-stable_win64_console.exe --headless --path remake -- --closetest
tools\Godot_v4.7.2-stable_win64_console.exe --headless --path remake -- --piecetest
tools\Godot_v4.7.2-stable_win64_console.exe --headless --path remake -- --langtest
tools\Godot_v4.7.2-stable_win64_console.exe --headless --path remake -- --helptest
```

Run `--autotest=N` for N = 0…17 to cover the whole corpus. Judge the result on
**counts and geometry** (`cells=`, `components=`, `ghosts_total=`, `top=`), never on
`score=` (§6.1.3). Windowed runs take the same flags after `--`.

### 7.4 Compare against the running original (ground truth)

The shipped `FiberTwig.exe` **runs natively on the development host** — no Wine
required. Its client area is exactly **800×600**. Note that the process's
`MainWindowHandle` is a degenerate 0×0 window: enumerate the process's windows and
select the one whose client rect is 800×600 (`class='T'`). Capture it with
`PrintWindow(…, PW_RENDERFULLCONTENT)` and compare against a windowed middleware
screenshot **at the same size**.

Working scripts and the captured frames are in `work/reveng/lead/`
(`capture3.ps1`, `snap.ps1`, `snap_all.ps1`, `orig_pw_flag3.png`, `shot_*.png`),
with provenance and measured agreement in
`work/reveng/lead/CAPTURE_INVENTORY.md`.

---

## 8. One-paragraph summary

The original is unmodifiable; the middleware is a readable, executable, testable
reproduction of it built so that a refactor — largely automated — has something
precise to work from instead of a binary. The middleware is authoritative for
**formats and rule structure** and explicitly *not* authoritative for exact
pixel/parameter fidelity, where the **shipped original** remains the only source
of truth. Above the middleware sit the recovered ledgers, and above everything sits
the artifact itself; when they disagree the evidence decides, and an unresolved
question stays recorded rather than being smoothed over. The refactor may replace
the middleware's structure entirely, but it must keep the level corpus and formats
byte-compatible, keep the headless harness green, and keep
`work/reveng/DIFF_REPORT.md` as the fidelity baseline.
