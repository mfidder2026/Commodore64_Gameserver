"""
Driving VICE through its remote text monitor, for every game's tools.

    import vicemon
    vice = vicemon.start("disk.d64", port=6560, extra=["-warp"])
    regs, ram = vicemon.stop_at(6560, 0x1158, "ram.bin")   # all 64 KB of RAM when the CPU gets there
    vicemon.monitor(6560, "m 0400 040f")                     # any monitor commands; the emulation goes on

Every command's answer must be read before the next one, and VICE refuses a new connection while
it is stopped in the monitor: always leave with "x" (monitor() does that).
"""
from __future__ import annotations

import os
import re
import socket
import subprocess
import time

import c64env

REG_RE = re.compile(r"\.;([0-9a-f]{4}) ([0-9a-f]{2}) ([0-9a-f]{2}) ([0-9a-f]{2}) ([0-9a-f]{2}) "
                    r"([0-9a-f]{2}) ([0-9a-f]{2})", re.I)


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
    return data.decode("latin-1")


def connect(port: int) -> socket.socket:
    for _ in range(20):
        try:
            return socket.create_connection(("127.0.0.1", port), timeout=5)
        except OSError:
            time.sleep(0.5)
    raise OSError(f"no VICE monitor on port {port}")


def monitor(port: int, *cmds: str, wait: float = 2.0) -> str:
    """Sends the commands, returns all answers; the emulation goes on afterwards."""
    with connect(port) as s:
        recv_all(s, 0.3)
        out = ""
        for cmd in cmds:
            s.sendall((cmd + "\n").encode())
            out += recv_all(s, wait)
        s.sendall(b"x\n")
        recv_all(s, 0.2)
    return out


def start(disk: str, port: int, extra: list[str] | None = None, pal: bool = True) -> subprocess.Popen:
    args = [c64env.vice("x64sc"), "-default", "-minimized", "-sounddev", "dummy", *(["-pal"] if pal else []),
            "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{port}", *(extra or []),
            "-autostart", disk]
    return subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def parse_registers(out: str) -> dict[str, int] | None:
    m = REG_RE.search(out)
    if not m:
        return None
    pc, a, x, y, sp, p00, p01 = (int(v, 16) for v in m.groups())
    return {"pc": pc, "a": a, "x": x, "y": y, "sp": sp, "00": p00, "01": p01}


def registers(port: int) -> dict[str, int]:
    """PC, A, X, Y, SP and the CPU port ($00/$01) from the monitor's 'r'."""
    for _ in range(5):
        r = parse_registers(monitor(port, "r"))
        if r:
            return r
        time.sleep(0.5)
    raise RuntimeError("cannot read the registers")


def stop_at(port: int, pc: int, ram_path: str, timeout: float = 120) -> tuple[dict[str, int], bytes]:
    """Sets an execution breakpoint at pc, waits until the CPU stops there and saves all 64 KB of RAM
    (bank ram: also under the ROMs and I/O) into ram_path. Returns the registers and the RAM.
    The connection stays open while waiting: VICE only reports a breakpoint to a connected client
    (otherwise it opens its own monitor window)."""
    if os.path.exists(ram_path):
        os.remove(ram_path)
    vpath = ram_path.replace("\\", "/")
    with connect(port) as s:
        recv_all(s, 0.3)
        s.sendall(f"break {pc:04x}\n".encode())
        recv_all(s, 0.5)
        s.sendall(b"x\n")
        t0 = time.time()
        seen = ""
        while time.time() - t0 < timeout:
            seen += recv_all(s, 1.0)
            if f"{pc:04x}".lower() in seen.lower() and "(C:$" in seen:
                break
        else:
            raise TimeoutError(f"the CPU did not reach ${pc:04X}")
        s.sendall(b"r\n")
        r = parse_registers(recv_all(s, 2.0))
        if r is None or r["pc"] != pc:
            raise RuntimeError(f"stopped, but not at ${pc:04X}: {r}")
        s.sendall(b"bank ram\n")
        recv_all(s, 0.5)
        s.sendall(f'bsave "{vpath}" 0 0000 ffff\n'.encode())
        recv_all(s, 2.0)
        s.sendall(b"x\n")
        recv_all(s, 0.2)
    for _ in range(20):
        if os.path.exists(ram_path) and os.path.getsize(ram_path) == 0x10000:
            break
        time.sleep(0.25)
    with open(ram_path, "rb") as f:
        return r, f.read()
