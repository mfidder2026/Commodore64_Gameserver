#!/usr/bin/env python3
"""
Build script for The Way of the Exploding Fist OME (framework/tools/imagebuild.py does the work).

There is no source code of the game: the base is the RAM image the original
loader leaves when it jumps into the game (orig/fist-1158.bin, made by
tools/snapshot.py from the clean disk). Our changes are patches in src/main.s;
src/areas.json lists where they may go.

    python tools/build.py              build/fist-raw.prg (the patched image) and build/fist.prg (packed)
    python tools/build.py disk         build/fist.d64: the standard lobby + the game files
    python tools/build.py testdisk     build/fist-test.d64: the same with a test bot (framework/tools/nettest.py)
    python tools/build.py run          build and start the game in VICE (local game, no network)
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
sys.path.insert(0, os.path.join(ROOT, "..", "..", "framework", "tools"))
import imagebuild  # noqa: E402

GAME = imagebuild.ImageGame(ROOT, snapshot="orig/fist-1158.bin", lobby_file="fist",
                            files={"NET_UCI": "fistu", "NET_WIC": "fistw", "NET_RR": "fistr"},
                            disk_title="fist ome,ef", entry_label="fist_entry")
build = GAME.build
read_labels = GAME.read_labels

if __name__ == "__main__":
    GAME.main(sys.argv)
