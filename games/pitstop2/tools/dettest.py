#!/usr/bin/env python3
"""
Determinism test for Pitstop II OME (framework/tools/determinism.py does the work).

    python tools/dettest.py [ticks]

The race logic runs in the raster IRQ (every other frame); the main loop draws
both halves of the screen as fast as it can. A bot drives both cars; the runs
differ in timing: PAL, PAL with 0-39 raster lines of waiting per tick with
interrupts off (as the network will), and NTSC.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "framework", "tools"))
import build  # noqa: E402
import determinism  # noqa: E402  (framework/tools/determinism.py)

IGNORE = [
    (0x0000, 0x0001, "CPU port"),
    (0x0100, 0x01FF, "stack"),
    (0x9AB9, 0x9C71, "the test code"),
]
RUNS = [("pal", [], ["-pal"]), ("pal_jitter", ["JITTER"], ["-pal"]), ("ntsc", [], ["-ntsc"])]

if __name__ == "__main__":
    ticks = int(next((a for a in sys.argv[1:] if a.isdigit()), 1000))
    ok = determinism.main(build.GAME, ticks, "pit_halt", ["DETTEST"], RUNS, IGNORE)
    sys.exit(0 if ok else 1)
