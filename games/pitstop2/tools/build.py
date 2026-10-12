#!/usr/bin/env python3
"""
Build script for Pitstop II OME (framework/tools/imagebuild.py does the work).

The base is the RAM image the tape version's boot chain leaves when it jumps
into the game (orig/pitstop2-9403.bin, made by tools/snapshot.py: no intro, no
documents, no title picture, no trainer). Our changes are patches in
src/main.s; src/areas.json lists where they may go.

    python tools/build.py              build/pitstop-raw.prg and build/pitstop.prg (packed)
    python tools/build.py disk         build/pitstop.d64: the standard lobby + the game files
    python tools/build.py testdisk     build/pitstop-test.d64: the same with a test bot
    python tools/build.py run          build and start the game in VICE
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
sys.path.insert(0, os.path.join(ROOT, "..", "..", "framework", "tools"))
import imagebuild  # noqa: E402

GAME = imagebuild.ImageGame(ROOT, snapshot="orig/pitstop2-9403.bin", lobby_file="pitstop",
                            files={"NET_UCI": "pitu", "NET_WIC": "pitw", "NET_RR": "pitr"},
                            disk_title="pitstop ii ome,p2")
build = GAME.build
read_labels = GAME.read_labels

if __name__ == "__main__":
    GAME.main(sys.argv)
