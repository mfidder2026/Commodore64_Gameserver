"""
Determinism test for a game built with framework/tools/imagebuild.py.

A test build (the game's DETTEST options: a bot plays, HALT_AT=n stops before tick n at the label
<halt_label>) runs in several VICEs with different timing; each stops at the same tick and its RAM is
saved. Lockstep needs the game state to be identical; only the display, the sound and our own test
code may differ (the ignore list). Differences are listed by address, to be traced to their code.

    import determinism
    determinism.main(game, ticks=2000, halt_label="pit_halt", defines=["DETTEST"],
                 runs=[("pal", [], ["-pal"]), ("pal_jitter", ["JITTER"], ["-pal"])],
                 ignore=[(0x0100, 0x01FF, "stack"), ...])
Each run is (name, extra defines, VICE options).
"""
from __future__ import annotations

import os
import sys

import vicemon


def ranges(addrs: list[int]) -> list[tuple[int, int]]:
    out: list[list[int]] = []
    for a in addrs:
        if out and a == out[-1][1] + 1:
            out[-1][1] = a
        else:
            out.append([a, a])
    return [(s, e) for s, e in out]


def compare(results: dict[str, bytes], ignore: list[tuple[int, int, str]], show: int = 40) -> bool:
    base_name, base = next(iter(results.items()))
    ok = True
    for name, ram in results.items():
        if name == base_name:
            continue
        diff = [a for a in range(0x10000) if ram[a] != base[a] and not any(s <= a <= e for s, e, _ in ignore)]
        if diff:
            ok = False
            print(f"DIFF {base_name} vs {name}: {len(diff)} bytes")
            for s, e in ranges(diff)[:show]:
                print(f"    ${s:04X}-${e:04X}  "
                      + " ".join(f"{base[a]:02X}/{ram[a]:02X}" for a in range(s, min(e, s + 7) + 1)))
    print("PASS: the game state is identical" if ok else "FAIL")
    return ok


def main(game, ticks: int, halt_label: str, defines: list[str], runs: list[tuple[str, list[str], list[str]]],
         ignore: list[tuple[int, int, str]], port: int = 6580, timeout: float = 900) -> bool:
    results = {}
    for name, defs, vice_args in runs:
        prg = game.build([*defines, f"HALT_AT={ticks}", *defs], name=f"dt_{name}")
        labels = game.read_labels()
        p = port + len(results)
        v = vicemon.start(prg, p, extra=["-warp", "+drive8truedrive", "-virtualdev8", *vice_args], pal=False)
        try:
            _, ram = vicemon.stop_at(p, labels[halt_label], os.path.join(game.build_dir, f"dt_{name}.bin"),
                                     timeout=timeout)
        finally:
            v.kill()
        results[name] = ram
        print(f"  {name:11} halted at tick {ticks}", flush=True)
    ok = compare(results, ignore)
    return ok


if __name__ == "__main__":
    sys.exit("use it from a game's tools/dettest.py")
