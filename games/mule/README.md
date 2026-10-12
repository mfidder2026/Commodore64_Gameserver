# M.U.L.E. (work in progress)

> Part of the **[Commodore 64 Game Server](../../README.md)**. Not yet *Online Multiplayer Enabled*: see the status below.

**M.U.L.E.** (Ozark Softscape / Electronic Arts, 1983): four colonists on the planet Irata
grab land, build M.U.L.E.s and trade food, energy, smithore and crystite. Up to four
players; the computer plays the empty seats.

## Status

| Step | State |
|---|---|
| 1. Deterministic game (computer players) | **done**: `python tools/dettest.py 50000`: PAL, PAL with 0-3 frames of network-like waiting per tick, and NTSC end in the same game state after 50,000 ticks (nearly a whole beginner game of six months) |
| 2. Deterministic with human inputs | **done**: `python tools/dettest.py <ticks> humans=N` with a bot's random inputs for the human players: PASS for 1 (40,000 ticks), 2 (30,000), 3 (20,000) and 4 human players (10,000: the bots ruin the colony quickly) |
| 3. Network code for 4 players (`framework/c64/net`) | planned |
| 4. Server and lobby: tables (host opens one, up to 3 join; empty seats are the computer's) | planned |
| 5. End-to-end test, docs, release | planned |

## The disk

The tape image's disk (cracked by "Jedi", 1984) has two files:

| File | Address | What |
|---|---|---|
| `m.u.l.e.` | `$0801-$84FF` | `SYS 2068` -> `JMP $5349`: title, options (F3 level -> `$E504`, F5 players -> `$43FF`), "each planeteer press your button" (input devices -> `$E500-$E503`); then `$65E4` loads `&` |
| `&` | `$4000-$CBFF` | the game: `JMP $4000` -> `JMP $972B`; at the end of a game its own title, which loads `m.u.l.e.` again |

`tools/crackfix.py` removes what the cracker added: "CRACKED 1984 BY JEDI" on the credits
and on the second title, the "JEDISCAPE" logo, and the pirates he renamed ("JEDI SHIP",
"JEDIS TAKE ALL" -> "PIRATE SHIP", "PIRATES TAKE ALL"). Every string keeps its length.

## How the online version works (so far)

In the original the raster IRQ (`$5F17`) runs the **frame logic** every frame:
- the clocks `$14/$13/$12`, and a random mix `$FD` with the SID's noise;
- the inputs of the four players (`$E500,X` = device: negative = computer, 8/9 = joystick
  ports, else keyboard sets; `$49,X` button, `$54,X` direction);
- count-downs `$5A,X`, `$5C`, `$60CF`, the button latch `$4D/$2C/$35`, the music;
- the **frame task** of the phase (`$58`, table `$60D1`: walking, the auction, events ...).

The main program waits for it in many places, so how far each gets depends on timing.
The online build (`src/main.s`) uses **virtual frames**:
- the IRQ only draws and counts real frames (`mule_due`);
- the frame logic runs as a **tick**, only where the main program waits, one per real
  frame (`mule_tick`). "Wait n frames" (`$44EE`) is n ticks;
- the main program's wait loops tick while they wait (`tools/waits.py`: tight loops,
  loop heads, calls and jumps back; found with a flow trace of the game and by running
  the test build until it hung);
- a human player X has the input device 8+X (`$E500,X`); the frame logic and `$74F0` read
  the device's port at `$DBF8+device`, which becomes our table of this tick's inputs
  (`mule_in`: from the network, or the test bot). The keyboard scanner (`$8850`: keyboard
  players, F1 pause, F3/F5/F7 restart) reads nothing; `$A8` stays "no key";
- the SID's noise becomes our own generator; the keys and fire buttons read directly
  (`$6911`) are never pressed (the players' buttons come through the frame logic);
  no pause key and no attract mode.

## Building

```bash
python tools/snapshot.py      # orig/mule-972b.bin (+ -io.bin) from the clean disk: four computer players
python tools/build.py         # build/mule.prg: that game as one PRG
python tools/crackfix.py      # build/mule-clean.d64: the original two files without the crack's texts
python tools/dettest.py 50000 # determinism test
```

`tools/dettest.py` ignores only the CPU port, the stack, our tick code and the raster IRQ
handlers' own bytes (`$1C/$1D`: their saved registers, `$29`: the step of the screen split).

Free memory in the game: `$CC00-$CDFF` and `$E9C9-$EC53` (never touched, VICE
watchpoints over a whole game); the game's init clears `$EC55-$FEFE`, so the entry code
and the copy of low memory lie there.

## Credits

**M.U.L.E.** © 1983 Ozark Softscape (Dan Bunten, Bill Bunten, Jim Rushing, Alan Watson;
music by Roy Glover), published by Electronic Arts. This is a non-commercial fan
project; all rights stay with the owners.
