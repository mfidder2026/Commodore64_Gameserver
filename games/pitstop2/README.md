# Pitstop II OME

> Part of the **[Commodore 64 Game Server](../../README.md)**. *Online Multiplayer Enabled*: two C64s race each other over the network, one driver per C64.

**Pitstop II** (Epyx, 1984): split-screen Formula 1 racing for two players on one
C64, with pit stops for tyres and fuel.

## Playing

Load the disk's first file (`LOAD"*",8,1` / `RUN`): the framework's standard lobby
([framework/c64/lobby](../../framework/c64/lobby/README.md)). Invite a player with FIRE.
- Slot 0 (the inviter) is **driver 1** (the top half of the screen), slot 1 is **driver 2** (the
  bottom half). Both C64s show the whole split screen; each player uses joystick **port 2**.
- The session picks one of the seven tracks (from its seed); three laps, rookie.
- `Q` (either player) ends the race for both. After the finish the screen stays for three
  seconds, then both C64s go back to the lobby.
- Key `L` in the lobby loads the **original game** (`pitl`: menu, one or two players, all options).

## Status

| Part | State |
|---|---|
| Single PRG | `python tools/build.py` makes `build/pitstop.prg`: the clean original as one file, straight into the options menu. No crack intro, no documents reader, no title picture, no trainer |
| Determinism | `python tools/dettest.py 6000`: PAL, PAL with 0-3 frames of network-like waiting per tick, and NTSC end in the same race state |
| Online | see the top-level README's status table |

## How the online version works

In the original the race logic, including the joystick reads, runs in the **raster IRQ**: one
car per screen half. The **main loop** draws the views as fast as it can, and also changes the
cars' state (crash, recovery and pit states). How far the main loop got between two logic runs
depended on timing, so two C64s would drift apart (2105 bytes of game state differed after 1000
ticks in the first test).

The online build makes the interleaving fixed (`src/main.s`):
- the raster IRQ only draws and counts screen halves (`pit_due`);
- the main loop runs the logic itself, as **slots**, at the start of every drawing pass
  (`$41A0`): one slot per car, after waiting for two screen halves, so the game is never faster
  than the original. A **tick** of the lockstep is one pass; the inputs are read once per tick;
- the logic reads its car numbers from our variables instead of the IRQ's (`$16`/`$17`);
- the main loop's waits for the logic counter `$04` (start countdown, pit stop) run slots;
- the steering state `$620B,X`, which the display IRQ derived from `$70,X` and the logic reads,
  is computed at the start of each slot (`src/areas-online.json` lists every patch).

A flow trace of the IRQ, the logic and the main loop (every address read and written) found
the couplings; `tools/dettest.py` confirmed them.

The state checksum (`src/netgame.inc`) covers the race state: zero page `$24-$EC` (without
the IRQ's sprite temporary `$27` and our frame counter `$E4`), `$0380-$039F` and `$61D0-$6226`
(without the sprite drawing temporaries).

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
| `$0800-$0FFF`, `$8C00-$8EFF`, `$C000-$CFFF`, `$E000-$EFFF` | All used by the game (tables, screens, charsets, sprites): free memory for new code is scarce. Online, the menu and name entry code is free: the network code goes to `$953E-$9C71`, the scheduler to `$9C87-$9FFF` |
| `$3670`-`$3834`, `$3ECD`-`$4053` | The raster IRQ: display of the two halves; the logic block `$3835`-`$3EC9` (ends with RTI) |

## Building

```bash
python tools/snapshot.py      # orig/pitstop2-9403.bin from orig/pitstop2.prg (the tape version)
python tools/build.py         # build/pitstop.prg: the original game as one PRG
python tools/build.py disk    # build/pitstop.d64: lobby, original game (pitl), pitu / pitw / pitr
python tools/dettest.py 6000  # determinism test (test build: a bot drives both cars)
python ../../framework/tools/nettest.py . 180   # server + two VICEs over RR-Net (--wic64, --bot)
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
