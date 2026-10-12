#!/usr/bin/env python3
"""
Determinism test for Archon OME (framework/tools/determinism.py does the work).

    python tools/dettest.py [ticks] [humans=2]

The test build (DETTEST) runs the game with virtual frames (src/main.s): the
frame logic only runs in ticks. Without players the game plays its demo (the
computer on both sides, on the board and in the arena); humans=2: a two-player
game, a bot's random joysticks on both sides. The runs differ in
timing: PAL, PAL with 0-3 whole frames of waiting per tick (as the network
will), and NTSC.
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
    (0xC500, 0xCFFF, "our code and data (the test builds differ; arch_due)"),
    (0xFFFB, 0xFFFF, "RAM under the KERNAL's vectors: not in the packed image, never used"),
]
RUNS = [("pal", [], ["-pal"]), ("pal_jitter", ["JITTER"], ["-pal"]), ("ntsc", [], ["-ntsc"])]

if __name__ == "__main__":
    ticks = int(next((a for a in sys.argv[1:] if a.isdigit()), 5000))
    humans = next((a.split("=")[1] for a in sys.argv[1:] if a.startswith("humans=")), None)
    defines = ["DETTEST"] + ([f"HUMANS={humans}"] if humans else [])
    ok = determinism.main(build.GAME, ticks, "arch_halt", defines, RUNS, IGNORE)
    sys.exit(0 if ok else 1)
