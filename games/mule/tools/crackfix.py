#!/usr/bin/env python3
"""
Removes what the cracker ("Jedi", 1984) added to M.U.L.E., so our files show the
game as Electronic Arts released it:

  "m.u.l.e."  the credits screen: "CRACKED 1984 BY / JEDI" above the real credits,
              and the "JEDISCAPE" logo with its pyramid below them;
              the planet events: the pirates were renamed ("JEDI SHIP",
              "JEDIS TAKE ALL"): back to "PIRATE SHIP", "PIRATES TAKE ALL";
              a hidden "1 JEDI" behind the SYS in the BASIC line
  "&"         its title screen: "CRACKED 1984 BY / JEDI"

The game's strings are ASCII with bit 7 set; the last character of a string has
bit 7 clear ($0D = new line). The cracker kept every string's length, so every
fix here keeps it too: removed text becomes spaces ($A0, or $20 as the last
character), and the pirates fit exactly where they were.

    python tools/crackfix.py      orig/mule.d64 -> build/mule-clean.d64 (+ build/clean/*.prg)
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "..", "..", "framework", "tools"))
import c64env  # noqa: E402

D64 = os.path.join(ROOT, "orig", "mule.d64")
FILES = {"m.u.l.e.": "mule.prg", "&": "amp.prg"}   # name on the disk -> local name


def text(s: str, last_bit7: bool = False) -> bytes:
    """The game's encoding: bit 7 set, except on the last character (unless last_bit7)."""
    b = bytearray(ord(c) | 0x80 for c in s)
    if not last_bit7:
        b[-1] &= 0x7F
    return bytes(b)


def blank(old: bytes) -> bytes:
    """The same length, all spaces; line ends ($0D/$8D) and the terminator's bit stay."""
    out = bytearray()
    for c in old:
        if c & 0x7F == 0x0D:
            out.append(c)
        else:
            out.append(0xA0 if c & 0x80 else 0x20)
    return bytes(out)


# (file, address, the cracked bytes, the fixed bytes)
_CREDIT = text("CRACKED 1984 BY   ", True) + b"\x0d" + text("     JEDI     ", True) + b"\x0d"
_AMP_TITLE = text(" CRACKED 1984 BY   Y") + text("     JEDI      E")
FIXES: list[tuple[str, int, bytes, bytes]] = [
    ("mule.prg", 0x5AE6, _CREDIT, blank(_CREDIT)),
    ("mule.prg", 0x5B58, text("   JEDISCAPE  ", True) + b"\x20", blank(text("   JEDISCAPE  ", True) + b"\x20")),
    ("mule.prg", 0x5B67, bytes.fromhex("a0 a0 f5 f4 f5 20"), bytes.fromhex("a0 a0 a0 a0 a0 20")),
    ("mule.prg", 0x5B6D, bytes.fromhex("a0 a0 f9 fa fb 20"), bytes.fromhex("a0 a0 a0 a0 a0 20")),
    ("mule.prg", 0x1792, text("    JEDI  SHIP"), text("   PIRATE SHIP")),
    ("mule.prg", 0x17BB, text("   JEDIS TAKE ALL", True), text(" PIRATES TAKE ALL", True)),
    ("mule.prg", 0x080B, b"1 JEDI", b"      "),
    ("amp.prg", 0x639C, _AMP_TITLE, blank(_AMP_TITLE)),
]
LOAD = {"mule.prg": 0x0801, "amp.prg": 0x4000}


def fix(name: str, prg: bytes) -> bytes:
    data = bytearray(prg)
    assert data[0] | data[1] << 8 == LOAD[name]
    for fname, addr, old, new in FIXES:
        if fname != name:
            continue
        assert len(old) == len(new), (fname, hex(addr))
        i = addr - LOAD[name] + 2
        if bytes(data[i:i + len(old)]) != old:
            sys.exit(f"{fname} ${addr:04X}: not the expected cracked bytes")
        data[i:i + len(new)] = new
    return bytes(data)


def c1541(*args: str) -> None:
    subprocess.run([c64env.vice("c1541"), *args], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def clean_disk(out_d64: str) -> dict[str, str]:
    """A copy of orig/mule.d64 with the fixed files; returns {disk name: fixed prg path}."""
    work = os.path.join(ROOT, "build", "clean")
    os.makedirs(work, exist_ok=True)
    shutil.copy(D64, out_d64)
    paths = {}
    for disk_name, local in FILES.items():
        raw = os.path.join(work, "cracked-" + local)
        if os.path.exists(raw):
            os.remove(raw)
        c1541("-attach", D64, "-read", disk_name, raw)
        with open(raw, "rb") as f:
            fixed = fix(local, f.read())
        path = os.path.join(work, local)
        with open(path, "wb") as f:
            f.write(fixed)
        c1541("-attach", out_d64, "-delete", disk_name, "-write", path, disk_name)
        paths[disk_name] = path
    return paths


if __name__ == "__main__":
    out = os.path.join(ROOT, "build", "mule-clean.d64")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    for name, path in clean_disk(out).items():
        print(f"{name:10} -> {os.path.relpath(path, ROOT)}")
    print(f"built {os.path.relpath(out, ROOT)}")
