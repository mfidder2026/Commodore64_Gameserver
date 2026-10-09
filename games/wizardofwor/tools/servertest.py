"""
End-to-end test via the C64 Game Server: the server plus two VICEs, each with
the emulated WiC64 (default) or as the bot opponent.

    python tools/servertest.py [seconds] [--no-build] [--bot]

Two C64s (ANNA and ERIK) with a WOW.CFG on their own copy of build/wow.d64
connect to the server on 127.0.0.1 (TCP 6466). The server pairs them by
itself (autoPair) and both accept through the test hook test_accept, so the
session runs without key presses. The server compares the state checksums of
the two C64s. With --bot only ANNA plays: a bot (C64Bot, the same code as the
server's built-in bots) invites her.

Progress comes from the dashboard API; screenshots go to build/srv_<name>_<n>.png.
"""
from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from paths import VICE_DIR  # noqa: E402
import c64env  # noqa: E402  (paths.py put framework/tools on the path)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
SRV_DIR = os.path.join(BUILD, "srvtest")
PLAYERS = [("ANNA", 6531), ("ERIK", 6532)]


def monitor(port: int, *cmds: str) -> str:
    out = ""
    with socket.create_connection(("127.0.0.1", port), timeout=5) as s:
        for c in cmds:
            s.sendall((c + "\n").encode())
            time.sleep(0.3)
        s.settimeout(0.5)
        try:
            while True:
                d = s.recv(65536)
                if not d:
                    break
                out += d.decode("latin-1")
        except socket.timeout:
            pass
        s.sendall(b"x\n")
    return out


def label(name: str) -> int:
    with open(os.path.join(BUILD, "wow.lbl")) as f:
        for line in f:
            parts = line.split()
            if len(parts) == 3 and parts[2] == "." + name:
                return int(parts[1], 16)
    raise SystemExit(f"label {name} not found")


def status() -> dict | None:
    try:
        with urllib.request.urlopen("http://localhost:8080/api/status", timeout=2) as r:
            return json.load(r)
    except Exception:  # noqa: BLE001
        return None


def main() -> None:
    seconds = float(next((a for a in sys.argv[1:] if a.replace(".", "").isdigit()), 120))
    vs_bot = "--bot" in sys.argv
    if "--no-build" not in sys.argv:
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", "build.py")], check=True, stdout=subprocess.DEVNULL)
    os.makedirs(SRV_DIR, exist_ok=True)
    exe = os.path.join(SRV_DIR, "bin", "C64GameServer.exe")
    subprocess.run(["dotnet", "build", os.path.join(c64env.SERVER, "src", "C64GameServer"), "-c", "Release",
                    "-o", os.path.dirname(exe), "-v", "q"], check=True, stdout=subprocess.DEVNULL)
    with open(os.path.join(SRV_DIR, "server.json"), "w") as f:
        json.dump({"gamePort": 6465, "tcpPort": 6466, "dashboardPort": 8080, "logFile": "server.log",
                   "autoPair": not vs_bot,
                   "games": [{"id": 1, "name": "Wizard of Wor", "module": "wizardofwor", "version": 1,
                              "bots": []}]}, f, indent=1)
    log = os.path.join(SRV_DIR, "server.log")
    if os.path.exists(log):
        os.remove(log)
    server = subprocess.Popen([exe, "server.json"], cwd=SRV_DIR, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    c1541 = c64env.vice("c1541")
    x64sc = os.path.join(VICE_DIR, "x64sc.exe")
    players = PLAYERS[:1] if vs_bot else PLAYERS
    vices = []
    try:
        time.sleep(3)
        for nick, port in players:
            disk = os.path.join(BUILD, f"srv_{nick.lower()}.d64")
            shutil.copy(os.path.join(BUILD, "wow.d64"), disk)
            cfg = os.path.join(BUILD, f"srv_{nick.lower()}.cfg")
            with open(cfg, "wb") as f:
                f.write(f"NAME={nick}\rSERVER=127.0.0.1\r".encode())
            subprocess.run([c1541, "-attach", disk, "-write", cfg, "wow.cfg,s"], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            vices.append(subprocess.Popen(
                [x64sc, "-default", "-minimized", "-sounddev", "dummy", "+drive8truedrive", "-virtualdev8",
                 "-userportdevice", "23", "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{port}",
                 "-autostart", disk], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
            time.sleep(4)
        time.sleep(8)
        hook = label("test_accept")
        for _, port in players:
            monitor(port, f"> {hook:04x} 01")
        if vs_bot:
            bot_dir = os.path.join(SRV_DIR, "bot")
            subprocess.run(["dotnet", "build", os.path.join(c64env.SERVER, "src", "C64Bot"), "-c", "Release",
                            "-o", bot_dir, "-v", "q"], check=True, stdout=subprocess.DEVNULL)
            vices.append(subprocess.Popen(
                [os.path.join(bot_dir, "C64Bot.exe"), "--server", "127.0.0.1", "--nick", "WORBOT", "--game", "1",
                 "--invite", "ANNA", "--human", "--no-checksum", "--ticks", "1000000", "--quiet"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        t0 = time.time()
        n = 0
        while time.time() - t0 < seconds:
            time.sleep(10)
            n += 1
            st = status()
            line = f"[{time.time() - t0:5.0f}s]"
            if st:
                line += " players: " + ", ".join(f"{c['nick']}({c['state']})" for c in st["players"])
                for s in st["sessions"]:
                    line += f" | session {s['id']} {s['duration']}: " + ", ".join(
                        f"{f['name']}={f['value']}" for f in (s.get("status") or []))
            print(line, flush=True)
            for nick, port in players:
                try:
                    path = os.path.join(BUILD, f"srv_{nick.lower()}_{n}.png").replace("\\", "/")
                    monitor(port, f'screenshot "{path}" 2')
                except OSError:
                    pass
    finally:
        for v in vices:
            v.kill()
        server.kill()
    if os.path.exists(log):
        print("--- server log (last lines)")
        with open(log, encoding="utf-8", errors="replace") as f:
            print("".join(f.readlines()[-20:]))


if __name__ == "__main__":
    main()
