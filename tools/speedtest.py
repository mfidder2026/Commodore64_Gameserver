"""
Can a real C64 keep up with 60 ticks per second? Runs build/wow_speedtest.prg (python tools/build.py speedtest)
in VICE (PAL or NTSC, warp - the pacing uses the emulated CIA2 cycle counter) and reports ticks per second,
idle time and resyncs (more than 3 ticks behind).

    python tools/speedtest.py [seconds] [pal|ntsc]
"""
from __future__ import annotations

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dettest import monitor, ROOT  # noqa: E402
from profile_run import labels  # noqa: E402
import subprocess  # noqa: E402
import vicemon as vm  # noqa: E402

CLOCK = {"pal": 985248, "ntsc": 1022727}


def main() -> None:
    seconds = float(sys.argv[1]) if len(sys.argv) > 1 else 30
    video = sys.argv[2] if len(sys.argv) > 2 else "pal"
    lbl = labels(os.path.join(ROOT, "build", "wow_speedtest.lbl"))
    p = subprocess.Popen([os.path.join(vm.VICE_DIR, "x64sc.exe"), "-default", f"-{video}", "-sounddev", "dummy",
                          "-warp", "-remotemonitor", "-remotemonitoraddress", "ip4://127.0.0.1:6510",
                          "-autostart", os.path.join(ROOT, "build", "wow_speedtest.prg")],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    path = os.path.join(ROOT, "build", "speed.bin").replace("\\", "/")
    try:
        time.sleep(seconds)
        out = monitor(6510, f's "{path}" 0 {lbl["speed_ticks"]:04x} {lbl["speed_resyncs"] + 1:04x}', "r")
        time.sleep(0.5)
    finally:
        p.kill()
    d = open(path, "rb").read()[2:]
    ticks = d[0] | d[1] << 8 | d[2] << 16
    idle = (d[3] | d[4] << 8 | d[5] << 16) * 90
    resyncs = d[6] | d[7] << 8
    print(f"{video.upper()}: {ticks} ticks during sessions, idle ~{idle / CLOCK[video]:.1f} s, resyncs {resyncs}")
    if ticks:
        print(f"  idle per tick ~{idle / ticks:.0f} cycles of a {CLOCK[video] / 60:.0f} cycle tick "
              f"({100 * idle / ticks / (CLOCK[video] / 60):.0f}% free)")


if __name__ == "__main__":
    main()
