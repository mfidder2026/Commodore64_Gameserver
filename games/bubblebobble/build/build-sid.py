#!/usr/bin/env python3
"""
Build a standalone PSID v2 SID file from any conforming sound source.

Assembles sid-wrapper.s (which .includes the specified sound source) with ca65,
links with sid.cfg via ld65 into a single contiguous binary at a configurable
base address, then wraps it in a PSID v2 header.

The sound source is selected via --sound-src (default: sound.s).

All conforming sources export the same API symbols (sound_init, sound_update,
music_start, song labels, etc.) and use three segments (SOUND_LO,
SCREEN_BUFFER, SOUND_HI) that the linker places contiguously. The result
is fully relocatable.

Usage:
    python3 build-sid.py [--sound-src sound.s] [output.sid]
"""

import argparse
import os
import struct
import subprocess
import sys
import tempfile

PSID_HEADER_SIZE = 0x7C
NUM_SONGS = 12
DEFAULT_BASE = 0x1000

# Per-source metadata for the PSID header.
# Any source not listed here gets generic defaults.
SOUND_METADATA = {
    "sound.s": {
        "title": "Bubble Bobble",
        "author": "Peter Clarke / Greve / MTR",
        "released": "1987 Firebird",
        "default_song": 7,  # Title screen (1-based)
    },
}

SONG_NAMES = [
    "Main level theme",
    "Level resume",
    "Level 99 theme",
    "Bonus round",
    "Game over",
    "Level complete",
    "Title screen",
    "EXTEND fanfare",
    "Hurry-up",
    "Round start",
    "Super bonus",
    "Ending",
]


def run_cmd(cmd, desc):
    print(f"  {desc}: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"ERROR: {desc} failed:", file=sys.stderr)
        if result.stdout:
            print(result.stdout, file=sys.stderr)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
        sys.exit(1)
    return result


def parse_labels(label_file):
    labels = {}
    with open(label_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith(";"):
                continue
            parts = line.split()
            if len(parts) >= 3 and parts[0] == "al":
                addr = int(parts[1], 16)
                name = parts[2].lstrip(".")
                labels[name] = addr
    return labels


def trim_trailing(data):
    """Trim trailing zero/NOP padding bytes."""
    end = len(data)
    while end > 0 and data[end - 1] in (0x00, 0xEA):
        end -= 1
    return data[:end]


def build_psid_header(
    init_addr, play_addr, num_songs, start_song, title, author, released
):
    hdr = bytearray()
    hdr += b"PSID"
    hdr += struct.pack(">H", 2)  # version
    hdr += struct.pack(">H", PSID_HEADER_SIZE)  # data offset
    hdr += struct.pack(">H", 0)  # load addr (embedded in data)
    hdr += struct.pack(">H", init_addr)
    hdr += struct.pack(">H", play_addr)
    hdr += struct.pack(">H", num_songs)
    hdr += struct.pack(">H", start_song)
    hdr += struct.pack(">I", 0)  # speed: 0 = VBlank for all
    for s in (title, author, released):
        b = s.encode("ascii")[:31] + b"\x00"
        hdr += b.ljust(32, b"\x00")
    hdr += struct.pack(">H", 0x0024)  # flags: PAL, uses $D400
    hdr += bytes(4)  # reserved
    assert len(hdr) == PSID_HEADER_SIZE
    return bytes(hdr)


def main():
    parser = argparse.ArgumentParser(
        description="Build a standalone SID file from a conforming sound source"
    )
    parser.add_argument(
        "--sound-src",
        default="sound.s",
        help="Sound source file to include (default: sound.s)",
    )
    parser.add_argument(
        "--base",
        type=lambda x: int(x, 0),
        default=DEFAULT_BASE,
        help=f"Load base address (default: ${DEFAULT_BASE:04X})",
    )
    parser.add_argument("output", nargs="?", default=None, help="Output SID file path")
    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    src_dir = os.path.join(os.path.dirname(script_dir), "src")

    sound_src = args.sound_src
    base_addr = args.base

    # Look up source metadata (fall back to generic defaults)
    meta = SOUND_METADATA.get(sound_src, {})
    title = meta.get("title", "Bubble Bobble")
    author = meta.get("author", "Unknown")
    released = meta.get("released", "")
    default_song = meta.get("default_song", 1)

    # Default output filename derived from source name
    if args.output:
        output_path = args.output
    else:
        stem = os.path.splitext(sound_src)[0]
        output_path = os.path.join(script_dir, f"rebb64-{stem}.sid")

    wrapper_src = os.path.join(src_dir, "sid-wrapper.s")
    linker_cfg = os.path.join(script_dir, "sid.cfg")

    # Verify source files exist
    sound_path = os.path.join(src_dir, sound_src)
    if not os.path.exists(sound_path):
        print(f"ERROR: Sound source not found: {sound_path}", file=sys.stderr)
        sys.exit(1)

    print(f"Building standalone SID from {sound_src}...")
    print(f"  Base address: ${base_addr:04X}")
    print(f"  Songs: {NUM_SONGS}")
    for i, name in enumerate(SONG_NAMES):
        print(f"    {i + 1:2d}. {name}")

    with tempfile.TemporaryDirectory(prefix="rebb64-sid-") as tmpdir:
        obj_file = os.path.join(tmpdir, "sid-wrapper.o")
        bin_file = os.path.join(tmpdir, "sid.bin")
        lbl_file = os.path.join(tmpdir, "sid.lbl")

        # Write a tiny include file that selects the sound source.
        # ca65 -D only supports numeric constants, so we use a generated
        # include file for the string parameter.
        sound_inc = os.path.join(tmpdir, "sound-select.inc")
        with open(sound_inc, "w") as f:
            f.write(f'.include "{sound_src}"\n')

        # Assemble: pass SID_BUILD flag and include path for sound-select.inc
        run_cmd(
            [
                "ca65",
                "--cpu",
                "6502",
                "-g",
                "-D",
                "SID_BUILD=1",
                "-I",
                src_dir,
                "-I",
                tmpdir,
                "-o",
                obj_file,
                wrapper_src,
            ],
            "Assemble",
        )

        # Link: single output binary at configurable base address
        run_cmd(
            [
                "ld65",
                "-C",
                linker_cfg,
                "-D",
                f"__BASE__=${base_addr:04X}",
                "-Ln",
                lbl_file,
                "-o",
                bin_file,
                obj_file,
            ],
            "Link",
        )

        # Read output binary and labels
        with open(bin_file, "rb") as f:
            raw_data = f.read()

        labels = parse_labels(lbl_file)

    # Validate required labels
    init_addr = labels.get("sid_init")
    play_addr = labels.get("sid_play")

    if init_addr is None or play_addr is None:
        print("ERROR: Could not find sid_init/sid_play in labels", file=sys.stderr)
        sys.exit(1)

    # Trim trailing padding
    trimmed = trim_trailing(raw_data)
    end_addr = base_addr + len(trimmed)

    # Print segment info from labels
    print(f"\n  Binary size: {len(trimmed)} bytes (trimmed from {len(raw_data)})")
    print(f"  Load range:  ${base_addr:04X}-${end_addr - 1:04X}")
    print(f"  sid_init:    ${init_addr:04X}")
    print(f"  sid_play:    ${play_addr:04X}")

    for name in [
        "sound_init",
        "sound_update",
        "music_start",
        "L_7040",
        "musichandlers_end",
        "title_music_voice0",
        "screen_buffer_end",
    ]:
        if name in labels:
            print(f"    {name:24s} ${labels[name]:04X}")

    # Build PSID header
    header = build_psid_header(
        init_addr=init_addr,
        play_addr=play_addr,
        num_songs=NUM_SONGS,
        start_song=default_song,
        title=title,
        author=author,
        released=released,
    )

    # Assemble final SID: header + load address (little-endian) + data
    sid_file = header + struct.pack("<H", base_addr) + trimmed

    with open(output_path, "wb") as f:
        f.write(sid_file)

    file_size = len(sid_file)
    print(f"\nSID file written: {output_path}")
    print(f"  Size:       {file_size:,} bytes ({file_size / 1024:.1f} KB)")
    print(f"  Load range: ${base_addr:04X}-${end_addr - 1:04X}")
    print(f"  Init:       ${init_addr:04X}")
    print(f"  Play:       ${play_addr:04X}")
    print(
        f"  Songs:      {NUM_SONGS} (default: #{default_song} {SONG_NAMES[default_song - 1]})"
    )
    print(f"  Title:      {title}")
    print(f"  Author:     {author}")
    print(f"  Clock:      PAL (50 Hz)")


if __name__ == "__main__":
    main()
