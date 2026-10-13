#!/usr/bin/env python3
"""
Determinism test for Spy vs Spy OME (framework/tools/determinism.py does the work).

    python tools/dettest.py [ticks] [humans=1|2] [level=1-8]

The test build (DETTEST) runs the game with ticks (src/main.s): one pass of the
main loop per tick, the clocks in ticks. humans=1: a bot as white against
the computer; humans=2 (the default): two bots. The runs differ in timing: PAL,
PAL with 0-3 whole frames of waiting per tick (as the network will), and NTSC.
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
    (0x0029, 0x0040, "the IRQ's work bytes (drawing, sound, music) and its screen half ($35)"),
    (0x0067, 0x0068, "the sound effect per spy (the IRQ plays and clears it; only sound reads it)"),
    (0x008B, 0x008C, "the flash per half (the IRQ counts it down; the game only sets it)"),
    (0x0100, 0x01FF, "stack"),
    (0x0258, 0x0259, "a blink counter of the IRQ"),
    (0x0263, 0x0281, "the music player's state (the IRQ, $954E)"),
    (0xC000, 0xC983, "our code and data (the test builds differ; spy_due)"),
    (0xFFFB, 0xFFFF, "RAM under the KERNAL's vectors: not in the packed image"),
]
RUNS = [("pal", [], ["-pal"]), ("pal_jitter", ["JITTER"], ["-pal"]), ("ntsc", [], ["-ntsc"])]

if __name__ == "__main__":
    ticks = int(next((a for a in sys.argv[1:] if a.isdigit()), 5000))
    humans = next((a.split("=")[1] for a in sys.argv[1:] if a.startswith("humans=")), None)
    level = next((a.split("=")[1] for a in sys.argv[1:] if a.startswith("level=")), None)
    defines = ["DETTEST"] + ([f"HUMANS={humans}"] if humans else []) + ([f"LEVEL={level}"] if level else [])
    ok = determinism.main(build.GAME, ticks, "spy_halt", defines, RUNS, IGNORE)
    sys.exit(0 if ok else 1)
