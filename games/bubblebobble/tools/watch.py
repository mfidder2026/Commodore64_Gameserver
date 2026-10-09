#!/usr/bin/env python3
"""Run a build in VICE (warp) and print progress every few seconds.

    python tools/watch.py NAME [seconds] [interval]

Reads level ($10), frame counter ($08), bb_tick and bb_rframe through the
remote monitor, plus the CPU registers, and saves build/watch_NAME_<n>.png.
A main loop that hangs shows up as bb_rframe moving while bb_tick does not.
"""
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dettest import BUILD, VICE, labels, monitor, read_mem  # noqa: E402

PORT = 6530


def main():
    name = sys.argv[1]
    seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 60
    interval = float(sys.argv[3]) if len(sys.argv) > 3 else 4
    lbl = labels(name)
    p = subprocess.Popen(
        [VICE, "-default", "-minimized", "-pal", "-warp", "-sounddev", "dummy", "-autostartprgmode", "1",
         "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{PORT}",
         "-autostart", os.path.join(BUILD, name + ".prg")],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        t0 = time.time()
        n = 0
        while time.time() - t0 < seconds:
            time.sleep(interval)
            n += 1
            lvl = read_mem(PORT, 0x10, 0x10)[0]
            frame = read_mem(PORT, 0x08, 0x08)[0]
            tick = read_mem(PORT, lbl["bb_tick"], lbl["bb_tick"] + 1)
            rf = read_mem(PORT, lbl["bb_rframe"], lbl["bb_rframe"])[0]
            minsp = read_mem(PORT, lbl["bb_minsp"], lbl["bb_minsp"])[0] if "bb_minsp" in lbl else 0
            regs = monitor(PORT, "r").strip().splitlines()
            regs = regs[-2] if len(regs) >= 2 else "?"
            shot = os.path.join(BUILD, f"watch_{name}_{n}.png")
            monitor(PORT, f'screenshot "{shot}" 2')
            print(f"[{n:3d}] level {lvl + 1:3d}  $08={frame:02x}  tick={tick[0] | tick[1] << 8:5d}"
                  f"  rframe={rf:3d}  minsp={minsp:02x}  {regs.strip()}", flush=True)
    finally:
        p.kill()


if __name__ == "__main__":
    main()
