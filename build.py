#!/usr/bin/env python3
"""
Build and test the whole C64 Game Server project: the server and every game in games/.

    python build.py                  build the server and all games
    python build.py list             list the games (from games/*/game.json)
    python build.py server           build and unit-test the server only
    python build.py <game>           build one game (folder name, e.g. bubblebobble)
    python build.py test [<game>]    server tests plus the game tests (these start VICE, minimized)

A game takes part when its folder has a game.json (see docs/adding-a-game.md):
    {"id": 3, "name": "Bubble Bobble", "module": "bubblebobble",
     "build": ["python", "tools/build.py", "disk"], "disk": "build/bblan.d64",
     "tests": [["python", "tools/dettest.py"]]}
Commands run in the game's folder; "python" means the Python running this script.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(REPO, "server")


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


def main() -> None:
    args = sys.argv[1:]
    all_games = games()
    if args[:1] == ["list"]:
        for name, g in all_games.items():
            print(f"{g['id']:3}  {name:16} {g['name']:20} module {g['module']:14} lobby: {g.get('lobby', '?')}")
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
