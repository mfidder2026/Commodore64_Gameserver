# Pitstop II (work in progress)

> Part of the **[Commodore 64 Game Server](../../README.md)**. Not yet *Online Multiplayer Enabled*: see the status below.

**Pitstop II** (Epyx, 1984): split-screen Formula 1 racing for two players on one
C64, with pit stops for tyres and fuel.

## Status

| Part | State |
|---|---|
| Single PRG | **done**: `python tools/build.py` makes `build/pitstop.prg` (33.6 KB), which starts straight in the game's options menu. No crack intro, no documents reader, no title picture, no trainer |
| Analysis | menu, options, race start, joystick reads, race loop and race end found (below) |
| Online (lockstep) | **not yet possible as it is**: the game is not deterministic under timing differences (`tools/dettest.py`) |

### Why online is harder here

The race logic, including the joystick reads, runs in the **raster IRQ**, every other frame.
The **main loop** draws the two halves of the screen as fast as it can, and it also changes
the cars' state:
- `$41CE-$424B`: crash, recovery and pit states in `$50,X` and `$039C,X`;
- track sections in `$61DE,X` / `$61EA,X`.

How far the main loop gets between two logic ticks depends on timing. A network wait in the IRQ
therefore makes the two C64s diverge. `tools/dettest.py` shows it: after 1000 ticks with a bot on
both cars, PAL with network-like waits differs from plain PAL in 2105 bytes of game state.

Possible ways forward:
1. Make the interleaving deterministic. After every tick the IRQ resumes at exactly the same raster
   cycle, with network waits rounded to whole frames (PAL only).
2. Hand the main loop's state changes over at fixed ticks.

Both need more study of the race code.

## What the analysis found

| Address | What |
|---|---|
| `$9403` | The game's start (`$01=$25`, stack, zero page, VIC, charsets `$A600` → `$E000`) |
| `$99BC` | Menu IRQ; options in `$039E` (drivers 0-1), `$039F` (track 0-6), `$03A0` (laps 0-2), `$03A1` (difficulty 0-2). `$09` = "start the race" |
| `$9A60` / `$9AB9` | The drivers type their names (keyboard) |
| `$3300` | Race set-up; then the main loop `$41A0` (alternating the two views) |
| `$4FB4-$5013` | "Press your button": whoever presses first becomes driver 1 (`$7C` = his port) |
| `$387A` | In the raster IRQ: both joysticks read into `$03D2` / `$03D3` (every other frame) |
| `$4254` → `$42B3` | Race over: results to `$03A2-$03A7`, then `JMP $6D18` → `$9400` (title, menu) |
| `$9D4B`, `$9D82` | A random generator that mixes in the raster line; only used outside the race |
| `$0800-$0FFF`, `$8C00-$8EFF`, `$C000-$CFFF`, `$E000-$EFFF` | All used by the game (tables, screens, charsets, sprites): free memory for new code is scarce. Online, the menu and name entry code (`$94xx-$9Cxx`) would be free during the race |

## Building

```bash
python tools/snapshot.py      # orig/pitstop2-9403.bin from orig/pitstop2.prg (the tape version)
python tools/build.py         # build/pitstop.prg: the original game as one PRG
python tools/dettest.py 1000  # determinism test (test build: a bot drives both cars)
```

`tools/snapshot.py` runs the tape version's boot chain in VICE:
1. the decruncher;
2. the crack intro;
3. the documents reader;
4. a second unpacker;
5. the title picture;
6. the trainer question, answered N, so the game stays original.

It saves the RAM at the jump into the game (`JMP $9403`). The build is the framework's
"snapshot + patches" build (`framework/tools/imagebuild.py`), like
[The Way of the Exploding Fist](../explodingfist/README.md).

## Credits

**Pitstop II** © 1984 Epyx, by Stephen H. Landrum with Dennis Caswell. The tape image is
a cracked release ("Remember"); none of the crack's code is in our build. This is a
non-commercial fan project; all rights stay with the owners.
