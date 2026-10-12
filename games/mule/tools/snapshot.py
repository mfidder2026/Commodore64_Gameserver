#!/usr/bin/env python3
"""
Takes the "original image" of M.U.L.E.: the disk's own first part (title and
options) runs once in VICE, then all 64 KB of RAM are saved when it jumps into
the game itself (JMP $972B), with the CPU registers.

    python tools/snapshot.py      orig/mule.d64 -> orig/mule-972b.bin + .json + -io.bin
                                  (-io.bin: $D000-$DFFF with I/O banked in: the VIC, SID
                                  and CIA set-up the first part leaves for the game)

The disk (cracked by "Jedi"):
  "m.u.l.e."  $0801-$84FF: SYS 2068 -> $01 = $36, JMP $4000 -> JMP $5349: title,
              options (F3 level -> $E504, F5 players -> $43FF), "each planeteer
              press your button" (devices -> $E500-$E503); then $65E4 clears
              $4000-$7FFF and loads "&"
  "&"         $4000-$CBFF: the game: JMP $4000 -> JMP $972B (and at the end of a
              game its own title, which loads "m.u.l.e." again)
It runs from build/mule-clean.d64 (tools/crackfix.py: the cracker's texts
removed, the pirates back), so the image has the game's own texts.
The options are set through VICE's monitor: level beginner, no human players
(all four are the computer's), F7. The online build sets the session's players.
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

D64 = os.path.join(ROOT, "build", "mule-clean.d64")
ENTRY = 0x972B
OUT = os.path.join(ROOT, "orig", f"mule-{ENTRY:04x}")
PORT = 6611


def main() -> None:
    os.makedirs(os.path.dirname(D64), exist_ok=True)
    crackfix.clean_disk(D64)
    vice = vicemon.start(D64, PORT, extra=["+drive8truedrive", "-virtualdev8", "-warp"])
    try:
        time.sleep(8)                                    # the title and its options
        regs, ram = vicemon.stop_at(PORT, ENTRY, OUT + ".bin", timeout=90, io_path=OUT + "-io.bin",
                                    then=["> e504 00",   # level: beginner
                                          "> 43ff 00",   # no human players
                                          "> 00a8 03"])  # F7
    finally:
        vice.kill()
    info = {"entry": ENTRY, "registers": regs, "sha256": hashlib.sha256(ram).hexdigest(),
            "orig_d64_sha256": hashlib.sha256(open(crackfix.D64, "rb").read()).hexdigest(),
            "options": "beginner, no human players"}
    with open(OUT + ".json", "w") as f:
        json.dump(info, f, indent=1)
    print(json.dumps(info, indent=1))


if __name__ == "__main__":
    main()
