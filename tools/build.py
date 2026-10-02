"""
Build script for Wizard of Wor LAN.

    python tools/build.py            build everything
    python tools/build.py run        build and start the PRG in VICE
    python tools/build.py shot [N]   build, run N million cycles in VICE (warp) and save a screenshot

64tass runs inside WSL (tools/64tass.sh fetches it on first use).
VICE is taken from the VICE_DIR environment variable or the default path below.
"""
from __future__ import annotations

import hashlib
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
BUILD = os.path.join(ROOT, "build")
VICE_DIR = os.environ.get("VICE_DIR", r"C:\Users\user\OneDrive\dev\c64\vice\bin")
WSL_DISTRO = os.environ.get("WSL_DISTRO", "Ubuntu-24.04")

# md5 of the unmodified upstream source assembled as a cartridge
# the cartridge build must keep matching this as long as all NET changes are PRG-only
BASELINE_CART_MD5 = "c2c674a27896a389ff31cc0bb42292fc"


def tass(*args: str) -> None:
    """Run 64tass in WSL with the project root as working directory (paths relative, forward slashes)."""
    cmd = ["wsl", "-d", WSL_DISTRO, "--", "bash", "tools/64tass.sh", "-q", *args]
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    out = (r.stdout + r.stderr).strip()
    if r.returncode != 0:
        print(out)
        sys.exit(f"64tass failed: {' '.join(args)}")
    if out:
        print(out)


def md5(path: str) -> str:
    with open(path, "rb") as f:
        return hashlib.md5(f.read()).hexdigest()


def vice(name: str) -> str:
    return os.path.join(VICE_DIR, name)


def build() -> None:
    os.makedirs(BUILD, exist_ok=True)

    # 1. original cartridge layout - regression check against the upstream binary
    tass("-a", "src/wizard_of_wor.asm", "-b", "-o", "build/wow_cart.bin",
         "-L", "build/wow_cart.lst", "-l", "build/wow_cart.lbl")
    cart_md5 = md5(os.path.join(BUILD, "wow_cart.bin"))
    if cart_md5 == BASELINE_CART_MD5:
        print("cartridge build : identical to upstream")
    else:
        print(f"cartridge build : DIFFERS from upstream ({cart_md5})")
    subprocess.run([vice("cartconv.exe"), "-i", "build/wow_cart.bin", "-o", "build/wow_cart.crt",
                    "-t", "normal", "-n", "WIZARD OF WOR"], cwd=ROOT, check=True, capture_output=True)

    # 2. RAM based version packed into a PRG
    tass("-a", "-D", "TARGET_PRG=1", "src/wizard_of_wor.asm", "-b", "-o", "build/wow_payload.bin",
         "-L", "build/wow.lst", "-l", "build/wow.lbl", "--vice-labels")
    layout_check()
    tass("-a", "src/loader.asm", "-o", "build/wow.prg")
    print(f"PRG             : build/wow.prg ({os.path.getsize(os.path.join(BUILD, 'wow.prg'))} bytes)")

    # 3. disk image
    d64 = os.path.join(BUILD, "wow.d64")
    if os.path.exists(d64):
        os.remove(d64)
    subprocess.run([vice("c1541.exe"), "-format", "wizard of wor,wl", "d64", "build/wow.d64",
                    "-write", "build/wow.prg", "wow"], cwd=ROOT, check=True, capture_output=True)
    print("disk image      : build/wow.d64")


def layout_check() -> None:
    """The PRG image must keep the layout of the original 16K image: only same-size patches are allowed there.
    (The sprite data block contains code, so any shift silently corrupts sprites.)"""
    with open(os.path.join(BUILD, "wow_cart.bin"), "rb") as f:
        cart = f.read()
    with open(os.path.join(BUILD, "wow_payload.bin"), "rb") as f:
        prg = f.read()[:len(cart)]
    ranges: list[list[int]] = []
    for i, (a, b) in enumerate(zip(cart, prg)):
        if a != b:
            if ranges and i - ranges[-1][1] <= 4:
                ranges[-1][1] = i
            else:
                ranges.append([i, i])
    labels = {}
    with open(os.path.join(BUILD, "wow.lbl")) as f:
        for line in f:
            parts = line.split()
            if len(parts) == 3:
                labels.setdefault(int(parts[1], 16), parts[2].lstrip("."))
    def near(addr: int) -> str:
        best = max((a for a in labels if a <= addr), default=None)
        return f"{labels[best]}+{addr - best}" if best is not None else "?"
    print(f"layout check    : {len(ranges)} patched area(s) in the original image")
    for lo, hi in ranges:
        print(f"                  ${0x8000 + lo:04X}-${0x8000 + hi:04X}  {near(0x8000 + lo)}")
    if len(ranges) > 40:
        sys.exit("layout check: too many differences - something shifted the original layout")


def run() -> None:
    subprocess.Popen([vice("x64sc.exe"), "-autostart", os.path.join(BUILD, "wow.prg"), "+confirmonexit"],
                     cwd=ROOT)


def shot(mcycles: int) -> str:
    png = os.path.join(BUILD, "shot.png")
    if os.path.exists(png):
        os.remove(png)
    subprocess.run([vice("x64sc.exe"), "-default", "-sounddev", "dummy", "-warp",
                    "-limitcycles", str(mcycles * 1_000_000), "-exitscreenshot", png,
                    "-autostart", os.path.join(BUILD, "wow.prg")],
                   cwd=ROOT, capture_output=True, timeout=300)
    print(f"screenshot      : {png}")
    return png


if __name__ == "__main__":
    build()
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    if action == "run":
        run()
    elif action == "shot":
        shot(int(sys.argv[2]) if len(sys.argv) > 2 else 60)
