"""
Where the external tools live. Order: environment variable, tools/paths.local.json (not in git), the PATH.

tools/paths.local.json example:
    {"VICE_DIR": "C:\\vice\\bin", "CC65_BIN": "C:\\cc65\\bin"}
"""
from __future__ import annotations

import json
import os
import shutil

_LOCAL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "paths.local.json")


def tool_dir(name: str, exe: str, fallback: str) -> str:
    """Directory of a tool: $name, paths.local.json[name], the directory of `exe` on the PATH, or fallback."""
    if os.environ.get(name):
        return os.environ[name]
    if os.path.exists(_LOCAL):
        with open(_LOCAL, encoding="utf-8") as f:
            value = json.load(f).get(name)
        if value:
            return value
    found = shutil.which(exe)
    return os.path.dirname(found) if found else fallback


VICE_DIR = tool_dir("VICE_DIR", "x64sc", r"C:\VICE\bin")
CC65_BIN = tool_dir("CC65_BIN", "ca65", r"C:\cc65\bin")
