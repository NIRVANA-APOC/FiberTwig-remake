# Fiber Twig remake — copy delivered to `gem:~/Documents/Games/FiberTwig/`

This copy exists so the remake can be debugged on the `gem` machine
(CachyOS, x86_64, 16 cores, X on `:0`/`:1`).  It contains everything needed to
run the game, run the headless tests and redo the pixel comparisons against
the original captures.

## What is here

| path | contents |
|---|---|
| `remake/` | the Godot 4 project (sources in `src/`, extracted assets, `docs/` screenshots) |
| `remake/assets/` | assets extracted from the original `.zxc` archives (sprites, `interface.json`, decrypted levels, `lng/`, `demo.dat`) |
| `assets/` | the original game's reference screenshots (`Game-1..6`, `Options`, `Help`, …) |
| `work/ref/` | those screenshots already cropped and resampled to the 800×600 client size — they are the ground truth for pixel diffs |
| `FiberTwig/` | the original 2004 installation (minus `temp/` and the intermediate `work/`) — `game.zxc`, `squares.zxc`, `levels/`, `lng/`, `demo.dat`, `FiberTwig.exe`, and the small Rust reverse-engineering crate with its uncommitted edits |
| `tools/` | `Godot_v4.7.2-stable_linux.x86_64`, the extraction/decryption scripts (`zxc.py`, `decrypt_levels.py`, `save_codec.py`, `build_ui_data.py`, `artmatch.py`) |
| `REVERSE_ENGINEERING.md` | the full analysis report (§10 is the 1:1 verification against the captures) |

Not copied: `.venv/`, `tools/godot.zip`, `FiberTwig/temp/` (older archives),
`FiberTwig/work/`, `work/extracted/`, `__pycache__`.

## Run it

```bash
cd ~/Documents/Games/FiberTwig
tools/Godot_v4.7.2-stable_linux.x86_64 --path remake                 # windowed
tools/Godot_v4.7.2-stable_linux.x86_64 --path remake --rendering-driver opengl3
```

Headless checks (no X needed):

```bash
G=tools/Godot_v4.7.2-stable_linux.x86_64
$G --headless --path remake -- --autotest=0      # greedy solver on level 1
$G --headless --path remake -- --autotest=6      # any level 0…17
$G --headless --path remake -- --wintest         # win condition
$G --headless --path remake -- --testsound       # all 16 WAVs load
$G --headless --path remake -- --closetest       # placement / lock rule checks
$G --headless --path remake -- --piecetest       # multi-cell piece bookkeeping
$G --headless --path remake -- --langtest        # all six localizations (incl. Chinese)
$G --headless --path remake -- --helptest       # every help topic switches the page
```

Debug flags for the screen flow (see `remake/README.md` for the full table):
`--screen=WTitle|WStartDialog|WOptions|WLanguage|WHelp|WLoad|WSave|WHighScores|WMenu|WBetweenLevelMenu|WGame`,
`--level=N`, `--complex` (generate multi-cell twigs only), `--shot=N`,
`--language=enu|deu|fra|ptb|rus|chs` (start in a language without writing
`options.cfg`; `chs` is the added Simplified Chinese localization).
`FT_DEBUG=1` prints the modal stack, the widget hit of every mouse press and
every `RunMethod` the interface triggers.

Screenshot / interaction loop on a headless machine:

```bash
Xvfb :99 -screen 0 1280x1024x24 &
export DISPLAY=:99
tools/Godot_v4.7.2-stable_linux.x86_64 --path remake -- --screen=WLoad &
sleep 9
# the window is centred on the root, so query its position instead of guessing
eval "$(xdotool search --name 'Fiber Twig' getwindowgeometry --shell | sed 's/^/WIN_/')"
import -window root /tmp/shot.png
convert /tmp/shot.png -crop 800x600+$WIN_X+$WIN_Y /tmp/shot800.png
xdotool mousemove $((WIN_X+500)) $((WIN_Y+445)) click 1   # design coords + window origin
```

The game requests a window at (240,212), so on a 1280×1024 root the design
coordinates `(x,y)` are `(x+240, y+212)`.  On a differently sized root (the
test box used a 1024×768 Xvfb, where the window landed at (112,84)) always
query the geometry first — a wrong offset shows up as a ≈9 % pixel error
instead of the ≈0.6…1 % the remake is at.

## Python tooling

`gem` has no `Pillow` in the system interpreter, so use a venv:

```bash
python3 -m venv .venv
.venv/bin/pip install Pillow numpy
```

Then, for example, the mean absolute difference of a fresh screenshot against
the original capture:

```bash
.venv/bin/python - <<'PY'
from PIL import Image
import numpy as np
a = np.array(Image.open('/tmp/shot800.png').convert('RGB')).astype(int)
b = np.array(Image.open('work/ref/Options.png').convert('RGB')).astype(int)
d = np.abs(a - b)
print('mean %.2f / 765 (%.2f %%)  max %d' % (d.mean(), d.mean()/765*100, d.max()))
PY
```

`work/ref/*.png` is the reference set (crop `(0,33,1000,783)` of the shipped
1000×783 captures, resampled 1.25× → 800×600).  §10.1 of the report explains
the geometry; §10.7 has the multi-cell twig table, §10.5 the dialog mechanics.

## Current state (2024-10-10)

* all 18 levels: `--autotest` clean (no script errors), see `remake/README.md`
* options/language dialogs, load/save grids, between-level hero pictures and
  the multi-cell twigs are implemented; the remaining known differences are
  listed at the end of `remake/README.md`
* mean per-pixel error against the reference captures: help 0.52 %, high
  scores 0.63 %, language 0.70 %, new game 0.81 %, options 0.84 %, title
  0.87 %, load game 1.09 %

## Updating this copy from the source machine

The source machine has no `rsync`, so the delivery used a single `tar | ssh`
stream.  Note that the archive members carry the `FiberTwig/` prefix, so the
exclude patterns must be relative to the parent directory:

```bash
cd /home/nirvana                     # parent of FiberTwig/
tar cf - --exclude=FiberTwig/.venv --exclude=FiberTwig/tools/godot.zip \
         --exclude=FiberTwig/tools/__pycache__ --exclude=FiberTwig/FiberTwig/temp \
         --exclude=FiberTwig/FiberTwig/work --exclude=FiberTwig/work/extracted \
         --exclude=FiberTwig/remake/.godot --exclude=__pycache__ --exclude="*.pyc" \
         FiberTwig | ssh gem "tar xf - -C Documents/Games"
```

Afterwards re-check with `sha256sum -c` (a manifest of the payload) as done for
this delivery.  On a host with `rsync` installed the same filter file works
with `rsync -a --delete` for an incremental sync.

## Delivery verification (2024-10-10, this copy)

* 621 files, 198 MiB payload; `sha256sum -c` of the manifest generated on the
  source machine: **all files match**, file count identical.
* Headless checks on this machine: `--wintest` reaches `WFinishLevelDialog`
  with one connected component, `--testsound` 16/16 WAVs, `--autotest=0`
  → 105 cells / 3 components, `--autotest=13` → 1065 cells / 47 components,
  `--autotest=0 --complex` → 220 cells; no `SCRIPT ERROR` in any run.
* Visual check under `Xvfb :99`: the title screen renders at a mean
  difference of 6.62/765 (0.87 %) and the language dialog at the same level as
  the source machine, i.e. the rendering is identical here.
* Installed into the venv: `Pillow 12.3.0`, `numpy`.
