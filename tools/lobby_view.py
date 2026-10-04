"""
Shows the lobby screen without a server: starts build/wow.prg in VICE (no network hardware), fills the lobby list
through the remote monitor, starts the game in the server role and saves screenshots.
(VICE with RR-Net cannot reach a server on the same PC, so this is how the screen is checked on the PC.)

    python tools/lobby_view.py

Writes build/lobby_1.png (first player selected) and build/lobby_2.png (a challenge on the status line).
"""
from __future__ import annotations

import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vicemon as vm  # noqa: E402
from dettest import monitor  # noqa: E402
from profile_run import labels  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORT = 6512

PLAYERS = [  # nickname, flags (bit 0 bot, bits 1-2: 0 free, 2 busy, 4 playing)
    ("ANNA", 0x00), ("BERT", 0x04), ("CARL", 0x04), ("WORLUK", 0x01), ("GARWOR", 0x01), ("THORWOR", 0x05),
]


def poke(lbl: dict[str, int], name: str, values: list[int], offset: int = 0) -> str:
    return f"> {lbl[name] + offset:04x} " + " ".join(f"{v:02x}" for v in values)


def main() -> None:
    lbl = labels(os.path.join(ROOT, "build", "wow.lbl"))
    p = subprocess.Popen([os.path.join(vm.VICE_DIR, "x64sc.exe"), "-default", "-sounddev", "dummy", "-warp",
                          "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{PORT}",
                          "-autostart", os.path.join(ROOT, "build", "wow.prg")],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(12)
        monitor(PORT, 'screenshot "build/setup_menu.png" 2')
        cmds = [poke(lbl, "my_nick", list(b"ERIK")), poke(lbl, "my_nick_len", [4]),
                poke(lbl, "lobby_total", [len(PLAYERS)]), poke(lbl, "lobby_cursor", [0]),
                poke(lbl, "net_role", [3]), poke(lbl, "srv_state", [1]), poke(lbl, "in_ofs", [0])]
        for i, (nick, flags) in enumerate(PLAYERS):
            cmds += [poke(lbl, "lobby_id", [10 + i], i), poke(lbl, "lobby_flags", [flags], i),
                     poke(lbl, "lobby_len", [len(nick)], i), poke(lbl, "lobby_nick", list(nick.encode()), i * 8)]
        cmds.append(f"g {lbl['start_the_game']:04x}")
        monitor(PORT, *cmds)
        time.sleep(4)
        # without a server the status line says "no answer from the server": reset its silence timer first
        # (warp off: the monitor commands take a second each, and in warp mode the timer would run out again)
        quiet = [poke(lbl, "srv_silence", [0, 0]), poke(lbl, "srv_msg_timer", [0]), poke(lbl, "srv_state", [1])]
        monitor(PORT, "warp off", *quiet)
        time.sleep(0.2)
        monitor(PORT, 'screenshot "build/lobby_1.png" 2')
        # a challenge: the status line flashes
        monitor(PORT, *quiet[:2], poke(lbl, "opp_nick", list(b"ANNA")), poke(lbl, "opp_len", [4]),
                poke(lbl, "srv_state", [2]), poke(lbl, "lobby_cursor", [3]))
        time.sleep(0.3)
        monitor(PORT, 'screenshot "build/lobby_2.png" 2')
        print("build/setup_menu.png, build/lobby_1.png, build/lobby_2.png")
    finally:
        p.kill()


if __name__ == "__main__":
    main()
