#!/usr/bin/env python3
"""
Build script for The Way of the Exploding Fist OME.

There is no source code of the game: the base is the RAM image the original
loader leaves when it jumps into the game (orig/fist-1158.bin, made by
tools/snapshot.py from the clean disk). Our changes are patches, assembled
with ca65 from src/*.s: every segment named P_xxxx is placed at $xxxx. The
build checks that patches only touch the areas declared in src/areas.json.

    python tools/build.py              build/fist-raw.prg (the patched image) and build/fist.prg (packed)
    python tools/build.py disk         build/fist.d64: the standard lobby + the game files
    python tools/build.py testdisk     build/fist-test.d64: the same with a test bot (tools/nettest.py)
    python tools/build.py run          build and start the game in VICE (local game, no network)

Tools: framework/tools/c64env.py.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.normpath(os.path.join(ROOT, "..", ".."))
BUILD = os.path.join(ROOT, "build")
SRC = os.path.join(ROOT, "src")
sys.path.insert(0, os.path.join(REPO, "framework", "tools"))
import c64env  # noqa: E402

SNAPSHOT = os.path.join(ROOT, "orig", "fist-1158.bin")
IMAGE_START, IMAGE_END = 0x0400, 0xFFFB  # what the framework packer takes ($0400-$FFFA)


def run(cmd: list[str], cwd: str = BUILD) -> None:
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout + r.stderr)
        sys.exit(f"failed: {' '.join(cmd)}")


def snapshot() -> bytearray:
    with open(SNAPSHOT, "rb") as f:
        ram = f.read()
    with open(SNAPSHOT.replace(".bin", ".json")) as f:
        expected = json.load(f)["sha256"]
    if hashlib.sha256(ram).hexdigest() != expected:
        sys.exit("orig/fist-1158.bin is not the expected image (run tools/snapshot.py, check the disk)")
    return bytearray(ram)


NET_SRC = os.path.join(REPO, "framework", "c64", "net", "net.s")


def load_areas() -> list[dict]:
    with open(os.path.join(SRC, "areas.json"), encoding="utf-8") as f:
        return json.load(f)


def assemble(defines: list[str]) -> dict[int, int]:
    """Assembles src/main.s and the framework's net.s, links them twice (fill $00 and $FF):
    the bytes that agree are the patch bytes. Segments P_xxxx go to $xxxx; named segments
    to the start of their area in src/areas.json (in the listed order)."""
    placed = []  # (address or None for "after the previous", name)
    for name in os.listdir(SRC):
        if name.endswith((".s", ".inc")):
            with open(os.path.join(SRC, name), encoding="utf-8") as f:
                for a in re.findall(r'\.segment\s+"P_([0-9A-Fa-f]{4})"', f.read()):
                    placed.append((int(a, 16), f"P_{a.upper()}"))
    groups = []
    for area in load_areas():
        if area.get("segments"):
            groups.append((int(area["start"], 16), area["segments"]))
    order = sorted(set(placed), key=lambda p: p[0])
    for addr, names in groups:
        i = next((k for k, p in enumerate(order) if p[0] > addr), len(order))
        order[i:i] = [(addr, names[0])] + [(None, n) for n in names[1:]]
    dargs = sum((["-D", d] for d in defines), [])
    common = [c64env.cc65("ca65"), "--cpu", "6502", "-g", "-I", SRC, "--bin-include-dir", BUILD, *dargs]
    run([*common, "-o", "main.o", "-l", "main.lst", os.path.join(SRC, "main.s")])
    run([*common, "-o", "net.o", "-l", "net.lst", NET_SRC])
    images = []
    for fill in (0x00, 0xFF):
        cfg = os.path.join(BUILD, f"patch{fill:02x}.cfg")
        with open(cfg, "w") as f:
            f.write(f"MEMORY {{ RAM: start = $0000, size = $10000, file = %O, fill = yes, fillval = ${fill:02X}; }}\n")
            f.write("SEGMENTS {\n")
            for addr, name in order:
                where = f", start = ${addr:04X}" if addr is not None else ""
                f.write(f"  {name}: load = RAM, type = rw{where};\n")
            f.write("}\n")
        out = os.path.join(BUILD, f"patch{fill:02x}.bin")
        run([c64env.cc65("ld65"), "-C", cfg, "-o", out, "-m", "main.map", "-Ln", "main.lbl", "main.o", "net.o"])
        with open(out, "rb") as f:
            images.append(f.read())
    a, b = images
    return {i: a[i] for i in range(0x10000) if a[i] == b[i]}


def check_areas(patch: dict[int, int]) -> None:
    areas = [(int(a["start"], 16), int(a["end"], 16), a["what"]) for a in load_areas()]
    bad = sorted(a for a in patch if not any(s <= a <= e for s, e, _ in areas))
    if bad:
        sys.exit(f"patch outside src/areas.json at ${bad[0]:04X} ({len(bad)} bytes)")


def read_labels() -> dict[str, int]:
    """Labels of the last build (ld65 -Ln, all labels thanks to ca65 -g)."""
    labels = {}
    with open(os.path.join(BUILD, "main.lbl")) as f:
        for line in f:
            p = line.split()
            if len(p) == 3:
                labels[p[2].lstrip(".")] = int(p[1], 16)
    return labels


def build(defines: list[str] | None = None, name: str = "fist") -> str:
    os.makedirs(BUILD, exist_ok=True)
    ram = snapshot()
    with open(os.path.join(BUILD, "low.bin"), "wb") as f:  # included by src/main.s
        f.write(ram[0:0x400])
    patch = assemble(defines or [])
    check_areas(patch)
    for a, v in patch.items():
        ram[a] = v
    raw = os.path.join(BUILD, f"{name}-raw.prg")
    with open(raw, "wb") as f:
        f.write(bytes([IMAGE_START & 0xFF, IMAGE_START >> 8]) + ram[IMAGE_START:IMAGE_END])
    labels = read_labels()
    entry = labels.get("fist_entry", 0x1158)
    sys.path.insert(0, os.path.join(REPO, "framework", "c64", "packer"))
    import pack  # noqa: E402
    out = os.path.join(BUILD, f"{name}.prg")
    pack.pack(raw, out, entry, labels["net_hb"])
    used = max(a for a in patch if a >= 0xF540) - 0xF540 + 1 if any(a >= 0xF540 for a in patch) else 0
    print(f"{name}: {len(patch)} patched bytes, entry ${entry:04X}, new code {used} of 2560 bytes ($F540-$FF3F)")
    return out


LOBBY_SRC = os.path.join(REPO, "framework", "c64", "lobby")
DRIVERS = [("NET_UCI", "fistu"), ("NET_WIC", "fistw"), ("NET_RR", "fistr")]


def lobby() -> str:
    """The framework's lobby with this game's lobby/game.h: build/lobby.prg"""
    files = [os.path.join(LOBBY_SRC, f) for f in ("main.c", "net.c", "rrnet.s", "uci.s", "wic64.s", "loader.s")]
    run([c64env.cc65("cl65"), "-t", "c64", "-O", "-I", os.path.join(ROOT, "lobby"), "-o", "lobby.prg",
         "-m", "lobby.map", *files])
    return os.path.join(BUILD, "lobby.prg")


def disk(test: bool = False) -> str:
    """build/fist.d64: the lobby (first file, "fist") and the game per network type.
    test=True: build/fist-test.d64, game files with NETBOT (a bot plays when the lobby's cfg says bot=1)."""
    os.makedirs(BUILD, exist_ok=True)
    files = [(lobby(), "fist")]
    for define, name in DRIVERS:
        extra = ["NETBOT"] if test else []
        files.append((build([define, *extra], name=name + ("-test" if test else "")), name))
    d64 = os.path.join(BUILD, "fist-test.d64" if test else "fist.d64")
    args = [c64env.vice("c1541"), "-format", "fist ome,ef", "d64", d64]
    for prg, name in files:
        args += ["-write", prg, name]
    run(args)
    print(f"built {os.path.relpath(d64, ROOT)}")
    return d64


def run_vice(prg: str) -> None:
    subprocess.Popen([c64env.vice("x64sc"), "-pal", "+drive8truedrive", "-virtualdev8", "-autostart", prg])


if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    if action == "disk":
        disk()
    elif action == "testdisk":
        disk(test=True)
    else:
        prg = build()
        if action == "run":
            run_vice(prg)
