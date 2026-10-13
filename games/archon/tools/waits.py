#!/usr/bin/env python3
"""
Archon's wait loops, made into tick loops (online / DETTEST builds); see
framework/tools/waitpatch.py. In the original the raster IRQ runs the frame
logic and the main program waits for it ($BCD0: the task of the frame done);
here the frame logic only runs in ticks (src/main.s, arch_tick).

    python tools/waits.py      writes src/waits.inc and src/areas-waits.json
(tools/build.py runs it before every build.) The loops were found by running the
test build until it hung.
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "..", "..", "framework", "tools"))
import waitpatch  # noqa: E402

SEGMENTS = [("WAITS", 1024)]

# two instructions, a load and a branch back: what the loop waits for
SITES = {
    0x836F: "the frame task done ($BCD0)",
    0x9067: "the title: the frame task done ($BCD0)",
    0x6492: "the next jiffy ($A2: the clock runs in ticks)",
    0x64DE: "the next jiffy ($A2)",
    0x6C13: "the next jiffy ($A2)",
}
HEADS: dict = {}
CALLS: dict = {}
JUMPS = {
    0x81EF: "the options screen: a key, or the clock $A1 counts down to the demo",
    0x6779: "after a game: a key, or the clock $A1 counts down to the demo",
}


def generate() -> int:
    return waitpatch.generate(ROOT, "orig/archon-6100.bin", tick="arch_tick", segments=SEGMENTS,
                              sites=SITES, heads=HEADS, calls=CALLS, jumps=JUMPS)


if __name__ == "__main__":
    n = generate()
    print(f"{n} wait loops -> src/waits.inc, src/areas-waits.json")
