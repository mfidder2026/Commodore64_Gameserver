#!/usr/bin/env python3
"""Head-to-head test without the server: two VICEs with RR-Net, each with its own
copy of the test disk. A hosts (lobby AUTO=H), B searches and joins (AUTO=J); a
test bot plays on both C64s.
    python tools/directtest.py [seconds] [--no-build] [--iface NAME]
Every 10 s it prints both C64s' game tick; screenshots go to build/direct_a_*.png
and build/direct_b_*.png.
"""
import os
import re
import shutil
import subprocess
import sys
import time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dettest import BUILD, ROOT, VICE, c64env, monitor, read_mem  # noqa: E402

C1541 = c64env.vice("c1541")
DEFAULT_IF = r"\Device\NPF_{BD187BD7-EF69-4A3B-B098-BEC90E6A20AA}"   # as tools/nettest.py
PLAYERS = [("a", "ALICE", "H", "021111111101", 6530), ("b", "BOB", "J", "021111111102", 6531)]


def arg(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def make_disk(tag, nick, auto, mac):
    disk = os.path.join(BUILD, f"direct_{tag}.d64")
    shutil.copy(os.path.join(BUILD, "bblan-test.d64"), disk)
    cfg = os.path.join(BUILD, f"direct_{tag}.cfg")
    with open(cfg, "wb") as f:      # PETSCII upper case = ASCII upper case
        f.write(f"NAME={nick}\rMAC={mac}\rAUTO={auto}\rBOT=1\r".encode())
    subprocess.run([C1541, "-attach", disk, "-write", cfg, "bblan.cfg,s"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return disk


def label(name):
    """an address from the RR-Net build's label file"""
    with open(os.path.join(BUILD, "bbr.lbl"), encoding="utf-8") as f:
        for line in f:
            m = re.match(r"al ([0-9A-Fa-f]+) \.(\S+)", line)
            if m and m.group(2) == name:
                return int(m.group(1), 16)
    return None


def main():
    seconds = float(next((a for a in sys.argv[1:] if a.replace(".", "").isdigit()), 90))
    iface = arg("--iface", os.environ.get("NPCAP_IF", DEFAULT_IF))
    if "--no-build" not in sys.argv:
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", "build.py"), "testdisk"],
                       check=True, stdout=subprocess.DEVNULL)
    tick = label("bb_tick")
    vices = []
    try:
        for tag, nick, auto, mac, port in PLAYERS:
            disk = make_disk(tag, nick, auto, mac)
            vices.append(subprocess.Popen(
                [VICE, "-default", "-minimized", "-pal", "-sounddev", "dummy", "+drive8truedrive", "-virtualdev8",
                 "-ethernetcart", "-ethernetcartmode", "1", "-ethernetioif", iface,
                 "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{port}",
                 "-autostart", disk], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
            time.sleep(4)   # VICE instances started together miss their monitor port
        t0 = time.time()
        n = 0
        while time.time() - t0 < seconds:
            time.sleep(10)
            n += 1
            line = f"[{time.time() - t0:5.0f}s]"
            for tag, _, _, _, port in PLAYERS:
                try:
                    monitor(port, f'screenshot "{os.path.join(BUILD, f"direct_{tag}_{n}.png")}" 2')
                    if tick:
                        t = read_mem(port, tick, tick + 1)
                        line += f" {tag}: tick {t[0] | t[1] << 8}"
                except (OSError, RuntimeError):
                    line += f" {tag}: no monitor"
            print(line, flush=True)
    finally:
        for v in vices:
            v.kill()


if __name__ == "__main__":
    main()
