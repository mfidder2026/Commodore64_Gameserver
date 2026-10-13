#!/usr/bin/env python3
"""
Build script for Spy vs Spy OME (framework/tools/imagebuild.py does the work).

The base is the RAM image when the disk's file jumps into the game
(orig/spyvsspy-660f.bin, made by tools/snapshot.py). Our changes are patches
in src/main.s; src/areas*.json list where they may go.

    python tools/build.py              build/spyvsspy-raw.prg and build/spyvsspy.prg (packed)
    python tools/build.py run          build and start it in VICE
    python tools/build.py disk         build/spyvsspy.d64: the standard lobby, the online game files
                                       (spyu / spyw / spyr) and the original game ("spyl", the
                                       lobby's key L; without the cracker's line)
    python tools/build.py testdisk     build/spyvsspy-test.d64: the same with a test bot
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "..", "..", "framework", "tools"))
import imagebuild  # noqa: E402

GAME = imagebuild.ImageGame(ROOT, snapshot="orig/spyvsspy-660f.bin", lobby_file="spyvsspy",
                            files={"NET_UCI": "spyu", "NET_WIC": "spyw", "NET_RR": "spyr"},
                            disk_title="spy vs spy ome,sp", local_file="spyl",
                            local_net=False)   # spyl: no network code (no room for it)
GAME.variants = {d: "areas-online.json" for d in ("ONLINE", "DETTEST", "NET_UCI", "NET_WIC", "NET_RR")}
build = GAME.build
read_labels = GAME.read_labels

if __name__ == "__main__":
    GAME.main(sys.argv)
