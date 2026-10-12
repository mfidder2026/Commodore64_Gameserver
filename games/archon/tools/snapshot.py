#!/usr/bin/env python3
"""
Takes the "original image" of Archon: the tape version's own start runs once
in VICE until it jumps into the game (JMP $6100), then all 64 KB of RAM are
saved, with the CPU registers and the I/O registers.

    python tools/snapshot.py      orig/archon.prg -> orig/archon-6100.bin + .json + -io.bin

The tape image (orig/archon.t64, cracked by "The ... Associates") has one file,
$0801-$A9FF: SYS 2064 -> $0810 moves a block of the game to its place and
jumps to $6100, the game's start (title, options, the board). It runs from
build/clean/archon.prg (tools/crackfix.py: the cracker's line removed).
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import crackfix  # noqa: E402

PRG = crackfix.CLEAN                    # the tape's file without the cracker's line
ENTRY = 0x6100
OUT = os.path.join(ROOT, "orig", f"archon-{ENTRY:04x}")
PORT = 6612


def main() -> None:
    crackfix.clean()
    vice = vicemon.start(PRG, PORT, extra=["+drive8truedrive", "-virtualdev8",
                                           "+autostart-warp", "-autostart-delay", "3"])
    try:
        time.sleep(1.5)                                  # before the autostart (3 s)
        regs, ram = vicemon.stop_at(PORT, ENTRY, OUT + ".bin", timeout=60, io_path=OUT + "-io.bin")
    finally:
        vice.kill()
    info = {"entry": ENTRY, "registers": regs, "sha256": hashlib.sha256(ram).hexdigest(),
            "orig_prg_sha256": hashlib.sha256(open(crackfix.PRG, "rb").read()).hexdigest()}
    with open(OUT + ".json", "w") as f:
        json.dump(info, f, indent=1)
    print(json.dumps(info, indent=1))


if __name__ == "__main__":
    main()
