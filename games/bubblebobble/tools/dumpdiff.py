#!/usr/bin/env python3
"""Compare the RAM dumps of two C64s (tools/nettest.py --dump), with labels.

    python tools/dumpdiff.py [labels=build/bbr.lbl] [--all]

Without --all the expected differences are hidden: network buffers and
variables, the input rings, the stack, the sound player state.
"""
import os
import re
import sys

BUILD = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build")

# (start, end) inclusive: allowed to differ between the two C64s
EXPECTED = [(0x0001, 0x0001), (0x0078, 0x0079), (0x0080, 0x00A4), (0x0128, 0x0147), (0x01A7, 0x01FF),
            (0x7040, 0x743F), (0xF240, 0xFE8F)]


def main():
    lbl = next((a for a in sys.argv[1:] if not a.startswith("--")), os.path.join(BUILD, "bbr.lbl"))
    a = open(os.path.join(BUILD, "dump_a.bin"), "rb").read()[2:]
    b = open(os.path.join(BUILD, "dump_b.bin"), "rb").read()[2:]
    syms = []
    for line in open(lbl):
        m = re.match(r"al ([0-9A-F]+) \.(\S+)", line)
        if m and not m.group(2).startswith("@"):
            syms.append((int(m.group(1), 16), m.group(2)))
    syms.sort()
    code = dict((n, v) for v, n in syms)
    lo_ign = code.get("bb_rframe", 0xC5F2)

    def where(x):
        best = max((s for s in syms if s[0] <= x), default=(0, "?"), key=lambda s: s[0])
        return f"{best[1]}+{x - best[0]}"

    def expected(i):
        if "--all" in sys.argv:
            return False
        return any(s <= i <= e for s, e in EXPECTED) or lo_ign <= i < 0xCB1D
    diffs = [i for i in range(len(a)) if a[i] != b[i] and not expected(i)]
    groups = []
    for i in diffs:
        if groups and i - groups[-1][1] <= 4:
            groups[-1][1] = i
        else:
            groups.append([i, i])
    for lo, hi in groups[:120]:
        print(f"${lo:04X}-${hi:04X} {hi - lo + 1:4d} {where(lo):34s} "
              f"a={a[lo:min(hi + 1, lo + 10)].hex()} b={b[lo:min(hi + 1, lo + 10)].hex()}")
    print(f"{len(diffs)} bytes differ in {len(groups)} ranges")


if __name__ == "__main__":
    main()
