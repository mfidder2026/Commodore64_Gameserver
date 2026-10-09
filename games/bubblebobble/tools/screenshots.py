#!/usr/bin/env python3
"""Make the screenshots for the documentation (docs/images/).

Starts the server (raw Ethernet + two built-in bots in the Bubble Bobble
lobby) and two VICEs with RR-Net: ALICE is driven by keystrokes, BOB invites
her automatically. Needs build/bblan-test.d64 (python tools/build.py testdisk).
"""
import json
import os
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dettest import BUILD, ROOT, VICE, monitor  # noqa: E402
import nettest  # noqa: E402

IMG = os.path.join(ROOT, "docs", "images")


def shot(port, name):
    path = os.path.join(IMG, name).replace("\\", "/")
    monitor(port, f'screenshot "{path}" 2')
    print("  ", name)


def keys(port, codes):
    """put PETSCII codes into the KERNAL keyboard buffer"""
    data = " ".join(f"{c:02x}" for c in codes)
    monitor(port, f"> 0277 {data}", f"> 00c6 {len(codes):02x}")


def main():
    os.makedirs(IMG, exist_ok=True)
    iface = os.environ.get("NPCAP_IF", nettest.DEFAULT_IF)
    srv = nettest.SRV_DIR
    with open(os.path.join(srv, "server.json"), "w") as f:
        json.dump({"gamePort": 6465, "dashboardPort": 8080, "bots": ["WORLUK", "GARWOR"], "botGame": 3,
                   "logFile": "server.log", "pcapInterface": iface, "pcapMac": "02:BB:4C:41:4E:01",
                   "games": [{"id": 3, "name": "Bubble Bobble", "module": "bubblebobble", "version": 1,
                              "settings": {"inputDelay": 2, "inputDelayWiC64": 4,
                                           "inputTimeoutSeconds": 10, "loadTimeoutSeconds": 150}}]}, f)
    server = subprocess.Popen([os.path.join(srv, "bin", "C64GameServer.exe"), "server.json"], cwd=srv,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    vices = []
    try:
        time.sleep(3)
        disk_a = nettest.make_disk("a", "ALICE", "", "021111111101")
        disk_b = nettest.make_disk("b", "BOB", "I", "021111111102")
        hw = ["-ethernetcart", "-ethernetcartmode", "1", "-ethernetioif", iface]
        for disk, port in ((disk_a, 6520), (disk_b, 6521)):
            vices.append(subprocess.Popen(
                [VICE, "-default", "-minimized", "-pal", "-sounddev", "dummy", "+drive8truedrive", "-virtualdev8",
                 *hw, "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{port}", "-autostart", disk],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
            if port == 6520:
                time.sleep(8)
                shot(6520, "lobby-menu.png")
                keys(6520, [13])              # RETURN: play on the LAN
                time.sleep(5)
                shot(6520, "lobby-players.png")
            time.sleep(3)
        time.sleep(4)
        shot(6520, "lobby-invited.png")
        keys(6520, [0x59])             # Y: accept
        time.sleep(4)
        shot(6520, "loading.png")
        time.sleep(26)
        shot(6520, "game-alice.png")
        shot(6521, "game-bob.png")
        time.sleep(40)
        shot(6520, "game-alice-2.png")
        shot(6521, "game-bob-2.png")
        if "--wait" in sys.argv:
            input("server and VICEs running (dashboard: http://localhost:8080) - RETURN to stop")
    finally:
        for v in vices:
            v.kill()
        server.kill()


if __name__ == "__main__":
    main()
