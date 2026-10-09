#!/usr/bin/env python3
"""Soak test: let the DETTEST bot play in several VICE instances and report
crashes/hangs, to compare the original IRQ timing with the BB-LAN tick core.

    python tools/soak.py [seconds] [start_level] [seeds]

Builds, for each bot seed and each kind in $KINDS (default tick,ol):
  tick  BB-LAN tick core
  ol    the original game, code byte-identical in place (ORIGLAYOUT),
        always starts at level 1
A run counts as crashed when the PC is in $0000-$03FF (tables/zero page)
or when bb_tick stops moving for 3 polls in a row.
"""
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dettest import BUILD, ROOT, VICE, labels, monitor, read_mem  # noqa: E402


ALL_KINDS = {"tick": [], "ol": ["-D", "ORIGLAYOUT=1"]}
KINDS = [(k, ALL_KINDS[k]) for k in os.environ.get("KINDS", "tick,ol").split(",")]


def main():
    seconds = float(sys.argv[1]) if len(sys.argv) > 1 else 240
    level = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    seeds = [int(s, 0) for s in sys.argv[3].split(",")] if len(sys.argv) > 3 \
        else [0xACE1, 0x1234, 0xBEEF]
    runs = []
    for seed in seeds:
        for kind, extra in KINDS:
            name = f"soak_{kind}_{seed:04x}"
            subprocess.run([sys.executable, os.path.join(ROOT, "tools", "build.py"), "release",
                            "-D", "DETTEST=1",
                            *(["-D", f"START_LEVEL={level}"] if level > 1 else []),
                            "-D", f"BOT_SEED=${seed:04X}", *extra, "-o", name],
                           check=True, stdout=subprocess.DEVNULL)
            runs.append(name)
    procs = {}
    for i, name in enumerate(runs):
        port = 6600 + i
        procs[name] = (port, subprocess.Popen(
            [VICE, "-default", "-minimized", "-pal", "-warp", "-sounddev", "dummy", "-autostartprgmode", "1",
             "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{port}",
             "-autostart", os.path.join(BUILD, name + ".prg")],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    state = {n: {"tick": -1, "still": 0, "maxlvl": 0, "dead": None} for n in runs}
    t0 = time.time()
    try:
        while time.time() - t0 < seconds:
            time.sleep(10)
            for name, (port, _) in procs.items():
                st = state[name]
                if st["dead"]:
                    continue
                lbl = labels(name)
                try:
                    lvl = read_mem(port, 0x10, 0x10)[0] + 1
                    t = read_mem(port, lbl["bb_tick"], lbl["bb_tick"] + 1)
                    tick = t[0] | t[1] << 8
                    regs = monitor(port, "r")
                except Exception as e:  # noqa: BLE001
                    st["dead"] = f"monitor error {e}"
                    continue
                m = re.search(r"\.;([0-9a-f]{4})", regs)
                pc = int(m.group(1), 16) if m else 0xFFFF
                if lvl <= 100:
                    st["maxlvl"] = max(st["maxlvl"], lvl)
                st["still"] = st["still"] + 1 if tick == st["tick"] else 0
                st["tick"] = tick
                if pc < 0x0400:
                    st["dead"] = f"CRASH pc=${pc:04x} level {lvl}"
                elif st["still"] >= 3:
                    st["dead"] = f"HANG pc=${pc:04x} level {lvl}"
                if st["dead"]:
                    monitor(port, f'screenshot "{os.path.join(BUILD, name + "_dead.png")}" 2')
            line = "  ".join(f"{n[5:]}:{state[n]['maxlvl']}{'!' if state[n]['dead'] else ''}"
                             for n in runs)
            print(f"[{time.time() - t0:5.0f}s] {line}", flush=True)
    finally:
        for _, p in procs.values():
            p.kill()
    print()
    for n in runs:
        st = state[n]
        print(f"  {n:20s} max level {st['maxlvl']:3d}  {st['dead'] or 'OK'}")


if __name__ == "__main__":
    main()
