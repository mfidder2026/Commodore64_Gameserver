"""
Packs the files for a GitHub release into dist/ (not in git):

    python tools/make_release.py [version]

- WizardOfWor-LAN-C64-<version>.zip          wow.d64 and wow.prg (build first: build.bat)
- C64GameServer-<version>-win-x64.zip         C64GameServer.exe, C64Bot.exe (publish first: server\\publish.bat)
- C64GameServer-<version>-linux-arm64.tar.gz  the same for a Raspberry Pi (64-bit OS), executable bits set
- release-notes.md                            text for the release page
"""
from __future__ import annotations

import os
import sys
import tarfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, "dist")

START_TXT = """C64 Game Server
===============

Windows:      double-click C64GameServer.exe (or start it in a terminal)
Raspberry Pi: ./C64GameServer

- C64s connect to UDP port 6465; the window shows the addresses to use.
- Dashboard: http://localhost:8080/
- Three bots (WORLUK, GARWOR, THORWOR) start with the server.
- Settings: server.json is created next to where you start the server.
- Windows asks for firewall access the first time: allow "Private networks".
- LAN only: no encryption, no accounts. Never expose it to the internet.

C64Bot is a test client that behaves like a C64: C64Bot --help

More: https://github.com/mfidder2026/Commodore64_Gameserver/tree/main/server
"""


def need(path: str, hint: str) -> str:
    full = os.path.join(ROOT, path)
    if not os.path.exists(full):
        sys.exit(f"missing {path}: {hint}")
    return full


def main() -> None:
    version = sys.argv[1] if len(sys.argv) > 1 else "v1.0"
    os.makedirs(DIST, exist_ok=True)

    c64 = os.path.join(DIST, f"WizardOfWor-LAN-C64-{version}.zip")
    with zipfile.ZipFile(c64, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(need("build/wow.d64", "run build.bat"), "wow.d64")
        z.write(need("build/wow.prg", "run build.bat"), "wow.prg")

    win = os.path.join(DIST, f"C64GameServer-{version}-win-x64.zip")
    with zipfile.ZipFile(win, "w", zipfile.ZIP_DEFLATED) as z:
        for f in ("C64GameServer.exe", "C64Bot.exe"):
            z.write(need(f"server/publish/win-x64/{f}", "run server\\publish.bat"), f)
        z.writestr("START.txt", START_TXT.replace("\n", "\r\n"))

    arm = os.path.join(DIST, f"C64GameServer-{version}-linux-arm64.tar.gz")
    with tarfile.open(arm, "w:gz") as t:
        for f in ("C64GameServer", "C64Bot"):
            info = t.gettarinfo(need(f"server/publish/linux-arm64/{f}", "run server\\publish.bat"), f)
            info.mode = 0o755  # executable on the Pi
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            with open(os.path.join(ROOT, "server", "publish", "linux-arm64", f), "rb") as src:
                t.addfile(info, src)
        data = START_TXT.encode()
        info = tarfile.TarInfo("START.txt")
        info.size = len(data)
        info.mode = 0o644
        import io
        t.addfile(info, io.BytesIO(data))

    notes = os.path.join(DIST, "release-notes.md")
    with open(notes, "w", encoding="utf-8", newline="\n") as f:
        f.write(f"""## Wizard of Wor LAN {version}

Two players, two Commodore 64s, one dungeon – over the LAN, via the C64 Game Server.

### Downloads

| File | For |
|---|---|
| `WizardOfWor-LAN-C64-{version}.zip` | the C64: `wow.d64` (mount it as drive 8 and load `WOW`; your settings are saved on it) and `wow.prg` |
| `C64GameServer-{version}-win-x64.zip` | the server on Windows 10/11 (64-bit), no installation and no .NET needed |
| `C64GameServer-{version}-linux-arm64.tar.gz` | the server on a Raspberry Pi with a 64-bit OS (`tar xzf …`, then `./C64GameServer`) |

### Quick start

1. Start `C64GameServer.exe` on a PC in your network and note the address it shows (`192.168.x.x`).
2. On the C64 Ultimate (Command Interface enabled) mount `wow.d64` and load `WOW`.
3. Choose **4 PLAY VIA A GAME SERVER**, enter a nickname and the server's address.
4. In the lobby, pick a player or one of the bots and press FIRE.

The next start remembers your name and server ("Welcome Dungeon Master") and goes straight to the lobby; F1 in the lobby changes them.

### What's in it

- Lobby on the C64 in the game's own font and colors: everyone online, person or bot, free / busy / playing; choose your opponent.
- Three built-in bots that accept every challenge.
- Settings file `WOW.CFG` on the disk.
- Keepalive during the transition screens; no more hang after a lost connection.
- Web dashboard on the server (http://localhost:8080/).
""")
    for p in (c64, win, arm, notes):
        print(f"{os.path.relpath(p, ROOT)}  ({os.path.getsize(p) // 1024} KB)")


if __name__ == "__main__":
    main()
