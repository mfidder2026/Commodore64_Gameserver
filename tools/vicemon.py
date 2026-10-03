"""
Small helper to drive VICE through its text remote monitor (port 6510).

    python tools/vicemon.py <prg> <seconds> "<cmd1>" "<cmd2>" ...

Starts x64sc (warp, no sound) with the PRG, waits, sends the monitor commands and prints the answers.
Useful commands: "r" (registers), "m 0400 0427", "d 8000 8020", "bt" (backtrace)
"""
from __future__ import annotations

import os
import socket
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from paths import VICE_DIR  # noqa: E402  (environment, tools/paths.local.json or the PATH)


def recv_all(s: socket.socket, wait: float = 0.6) -> str:
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
    return "".join(ch if 32 <= ord(ch) < 127 or ch == "\n" else "." for ch in data.decode("latin-1"))


def session(prg: str, seconds: float, cmds: list[str], extra: list[str] | None = None) -> str:
    args = [os.path.join(VICE_DIR, "x64sc.exe"), "-default", "-sounddev", "dummy", "-warp",
            "-remotemonitor", "-remotemonitoraddress", "ip4://127.0.0.1:6510", *(extra or []),
            "-autostart", prg]
    p = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    out = ""
    try:
        time.sleep(seconds)
        s = socket.create_connection(("127.0.0.1", 6510), timeout=5)
        out += recv_all(s)
        for c in cmds:
            s.sendall((c + "\n").encode())
            out += f"\n>>> {c}\n" + recv_all(s)
        s.close()
    finally:
        p.kill()
    return out


if __name__ == "__main__":
    print(session(sys.argv[1], float(sys.argv[2]), sys.argv[3:]))
