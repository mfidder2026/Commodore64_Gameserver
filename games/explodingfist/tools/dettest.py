#!/usr/bin/env python3
"""
Determinism test for The Way of the Exploding Fist OME.

    python tools/dettest.py [ticks] [--keep]

A test build (DETTEST: a bot plays both fighters, the two-player match starts
at once) runs in several VICEs with different timing: PAL, NTSC, and PAL with
JITTER (a random wait every tick, as a network would cause). Each stops before
tick <ticks> (HALT_AT); then their RAM is compared. Lockstep needs the game
state to be identical; only the IRQ's display and sound may differ.
Differences are listed by address, so they can be traced to their code.
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "..", "..", "framework", "tools"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build  # noqa: E402
import determinism  # noqa: E402  (framework/tools/determinism.py)

# areas that only the display and sound use (written by the IRQ or rebuilt from the state each frame)
IGNORE = [
    (0x0000, 0x0001, "CPU port"),
    (0x0014, 0x002F, "IRQ: sprite positions, multiplexer, speech pointers; $24 drawing order (collision)"),
    (0x00F9, 0x00FE, "music driver pointers (IRQ)"),
    (0x0100, 0x01FF, "stack"),
    (0x0C80, 0x0CFF, "music driver variables (the music runs per frame in the IRQ, $09A5)"),
    (0x2600, 0x27FF, "raster handlers' self-modified raster lines (written by $2CF0-$2FDC)"),
    (0x2840, 0x2868, "raster handler's self-modified sprite pointers (written by $2FE4-$3022)"),
    (0xC040, 0xC93F, "fighter build buffers (sprite images)"),
    (0xCC00, 0xCFFF, "screen and sprite pointers"),
    (0xD000, 0xDFFF, "I/O area (RAM under it: sprites, unchanged)"),
    (0xF540, 0xFF3F, "our code and data (the test builds differ)"),
    (0xFFFE, 0xFFFF, "IRQ vector: the next raster handler"),
]
RUNS = [("pal", [], ["-pal"]), ("ntsc", [], ["-ntsc"]), ("pal_jitter", ["JITTER"], ["-pal"])]


def main() -> None:
    ticks = int(next((a for a in sys.argv[1:] if a.isdigit()), 2000))
    ok = determinism.main(build.GAME, ticks, "dt_halt", ["DETTEST"], RUNS, IGNORE)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
