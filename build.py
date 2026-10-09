#!/usr/bin/env python3
"""
Build and test the whole C64 Game Server project: the server and every game in games/.

    python build.py                  build the server and all games
    python build.py list             list the games (from games/*/game.json)
    python build.py server           build and unit-test the server only
    python build.py <game>           build one game (folder name, e.g. bubblebobble)
    python build.py test [<game>]    server tests plus the game tests (these start VICE, minimized)
    python build.py release          build everything and fill RELEASE/ (server, disk images, start scripts)

A game takes part when its folder has a game.json (see docs/adding-a-game.md):
    {"id": 3, "name": "Bubble Bobble", "module": "bubblebobble",
     "build": ["python", "tools/build.py", "disk"], "disk": "build/bblan.d64",
     "tests": [["python", "tools/dettest.py"]]}
Commands run in the game's folder; "python" means the Python running this script.
"""
from __future__ import annotations

import datetime
import json
import os
import shutil
import subprocess
import sys

REPO = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(REPO, "server")
RELEASE = os.path.join(REPO, "RELEASE")
RELEASE_FILES = os.path.join(REPO, "framework", "release")  # start scripts and README for RELEASE/
RELEASE_RIDS = ["win-x64", "linux-arm64"]  # Windows, Raspberry Pi (64-bit OS)


def games() -> dict[str, dict]:
    found = {}
    root = os.path.join(REPO, "games")
    for name in sorted(os.listdir(root)):
        manifest = os.path.join(root, name, "game.json")
        if os.path.isfile(manifest):
            with open(manifest, encoding="utf-8") as f:
                g = json.load(f)
            g["folder"] = os.path.join(root, name)
            found[name] = g
    return found


def run(cmd: list[str], cwd: str) -> None:
    cmd = [sys.executable if c == "python" else c for c in cmd]
    print(f"\n== {os.path.relpath(cwd, REPO)}: {' '.join(cmd[1:] if cmd[0] == sys.executable else cmd)}", flush=True)
    if subprocess.run(cmd, cwd=cwd).returncode != 0:
        sys.exit(f"failed: {' '.join(cmd)} (in {cwd})")


def server(test: bool = True) -> None:
    run(["dotnet", "build", "C64GameServer.sln", "-c", "Release", "-v", "q"], SERVER)
    if test:
        run(["dotnet", "test", "tests/C64GameServer.Tests", "-c", "Release", "-v", "q"], SERVER)


def build(g: dict) -> None:
    run(g["build"], g["folder"])
    disk = os.path.join(g["folder"], g.get("disk", ""))
    if g.get("disk") and not os.path.isfile(disk):
        sys.exit(f"{g['name']}: the build did not produce {g['disk']}")


def release(all_games: dict[str, dict]) -> None:
    """RELEASE/: the server (self-contained, one file per platform), every game's disk, the start scripts."""
    server()
    for name, g in all_games.items():
        build(g)
    for sub in ("games", "server"):
        shutil.rmtree(os.path.join(RELEASE, sub), ignore_errors=True)
    os.makedirs(os.path.join(RELEASE, "games"))
    for name, g in all_games.items():
        shutil.copy(os.path.join(g["folder"], g["disk"]), os.path.join(RELEASE, "games", name + ".d64"))
    for rid in RELEASE_RIDS:
        out = os.path.join(RELEASE, "server", rid)
        run(["dotnet", "publish", "src/C64GameServer", "-c", "Release", "-r", rid, "--self-contained",
             "-p:PublishSingleFile=true", "-p:IncludeNativeLibrariesForSelfExtract=true",
             "-p:EnableCompressionInSingleFile=true", "-p:DebugType=none", "-o", out, "-v", "q"], SERVER)
        for f in os.listdir(out):
            if not f.startswith("C64GameServer") or f.endswith(".pdb"):
                os.remove(os.path.join(out, f))
    for f in os.listdir(RELEASE_FILES):
        with open(os.path.join(RELEASE_FILES, f), encoding="utf-8") as src:
            text = src.read()
        newline = "\r\n" if f.endswith((".bat", ".cmd")) else "\n"  # cmd.exe wants CRLF
        with open(os.path.join(RELEASE, f), "w", encoding="utf-8", newline=newline) as dst:
            dst.write(text)
    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=REPO, capture_output=True,
                            text=True).stdout.strip()
    with open(os.path.join(RELEASE, "VERSION.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"C64 Game Server release, {datetime.date.today()} (based on commit {commit})\n")
        for name, g in all_games.items():
            f.write(f"  games/{name}.d64  {g['name']} OME (game id {g['id']})\n")
        f.write("  server/: " + ", ".join(RELEASE_RIDS) + "\n")
    print(f"\nRELEASE/ is ready ({os.path.relpath(RELEASE, REPO)})")


def main() -> None:
    args = sys.argv[1:]
    all_games = games()
    if args[:1] == ["list"]:
        for name, g in all_games.items():
            print(f"{g['id']:3}  {name:16} {g['name']:20} module {g['module']:14} lobby: {g.get('lobby', '?')}")
        return
    if args[:1] == ["release"]:
        release(all_games)
        return
    if args[:1] == ["server"]:
        server()
        return
    if args[:1] == ["test"]:
        chosen = args[1:] or list(all_games)
        server()
        for name in chosen:
            for t in all_games[name].get("tests", []):
                run(t, all_games[name]["folder"])
        print("\nall tests passed")
        return
    if args:
        unknown = [a for a in args if a not in all_games]
        if unknown:
            sys.exit(f"unknown game(s): {', '.join(unknown)}; known: {', '.join(all_games)}")
        for name in args:
            build(all_games[name])
        return
    server()
    for g in all_games.values():
        build(g)
    print("\nbuilt: server, " + ", ".join(g["name"] for g in all_games.values()))


if __name__ == "__main__":
    main()
