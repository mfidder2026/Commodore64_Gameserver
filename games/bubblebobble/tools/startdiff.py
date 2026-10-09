#!/usr/bin/env python3
"""Which memory differs at game start between a fresh machine and one that
has played before? (Both machines of a LAN session must start identically.)

Runs dettest_pre.prg (PREGAME: plays and quits a game first) twice, stops at
the first and at the second game start (bb_game_inited), dumps RAM
$0000-$FFFF and prints the differing ranges with labels.

    python tools/startdiff.py [--no-build] [--tick64]

--tick64: compare instead at the first checksum (tick 64) of the measured
game, a fresh machine (dettest) against one that played before (dettest_pre),
only over the ranges the checksum covers.
"""
import os
import re
import socket
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dettest import BUILD, ROOT, VICE, labels, recv_all  # noqa: E402


def run(name, hits, port, at="bb_game_inited", cond=""):
    lbl = labels(name)
    addr = lbl[at]
    if cond:
        cond = " if " + cond.format(**{k: f"${v:04x}" for k, v in lbl.items() if k.isidentifier()})
    out = os.path.join(BUILD, f"start_{name}.bin")
    if os.path.exists(out):
        os.remove(out)
    p = subprocess.Popen(
        [VICE, "-default", "-minimized", "-pal", "-warp", "-sounddev", "dummy", "-autostartprgmode", "1",
         "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{port}",
         "-autostart", os.path.join(BUILD, name + ".prg")],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(1.5)
        s = socket.create_connection(("127.0.0.1", port), timeout=5)
        recv_all(s, 1)
        s.sendall(f"break exec {addr:04x}{cond}\n".encode())
        recv_all(s, 1)
        if hits > 1:
            s.sendall(f"ignore 1 {hits - 1}\n".encode())
            recv_all(s, 1)
        s.sendall(b"x\n")
        s.settimeout(300)
        data = b""
        while b"#1 (Stop on" not in data:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
        recv_all(s, 1)
        path = out.replace("\\", "/")
        s.sendall(b"bank ram\n")
        recv_all(s, 1)
        s.sendall(f'save "{path}" 0 0000 ffff\n'.encode())
        resp = recv_all(s, 3)
        if os.environ.get("DEBUG"):
            print(data.decode("latin-1")[-300:], resp)
    finally:
        p.kill()
    return open(out, "rb").read()[2:]


def main():
    if "--no-build" not in sys.argv:
        for name, defs in (("dettest", []), ("dettest_pre", ["-D", "JITTER=1", "-D", "PREGAME=1"])):
            subprocess.run([sys.executable, os.path.join(ROOT, "tools", "build.py"), "release",
                            "-D", "DETTEST=1", *defs, "-o", name], check=True,
                           stdout=subprocess.DEVNULL)
    if "--tick64" in sys.argv:
        # first checksum of the measured game: fresh machine vs after a game
        cond = "@cpu:{det_on} == $01"
        a = run("dettest", 1, 6570, "det_checksum", cond)
        b = run("dettest_pre", 1, 6571, "det_checksum", cond)
    else:
        a = run("dettest_pre", 1, 6570)
        os.replace(os.path.join(BUILD, "start_dettest_pre.bin"), os.path.join(BUILD, "start_fresh.bin"))
        b = run("dettest_pre", 2, 6571)
    syms = sorted((v, k) for k, v in labels("dettest_pre").items() if not k.startswith("@"))

    def where(x):
        best = max((s for s in syms if s[0] <= x), default=(0, "?"), key=lambda s: s[0])
        return f"{best[1]}+{x - best[0]}"

    only = None
    if "--tick64" in sys.argv:        # the ranges det_checksum covers
        only = set()
        for lo, n in ((0x10, 1), (0x26, 2), (0x2A, 4), (0x5D, 2), (0xB2, 0x46), (0x14B, 0x5C),
                      (0x400, 0x5C), (0x8480, 0x480), (0xA824, 2), (0xA9B1, 1)):
            only.update(range(lo, lo + n))
    diffs = [i for i in range(len(a)) if a[i] != b[i] and (only is None or i in only)]
    groups = []
    for d in diffs:
        if groups and d - groups[-1][1] <= 4:
            groups[-1][1] = d
        else:
            groups.append([d, d])
    for lo, hi in groups:
        print(f"  ${lo:04X}-${hi:04X} {hi - lo + 1:5d}  {where(lo)}")
    print(f"{len(diffs)} bytes differ in {len(groups)} ranges")


if __name__ == "__main__":
    main()
