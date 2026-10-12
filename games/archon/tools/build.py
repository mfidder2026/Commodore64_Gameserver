#!/usr/bin/env python3
"""
Build script for Archon OME (framework/tools/imagebuild.py does the work).

The base is the RAM image when the tape version's file jumps into the game
(orig/archon-6100.bin, made by tools/snapshot.py from the file without the
cracker's line, tools/crackfix.py). Our changes are patches in src/main.s;
src/areas*.json list where they may go.

    python tools/build.py              build/archon-raw.prg and build/archon.prg (packed)
    python tools/build.py run          build and start it in VICE
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
sys.path.insert(0, os.path.join(ROOT, "..", "..", "framework", "tools"))
import imagebuild  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import waits  # noqa: E402

waits.generate()                        # src/waits.inc, src/areas-waits.json

GAME = imagebuild.ImageGame(ROOT, snapshot="orig/archon-6100.bin", lobby_file="archon",
                            files={"NET_UCI": "archu", "NET_WIC": "archw", "NET_RR": "archr"},
                            disk_title="archon ome,ar")
GAME.variants = {d: "areas-online.json" for d in ("ONLINE", "DETTEST", "NET_UCI", "NET_WIC", "NET_RR")}
build = GAME.build
read_labels = GAME.read_labels

if __name__ == "__main__":
    GAME.main(sys.argv)
