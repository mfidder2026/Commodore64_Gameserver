#!/usr/bin/env python3
"""
Determinism test for M.U.L.E. OME (framework/tools/determinism.py does the work).

    python tools/dettest.py [ticks] [humans=N]

The test build (DETTEST) runs the game with virtual frames (src/main.s): the
frame logic only runs in ticks. Players 0 .. N-1 are human (default 4), with a
bot's random inputs; the rest are the computer's. The runs differ in timing: PAL, PAL with 0-3 whole frames of
waiting per tick (as the network will), and NTSC. The halt comes at a different
raster position in each run, so the display IRQ's own state is ignored.
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
    (0x001C, 0x001D, "raster IRQ handlers ($8993, $89EE, ...): their saved A and Y"),
    (0x0029, 0x0029, "raster IRQ: the step of the screen split"),
    (0x0100, 0x01FF, "stack"),
    (0x60F3, 0x617C, "the test builds' bot (JITTER differs)"),
    (0xCC00, 0xCDFF, "our tick code and data (mule_due)"),
]
RUNS = [("pal", [], ["-pal"]), ("pal_jitter", ["JITTER"], ["-pal"]), ("ntsc", [], ["-ntsc"])]

if __name__ == "__main__":
    ticks = int(next((a for a in sys.argv[1:] if a.isdigit()), 3000))
    humans = next((a.split("=")[1] for a in sys.argv[1:] if a.startswith("humans=")), "4")
    ok = determinism.main(build.GAME, ticks, "mule_halt", ["DETTEST", f"HUMANS={humans}"], RUNS, IGNORE)
    sys.exit(0 if ok else 1)
