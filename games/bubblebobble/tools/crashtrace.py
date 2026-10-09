#!/usr/bin/env python3
"""Run a build in VICE until the CPU executes in an address range, then dump
registers and CPU history (what ran just before a crash).

    python tools/crashtrace.py NAME [from] [to] [timeout]

Default range $0200-$03FF (tables, never code during play).
Set BP to use any other monitor breakpoint command, e.g.
    BP="break store 008f if A < $40" python tools/crashtrace.py lvl8
"""
import os
import socket
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dettest import BUILD, VICE, recv_all  # noqa: E402

PORT = 6540


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    name = sys.argv[1]
    lo = sys.argv[2] if len(sys.argv) > 2 else "0200"
    hi = sys.argv[3] if len(sys.argv) > 3 else "03ff"
    timeout = float(sys.argv[4]) if len(sys.argv) > 4 else 180
    p = subprocess.Popen(
        [VICE, "-default", "-minimized", "-pal", "-warp", "-sounddev", "dummy", "-autostartprgmode", "1",
         "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{PORT}",
         "-autostart", os.path.join(BUILD, name + ".prg")],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(6)                       # past the unpacker, which runs at $0200
        s = socket.create_connection(("127.0.0.1", PORT), timeout=5)
        recv_all(s, 1)
        bp = os.environ.get("BP") or f"break exec {lo} {hi}"
        s.sendall((bp + "\n").encode())
        print(recv_all(s, 1.5), flush=True)
        s.sendall(b"x\n")
        recv_all(s, 0.5)
        s.settimeout(timeout)
        data = b""
        try:
            while b"(C:$" not in data:
                chunk = s.recv(4096)
                if not chunk:
                    break
                data += chunk
        except socket.timeout:
            print("no hit within timeout", flush=True)
            return
        print(data.decode("latin-1"), flush=True)
        for cmd in ("r", "chis " + os.environ.get("CHIS", "120"), "m 0080 00af", *[f"m {r}" for r in os.environ.get("MEM", "").split(",") if r]):
            s.sendall((cmd + "\n").encode())
            print(f">>> {cmd}\n" + recv_all(s, 3), flush=True)
    finally:
        p.kill()


if __name__ == "__main__":
    main()
