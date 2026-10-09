#!/usr/bin/env python3
"""Make the screenshots for the documentation (docs/images/).

Starts the server (raw Ethernet + the built-in bots BRUCE and CHUCK) and two
VICEs with RR-Net and the test disk (python tools/build.py testdisk): ALICE is
driven by keystrokes, BOB invites her automatically. The test bot plays on
both C64s.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "..", "..", "framework", "tools"))
import c64env  # noqa: E402
import vicemon  # noqa: E402

BUILD = os.path.join(ROOT, "build")
IMG = os.path.join(ROOT, "docs", "images")
IFACE = os.environ.get("NPCAP_IF", r"\Device\NPF_{BD187BD7-EF69-4A3B-B098-BEC90E6A20AA}")


def shot(port: int, name: str) -> None:
    path = os.path.join(IMG, name).replace("\\", "/")
    vicemon.monitor(port, f'screenshot "{path}" 2')
    print("  ", name)


def keys(port: int, codes: list[int]) -> None:
    """PETSCII codes into the KERNAL keyboard buffer (the lobby reads it)."""
    vicemon.monitor(port, "> 0277 " + " ".join(f"{c:02x}" for c in codes), f"> 00c6 {len(codes):02x}")


def disk(tag: str, nick: str, auto: str, mac: str) -> str:
    d64 = os.path.join(BUILD, f"shot_{tag}.d64")
    shutil.copy(os.path.join(BUILD, "fist-test.d64"), d64)
    cfg = os.path.join(BUILD, f"shot_{tag}.cfg")
    with open(cfg, "wb") as f:
        f.write(f"NAME={nick}\rMAC={mac}\rBOT=1\r".encode() + (f"AUTO={auto}\r".encode() if auto else b""))
    subprocess.run([c64env.vice("c1541"), "-attach", d64, "-write", cfg, "fist.cfg,s"], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return d64


def main() -> None:
    os.makedirs(IMG, exist_ok=True)
    srv = os.path.join(BUILD, "srvtest")
    exe = os.path.join(srv, "bin", "C64GameServer.exe")
    os.makedirs(srv, exist_ok=True)
    subprocess.run(["dotnet", "build", os.path.join(c64env.SERVER, "src", "C64GameServer"), "-c", "Release",
                    "-o", os.path.dirname(exe), "-v", "q"], check=True, stdout=subprocess.DEVNULL)
    with open(os.path.join(ROOT, "game.json"), encoding="utf-8") as f:
        entry = dict(json.load(f)["nettest"]["server"], bots=["BRUCE", "CHUCK"])
    with open(os.path.join(srv, "server.json"), "w") as f:
        json.dump({"gamePort": 6465, "dashboardPort": 8080, "logFile": "server.log", "pcapInterface": IFACE,
                   "pcapMac": "02:BB:4C:41:4E:01", "games": [entry]}, f)
    server = subprocess.Popen([exe, "server.json"], cwd=srv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    hw = ["+drive8truedrive", "-virtualdev8", "-ethernetcart", "-ethernetcartmode", "1", "-ethernetioif", IFACE]
    vices = []
    try:
        time.sleep(3)
        vices.append(vicemon.start(disk("a", "ALICE", "", "021111111101"), 6520, extra=hw))
        time.sleep(12)                       # ALICE goes straight into the lobby
        shot(6520, "lobby-players.png")
        keys(6520, [133])                    # F1: the setup screen
        time.sleep(2)
        shot(6520, "lobby-menu.png")
        keys(6520, [13])                     # RETURN: back to the lobby
        time.sleep(4)
        vices.append(vicemon.start(disk("b", "BOB", "I", "021111111102"), 6521, extra=hw))
        time.sleep(14)                       # BOB connects and invites ALICE
        shot(6520, "lobby-invited.png")
        keys(6520, [0x59])                   # Y: accept
        time.sleep(3)
        shot(6520, "loading.png")
        time.sleep(30)
        shot(6520, "game-alice.png")
        shot(6521, "game-bob.png")
        time.sleep(45)
        shot(6520, "game-alice-2.png")
        shot(6521, "game-bob-2.png")
    finally:
        for v in vices:
            v.kill()
        server.kill()


if __name__ == "__main__":
    main()
