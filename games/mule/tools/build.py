#!/usr/bin/env python3
"""
Build script for M.U.L.E. OME (framework/tools/imagebuild.py does the work).

The base is the RAM image when the disk's first part (title, options) jumps
into the game itself (orig/mule-972b.bin, made by tools/snapshot.py from the
disk with the cracker's texts removed, tools/crackfix.py). Our changes are
patches in src/main.s; src/areas*.json list where they may go.

    python tools/build.py              build/mule-raw.prg and build/mule.prg (packed): a game of
                                       four computer players (the snapshot's options)
    python tools/build.py run          build and start it in VICE
    python tools/build.py disk         build/mule.d64: the standard lobby and the online game files
                                       (muleu / mulew / muler: 153 blocks each, so the original game
                                       has a disk of its own: build/mule-original.d64, tools/crackfix.py)
    python tools/build.py testdisk     build/mule-test.d64: the same with a test bot
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
sys.path.insert(0, os.path.join(ROOT, "..", "..", "framework", "tools"))
import imagebuild  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import crackfix  # noqa: E402
import waits  # noqa: E402

waits.generate()                        # src/waits.inc, src/areas-waits.json

GAME = imagebuild.ImageGame(ROOT, snapshot="orig/mule-972b.bin", lobby_file="mule",
                            files={"NET_UCI": "muleu", "NET_WIC": "mulew", "NET_RR": "muler"},
                            disk_title="m.u.l.e. ome,mu")
GAME.variants = {d: "areas-online.json" for d in ("ONLINE", "DETTEST", "NET_UCI", "NET_WIC", "NET_RR")}
build = GAME.build
read_labels = GAME.read_labels

if __name__ == "__main__":
    GAME.main(sys.argv)
    if sys.argv[1:2] == ["disk"]:
        crackfix.clean_disk(os.path.join(BUILD, "mule-original.d64"))
        print("built build/mule-original.d64 (the original game, without the cracker's texts)")
