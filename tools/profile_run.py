"""
Runs build/wow_profile.prg (python tools/build.py profile) in VICE and prints the measured cost of the
actor passes of the original game loop, per loop and category.

    python tools/profile_run.py [seconds] [ntsc|pal]

The bot in game_net.asm (PROFILE=1) starts a 2 player game and keeps both players moving and shooting.
Time is emulated time (warp mode), the CIA2 cycle counter counts emulated cycles.
"""
from __future__ import annotations

import os
import socket
import struct
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vicemon as vm  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATS = ["dead", "dying", "monster idle", "monster acts", "player idle", "player moves"]
LOOPS = ["normal", "worluk", "wizard"]


def labels(path: str) -> dict[str, int]:
    out = {}
    with open(path) as f:
        for line in f:
            p = line.split()
            if len(p) == 3:
                out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def monitor(*cmds: str) -> str:
    s = socket.create_connection(("127.0.0.1", 6510), timeout=5)
    out = vm.recv_all(s)
    for c in cmds:
        s.sendall((c + "\n").encode())
        out += vm.recv_all(s, 1.0)
    s.sendall(b"x\n")
    vm.recv_all(s, 0.2)
    s.close()
    return out


def main() -> None:
    seconds = float(sys.argv[1]) if len(sys.argv) > 1 else 60
    video = sys.argv[2] if len(sys.argv) > 2 else "ntsc"
    lbl = labels(os.path.join(ROOT, "build", "wow_profile.lbl"))
    start = lbl["prof_stats"]
    size = len(CATS) * len(LOOPS) * 8 + 2
    vice = subprocess.Popen([os.path.join(vm.VICE_DIR, "x64sc.exe"), "-default", f"-{video}", "-sounddev", "dummy",
                             "-warp", "-remotemonitor", "-remotemonitoraddress", "ip4://127.0.0.1:6510",
                             "-autostart", os.path.join(ROOT, "build", "wow_profile.prg")],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    dump = os.path.join(ROOT, "build", "prof.bin").replace("\\", "/")
    try:
        time.sleep(seconds)
        monitor(f's "{dump}" 0 {start:04x} {start + size - 1:04x}', 'screenshot "build/shot_prof.png" 2')
        time.sleep(1)
    finally:
        vice.kill()
    data = open(dump, "rb").read()[2:]
    frames = struct.unpack_from("<H", data, len(CATS) * len(LOOPS) * 8)[0]
    print(f"{video.upper()}  frames seen by the IRQ: {frames}")
    print(f"{'loop':8s} {'category':14s} {'passes':>8s} {'avg cycles':>11s} {'share':>7s}")
    for li, loop in enumerate(LOOPS):
        rows = []
        for ci, cat in enumerate(CATS):
            n, total, mx = struct.unpack_from("<HIH", data, (li * len(CATS) + ci) * 8)
            rows.append((cat, n, total, mx))
        alltotal = sum(r[2] for r in rows) or 1
        for cat, n, total, mx in rows:
            if n:
                print(f"{loop:8s} {cat:14s} {n:8d} {total / n:11.0f} {100 * total / alltotal:6.1f}%  max {mx}")


if __name__ == "__main__":
    main()
