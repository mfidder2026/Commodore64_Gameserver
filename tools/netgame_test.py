"""
Network game test: build/wow_netbot.prg (python tools/build.py netbot) in two VICE instances with RR-Net on the
same Npcap adapter, one hosting, one joining. Each machine's bot plays its own player; the game runs in lockstep,
so both machines must log exactly the same state checksums.

    python tools/netgame_test.py [seconds]

Environment: NPCAP_IF (default: the Wi-Fi adapter), C64_IP (host, 192.168.1.201), C64_IP2 (join, 192.168.1.202).
"""
from __future__ import annotations

import os
import struct
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vicemon as vm  # noqa: E402
from dettest import monitor  # noqa: E402
from profile_run import labels  # noqa: E402
from rrnet_test import IF_WIFI  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = "wow_netbot"


def start(port: int, iface: str) -> subprocess.Popen:
    return subprocess.Popen([os.path.join(vm.VICE_DIR, "x64sc.exe"), "-default", "-sounddev", "dummy",
                             "-ethernetcart", "-ethernetcartmode", "1", "-ethernetioif", iface,
                             "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{port}",
                             "-autostart", os.path.join(ROOT, "build", NAME + ".prg")],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def keys(port: int, text: str) -> None:
    monitor(port, "keybuf " + text)


def dump(port: int, tag: str, lbl: dict[str, int]) -> dict:
    log_path = os.path.join(ROOT, "build", f"net_{tag}_log.bin").replace("\\", "/")
    vars_path = os.path.join(ROOT, "build", f"net_{tag}_vars.bin").replace("\\", "/")
    net_path = os.path.join(ROOT, "build", f"net_{tag}_net.bin").replace("\\", "/")
    snap_path = os.path.join(ROOT, "build", f"net_{tag}_snap.bin").replace("\\", "/")
    monitor(port, "bank ram", f's "{log_path}" 0 {lbl["det_log"]:04x} {lbl["det_log"] + 2047:04x}',
            f's "{snap_path}" 0 {lbl["det_snap"]:04x} {lbl["det_snap"] + 0x6ff:04x}',
            "bank default",
            f's "{vars_path}" 0 {lbl["det_sessions"]:04x} {lbl["det_log_count"] + 1:04x}',
            f's "{net_path}" 0 {lbl["net_role"]:04x} {lbl["desync"]:04x}',
            f'screenshot "build/shot_net_{tag}.png" 2')
    ev_path = os.path.join(ROOT, "build", f"net_{tag}_ev.bin").replace("\\", "/")
    monitor(port, "bank ram", f's "{ev_path}" 0 e800 ebff', "bank default",
            f's "{ev_path}.cnt" 0 {lbl["ev_count"]:04x} {lbl["ev_count"] + 1:04x}')
    time.sleep(0.5)
    log = open(log_path, "rb").read()[2:]
    v = open(vars_path, "rb").read()[2:]
    n = open(net_path, "rb").read()[2:]
    count = struct.unpack_from("<H", v, lbl["det_log_count"] - lbl["det_sessions"])[0]
    ev = open(ev_path, "rb").read()[2:]
    evn = struct.unpack_from("<H", open(ev_path + ".cnt", "rb").read()[2:])[0]
    names = {1: "session start", 2: "session end", 3: "ABORT", 4: "START sent", 5: "START rx", 6: "ACK rx",
             7: "DESYNC", 8: "first tick"}
    events = []
    last = None
    for i in range(min(evn, 256)):
        code, lo, hi, extra = ev[4 * i:4 * i + 4]
        item = f"{names.get(code, code)}({extra})@{lo | hi << 8}"
        if code in (4,) and last == code:
            continue  # repeated START
        events.append(item)
        last = code
    return {
        "events": events,
        "sessions": v[0],
        "log": [struct.unpack_from("<H", log, 2 * i)[0] for i in range(min(count, 1024))],
        "role": n[0],
        "connected": n[lbl["net_connected"] - lbl["net_role"]],
        "desync": n[lbl["desync"] - lbl["net_role"]],
        "vars": {k: n[lbl[k] - lbl["net_role"]] | (n[lbl[k] - lbl["net_role"] + 1] << 8)
                 for k in ("game_id", "local_actor", "local_newest", "remote_newest", "netio_state", "start_state")},
    }


def main() -> None:
    seconds = float(sys.argv[1]) if len(sys.argv) > 1 else 60
    iface = os.environ.get("NPCAP_IF", IF_WIFI)
    host_ip = os.environ.get("C64_IP", "192.168.1.201")
    join_ip = os.environ.get("C64_IP2", "192.168.1.202")
    lbl = labels(os.path.join(ROOT, "build", NAME + ".lbl"))
    a = start(6510, iface)
    time.sleep(4)
    b = start(6511, iface)
    try:
        time.sleep(7)
        keys(6510, "2")                       # host
        time.sleep(1)
        keys(6510, host_ip + "\\x0d")        # my ip
        keys(6511, "3")                       # join
        time.sleep(1)
        keys(6511, join_ip + "\\x0d")        # my ip
        time.sleep(1)
        keys(6511, host_ip + "\\x0d")        # host ip
        time.sleep(8)
        monitor(6510, 'screenshot "build/shot_net_setup_host.png" 2')
        monitor(6511, 'screenshot "build/shot_net_setup_join.png" 2')
        keys(6510, r"\x0d")                  # PRESS A KEY -> game (a plain space would be an empty argument)
        keys(6511, r"\x0d")
        time.sleep(seconds)
        ra = dump(6510, "host", lbl)
        rb = dump(6511, "join", lbl)
    finally:
        a.kill()
        b.kill()
    for tag, r in (("HOST", ra), ("JOIN", rb)):
        print(f"{tag}: role {r['role']} connected {r['connected']} desync {r['desync']} "
              f"sessions {r['sessions']} checksums {len(r['log'])}  {r['vars']}")
        print("   events: " + ", ".join(r["events"][:40]))
    la, lb = ra["log"], rb["log"]
    n = min(len(la), len(lb))
    diff = next((i for i in range(n) if la[i] != lb[i]), None)
    if n == 0:
        print("no checksums - did the game start? see build/shot_net_*.png")
        sys.exit(1)
    if diff is None:
        print(f"IDENTICAL: {n} checksums = {n * 32} ticks ({n * 32 / 60:.0f} s) of lockstep play")
    else:
        print(f"DIFFERENT from checksum {diff} (tick {diff * 32})")
        sa = open(os.path.join(ROOT, "build", "net_host_snap.bin"), "rb").read()[2:]
        sb = open(os.path.join(ROOT, "build", "net_join_snap.bin"), "rb").read()[2:]
        names = {}
        for k, v in sorted(lbl.items(), key=lambda kv: -len(kv[0])):
            names[v] = k
        def where(i: int) -> str:
            if i < 0x200:
                a = i if i < 0x100 else 0x100 + i
            elif i < 0x300:
                return f"$D0{i - 0x200:02X}"
            else:
                a = 0x400 + i - 0x300
            near = max((x for x in names if x <= a), default=0)
            return f"${a:04X} {names.get(near, '')}+{a - near}"
        diffs = [i for i in range(0x700) if sa[i] != sb[i]]
        print(f"  first snapshot: {len(diffs)} bytes differ")
        for i in diffs[:40]:
            print(f"    {where(i):42s} host {sa[i]:02x}  join {sb[i]:02x}")
    sys.exit(0 if diff is None and not ra["desync"] and not rb["desync"] else 1)


if __name__ == "__main__":
    main()
