#!/usr/bin/env python3
"""
The main program's tight wait loops, made into tick loops (online / DETTEST builds).

In the original the raster IRQ runs the frame logic, and the main program waits
for it in loops like
    $5481  LDA $70 / BNE $5481        (until the transport ship has landed)
In the online build the frame logic only runs in ticks (src/main.s, mule_tick),
so each such loop must tick while it waits. Every site below is two
instructions, a load (LDA/LDX/LDY/BIT, zero page or absolute) and a branch back
to it; it becomes JSR to a stub (plus NOPs to the same length):
    stub:  load / branch -> tick / RTS        tick: JSR mule_tick / JMP stub
so the registers and flags at the end are the original's. When the branch goes
back further than the load (a loop with more checks), the tick drops the stub's
return address and jumps to the branch's target instead. A site marked "first"
is also the target of a longer loop: its stub ticks once before it checks.

Longer wait loops (HEADS) tick at their head: the first instructions of the loop
(3 bytes or more, no branches) become JSR to a stub that ticks and then runs
them:   stub:  JSR mule_tick / <the instructions> / RTS

Loops whose head is a JSR (CALLS) tick in that call: JSR stub, stub = JSR
mule_tick / JMP <the original target>.

Loops closed by a JMP back (JUMPS) tick there: JMP stub, stub = JSR mule_tick /
JMP <the original target>.

The stubs go to the segments WAITS, WAITS2, WAITS3 (SEGMENTS: the online build
has no room for all of them in one piece), each while it has room.

    python tools/waits.py      writes src/waits.inc and src/areas-waits.json
(tools/build.py runs it before every build.) The sites were found with a flow
trace of the game (every two-instruction loop of the main program on memory
the frame logic writes) and by running the online build until it hung.
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "..", "..", "framework", "tools"))
import waitpatch  # noqa: E402  (framework/tools/waitpatch.py does the work)

# the segments for the stubs and their room (src/areas-online.json), filled in this order
SEGMENTS = [("WAITS", 230), ("WAITS2", 150), ("WAITS3", 138)]

# address: what it waits for
SITES = {
    0x407B: "the button latch $35",
    0x4BD7: "the frame task's flag $70",
    0x50C4: "the button latch $35",
    0x50D9: "the button latch $35",
    0x5481: "the transport ship: $70",
    0x582C: "an event's animation: $74 (or $42)",
    0x64F5: "$74",
    0x7925: "the frame task's flag $45",
    0x795E: "the auction's clock $5C (trading)",
    0x7E82: "the frame task's flag $45",
    0x7F56: "$40",
    0x8F7E: "$E1AD",
    0x9D05: "the count-down $5A",
    0xA7B9: "the count-down $5C",
    0xABFA: "$40",
    0xAE1F: ("a sprite's position ($D002), moved by the frame task; the loop to $AE2D", "first"),
    0xB5FC: "the frame task's flag $45",
    0xB74A: "$40",
    0xB9FF: "the frame task's flag $45",
    0xBAD8: "$40",
}

# loop head: (bytes replaced, what the loop waits for)
HEADS = {
    0x4CCB: (4, "the count-down $5A or all buttons ($2C)"),
    0x597A: (5, "an event's sprite: $D010 (moved by the frame task)"),
    0x5981: (5, "an event's sprite: $D002 >= $58 (idem)"),
    0x6AE9: (3, "the player's button $49,Y"),
    0x90EE: (4, "$E1B5-$E1B8 all $FF (the frame task)"),
    0xA75B: (3, "a button $49,Y or the count-down $5A"),
    0xAE35: (5, "the radiation event's sprite: $D002 >= $58 (moved by the frame task)"),
    0xB303: (4, "the count-down $5A or all buttons ($2C)"),
}

# JSR at the head of a wait loop: what the loop waits for
CALLS = {
    0x4F99: "the clock $14 (or a key, $6911)",
    0x6B2F: "the clock $14 (or a key, $6911)",
}

# JMP back that closes a wait loop: what the loop waits for
JUMPS = {
    0x5068: "the status summary: all buttons ($4D, $2C) or the count-down $5A",
    0xA8F5: "the town: the player walking (the frame task), the time $6A",
    0xA917: "the town: idem",
    0xAA5A: "the town: idem",
    0xADA2: "the map: the player walking, the time $6A",
}


def generate() -> int:
    return waitpatch.generate(ROOT, "orig/mule-972b.bin", tick="mule_tick", segments=SEGMENTS,
                              sites=SITES, heads=HEADS, calls=CALLS, jumps=JUMPS)


if __name__ == "__main__":
    n = generate()
    print(f"{n} wait loops -> src/waits.inc, src/areas-waits.json")
