#!/usr/bin/env python3
"""Pack the raw $0400-$FFFA game image into a self-extracting, autostartable PRG.

The unpacker (tools/sfx.s) is assembled with ca65/ld65.

Stream format (optimal parse):
  0LLLLLLL               literal run, L+1 bytes follow (1..128)
  10LLLLLL o             match, length L+2 (2..65), distance o+1 (1..256)
  11LLLLLL lo hi         match, length L+3 (3..65; L < 63), distance 1..65535
  11111111 lo hi e       match, length e+66 (66..255), distance 1..65535
Decoding stops when the output reaches OUT_END (no end marker).
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

OUT_START = 0x0400
BLOB_END = 0xFFFB           # end of the raw image ($FFFA inclusive)
LOAD_LIMIT = 0xD000         # the PRG must load below the I/O area
MAX_LIT = 128
SHORT_MAX = 65
LONG_MAX = 255
MAX_TAIL = 0x40             # raw tail bytes (unpacker + tail must fit one page)
CHAIN = 48


def compress(data):
    """Optimal parse. Returns (stream, [(out_pos_after, stream_pos_after)])."""
    n = len(data)
    heads = {}
    prev = [-1] * n
    for i in range(n - 1):
        k = data[i] | data[i + 1] << 8
        prev[i] = heads.get(k, -1)
        heads[k] = i

    def matches(i):
        out = []
        best = 1
        j = prev[i] if i < n - 1 else -1
        steps = 0
        while j >= 0 and steps < CHAIN:
            d = i - j
            if d > 0xFFFF:
                break
            l = 0
            lim = min(LONG_MAX, n - i)
            while l < lim and data[j + l] == data[i + l]:
                l += 1
            if l > best or (d <= 256 and 2 <= l):
                out.append((l, d))
                best = max(best, l)
            j = prev[j]
            steps += 1
        return out

    def mcost(length, dist):
        if dist <= 256 and length <= SHORT_MAX:
            return 2
        if length < 3:
            return None
        return 3 if length <= 65 else 4

    INF = 1 << 30
    cost = [INF] * (n + 1)
    choice = [None] * (n + 1)
    cost[n] = 0
    for i in range(n - 1, -1, -1):
        best, bc = INF, None
        for r in range(1, min(MAX_LIT, n - i) + 1):
            c = 1 + r + cost[i + r]
            if c < best:
                best, bc = c, ("L", r)
        for l, d in matches(i):
            for ll in {l, min(l, SHORT_MAX), min(l, 65)}:
                if ll < 2:
                    continue
                mc = mcost(ll, d)
                if mc is None:
                    continue
                c = mc + cost[i + ll]
                if c < best:
                    best, bc = c, ("M", ll, d)
        cost[i], choice[i] = best, bc

    out = bytearray()
    marks = []
    i = 0
    while i < n:
        ch = choice[i]
        if ch[0] == "L":
            r = ch[1]
            out.append(r - 1)
            out += data[i:i + r]
            i += r
        else:
            _, l, d = ch
            if d <= 256 and l <= SHORT_MAX:
                out += bytes([0x80 | (l - 2), d - 1])
            elif l <= 65:
                out += bytes([0xC0 | (l - 3), d & 0xFF, d >> 8])
            else:
                out += bytes([0xFF, d & 0xFF, d >> 8, l - 66])
            i += l
        marks.append((i, len(out)))
    return bytes(out), marks


def decompress(stream, n):
    """Reference decoder, used to verify the packer output."""
    out = bytearray()
    p = 0
    while len(out) < n:
        t = stream[p]
        if t < 0x80:
            out += stream[p + 1:p + 2 + t]
            p += 2 + t
            continue
        if t < 0xC0:
            ln, dist = (t & 0x3F) + 2, stream[p + 1] + 1
            p += 2
        elif t != 0xFF:
            ln, dist = (t & 0x3F) + 3, stream[p + 1] | stream[p + 2] << 8
            p += 3
        else:
            ln, dist = stream[p + 3] + 66, stream[p + 1] | stream[p + 2] << 8
            p += 4
        for _ in range(ln):
            out.append(out[-dist])
    return bytes(out)


def overlap(marks, clen):
    """Max bytes by which the output overtakes unread input (<= 0 is safe)."""
    base = BLOB_END - clen
    return max(OUT_START + d - (base + s) for d, s in marks)


def pack(raw_prg, out_prg, entry, hb_addr=0):
    with open(raw_prg, "rb") as f:
        raw = f.read()
    assert raw[0] | (raw[1] << 8) == OUT_START, "raw image must start at $0400"
    image = raw[2:]
    assert OUT_START + len(image) == BLOB_END, f"image ends at ${OUT_START + len(image):04X}"

    # Find the smallest raw tail that makes in-place decompression safe.
    tail_len = 0
    while True:
        body = image[:len(image) - tail_len]
        stream, marks = compress(body)
        if overlap(marks, len(stream)) <= 0:
            break
        tail_len += overlap(marks, len(stream))
        if tail_len > MAX_TAIL:
            sys.exit(f"pack: tail too large ({tail_len})")
    assert decompress(stream, len(body)) == body
    tail = image[len(image) - tail_len:]

    build = os.path.dirname(os.path.abspath(out_prg))
    with open(os.path.join(build, "sfx-blob.bin"), "wb") as f:
        f.write(stream)
    with open(os.path.join(build, "sfx-tail.bin"), "wb") as f:
        f.write(tail)

    sys.path.insert(0, HERE)
    from build import find_tool
    ca65, ld65 = find_tool("ca65"), find_tool("ld65")
    defs = {"ENTRY": entry, "BLOB_END": BLOB_END, "OUT_END": BLOB_END - tail_len,
            "CLEN": len(stream), "TAIL_LEN": tail_len, "HB_ADDR": hb_addr}
    dargs = []
    for k, v in defs.items():
        dargs += ["-D", f"{k}=${v:04X}"]
    subprocess.run([ca65, "--cpu", "6502", *dargs, "-o", "sfx.o",
                    os.path.join(HERE, "sfx.s")], cwd=build, check=True)
    subprocess.run([ld65, "-C", os.path.join(HERE, "sfx.cfg"), "-o", out_prg, "sfx.o"],
                   cwd=build, check=True)
    size = os.path.getsize(out_prg) - 2
    end = 0x0801 + size
    if end > LOAD_LIMIT:
        sys.exit(f"pack: PRG too large, ends at ${end:04X}")
    print(f"packed {len(image)} -> {len(stream)} bytes (+{tail_len} raw tail), "
          f"PRG $0801-${end - 1:04X}, entry ${entry:04X}")
