#!/usr/bin/env python3
"""
End-to-end network test for a game on the framework's network code: the game
server plus two VICEs (or one against a server bot), each with its own copy of
the game's test disk.

    python framework/tools/nettest.py <game folder> [seconds] [--no-build] [--wic64] [--bot]
        [--players N] [--option N] [--iface NAME] [--direct]

The game's game.json has a "nettest" section:
    "nettest": {"testdisk": [build command], "disk": "build/x-test.d64", "cfg": "x.cfg",
                "server": {the game's entry for server.json}, "bot": "NAME"}

Player A ("ALICE") invites, player B ("BOB") accepts; the test disk's bot plays
on both C64s (cfg bot=1). --bot: only ALICE, who invites the server's bot.
--players N (2-4, games with tables): ALICE opens a table, BOB, CARL and DORA
sit down, and ALICE starts it when N players sit there (cfg seats=N); --option N:
the table's option (cfg option=N, e.g. the level).
--wic64: VICE's WiC64 emulation (TCP to 127.0.0.1:6466) instead of RR-Net
(raw Ethernet through the server's pcap interface: $NPCAP_IF or --iface).
--direct: head-to-head without the server (games with DIRECT_DELAY in lobby/game.h):
ALICE hosts (cfg auto=h), BOB searches and joins (auto=j), RR-Net only.
Progress comes from the server's dashboard API (--direct: both C64s' net_tick, from
the RR-Net test build's labels); screenshots go to <game>/build/net_a_<n>.png / net_b_<n>.png.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request

import c64env
import vicemon

DEFAULT_IF = r"\Device\NPF_{BD187BD7-EF69-4A3B-B098-BEC90E6A20AA}"
PLAYERS = [("a", "ALICE", "I", "021111111101", 6520), ("b", "BOB", "A", "021111111102", 6521),
           ("c", "CARL", "A", "021111111103", 6522), ("d", "DORA", "A", "021111111104", 6523)]


def arg(name: str, default: str | None = None) -> str | None:
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def status() -> dict | None:
    try:
        with urllib.request.urlopen("http://localhost:8080/api/status", timeout=2) as r:
            return json.load(r)
    except Exception:  # noqa: BLE001
        return None


def main() -> None:
    game_dir = os.path.abspath(sys.argv[1])
    with open(os.path.join(game_dir, "game.json"), encoding="utf-8") as f:
        game = json.load(f)
    nt = game["nettest"]
    build_dir = os.path.join(game_dir, "build")
    seconds = float(next((a for a in sys.argv[2:] if a.replace(".", "").isdigit()), 120))
    wic, vs_bot, direct = "--wic64" in sys.argv, "--bot" in sys.argv, "--direct" in sys.argv
    if direct and (wic or vs_bot):
        sys.exit("--direct: two C64s with RR-Net, no --wic64 or --bot")
    iface = arg("--iface", os.environ.get("NPCAP_IF", DEFAULT_IF))
    if "--no-build" not in sys.argv:
        cmd = [sys.executable if c == "python" else c for c in nt["testdisk"]]
        subprocess.run(cmd, cwd=game_dir, check=True, stdout=subprocess.DEVNULL)

    tick = None
    if direct:      # the game's tick counter, from the last build's labels (RR-Net is built last)
        with open(os.path.join(build_dir, "main.lbl")) as f:
            for line in f:
                p = line.split()
                if len(p) == 3 and p[2].lstrip(".") == "net_tick":
                    tick = int(p[1], 16)
    srv_dir = os.path.join(build_dir, "srvtest")
    log = os.path.join(srv_dir, "server.log")
    server = None
    if not direct:
        os.makedirs(srv_dir, exist_ok=True)
        exe = os.path.join(srv_dir, "bin", "C64GameServer.exe")
        subprocess.run(["dotnet", "build", os.path.join(c64env.SERVER, "src", "C64GameServer"), "-c", "Release",
                        "-o", os.path.dirname(exe), "-v", "q"], check=True, stdout=subprocess.DEVNULL)
        entry = dict(nt["server"], bots=[nt["bot"]] if vs_bot else [])
        with open(os.path.join(srv_dir, "server.json"), "w") as f:
            json.dump({"gamePort": 6465, "tcpPort": 6466, "dashboardPort": 8080, "logFile": "server.log",
                       "pcapInterface": "" if wic else iface, "pcapMac": "02:BB:4C:41:4E:01", "games": [entry]},
                      f, indent=1)
        if os.path.exists(log):
            os.remove(log)
        server = subprocess.Popen([exe, "server.json"], cwd=srv_dir, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL)
    c1541 = c64env.vice("c1541")
    count = int(arg("--players", "2"))
    players = PLAYERS[:1] if vs_bot else PLAYERS[:count]
    vices = []
    try:
        time.sleep(3)
        for tag, nick, auto, mac, port in players:
            if direct:
                auto = "H" if tag == "a" else "J"
            disk = os.path.join(build_dir, f"net_{tag}.d64")
            shutil.copy(os.path.join(game_dir, nt["disk"]), disk)
            cfg = os.path.join(build_dir, f"net_{tag}.cfg")
            with open(cfg, "wb") as f:  # PETSCII upper case = ASCII upper case
                f.write(f"NAME={nick}\rMAC={mac}\rAUTO={'B' if vs_bot else auto}\rBOT=1\rSEATS={count}\rOPTION={arg('--option', '0')}\r".encode()
                        + (b"SERVER=127.0.0.1\r" if wic else b""))
            subprocess.run([c1541, "-attach", disk, "-write", cfg, nt["cfg"] + ",s"], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            hw = ["-userportdevice", "23"] if wic else ["-ethernetcart", "-ethernetcartmode", "1", "-ethernetioif", iface]
            vices.append(vicemon.start(disk, port, extra=["+drive8truedrive", "-virtualdev8", *hw]))
            time.sleep(4)  # VICEs started together miss their monitor port
        t0 = time.time()
        n = 0
        while time.time() - t0 < seconds:
            time.sleep(10)
            n += 1
            st = None if direct else status()
            line = f"[{time.time() - t0:5.0f}s]"
            if direct and tick is not None:
                for tag, *_, port in players:
                    try:
                        out = vicemon.monitor(port, "bank ram", f"m {tick:04x} {tick + 1:04x}")
                        b = out.split(f">C:{tick:04x}")[1].split()[:2]
                        line += f" {tag}: tick {int(b[0], 16) | int(b[1], 16) << 8}"
                    except (OSError, IndexError, ValueError):
                        line += f" {tag}: ?"
            if st:
                line += " players: " + ", ".join(f"{c['nick']}({c['state']})" for c in st["players"])
                for s in st["sessions"]:
                    line += f" | session {s['id']} {s['duration']}: " + ", ".join(
                        f"{f['name']}={f['value']}" for f in (s.get("status") or []))
            print(line, flush=True)
            for tag, *_, port in players:
                try:
                    path = os.path.join(build_dir, f"net_{tag}_{n}.png").replace("\\", "/")
                    vicemon.monitor(port, f'screenshot "{path}" 2')
                except OSError:
                    pass
    finally:
        for v in vices:
            v.kill()
        if server:
            server.kill()
    if server and os.path.exists(log):
        print("--- server log (last lines)")
        with open(log, encoding="utf-8", errors="replace") as f:
            print("".join(f.readlines()[-25:]))


if __name__ == "__main__":
    main()
