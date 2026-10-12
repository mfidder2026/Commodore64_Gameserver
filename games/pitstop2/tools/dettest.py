#!/usr/bin/env python3
"""
Determinism test for Pitstop II OME (framework/tools/determinism.py does the work).

    python tools/dettest.py [ticks]

The race logic runs in logic slots from the main loop (src/main.s, pit_pass);
the raster IRQ only draws. A bot drives both cars; the runs differ in timing:
PAL, PAL with 0-3 whole frames of waiting per tick (as the network will), and
NTSC. The halt comes at a different raster position in each run, so the
display IRQ's own state is ignored.
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
    (0x0010, 0x0010, "display IRQ: raster offset of the current half"),
    (0x0015, 0x0018, "display IRQ: line counter, the half's car ($16/$17), next raster line"),
    (0x001D, 0x0022, "IRQ: saved registers, $22 (handler $3ECD)"),
    (0x00E4, 0x00E4, "our frame counter (pit_due)"),
    (0x00F0, 0x00F0, "sprite multiplexer ($7C8E, IRQ only)"),
    (0x0100, 0x01FF, "stack"),
    (0x6200, 0x6204, "sprite drawing temporaries ($4821, IRQ only)"),
    (0x6207, 0x6207, "sprite drawing temporary ($4821, IRQ only)"),
    (0x9C87, 0x9FFF, "our code and data (the test builds differ)"),
    (0xC3F8, 0xC3FF, "sprite pointers (display)"),
    (0xC7F8, 0xC7FF, "sprite pointers (display)"),
]
RUNS = [("pal", [], ["-pal"]), ("pal_jitter", ["JITTER"], ["-pal"]), ("ntsc", [], ["-ntsc"])]

if __name__ == "__main__":
    ticks = int(next((a for a in sys.argv[1:] if a.isdigit()), 1000))
    ok = determinism.main(build.GAME, ticks, "pit_halt", ["DETTEST"], RUNS, IGNORE)
    sys.exit(0 if ok else 1)
