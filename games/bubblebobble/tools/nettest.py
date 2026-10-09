#!/usr/bin/env python3
"""End-to-end LAN test: the game server (raw Ethernet via pcap) and two VICEs
with RR-Net, each with its own copy of the test disk.

    python tools/nettest.py [seconds] [--no-build] [--iface NAME] [--warp] [--dump N] [--wic64]

--wic64: the C64s use VICE's WiC64 emulation (TCP to 127.0.0.1:6466)
instead of RR-Net.

--dump N: after N polls save the RAM of both C64s (build/dump_a.bin, dump_b.bin);
use with a test disk built with -D HALT_AT=tick to compare them at one tick.

Player A ("ALICE") invites automatically, player B ("BOB") accepts; a test bot
plays on both C64s (build/bblan-test.d64). The server compares the C64s'
state checksums; a desync ends the session. Progress comes from the server's
dashboard API; screenshots go to build/net_a_*.png / net_b_*.png.

The interface defaults to $NPCAP_IF or the Wi-Fi interface of this PC; see
"C64GameServer --list-interfaces".
"""
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dettest import BUILD, ROOT, VICE, monitor  # noqa: E402

C1541 = os.path.join(os.path.dirname(VICE), "c1541.exe")
SRV_DIR = os.path.join(BUILD, "srvtest")
DEFAULT_IF = r"\Device\NPF_{BD187BD7-EF69-4A3B-B098-BEC90E6A20AA}"
PLAYERS = [("a", "ALICE", "I", "021111111101", 6520), ("b", "BOB", "A", "021111111102", 6521)]


def arg(name, default=None):
    if name in sys.argv:
        return sys.argv[sys.argv.index(name) + 1]
    return default


def make_disk(tag, nick, auto, mac, server=""):
    disk = os.path.join(BUILD, f"net_{tag}.d64")
    shutil.copy(os.path.join(BUILD, "bblan-test.d64"), disk)
    cfg = os.path.join(BUILD, f"net_{tag}.cfg")
    with open(cfg, "wb") as f:      # PETSCII upper case = ASCII upper case
        f.write(f"NAME={nick}\rMAC={mac}\rAUTO={auto}\rBOT=1\r".encode()
                + (f"SERVER={server}\r".encode() if server else b""))
    subprocess.run([C1541, "-attach", disk, "-write", cfg, "bblan.cfg,s"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return disk


def status():
    try:
        with urllib.request.urlopen("http://localhost:8080/api/status", timeout=2) as r:
            return json.load(r)
    except Exception:  # noqa: BLE001
        return None


def main():
    seconds = float(next((a for a in sys.argv[1:] if a.replace(".", "").isdigit()), 120))
    iface = arg("--iface", os.environ.get("NPCAP_IF", DEFAULT_IF))
    if "--no-build" not in sys.argv:
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", "build.py"), "testdisk",
                        *sum((["-D", d] for d in os.environ.get("TESTDEFS", "").split() if d), [])],
                       check=True, stdout=subprocess.DEVNULL)
    os.makedirs(SRV_DIR, exist_ok=True)
    srv_exe = os.path.join(SRV_DIR, "bin", "C64GameServer.exe")
    subprocess.run(["dotnet", "build", os.path.join(ROOT, "server", "src", "C64GameServer"),
                    "-c", "Release", "-o", os.path.dirname(srv_exe), "-v", "q"],
                   check=True, stdout=subprocess.DEVNULL)
    with open(os.path.join(SRV_DIR, "server.json"), "w") as f:
        json.dump({"gamePort": 6465, "dashboardPort": 8080, "bots": [], "logFile": "server.log",
                   "pcapInterface": iface, "pcapMac": "02:BB:4C:41:4E:01",
                   "games": [{"id": 3, "name": "Bubble Bobble", "module": "bubblebobble", "version": 1,
                              "settings": {"inputDelay": 2, "inputDelayWiC64": 4, "inputTimeoutSeconds": 10,
                                           "loadTimeoutSeconds": 150}}]}, f, indent=1)
    log = os.path.join(SRV_DIR, "server.log")
    if os.path.exists(log):
        os.remove(log)
    server = subprocess.Popen([srv_exe, "server.json"], cwd=SRV_DIR,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    vices = []
    try:
        time.sleep(3)
        wic = "--wic64" in sys.argv
        for tag, nick, auto, mac, port in PLAYERS:
            disk = make_disk(tag, nick, auto, mac, "127.0.0.1" if wic else "")
            hw = (["-userportdevice", "23"] if wic else
                  ["-ethernetcart", "-ethernetcartmode", "1", "-ethernetioif", iface])
            vices.append(subprocess.Popen(
                [VICE, "-default", "-minimized", "-pal", "-sounddev", "dummy", "+drive8truedrive", "-virtualdev8",
                 *(["-warp"] if "--warp" in sys.argv else []), *hw,
                 "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{port}",
                 "-autostart", disk], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
            time.sleep(4)   # VICE instances started together miss their monitor port
        t0 = time.time()
        n = 0
        dumps = {}
        while time.time() - t0 < seconds:
            time.sleep(10)
            n += 1
            st = status()
            line = f"[{time.time() - t0:5.0f}s]"
            if st:
                cl = st.get("players", [])
                line += " players: " + ", ".join(f"{c.get('nick')}({c.get('state')})" for c in cl)
                for s in st.get("sessions", []):
                    line += f" | session {s.get('id')} {s.get('duration')}: " + ", ".join(
                        f"{f['name']}={f['value']}" for f in (s.get("status") or []))
            print(line, flush=True)
            for tag, _, _, _, port in PLAYERS:
                try:
                    monitor(port, f'screenshot "{os.path.join(BUILD, f"net_{tag}_{n}.png")}" 2')
                except OSError:
                    pass
            if "--dump" in sys.argv and n >= int(arg("--dump")):
                for tag, _, _, _, port in PLAYERS:
                    path = os.path.join(BUILD, f"dump_{tag}.bin").replace("\\", "/")
                    monitor(port, "bank ram", f'save "{path}" 0 0000 ffff')
                    dumps[tag] = path
                break
    finally:
        for v in vices:
            v.kill()
        server.kill()
    if os.path.exists(log):
        print("--- server log (last lines)")
        with open(log, encoding="utf-8", errors="replace") as f:
            print("".join(f.readlines()[-25:]))


if __name__ == "__main__":
    main()
