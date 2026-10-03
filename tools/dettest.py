"""
Determinism test: runs build/wow_dettest.prg (python tools/build.py dettest) in two VICE instances with
different timing (PAL and NTSC, warp) and compares the game state checksums they logged every 32 ticks.

    python tools/dettest.py [seconds] [build name, default wow_dettest]

The players are driven by a bot whose inputs depend on the tick number only, so two correct runs must log
exactly the same checksums, no matter how fast the machine is or when the IRQ hits.
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
from profile_run import labels  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD_NAME = sys.argv[2] if len(sys.argv) > 2 else "wow_dettest"


def monitor(port: int, *cmds: str) -> str:
    s = socket.create_connection(("127.0.0.1", port), timeout=5)
    out = vm.recv_all(s)
    for c in cmds:
        s.sendall((c + "\n").encode())
        out += vm.recv_all(s, 1.0)
    s.sendall(b"x\n")
    vm.recv_all(s, 0.2)
    s.close()
    return out


def run(video: str, port: int) -> subprocess.Popen:
    return subprocess.Popen([os.path.join(vm.VICE_DIR, "x64sc.exe"), "-default", f"-{video}", "-sounddev", "dummy",
                             "-warp", "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{port}",
                             "-autostart", os.path.join(ROOT, "build", BUILD_NAME + ".prg")],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def dump(port: int, name: str, lbl: dict[str, int]) -> tuple[int, int, list[int]]:
    path = os.path.join(ROOT, "build", f"det_{name}.bin").replace("\\", "/")
    vars_path = os.path.join(ROOT, "build", f"det_{name}_vars.bin").replace("\\", "/")
    start = lbl["det_log"]
    end = lbl["det_snap"] + 0x700 - 1
    monitor(port, "bank ram", f's "{path}" 0 {start:04x} {end:04x}',
            f's "{vars_path}" 0 {lbl["det_sessions"]:04x} {lbl["det_loop_passes_hi"] + 2:04x}',
            f'screenshot "build/shot_det_{name}.png" 2')
    time.sleep(0.5)
    data = open(path, "rb").read()[2:]
    v = open(vars_path, "rb").read()[2:]
    sessions = v[0]
    count = struct.unpack_from("<H", v, lbl["det_log_count"] - lbl["det_sessions"])[0]
    base = lbl["det_log"] - start
    log = [struct.unpack_from("<H", data, base + 2 * i)[0] for i in range(min(count, 1024))]
    lo, hi = lbl["det_loop_passes_lo"] - lbl["det_sessions"], lbl["det_loop_passes_hi"] - lbl["det_sessions"]
    passes = [v[lo + i] + 256 * v[hi + i] for i in range(3)]
    print(f"{name.upper():4s}: passes normal {passes[0]}  worluk {passes[1]}  wizard {passes[2]} (16 bit, wraps)")
    snap = data[lbl["det_snap"] - start:lbl["det_snap"] - start + 0x700]
    open(os.path.join(ROOT, "build", f"det_snap_{name}.bin"), "wb").write(snap)
    return sessions, count, log


def main() -> None:
    seconds = float(sys.argv[1]) if len(sys.argv) > 1 else 60
    lbl = labels(os.path.join(ROOT, "build", BUILD_NAME + ".lbl"))
    a = run("pal", 6510)
    time.sleep(4)
    b = run("ntsc", 6511)
    try:
        time.sleep(seconds)
        sa, ca, la = dump(6510, "pal", lbl)
        sb, cb, lb = dump(6511, "ntsc", lbl)
    finally:
        a.kill()
        b.kill()
    print(f"PAL : sessions {sa}  checksums {ca}")
    print(f"NTSC: sessions {sb}  checksums {cb}")
    n = min(len(la), len(lb))
    first_diff = next((i for i in range(n) if la[i] != lb[i]), None)
    if n == 0:
        print("no checksums logged - did a game start?")
    elif first_diff is None:
        print(f"IDENTICAL: {n} checksums = {n * 32} ticks ({n * 32 / 60:.0f} s of play) match")
    else:
        print(f"DIFFERENT from checksum {first_diff} (tick {first_diff * 32}) on, {n} compared")
        for i in range(max(0, first_diff - 2), min(n, first_diff + 4)):
            print(f"  {i:4d} tick {i * 32:6d}  PAL {la[i]:04x}  NTSC {lb[i]:04x}")
        if first_diff == 0:
            sa_ = open(os.path.join(ROOT, "build", "det_snap_pal.bin"), "rb").read()
            sb_ = open(os.path.join(ROOT, "build", "det_snap_ntsc.bin"), "rb").read()
            names = {v: k for k, v in sorted(lbl.items(), key=lambda kv: -len(kv[0]))}
            def where(i: int) -> str:
                if i < 0x100:
                    a = i
                elif i < 0x200:
                    a = 0x100 + i
                elif i < 0x300:
                    return f"$D0{i - 0x200:02X}"
                else:
                    a = 0x400 + i - 0x300
                near = max((x for x in names if x <= a), default=0)
                return f"${a:04X} {names.get(near, '')}+{a - near}"
            diffs = [i for i in range(0x700) if sa_[i] != sb_[i]]
            print(f"  first snapshot: {len(diffs)} bytes differ")
            for i in diffs[:30]:
                print(f"    {where(i):40s} PAL {sa_[i]:02x}  NTSC {sb_[i]:02x}")
    sys.exit(0 if n and first_diff is None else 1)


if __name__ == "__main__":
    main()
