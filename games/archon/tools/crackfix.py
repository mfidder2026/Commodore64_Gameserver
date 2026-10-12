#!/usr/bin/env python3
"""
Removes what the cracker ("The ... Associates", 1984) added to Archon: the line
"CRACKED (C) 1984 BY THE ... ASSOCIATES" on the title screen. The title's texts
are records [row] [column] [text], the text in ASCII with $00 as a space and a
few characters of its own ("(C) 1984" and the group's name); the line becomes
spaces of the same length, so everything around it stays where it was.

    python tools/crackfix.py      orig/archon.prg -> build/clean/archon.prg

(orig/archon.prg is the one file of orig/archon.t64; tools/snapshot.py runs the
clean one.)
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PRG = os.path.join(ROOT, "orig", "archon.prg")
CLEAN = os.path.join(ROOT, "build", "clean", "archon.prg")
LOAD = 0x0801

# (address in the file, the cracked bytes); the fix is spaces ($00) of the same length
_LINE = b"CRACKED\x00ZC[\x00\\]^_\x00BY\x00THE\x00\x12\x13\x14\x15\x00ASSOCIATES"
FIXES = [(0x9609, _LINE)]


def fix(prg: bytes) -> bytes:
    data = bytearray(prg)
    assert data[0] | data[1] << 8 == LOAD
    for addr, old in FIXES:
        i = addr - LOAD + 2
        if bytes(data[i:i + len(old)]) != old:
            sys.exit(f"${addr:04X}: not the expected cracked bytes")
        data[i:i + len(old)] = bytes(len(old))
    return bytes(data)


def clean() -> str:
    os.makedirs(os.path.dirname(CLEAN), exist_ok=True)
    with open(PRG, "rb") as f:
        fixed = fix(f.read())
    with open(CLEAN, "wb") as f:
        f.write(fixed)
    return CLEAN


if __name__ == "__main__":
    print("built", os.path.relpath(clean(), ROOT))
