#!/usr/bin/env python3
"""
Takes the "original image" of Pitstop II: the tape version's own boot chain
runs once in VICE until it jumps into the game (JMP $9403), then all 64 KB of
RAM are saved, with the CPU registers.

    python tools/snapshot.py      orig/pitstop2.prg -> orig/pitstop2-9403.bin + .json

The boot chain of this (cracked) tape version, none of which is in our build:
  $080D  decruncher, then the crack's intro (waits for SPACE at $0876)
  $08xx  a documents reader (SPACE: next page, RUN/STOP: start at $08E1)
  $3400  a second unpacker, then JMP $C118
  $C118  the Epyx title picture (waits for SPACE at $C16F)
  $C1AA  "trainer? N/T": N leaves the game untouched -> $C1F3 -> JMP $9403
The waits are skipped through VICE's monitor, and N is put in the keyboard
buffer, so the game is exactly the original (no trainer bytes poked).
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

PRG = os.path.join(ROOT, "orig", "pitstop2.prg")
ENTRY = 0x9403
OUT = os.path.join(ROOT, "orig", f"pitstop2-{ENTRY:04x}")
PORT = 6610


def main() -> None:
    vice = vicemon.start(PRG, PORT, extra=["+drive8truedrive", "-virtualdev8"])
    try:
        time.sleep(22)                                   # decrunched, the intro waits
        vicemon.monitor(PORT, "> 087b ea ea")            # intro: no SPACE wait
        time.sleep(4)                                    # the documents reader runs
        vicemon.monitor(PORT, "> 0884 4c e1 08")         # documents: as RUN/STOP
        time.sleep(4)                                    # unpacked; the title waits
        regs, ram = vicemon.stop_at(PORT, ENTRY, OUT + ".bin", timeout=60,
                                    then=["> c174 ea ea",              # title: no SPACE wait
                                          "> 0277 4e", "> 00c6 01"])   # trainer question: N
    finally:
        vice.kill()
    info = {"entry": ENTRY, "registers": regs, "sha256": hashlib.sha256(ram).hexdigest(),
            "prg_sha256": hashlib.sha256(open(PRG, "rb").read()).hexdigest(),
            "trainer": "none (N)"}
    with open(OUT + ".json", "w") as f:
        json.dump(info, f, indent=1)
    print(json.dumps(info, indent=1))


if __name__ == "__main__":
    main()
