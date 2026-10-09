"""
Where the external tools live: the framework's shared lookup (framework/tools/c64env.py):
an environment variable, paths.local.json in the repository root, a c64/ folder next to
the repository, or the PATH.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "framework", "tools"))
import c64env  # noqa: E402

VICE_DIR = c64env.VICE_DIR or r"C:\VICE\bin"
CC65_BIN = c64env.CC65_BIN or r"C:\cc65\bin"
