#!/usr/bin/env python3
"""
Takes the "original image" of The Way of the Exploding Fist: the clean disk's
own loader (m.opt: boot picture, the scream, loading and copying the m.* files)
runs once in VICE until it jumps into the game (JMP $1158). Then all 64 KB of
RAM are saved, with the CPU registers.

    python tools/snapshot.py      orig/exploding_fist.d64 -> orig/fist-1158.bin + orig/fist-1158.json

Everything the game needs is in that image; the boot screen, the scream
(m.tsound, m.mytiny) and the loader are not part of our build.
"""
from __future__ import annotations

import hashlib
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "..", "..", "framework", "tools"))
import vicemon  # noqa: E402

DISK = os.path.join(ROOT, "orig", "exploding_fist.d64")
ENTRY = 0x1158  # m.opt ends with JSR $C400 (m.prerun), JMP $1158
OUT = os.path.join(ROOT, "orig", f"fist-{ENTRY:04x}")
PORT = 6561


def main() -> None:
    vice = vicemon.start(DISK, PORT, extra=["-warp", "+drive8truedrive", "-virtualdev8"])
    try:
        # at once: in warp the loader is done in seconds
        regs, ram = vicemon.stop_at(PORT, ENTRY, OUT + ".bin", timeout=180)
    finally:
        vice.kill()
    info = {"entry": ENTRY, "registers": regs, "sha256": hashlib.sha256(ram).hexdigest(),
            "disk_sha256": hashlib.sha256(open(DISK, "rb").read()).hexdigest()}
    with open(OUT + ".json", "w") as f:
        json.dump(info, f, indent=1)
    print(json.dumps(info, indent=1))


if __name__ == "__main__":
    main()
