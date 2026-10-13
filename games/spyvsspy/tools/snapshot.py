#!/usr/bin/env python3
"""
Takes the "original image" of Spy vs Spy: the disk's file runs once in VICE
until it jumps into the game (JMP $660F), then all 64 KB of RAM are saved,
with the CPU registers and the I/O registers.

    python tools/snapshot.py      orig/spyvsspy.prg -> orig/spyvsspy-660f.bin + .json + -io.bin

The disk image (orig/spyvsspy.d64, cracked by 1701) has one file, $0801-$A5F7
(orig/spyvsspy.prg): SYS 2066 runs two unpackers ($033C), then the cracker's
mover at $3400 ($2F00-$33FF -> $F700, $3450-$C3FF -> $4000-$CFFF) jumps to
$660F, the game's start (the options screen). The cracker's line on that
screen ("1701 CRACKWARE") is blanked by a patch (src/main.s).
"""
from __future__ import annotations

import hashlib
import json
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "..", "..", "framework", "tools"))
import vicemon  # noqa: E402

PRG = os.path.join(ROOT, "orig", "spyvsspy.prg")
ENTRY = 0x660F
OUT = os.path.join(ROOT, "orig", f"spyvsspy-{ENTRY:04x}")
PORT = 6613


def main() -> None:
    vice = vicemon.start(PRG, PORT, extra=["+drive8truedrive", "-virtualdev8",
                                           "+autostart-warp", "-autostart-delay", "3"])
    try:
        time.sleep(1.5)                                  # before the autostart (3 s)
        regs, ram = vicemon.stop_at(PORT, ENTRY, OUT + ".bin", timeout=60, io_path=OUT + "-io.bin")
    finally:
        vice.kill()
    info = {"entry": ENTRY, "registers": regs, "sha256": hashlib.sha256(ram).hexdigest(),
            "orig_prg_sha256": hashlib.sha256(open(PRG, "rb").read()).hexdigest()}
    with open(OUT + ".json", "w") as f:
        json.dump(info, f, indent=1)
    print(json.dumps(info, indent=1))


if __name__ == "__main__":
    main()
