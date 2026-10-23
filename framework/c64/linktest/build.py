#!/usr/bin/env python3
"""
Builds the C64 Ultimate link test: build/linktest.prg and build/linktest.d64.

    python build.py            build
    python build.py run        build and start it in VICE with an RR-Net cartridge
                               (the host interface: $NPCAP_IF, as framework/tools/nettest.py)

The program uses the standard lobby's drivers (../lobby/uci.s, ../lobby/rrnet.s).
"""
from __future__ import annotations

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))
import c64env  # noqa: E402

BUILD = os.path.join(HERE, "build")
LOBBY = os.path.join(HERE, "..", "lobby")


def build() -> str:
    os.makedirs(BUILD, exist_ok=True)
    prg = os.path.join(BUILD, "linktest.prg")
    subprocess.run([c64env.cc65("cl65"), "-t", "c64", "-O", "-o", prg, "-m", os.path.join(BUILD, "linktest.map"),
                    os.path.join(HERE, "main.c"), os.path.join(HERE, "timer.s"),
                    os.path.join(LOBBY, "uci.s"), os.path.join(LOBBY, "rrnet.s")], check=True, cwd=BUILD)
    d64 = os.path.join(BUILD, "linktest.d64")
    subprocess.run([c64env.vice("c1541"), "-format", "link test,lt", "d64", d64, "-write", prg, "linktest"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"built {os.path.relpath(prg, HERE)} ({os.path.getsize(prg)} bytes) and {os.path.relpath(d64, HERE)}")
    return d64


if __name__ == "__main__":
    disk = build()
    if len(sys.argv) > 1 and sys.argv[1] == "run":
        iface = os.environ.get("NPCAP_IF", r"\Device\NPF_{BD187BD7-EF69-4A3B-B098-BEC90E6A20AA}")
        subprocess.Popen([c64env.vice("x64sc"), "-ethernetcart", "-ethernetcartmode", "1",
                          "-ethernetioif", iface, "-autostart", disk])
