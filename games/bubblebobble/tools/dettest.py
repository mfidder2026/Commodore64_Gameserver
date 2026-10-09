#!/usr/bin/env python3
"""Determinism test for the BB-LAN tick core.

Builds the DETTEST variants, runs each in its own VICE (warp, no sound) and
compares the game-state checksums they log every 64 ticks. The bot's input
depends on the tick number only, so every correct run must log exactly the
same checksums, whatever the timing:

    dettest         PAL
    dettest_jit     PAL, random CPU load every frame + random title time
    dettest (ntsc)  NTSC: different cycles per frame and IRQ positions
    dettest_jit (ntsc)
    dettest_stall   PAL, jitter and now and then 1-7 real frames stalled
                    (like waiting for the network)

    python tools/dettest.py [seconds] [--no-build] [--break]

--break builds with a known source of non-determinism (CIA timer in the
PRNG) to prove the test catches it.
"""
import os
import re
import socket
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
VICE = os.environ.get("VICE") or os.path.normpath(
    os.path.join(ROOT, "..", "c64", "vice", "bin", "x64sc.exe"))

VARIANTS = [  # (run name, build name, video)
    ("pal", "dettest", "pal"),
    ("pal_jitter", "dettest_jit", "pal"),
    ("ntsc", "dettest", "ntsc"),
    ("ntsc_jitter", "dettest_jit", "ntsc"),
    ("pal_stall", "dettest_stall", "pal"),
]
DET_MAX = 200                   # must match bblan.s
BUILDS = {"dettest": ["-D", "DETTEST=1"],
          "dettest_jit": ["-D", "DETTEST=1", "-D", "JITTER=1"],
          "dettest_stall": ["-D", "DETTEST=1", "-D", "JITTER=2"]}


def labels(name):
    lbl = {}
    with open(os.path.join(BUILD, name + ".lbl")) as f:
        for line in f:
            m = re.match(r"al ([0-9A-Fa-f]+) \.(\S+)", line)
            if m:
                lbl[m.group(2)] = int(m.group(1), 16)
    return lbl


def recv_all(s, wait=0.5):
    s.settimeout(wait)
    data = b""
    try:
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
    except socket.timeout:
        pass
    return data.decode("latin-1")


def monitor(port, *cmds):
    s = socket.create_connection(("127.0.0.1", port), timeout=5)
    recv_all(s)
    out = ""
    for cmd in cmds:
        s.sendall((cmd + "\n").encode())
        out += recv_all(s, 2.0)
    s.sendall(b"x\n")
    recv_all(s, 0.2)
    s.close()
    return out


def read_mem(port, start, end):
    """Read RAM via the monitor's 'm' command."""
    out = monitor(port, "bank ram", f"m {start:04x} {end:04x}")
    mem = {}
    for line in out.splitlines():
        m = re.search(r">C:([0-9a-f]{4})((?:\s+[0-9a-f]{2}){1,16})", line)
        if m:
            addr = int(m.group(1), 16)
            for i, b in enumerate(m.group(2).split()):
                mem[addr + i] = int(b, 16)
    missing = [a for a in range(start, end + 1) if a not in mem]
    if missing:
        raise RuntimeError(f"monitor read failed at ${missing[0]:04x}")
    return bytes(mem[a] for a in range(start, end + 1))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    seconds = float(args[0]) if args else 40
    if "--break" in sys.argv:            # negative test: must FAIL
        for defs in BUILDS.values():
            defs += ["-D", "DETBREAK=1"]
    if "--no-build" not in sys.argv:
        for name, defs in BUILDS.items():
            subprocess.run([sys.executable, os.path.join(ROOT, "tools", "build.py"),
                            "release", *defs, "-o", name], check=True,
                           stdout=subprocess.DEVNULL)

    procs = []
    for i, (run, build, video) in enumerate(VARIANTS):
        port = 6510 + i
        procs.append(subprocess.Popen(
            [VICE, "-default", "-minimized", f"-{video}", "-warp", "-sounddev", "dummy",
             "-autostartprgmode", "1", "-remotemonitor",
             "-remotemonitoraddress", f"ip4://127.0.0.1:{port}",
             "-autostart", os.path.join(BUILD, build + ".prg")],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    print(f"running {len(VARIANTS)} VICE instances for {seconds:.0f} s ...")
    time.sleep(seconds)

    logs = {}
    try:
        for i, (run, build, video) in enumerate(VARIANTS):
            lbl = labels(build)
            port = 6510 + i
            n = read_mem(port, lbl["det_n"], lbl["det_n"])[0]
            lo = read_mem(port, lbl["det_lo"], lbl["det_lo"] + DET_MAX - 1)
            hi = read_mem(port, lbl["det_hi"], lbl["det_hi"] + DET_MAX - 1)
            logs[run] = [lo[k] | (hi[k] << 8) for k in range(n)]
            monitor(port, f'screenshot "{os.path.join(BUILD, "det_" + run + ".png")}" 2')
    finally:
        for p in procs:
            p.kill()

    common = min(len(v) for v in logs.values())
    ref = logs[VARIANTS[0][0]]
    ok = True
    for run, log in logs.items():
        bad = next((k for k in range(common) if log[k] != ref[k]), None)
        status = "OK" if bad is None else f"DIFFERS from entry {bad} (tick {bad * 64})"
        ok &= bad is None
        print(f"  {run:12s} {len(log):3d} checksums  {status}")
    print(f"compared {common} checksums ({common * 64} ticks, "
          f"{common * 64 / 25:.0f} s game time)")
    if common < 2:
        print("FAIL: too few checksums")
        sys.exit(1)
    if not ok:
        for run, log in logs.items():
            print(f"  {run:12s} " + " ".join(f"{c:04x}" for c in log[:common]))
        sys.exit(1)
    print("PASS: all runs identical")


if __name__ == "__main__":
    main()
