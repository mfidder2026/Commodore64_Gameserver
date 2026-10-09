# BB-LAN technical description

This document explains how BB-LAN turns the C64 Bubble Bobble into a
lockstep network game, and what was learned on the way. It is meant for
people who want to change the code or reuse the approach for another game.

## Overview

```
 C64 #1 (Bub)                     game server (C#, .NET 8)              C64 #2 (Bob)
┌──────────────────┐            ┌─────────────────────────┐           ┌──────────────────┐
│ lobby (BBLAN)     │  lobby,    │ lobby, invitations,     │  lobby,   │ lobby (BBLAN)     │
│   ↓ START         │  START     │ sessions, dashboard     │  START    │   ↓ START         │
│ game (BBU/W/R)    │◄──────────►│ Bubble Bobble module:   │◄─────────►│ game (BBU/W/R)    │
│ full simulation   │   INPUT    │  seed, input delay,     │   INPUT   │ full simulation   │
│ in lockstep       │  25 Hz     │  relay, checksums       │  25 Hz    │ in lockstep       │
└──────────────────┘            └─────────────────────────┘           └──────────────────┘
   UDP (Ultimate) · TCP (WiC64) · raw Ethernet (VICE RR-Net)
```

- **Lobby** (`lobby/`, C with cc65):
  - finds the network hardware;
  - talks to the server until a session starts;
  - writes a handoff block to `$03C0` and loads the game file for its network type.
- **Game** (`src/`): the reconstructed original with:
  - a deterministic tick core (`bblan.s`);
  - the network code (`bbnet.s`).
- **Server** (`server/`): relays the inputs, compares checksums and handles timeouts. It is not authoritative: it does not know the game.

## 1. The source

The game is built from [rebb64](https://github.com/zaidka/rebb64), a reconstruction of the C64 version in ca65 assembly:

- `python tools/build.py verify` still produces the original byte for byte.
- All BB-LAN changes are in `.ifdef BBLAN` blocks.

### Rule 1: no byte of the original may move

The first version of the changes made some routines longer or shorter. Everything behind them moved, and the game broke in subtle ways:

- After a few minutes an enemy got an invalid type.
- The entity dispatch jumped through a vector behind the end of its table into random code.
- That code drew into the zero page, which corrupted the sound player's stack index and crashed the C64 around level 9 or 13.

A reference build that keeps the original layout (`ORIGLAYOUT`) did not crash with the same bot. The reconstructed source still contains absolute references that the assembler does not know about.

So now:

- Every patch replaces original code with code of **at most the same size**. The `BB_PATCH_END` macro pads with NOPs.
- New code goes into the segment `BBLAN_CODE`.
- `tools/build.py` compares every original segment with `tools/original-layout.json` and refuses to build when one moved.

### Memory

RAM is full in the original. The room for BB-LAN comes from compressing the level bitmaps (an option of rebb64):

- the compressed bitmaps fill the RAM under the I/O area;
- `build.py` chooses the split so the I/O shadow is exactly full;
- that frees about 1.3 KB in normal RAM (`$C5F2-$CB1C`) for `BBLAN_CODE`.

Each network driver gets its own game file, so only one is in memory:

| Build | BBLAN_CODE used | Free |
|---|---|---|
| RR-Net | 1321 bytes | 2 |
| Ultimate | 1297 bytes | 26 |
| WiC64 | 1286 bytes | 37 |

Small buffers live in unused stack page bytes:

- the input rings at `$0128-$0147`;
- the game itself uses `$0100`, `$0107-$0126` and `$014B-$01A6`.

## 2. Deterministic game time (`src/bblan.s`)

In the original, part of the game logic runs in the raster interrupt:

- the frame counter;
- the second and hurry-up timers;
- on every odd frame, the player/sprite state machine `D_1CBD`.

The main loop runs the rest at 25 Hz. How the two interleave depends on how long the main loop takes, so two C64s would compute different games.

BB-LAN makes game time **virtual**:

- The IRQ only counts real frames (`bb_rframe`) and keeps doing display and sound.
- Every place where the game waited for the frame counter now calls `vframe`, which runs exactly one logical frame:
  - the timers;
  - the frame counter `$08`;
  - on odd frames, what the IRQ used to do (`D_1805`, `D_1B40`, `D_1CBD`).
- `vframe` is paced against real frames and may catch up up to 4 frames.
  - The game keeps its speed: measured 3.09 real frames per main loop pass, the original 3.01.
  - The sequence of logic no longer depends on time.

**One tick = one odd logical frame (25 Hz).** At every tick `bb_sample` provides the input of both players:

- `bb_in0`/`bb_in1`: the joystick bytes, as `$DC00`/`$DC01` would read;
- `bb_key`: the keyboard row 7 that pause/quit/title read.

All game code reads input from there.

Other things that had to change:

- the random generator no longer mixes in a CIA timer;
- the seed and the frame/tick counters are set when a game starts;
- starting a song and initialising the sound from the main program now run with the IRQ held off (they used to run inside the IRQ).

### Same start on both machines

A game that starts after an earlier game does not start from the same state as a freshly loaded one: entity tables, buffers and the sound state differ. BB-LAN therefore starts every session from a **freshly loaded game file**:

- the lobby loads it;
- the unpacker clears the part of the stack page the game uses for tables;
- after the game, the lobby is loaded again.

## 3. Lockstep (`src/bbnet.s`)

At tick `t` each C64:

1. **Reads its own joystick** (port 2) and the keys `C=` (pause) and `Q` (quit), and stores the result as the input for tick `t + delay`.
2. **Sends an INPUT message** with the newest 8 inputs. Each message repeats the last 8, so a lost message costs nothing.
3. **Waits until the other player's input for tick `t` is there.**
   - Only then does it poll the network.
   - While waiting it resends every real frame.
   - It gives up after 10 s, or after 120 s at the start while the other C64 is still loading.
4. **Runs the tick:**
   - slot 0 drives Bub, slot 1 drives Bob;
   - the keys of both players are combined, so a pause or quit happens on both machines.

Every 64 ticks a Fletcher-16 checksum goes along in the INPUT message. It covers the level, the random generator, the timers, the entity state, the scores and the lives. The server compares the two checksums and ends the session with *desync* when they differ.

```
INPUT, 16 bytes:
  $80, session, newest tick (16 bit), checksum tick (16 bit, $FFFF = none),
  checksum (16 bit), 8 inputs for ticks newest-7 .. newest
input byte: bits 0-4 joystick (active low, as $DC00),
            bit 5 C= (pause), bit 6 Q (quit)
```

### Handoff block (lobby → game), at `$03C0`

| Offset | Contents |
|---|---|
| 0-1 | `BL` (valid block) |
| 2 | driver: 0 local, 1 Ultimate, 2 RR-Net, 3 WiC64 |
| 3 | slot (0 = Bub) |
| 4 | session id |
| 5-6 | seed |
| 7 | input delay |
| 8 | UCI socket |
| 9 | flags (bit 0: test bot) |
| 10 | drive number (to load the lobby again) |
| 12-17 | RR-Net: the server's MAC |
| 18-23 | RR-Net: our MAC |

The unpacker copies the block into the game (`bb_hb`) and clears the marker. Without a valid block the game runs locally with two joysticks. After the game, `bb_end`:

1. resets the C64 to KERNAL state;
2. leaves the result for the lobby at `$033C`: `BR`, reason, UCI socket;
3. loads `BBLAN`.

### Network drivers

**Ultimate** (Ultimate Command Interface, `$DF1C-$DF1F`):

- UDP through the socket the lobby opened.
- One command at a time: a read is pending whenever nothing is sent, and a send waits for the read.
- Same rules as the WoW-LAN driver: never read-modify-write `$DF1C`, reads of at most 48 bytes.

**WiC64** (firmware 2.x):

- Requests `"R", command, length(16), data`; the answer is `status, length(16), data`.
- Every byte is confirmed with FLAG2 (`$DD0D` bit 4). PA2 sets the direction.
- TCP to the server; the stream carries `[length][message]`.
- The driver hands every completed message in a transfer to the lockstep, because several can arrive at once.
- A WiC64 transfer costs the C64 time (about 1 frame per send and 2-3 per poll in VICE's emulation). So:
  - a WiC64 sends every other tick;
  - the server uses an input delay of 4 when a WiC64 takes part.

**RR-Net** (CS8900a):

- Raw Ethernet frames with EtherType `$88B5`: destination MAC, source MAC, type, length, message.
- No IP, so no ARP and no IP set-up.
- Only frames from the server's MAC to our own are accepted: VICE's emulated chip lets other frames through.

## 4. The server

The server started as the WoW-LAN game server. Its core:

- the lobby;
- invitations;
- sessions;
- timeouts;
- the dashboard;
- unit tests with a fake clock.

The **Bubble Bobble module** (game id 3):

- picks the seed and the input delay;
- relays INPUT messages (cutting off Ethernet padding);
- compares the checksums;
- gives a player up to `loadTimeoutSeconds` to load the game before his first INPUT.

The core asks the module how long a player in a session may stay silent, so a C64 loading from a 1541 is not dropped.

Three transports share one core. Each client is identified by an `IPEndPoint`:

| Transport | Clients | End point |
|---|---|---|
| UDP, port 6465 | Ultimate | its IPv4 address and port |
| TCP, port 6466, `[length][message]`, NoDelay | WiC64 | IPv4-mapped IPv6 address |
| pcap, raw Ethernet `$88B5` | VICE RR-Net | IPv6 link-local address made from its MAC (EUI-64) |

The pcap transport opens the interface in immediate mode and answers with the server's own MAC (`pcapMac`). The C64s find it by broadcasting their HELLO.

## 5. The packer

The game image (`$0400-$FFFA`, 64.5 KB) is too big for a normal PRG. `tools/pack.py`:

- compresses it with an optimal-parse LZ to 46.5 KB;
- adds the 6502 unpacker from `tools/sfx.s`.

The unpacker:

1. runs from `$0200-$03BF`;
2. moves the compressed data to the top of memory;
3. decompresses forward in place, with `pack.py` checking that the output never overtakes the input;
4. passes on the handoff block;
5. clears the stack page.

```
0LLLLLLL                 literal run, L+1 bytes
10LLLLLL o               match, length L+2, distance o+1 (1-256)
11LLLLLL lo hi           match, length L+3 (3-65)
11111111 lo hi e         match, length e+66 (up to 255)
```

## 6. Tests and tools

| Tool | What it does |
|---|---|
| `tools/dettest.py` | Runs a built-in bot in 5 VICEs: PAL, NTSC, CPU jitter, and stalls of 1-7 frames like network waits. All must log the same checksums (`--break` proves the test notices a difference) |
| `tools/soak.py` | Lets the bot play in several VICEs and reports crashes (PC in `$0000-$03FF`) and hangs; can compare with `ORIGLAYOUT` |
| `tools/nettest.py` | Server plus two VICEs (RR-Net, or `--wic64`), automatic invite/accept, test bot; follows the session on the dashboard API |
| `tools/crashtrace.py` | Runs to a breakpoint/watchpoint (any VICE monitor condition) and dumps registers and CPU history |
| `tools/watch.py`, `tools/dumpdiff.py`, `tools/startdiff.py` | Progress, memory comparison between two C64s, start-state comparison |
| `tools/screenshots.py` | The screenshots of this documentation |

Bugs these tools found, among others:

- the layout problem above;
- a sound start racing the IRQ;
- the received tick window wrapping below tick 0;
- VICE passing frames for other MACs to the CS8900a;
- the pause key decoded from the fire button;
- cc65's `'\r'` not being the RETURN key.
