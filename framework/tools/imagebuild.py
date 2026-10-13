"""
Building a game that has no source code: the base is the RAM image the game's
own loader leaves at the game's entry (a snapshot, made with VICE), and every
change is a patch to it, assembled with ca65.

    import imagebuild
    game = imagebuild.ImageGame(root, snapshot="orig/fist-1158.bin", lobby_file="fist",
                                files={"NET_UCI": "fistu", "NET_WIC": "fistw", "NET_RR": "fistr"},
                                disk_title="fist ome,ef")
    game.build(["NET_RR"], name="fistr")    # build/fistr.prg (packed) and build/fistr-raw.prg
    game.disk()                             # build/<lobby_file>.d64: the lobby + the game files

The game folder has:
  orig/<snapshot>.bin + .json   the RAM image ($0000-$FFFF) and its sha256 ("sha256")
  src/main.s                    the patches; a segment P_xxxx is placed at $xxxx
  src/areas.json                every area a patch may touch:
                                [{"start": "C000", "end": "C03E", "what": "...", "segments": ["X"]}]
                                (named segments go to the start of their area, in that order;
                                {"include": "other.json"} adds the areas of another file)
  src/netgame.inc               settings for framework/c64/net/net.s, which is linked in
  lobby/game.h                  settings for the standard lobby
The build writes build/low.bin ($0000-$03FF of the snapshot) for src/main.s to include: the
framework's unpacker uses $0200-$03BF, so a game usually restores low memory at its entry.
The entry is the label <entry_label> (exported), the handoff block net_hb (net.s).
Example: games/explodingfist; see docs/adding-a-game.md.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys

import c64env

FRAMEWORK = c64env.FRAMEWORK
NET_SRC = os.path.join(FRAMEWORK, "c64", "net", "net.s")
LOBBY_SRC = os.path.join(FRAMEWORK, "c64", "lobby")
IMAGE_START, IMAGE_END = 0x0400, 0xFFFB  # what the framework packer takes ($0400-$FFFA)


class ImageGame:
    def __init__(self, root: str, snapshot: str, lobby_file: str, files: dict[str, str], disk_title: str,
                 entry_label: str = "game_entry", local_file: str | None = None,
                 extra_files=None, local_net: bool = True):
        self.root = root
        self.build_dir = os.path.join(root, "build")
        self.src = os.path.join(root, "src")
        self.snapshot_path = os.path.join(root, snapshot)
        self.lobby_file = lobby_file
        self.files = files
        self.disk_title = disk_title
        self.entry_label = entry_label
        self.local_file = local_file  # a build without defines on the disk too (lobby key L, LOCAL_GAME_FILE)
        self.extra_files = extra_files  # callable -> [(path, name on the disk)]: more files for the disk
        self.local_net = local_net      # False: a build without defines has no network code (net.s)
        self.areas_file = "areas.json"
        self.variants: dict[str, str] = {}  # define -> areas file (e.g. {"ONLINE": "areas-online.json"})

    # --- helpers -----------------------------------------------------------------
    def run(self, cmd: list[str]) -> None:
        r = subprocess.run(cmd, cwd=self.build_dir, capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stdout + r.stderr)
            sys.exit(f"failed: {' '.join(cmd)}")

    def snapshot(self) -> bytearray:
        with open(self.snapshot_path, "rb") as f:
            ram = f.read()
        with open(os.path.splitext(self.snapshot_path)[0] + ".json") as f:
            expected = json.load(f)["sha256"]
        if hashlib.sha256(ram).hexdigest() != expected:
            sys.exit(f"{self.snapshot_path} is not the expected image (make it again with tools/snapshot.py)")
        return bytearray(ram)

    def areas(self, name: str | None = None) -> list[dict]:
        """The areas file of this build; an entry {"include": "file.json"} adds that file's areas."""
        with open(os.path.join(self.src, name or self.areas_file), encoding="utf-8") as f:
            out = []
            for a in json.load(f):
                out += self.areas(a["include"]) if "include" in a else [a]
            return out

    def read_labels(self) -> dict[str, int]:
        """Labels of the last build (ld65 -Ln; all labels, since ca65 runs with -g)."""
        labels = {}
        with open(os.path.join(self.build_dir, "main.lbl")) as f:
            for line in f:
                p = line.split()
                if len(p) == 3:
                    labels[p[2].lstrip(".")] = int(p[1], 16)
        return labels

    # --- the patches ---------------------------------------------------------------
    def assemble(self, defines: list[str], net: bool = True) -> dict[int, int]:
        """Assembles src/main.s and net.s (net=False: main.s only), links them twice (fill $00
        and $FF): the bytes that agree are the patch bytes. Returns {address: byte}."""
        placed = []
        for name in os.listdir(self.src):
            if name.endswith((".s", ".inc")):
                with open(os.path.join(self.src, name), encoding="utf-8") as f:
                    for a in re.findall(r'\.segment\s+"P_([0-9A-Fa-f]{4})"', f.read()):
                        placed.append((int(a, 16), f"P_{a.upper()}"))
        order: list[tuple[int | None, str]] = sorted(set(placed), key=lambda p: p[0])
        for area in self.areas():
            if area.get("segments"):
                addr, names = int(area["start"], 16), area["segments"]
                i = next((k for k, p in enumerate(order) if p[0] is not None and p[0] > addr), len(order))
                order[i:i] = [(addr, names[0])] + [(None, n) for n in names[1:]]
        dargs = sum((["-D", d] for d in defines), [])
        common = [c64env.cc65("ca65"), "--cpu", "6502", "-g", "-I", self.src,
                  "--bin-include-dir", self.build_dir, *dargs]
        self.run([*common, "-o", "main.o", "-l", "main.lst", os.path.join(self.src, "main.s")])
        objs = ["main.o"]
        if net:
            self.run([*common, "-o", "net.o", "-l", "net.lst", NET_SRC])
            objs.append("net.o")
        images = []
        for fill in (0x00, 0xFF):
            cfg = os.path.join(self.build_dir, f"patch{fill:02x}.cfg")
            with open(cfg, "w") as f:
                f.write(f"MEMORY {{ RAM: start = $0000, size = $10000, file = %O, fill = yes, "
                        f"fillval = ${fill:02X}; }}\n")
                f.write("SEGMENTS {\n")
                for addr, name in order:
                    where = f", start = ${addr:04X}" if addr is not None else ""
                    f.write(f"  {name}: load = RAM, type = rw{where};\n")
                f.write("}\n")
            out = os.path.join(self.build_dir, f"patch{fill:02x}.bin")
            self.run([c64env.cc65("ld65"), "-C", cfg, "-o", out, "-m", "main.map", "-Ln", "main.lbl",
                      *objs])
            with open(out, "rb") as f:
                images.append(f.read())
        a, b = images
        return {i: a[i] for i in range(0x10000) if a[i] == b[i]}

    def check_areas(self, patch: dict[int, int]) -> None:
        areas = [(int(a["start"], 16), int(a["end"], 16)) for a in self.areas()]
        bad = sorted(a for a in patch if not any(s <= a <= e for s, e in areas))
        if bad:
            sys.exit(f"patch outside src/areas.json at ${bad[0]:04X} ({len(bad)} bytes)")

    def build(self, defines: list[str] | None = None, name: str | None = None) -> str:
        """The patched image (build/<name>-raw.prg) and the packed game file (build/<name>.prg)."""
        name = name or self.lobby_file
        defines = defines or []
        self.areas_file = next((f for d, f in self.variants.items() if d in defines), "areas.json")
        os.makedirs(self.build_dir, exist_ok=True)
        ram = self.snapshot()
        with open(os.path.join(self.build_dir, "low.bin"), "wb") as f:
            f.write(ram[0:0x400])
        patch = self.assemble(defines, net=self.local_net or bool(defines))
        self.check_areas(patch)
        for a, v in patch.items():
            ram[a] = v
        raw = os.path.join(self.build_dir, f"{name}-raw.prg")
        with open(raw, "wb") as f:
            f.write(bytes([IMAGE_START & 0xFF, IMAGE_START >> 8]) + ram[IMAGE_START:IMAGE_END])
        labels = self.read_labels()
        sys.path.insert(0, os.path.join(FRAMEWORK, "c64", "packer"))
        import pack  # noqa: E402
        out = os.path.join(self.build_dir, f"{name}.prg")
        pack.pack(raw, out, labels[self.entry_label], labels.get("net_hb", 0))
        report = []
        for area in self.areas():
            if area.get("segments"):
                s, e = int(area["start"], 16), int(area["end"], 16)
                used = [a for a in patch if s <= a <= e]
                report.append(f"{(max(used) - s + 1) if used else 0} of {e - s + 1} bytes at ${s:04X}")
        print(f"{name}: {len(patch)} patched bytes, entry ${labels[self.entry_label]:04X}; new code: "
              + ", ".join(report))
        return out

    # --- lobby and disk -------------------------------------------------------------
    def lobby(self) -> str:
        """The framework's lobby with this game's lobby/game.h: build/lobby.prg"""
        files = [os.path.join(LOBBY_SRC, f) for f in ("main.c", "net.c", "rrnet.s", "uci.s", "wic64.s", "loader.s")]
        self.run([c64env.cc65("cl65"), "-t", "c64", "-O", "-I", os.path.join(self.root, "lobby"),
                  "-o", "lobby.prg", "-m", "lobby.map", *files])
        return os.path.join(self.build_dir, "lobby.prg")

    def disk(self, test: bool = False) -> str:
        """build/<lobby_file>.d64: the lobby (first file), the local game (local_file, if set) and the
        game per network type.
        test=True: <lobby_file>-test.d64 with NETBOT game files (a bot plays when the cfg says bot=1)."""
        os.makedirs(self.build_dir, exist_ok=True)
        files = [(self.lobby(), self.lobby_file)]
        if self.local_file:
            files.append((self.build([], name=self.local_file), self.local_file))
        if self.extra_files:
            files += self.extra_files()
        for define, name in self.files.items():
            extra = ["NETBOT"] if test else []
            files.append((self.build([define, *extra], name=name + ("-test" if test else "")), name))
        d64 = os.path.join(self.build_dir, f"{self.lobby_file}{'-test' if test else ''}.d64")
        args = [c64env.vice("c1541"), "-format", self.disk_title, "d64", d64]
        for prg, name in files:
            args += ["-write", prg, name]
        self.run(args)
        print(f"built {os.path.relpath(d64, self.root)}")
        return d64

    def main(self, argv: list[str]) -> None:
        """Command line: (nothing) build, "disk", "testdisk", "run"."""
        action = argv[1] if len(argv) > 1 else ""
        if action == "disk":
            self.disk()
        elif action == "testdisk":
            self.disk(test=True)
        else:
            prg = self.build()
            if action == "run":
                subprocess.Popen([c64env.vice("x64sc"), "-pal", "+drive8truedrive", "-virtualdev8",
                                  "-autostart", prg])
