"""
Where the external tools live, for every game in this repository.

Search order for each tool directory:
  1. an environment variable (VICE_DIR, CC65_BIN)
  2. paths.local.json in the repository root (not in git), e.g.
         {"VICE_DIR": "C:\\vice\\bin", "CC65_BIN": "C:\\cc65\\bin"}
  3. a folder "c64" next to (or above) the repository: c64/vice/bin, c64/cc65/bin
  4. the PATH

Use:
    sys.path.insert(0, <repo>/framework/tools)
    import c64env
    c64env.cc65("ca65"), c64env.vice("x64sc"), c64env.REPO
"""
from __future__ import annotations

import json
import os
import shutil
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SERVER = os.path.join(REPO, "server")
FRAMEWORK = os.path.join(REPO, "framework")

_LOCAL = os.path.join(REPO, "paths.local.json")
_EXE = ".exe" if os.name == "nt" else ""


def _local(name: str) -> str | None:
    if os.path.exists(_LOCAL):
        with open(_LOCAL, encoding="utf-8") as f:
            return json.load(f).get(name)
    return None


def _sibling(*parts: str) -> str | None:
    """A folder like c64/vice/bin next to the repository or one of its parents."""
    d = REPO
    for _ in range(4):
        d = os.path.dirname(d)
        p = os.path.join(d, *parts)
        if os.path.isdir(p):
            return p
    return None


def tool_dir(var: str, exe: str, *sibling: str) -> str | None:
    for d in (os.environ.get(var), _local(var), _sibling(*sibling)):
        if d and os.path.isfile(os.path.join(d, exe + _EXE)):
            return d
    found = shutil.which(exe)
    return os.path.dirname(found) if found else None


def _tool(var: str, name: str, *sibling: str) -> str:
    d = tool_dir(var, name, *sibling)
    if not d:
        sys.exit(f"error: {name} not found (set {var} or add it to {_LOCAL})")
    return os.path.normpath(os.path.join(d, name + _EXE))


def cc65(name: str) -> str:
    """ca65, ld65, cl65, ..."""
    return _tool("CC65_BIN", name, "c64", "cc65", "bin")


def vice(name: str = "x64sc") -> str:
    """x64sc, c1541, ..."""
    return _tool("VICE_DIR", name, "c64", "vice", "bin")


VICE_DIR = tool_dir("VICE_DIR", "x64sc", "c64", "vice", "bin") or ""
CC65_BIN = tool_dir("CC65_BIN", "ca65", "c64", "cc65", "bin") or ""
