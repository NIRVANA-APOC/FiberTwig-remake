#!/usr/bin/env python3
"""Build the Windows distribution of the Fiber Twig remake (one self-contained .exe).

Why the extra steps
-------------------
The remake reads its art, audio, fonts and data *raw* at runtime
(`Image.load_from_file`, `FontFile.load_dynamic_font`, `FileAccess...`).
A normal Godot export replaces every imported resource (PNG/JPG/WAV/OGG/TTF)
with its imported form (`.ctex`, `.fontdata`, ...), which the game cannot read,
and it silently drops plain data files (`.dat`, `.li`, `.lng`, `.xml`, `.txt`)
because it classifies them as "TextFile".  This script therefore

  1. writes `res://assets/**` `.import` files with `importer="keep"`, so the
     pack ships the original bytes, and
  2. adds every asset extension to the preset's `include_filter`, so the plain
     data files are packed too,

exports, verifies that every asset really is inside the embedded pack with the
expected size, smoke-tests the finished executable, and restores the project
files afterwards.

Usage
-----
    python tools/build_windows.py                  # full build + smoke test
    python tools/build_windows.py --no-smoke       # export only
    python tools/build_windows.py --keep-imports   # leave the keep .import files
    python tools/build_windows.py --fetch-templates  # download the missing template
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import shutil
import subprocess
import sys
import time
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = os.path.join(ROOT, "remake")
OUT_DIR = os.path.join(ROOT, "build", "windows")
PRESET = "Windows Desktop"
APP = "FiberTwigRemake"
VERSION = "1.0.0"

# Extensions Godot would import (and therefore must be forced to keep as-is).
IMPORTABLE = {
    ".png", ".jpg", ".jpeg", ".webp", ".svg", ".bmp", ".tga", ".dds", ".ktx",
    ".exr", ".hdr", ".psd", ".wav", ".ogg", ".mp3", ".ttf", ".otf", ".woff",
    ".woff2", ".obj", ".gltf", ".glb", ".fbx", ".dae", ".blend",
}

README = """Fiber Twig Remake {version} - Windows (x86_64)
=================================================

A faithful, playable recreation of Puzzle Lab's 2004 puzzle game "Fiber Twig"
(RealArcade release), reverse-engineered from the original game files and
rebuilt with Godot 4.7.2.  See the repository's REVERSE_ENGINEERING.md for the
full analysis and MIDDLEWARE.md for what this build is.

This build is self-contained: the executable contains the game, its art, music
and all six localizations (English, German, French, Portuguese, Russian and
Simplified Chinese).  No installation is needed - just run the .exe.

Note: the executable is not code-signed, so Windows SmartScreen may show a
"Windows protected your PC" prompt the first time; choose "More info" ->
"Run anyway".

Requirements
------------
* Windows 10/11 (64-bit) and an OpenGL 3.3 capable GPU.
  The game uses Godot's Compatibility renderer (gl_compatibility).
  On very old drivers start it with:  {app}.exe --rendering-driver opengl3

Controls
--------
  LMB on a twig (belt, flying or placed)   pick it up / use the selected tool
  LMB on the play field                    place the held twig
  RMB                                      rotate the held twig 90 degrees
  RMB with a tool selected                 put the tool back
  1 ... 9                                  pick the n-th twig on the belt
  Space                                    pick the first belt twig
  Del                                      throw the held twig away
  LMB on the DROP SECTION area             drop the held twig
  LMB on the arrow in the drop panel       push a new twig onto the belt
  F3 / F4 (or the tool icons)              select the hammer / the amphora
  Esc                                      menu (pause)

Chinese interface
-----------------
Options -> Language -> 简体中文 -> OK.  The choice is remembered in
options.cfg; you can also start the game with:  {app}.exe -- --language=chs

Saved games and settings
------------------------
%APPDATA%\\Fiber Twig Remake\\  (options.cfg, saves\\, scores)

Credits and licence
-------------------
The original game and its assets are (c) 2004 Puzzle Lab / RealNetworks.
They are included here only as the subject of the reverse-engineering study
and the resulting non-commercial fan remake.
The Simplified Chinese captions are drawn with a subset of LXGW WenKai Screen
(霞鹜文楷屏幕阅读版) under the SIL Open Font License 1.1; see LICENSES\\.
Built with the Godot Engine 4.7.2 (MIT licence, https://godotengine.org).
"""

GODOT_LICENSE = """Godot Engine
Copyright (c) 2014-present Godot Engine contributors.
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""


def log(msg: str) -> None:
    print(f"[build] {msg}", flush=True)


def die(msg: str) -> None:
    print(f"[build] error: {msg}", file=sys.stderr, flush=True)
    raise SystemExit(1)


# --------------------------------------------------------------------------
# tool discovery


def find_godot(explicit: str | None) -> str:
    if explicit:
        if os.path.isfile(explicit):
            return explicit
        die(f"--godot {explicit}: not a file")
    tools = os.path.join(ROOT, "tools")
    candidates: list[str] = []
    if os.path.isdir(tools):
        if os.name == "nt":
            for f in sorted(os.listdir(tools)):
                if f.startswith("Godot_") and f.endswith("_console.exe"):
                    candidates.append(os.path.join(tools, f))
            for f in sorted(os.listdir(tools)):
                if f.startswith("Godot_") and f.endswith("win64.exe"):
                    candidates.append(os.path.join(tools, f))
        else:
            candidates.append(os.path.join(tools, "Godot_v4.7.2-stable_linux.x86_64"))
    for c in candidates:
        if os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    for c in ("godot4", "godot"):
        hit = shutil.which(c)
        if hit:
            return hit
    die("no Godot 4 executable found (put one in tools/ or pass --godot PATH)")


def engine_version(godot: str) -> str:
    out = subprocess.run([godot, "--version"], capture_output=True, text=True, timeout=120)
    text = (out.stdout + out.stderr).strip()
    if not text:
        die("could not determine the engine version (godot --version printed nothing)")
    # "4.7.2.stable.official.ed1daf0bf" -> "4.7.2.stable" (the template dir name)
    parts = text.split(".")
    if len(parts) < 4:
        die(f"unexpected engine version string: {text!r}")
    return ".".join(parts[:4])


def templates_dir() -> str:
    if os.name == "nt":
        base = os.path.join(os.environ.get("APPDATA", ""), "Godot")
    elif sys.platform == "darwin":
        base = os.path.expanduser("~/Library/Application Support/Godot")
    else:
        base = os.path.expanduser("~/.local/share/godot")
    return os.path.join(base, "export_templates")


def check_template(godot: str, version: str, fetch: bool) -> str:
    tdir = os.path.join(templates_dir(), version)
    template = os.path.join(tdir, "windows_release_x86_64.exe")
    if os.path.isfile(template):
        log(f"export template: {template}")
        return template
    if fetch:
        log("export template missing - downloading it from the Godot release (range requests)")
        fetch_script = os.path.join(ROOT, "tools", "fetch_export_templates.py")
        py = sys.executable
        subprocess.run(
            [py, fetch_script, "--version", version, "--dest", tdir,
             "windows_release_x86_64.exe", "windows_release_x86_64_console.exe", "version.txt"],
            check=True,
        )
        if os.path.isfile(template):
            log(f"export template: {template}")
            return template
    die(
        f"the Windows export template for {version} is missing:\n"
        f"    {template}\n"
        f"  install it with\n"
        f"    python tools/fetch_export_templates.py --version {version} \\\n"
        f"        --dest \"{tdir}\" windows_release_x86_64.exe windows_release_x86_64_console.exe version.txt\n"
        f"  (only ~105 MiB is downloaded, not the whole 1.2 GiB .tpz)"
    )


# --------------------------------------------------------------------------
# project files that the build changes and restores


def asset_files() -> list[str]:
    out = []
    base = os.path.join(PROJECT, "assets")
    for dirpath, _dirnames, filenames in os.walk(base):
        for fn in filenames:
            out.append(os.path.join(dirpath, fn))
    return sorted(out)


def include_filter() -> str:
    exts = set()
    for path in asset_files():
        ext = os.path.splitext(path)[1].lower()
        if ext and ext != ".import":
            exts.add(ext)
    return ",".join(f"*{e}" for e in sorted(exts))


def write_keep_imports() -> dict[str, str | None]:
    """Mark every importable asset as importer="keep"; return the previous state."""
    saved: dict[str, str | None] = {}
    count = 0
    for path in asset_files():
        if os.path.splitext(path)[1].lower() not in IMPORTABLE:
            continue
        imp = path + ".import"
        saved[imp] = open(imp, "r", encoding="utf-8").read() if os.path.isfile(imp) else None
        with open(imp, "w", encoding="utf-8", newline="\n") as fh:
            fh.write('[remap]\n\nimporter="keep"\n')
        count += 1
    log(f"keep imports: {count} asset file(s)")
    return saved


def restore(saved: dict[str, str | None]) -> None:
    for path, content in saved.items():
        if content is None:
            if os.path.isfile(path):
                os.remove(path)
        else:
            with open(path, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(content)


PRESET_TEMPLATE = """[preset.0]

name="{preset}"
platform="{preset}"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="{include}"
exclude_filter=""
export_path="build/windows/{app}.exe"
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=0
binary_format/embed_pck=true
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
binary_format/architecture="x86_64"
application/modify_resources=true
application/icon="res://icon.ico"
application/console_wrapper_icon=""
application/icon_interpolation=4
application/file_version="{version}.0"
application/product_version="{version}.0"
application/company_name="Fiber Twig Remake"
application/product_name="Fiber Twig Remake"
application/file_description="Reverse-engineered remake of Puzzle Lab's Fiber Twig (2004)"
application/copyright="Original game (c) 2004 Puzzle Lab / RealNetworks. Non-commercial fan remake."
application/trademarks=""
application/export_angle=0
application/export_d3d12=0
application/d3d12_agility_sdk_multiarch=false
ssh_remote_deploy/enabled=false
"""


def write_preset() -> str | None:
    path = os.path.join(PROJECT, "export_presets.cfg")
    saved = open(path, "r", encoding="utf-8").read() if os.path.isfile(path) else None
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(PRESET_TEMPLATE.format(preset=PRESET, app=APP, version=VERSION, include=include_filter()))
    log(f"export preset: {path} (include_filter={include_filter()})")
    return saved


# --------------------------------------------------------------------------
# running Godot


def run_godot(godot: str, args: list[str], capture: bool = True) -> str:
    cmd = [godot, "--headless", "--path", PROJECT] + args
    log("$ " + " ".join(f'"{c}"' if " " in c else c for c in cmd))
    out = subprocess.run(cmd, capture_output=capture, text=True, errors="replace")
    text = (out.stdout or "") + (out.stderr or "")
    errors = [ln for ln in text.splitlines() if ln.startswith("ERROR:") or ln.startswith("ERROR ")]
    if out.returncode != 0:
        print(text[-4000:])
        die(f"Godot exited with code {out.returncode}")
    if errors:
        log(f"{len(errors)} engine error line(s) during export:")
        for ln in errors[:20]:
            print("    " + ln)
    return text


# --------------------------------------------------------------------------
# verification


def load_pck_list():
    path = os.path.join(ROOT, "tools", "pck_list.py")
    spec = importlib.util.spec_from_file_location("pck_list", path)
    mod = importlib.util.module_from_spec(spec)  # type: ignore[arg-type]
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod


def verify_pack(exe: str) -> None:
    pck = load_pck_list()
    data = open(exe, "rb").read()
    start, embedded = pck.find_pack(data)
    if not embedded:
        die("the exported executable has no embedded pack")
    _version, _flags, entries = pck.parse(data, start)
    packed = {name: size for name, _pos, size, _eflags, _md5 in entries}

    missing, wrong = [], []
    for path in asset_files():
        rel = os.path.relpath(path, PROJECT).replace("\\", "/")
        if os.path.splitext(rel)[1].lower() == ".import":
            continue
        size = os.path.getsize(path)
        if rel not in packed:
            missing.append(rel)
        elif packed[rel] != size:
            wrong.append(f"{rel}: pack {packed[rel]} != source {size}")
    if missing or wrong:
        for m in missing[:40]:
            print("    missing: " + m)
        for w in wrong[:40]:
            print("    size:    " + w)
        die(f"embedded pack is incomplete ({len(missing)} missing, {len(wrong)} size mismatches)")
    assets = sum(1 for p in asset_files() if os.path.splitext(p)[1].lower() != ".import")
    log(f"pack verified: {assets} raw asset file(s), {len(entries)} entries, "
        f"{os.path.getsize(exe) / 1048576:.1f} MiB executable")


def smoke_test(exe: str) -> None:
    tests = [
        ["--wintest"],
        ["--testsound"],
        ["--langtest"],
        ["--helptest"],
        ["--closetest"],
        ["--piecetest"],
        ["--autotest=0"],
    ]
    for args in tests:
        cmd = [exe, "--headless", "--"] + args
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, errors="replace", timeout=300)
        except subprocess.TimeoutExpired:
            die(f"smoke test {' '.join(args)} timed out")
        text = (out.stdout or "") + (out.stderr or "")
        if "SCRIPT ERROR" in text:
            print("\n".join(ln for ln in text.splitlines() if "SCRIPT ERROR" in ln))
            die(f"smoke test {' '.join(args)} raised a script error")
        marks = [ln.strip() for ln in text.splitlines() if ln.strip().startswith("[")]
        log(f"{' '.join(args)}: " + (" | ".join(marks[:3]) if marks else "ok"))


# --------------------------------------------------------------------------
# packaging


def write_extra_files(dist: str) -> None:
    with open(os.path.join(dist, "README.txt"), "w", encoding="utf-8-sig", newline="\r\n") as fh:
        fh.write(README.format(app=APP, version=VERSION))
    lic = os.path.join(dist, "LICENSES")
    os.makedirs(lic, exist_ok=True)
    with open(os.path.join(lic, "Godot-MIT.txt"), "w", encoding="utf-8", newline="\r\n") as fh:
        fh.write(GODOT_LICENSE)
    for src, dst in [
        (os.path.join(PROJECT, "assets", "fonts", "OFL.txt"), "OFL-LXGWWenKaiScreen.txt"),
        (os.path.join(PROJECT, "assets", "fonts", "OFL-NotoSansSC.txt"), "OFL-NotoSansSC.txt"),
        (os.path.join(ROOT, "FiberTwig", "license.txt"), "OriginalGame-license.txt"),
    ]:
        if os.path.isfile(src):
            shutil.copyfile(src, os.path.join(lic, dst))
    log(f"wrote README.txt and LICENSES/ into {dist}")


def make_zip(dist: str, zip_path: str, top: str) -> None:
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for dirpath, _dirnames, filenames in os.walk(dist):
            for fn in filenames:
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, dist)
                zf.write(full, os.path.join(top, rel))
    log(f"zip: {zip_path} ({os.path.getsize(zip_path) / 1048576:.1f} MiB)")


# --------------------------------------------------------------------------


def main() -> int:
    global APP
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--godot", default=None, help="path to the Godot editor/console executable")
    ap.add_argument("--out", default=OUT_DIR, help="output directory for the executable")
    ap.add_argument("--name", default=APP, help="executable / application name")
    ap.add_argument("--no-smoke", action="store_true", help="skip running the exported game's tests")
    ap.add_argument("--no-zip", action="store_true", help="do not create the .zip archive")
    ap.add_argument("--keep-imports", action="store_true", help="leave the generated keep .import files in place")
    ap.add_argument("--fetch-templates", action="store_true", help="download the export template if missing")
    args = ap.parse_args()

    APP = args.name

    godot = find_godot(args.godot)
    version = engine_version(godot)
    log(f"engine: {godot} ({version})")
    check_template(godot, version, args.fetch_templates)

    exe = os.path.join(args.out, APP + ".exe")
    os.makedirs(args.out, exist_ok=True)
    if os.path.isfile(exe):
        os.remove(exe)

    saved_imports: dict[str, str | None] = {}
    saved_preset: str | None = None
    started = time.time()
    try:
        saved_preset = write_preset()
        saved_imports = write_keep_imports()
        run_godot(godot, ["--import"])
        run_godot(godot, ["--export-release", PRESET, os.path.abspath(exe)])
    finally:
        if saved_preset is not None:
            with open(os.path.join(PROJECT, "export_presets.cfg"), "w", encoding="utf-8", newline="\n") as fh:
                fh.write(saved_preset)
        elif os.path.isfile(os.path.join(PROJECT, "export_presets.cfg")):
            os.remove(os.path.join(PROJECT, "export_presets.cfg"))
        if not args.keep_imports:
            restore(saved_imports)
            log("restored the project's .import files")

    if not os.path.isfile(exe):
        die(f"export did not produce {exe}")
    log(f"exported: {exe} ({os.path.getsize(exe) / 1048576:.1f} MiB) in {time.time() - started:.0f}s")

    verify_pack(exe)
    if not args.no_smoke:
        smoke_test(exe)

    write_extra_files(args.out)
    if not args.no_zip:
        make_zip(args.out, os.path.join(os.path.dirname(args.out), f"{APP}-Windows-x86_64.zip"), APP)

    log("done")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[union-attr]
    raise SystemExit(main())
