# Bubble Bobble OME: Bub and Bob on two C64s

> Part of the **[Commodore 64 Game Server](../../README.md)**: one server, a shared framework and several *Online Multiplayer Enabled* C64 games.

**Bub on one Commodore 64, Bob on another, one game.** Bubble Bobble OME
(Online Multiplayer Enabled, formerly BB-LAN) turns the C64
version of Bubble Bobble into a two-player network game. Each player uses
their own machine: **VICE**, a **C64 Ultimate / Ultimate 64**, or a C64 with
a **WiC64**, in any combination. A small game server on the LAN brings them
together.

<p align="center">
  <img src="docs/images/game-alice-2.png" width="45%" alt="Bub's C64">
  &nbsp;
  <img src="docs/images/game-bob-2.png" width="45%" alt="Bob's C64">
  <br><em>The same moment of the same game on two emulated C64s.</em>
</p>

## How it works, in one paragraph

Both C64s run the complete, unmodified game logic in **lockstep**. Over the
network go only the joystick inputs, 25 times a second, plus a checksum of the
game state now and then. A tick only runs when the other player's input for
that tick has arrived, so both machines compute exactly the same game. The
server relays the inputs, compares the checksums and runs the lobby. Making the
original game behave identically on two machines took some work; see
[docs/TECHNICAL.md](docs/TECHNICAL.md).

| Lobby | Invited | Server dashboard |
|---|---|---|
| ![players](docs/images/lobby-players.png) | ![invited](docs/images/lobby-invited.png) | ![dashboard](../../docs/images/dashboard-bb.png) |

## What you need

| Player's machine | Network | Notes |
|---|---|---|
| **C64 Ultimate / Ultimate 64** | UDP via the Ultimate Command Interface | **Enable the Command Interface** in the Ultimate menu (F2 → C64 and Cartridge Settings); it is off by default |
| **C64 + WiC64** | TCP via the WiC64 (firmware 2.x) | |
| **VICE 3.9** with WiC64 emulation | TCP | Easiest way to play in an emulator: [`RELEASE/vice-wic64.bat`](../../RELEASE/vice-wic64.bat) |
| **VICE** with RR-Net | raw Ethernet | Server must run with pcap (Npcap) on the same LAN or PC: [`RELEASE/vice-rrnet.bat`](../../RELEASE/vice-rrnet.bat) |

Plus:

- **One PC on the LAN for the game server** (Windows, Linux, Raspberry Pi), or
  someone else's server: you can enter any server's IP address.
- **PAL machines.** The game is PAL only; the lobby refuses NTSC for online play.
- **The disk image**: [`RELEASE/games/bubblebobble.d64`](../../RELEASE/games/bubblebobble.d64), or build it yourself (see below).
  The disk holds the lobby `BBLAN` and the game files.

No second player? The server has two **bots**, BUBBLUN and BOBBLUN. They sit in
the lobby and accept every invitation.

## Quick start

1. **Start the server** on a PC on the LAN: [`RELEASE/start-server.bat`](../../RELEASE/start-server.bat)
   (Windows) or `RELEASE/start-server.sh` (Raspberry Pi). It prints the addresses the C64s can use.
   The dashboard is at http://localhost:8080/.

2. **On each C64:** `LOAD "BBLAN",8` and `RUN`. In VICE: double-click `RELEASE/vice-wic64.bat` and choose Bubble Bobble.

3. **The first start asks for your name** and, for the Ultimate and the WiC64, **the server's IP address**.
   Any server works, also someone else's. VICE with RR-Net needs no address: it finds the server by itself.
   Later starts go straight to the lobby.

4. **Play.** You see the other players, people and bots. Pick one with the joystick or the cursor keys and press `FIRE`/`RETURN` to invite them.
   - The other player accepts with `FIRE` or `Y`.
   - Both C64s then load the game. Bub (green) is the player who invited, Bob (blue) the one who accepted.
   - `F1` in the lobby opens the setup: change your name or the server.

The complete manual, including VICE setup, Ultimate settings, the server
configuration and troubleshooting, is in **[docs/MANUAL.md](docs/MANUAL.md)**.

## Controls

| Where | Key / joystick | Action |
|---|---|---|
| Setup | `RETURN` | Play online (connect to the lobby) |
| Setup | `L` | Local game, two joysticks, as the original |
| Setup | `S` | Name and server |
| Lobby | joystick up/down or cursor keys | Choose a player |
| Lobby | `FIRE` / `RETURN` | Invite |
| Lobby | `N` | Withdraw or decline an invitation |
| Lobby | `F1` | Setup (name, server) |
| Game | joystick in **port 2** | Move, jump, blow bubbles |
| Game | `C=` | Pause (both machines) |
| Game | `Q` | Quit the game (both machines) |

## Building from source

You need Python 3, [cc65](https://cc65.github.io/) (ca65/ld65/cl65), VICE
(`c1541` for the disk image) and the .NET 8 SDK for the server. The tools are found by
[framework/tools/c64env.py](../../framework/tools/c64env.py) (see the [main README](../../README.md#building-and-testing)).

```bash
python tools/build.py disk      # build/bblan.d64: lobby + game files
python tools/build.py verify    # the original game, byte-identical (SHA256 check)
```

From the repository root, `python build.py bubblebobble` does the same, and
`python build.py test` also runs the server tests.

Tests (they start VICE instances, minimized):

```bash
python tools/dettest.py         # determinism: PAL/NTSC/jitter/stalls give identical checksums
python tools/soak.py 300 8      # a bot plays from level 8; reports crashes and hangs
python tools/nettest.py 120     # server + two VICEs (RR-Net), complete LAN session
python tools/nettest.py 120 --wic64   # the same with VICE's WiC64 emulation
python tools/nettest.py 120 --bot     # one VICE against the server's bot BUBBLUN
python tools/screenshots.py           # the screenshots in docs/images
```

## Project layout

| Path | Contents |
|---|---|
| `src/` | The game: the reconstructed source of the C64 version (ca65), plus `bblan.s` (deterministic tick core) and `bbnet.s` (lockstep and network drivers) |
| `lobby/game.h` | Settings for the framework's [standard lobby](../../framework/c64/lobby/README.md) (title, file names, player names) |
| `tools/` | Build, test and debug tools |
| `docs/` | Manual, technical description, the original plan (Dutch), images |
| `release/` | The ready-made disk image |
| `game.json` | The game for the root `build.py` |

The game server is in [`../../server`](../../server/README.md), the lobby and the packer in [`../../framework`](../../framework).

## Credits and license

- The game source is based on **[rebb64](https://github.com/zaidka/rebb64)** by zaidka, a reconstruction of the C64 version that builds byte for byte identical to the original. Its README and technical notes are in [docs/REBB64-README.md](docs/REBB64-README.md) and [docs/REBB64-TECHNICAL.md](docs/REBB64-TECHNICAL.md).
- **Bubble Bobble** © 1986 Taito Corporation. The C64 version is by Software Creations and was published by Firebird. This is a non-commercial fan project; all rights to the game stay with their owners.
- The game server is shared with [Wizard of Wor OME](../wizardofwor/README.md).
- The WiC64 protocol follows the WiC64 team's [wic64-library](https://github.com/WiC64-Team/wic64-library).
- The CS8900a set-up follows [ip65](https://github.com/cc65/ip65) (Mozilla Public License 1.1, see [third_party/ip65-LICENSE.txt](third_party/ip65-LICENSE.txt)).
