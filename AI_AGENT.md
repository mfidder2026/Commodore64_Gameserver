# AI_AGENT.md: rules for AI agents working on this repository

Every AI agent (and every human) working on this repository reads this file first.

This repository is the **Commodore 64 Game Server**: one game server, a shared C64
framework and several *Online Multiplayer Enabled* (OME) games. Read this file
before changing anything. These rules keep all games working together. The
repository is public, so everything in it must be in **English**: code,
comments, docs and commit messages.

## Layout: where things live

| Path | What | Who uses it |
|---|---|---|
| `server/` | The game server (C#/.NET 8): core, transports, game modules, bots, dashboard, tests | all games |
| `framework/c64/lobby/` | The standard C64 lobby (cc65) with Ultimate/WiC64/RR-Net drivers; `tables.c` for games with tables (`GAME_TABLES`) | every game with `"lobby": "framework"` |
| `framework/c64/net/` | In-game network code for lockstep games: handoff, lockstep, checksums, drivers, back to the lobby. `NET_PLAYERS = 4` for up to four players, `NET_SPLIT = 1` for four segments (cramped games), `NET_BOT_PERSON = 1` for a test bot that moves like a person | Exploding Fist, Pitstop II, M.U.L.E., Archon, Spy vs Spy (Bubble Bobble still has its own copy, `src/bbnet.s`) |
| `framework/c64/packer/` | LZ packer + self-extracting loader | games that need it |
| `framework/c64/linktest/` | The C64 Ultimate link test (cc65): two C64s directly, the firmware's `$0A` (UDP from a fixed local port) or RR-Net; uses the lobby's `uci.s` and `rrnet.s` | `RELEASE/tools/linktest.d64` |
| `framework/tools/c64env.py` | Finds VICE and cc65 | every build/test script |
| `framework/tools/vicemon.py`, `dis6502.py`, `nettest.py` | VICE monitor helper, a 6502 disassembler, the generic end-to-end test (reads `game.json` "nettest") | game tools |
| `framework/tools/imagebuild.py`, `determinism.py` | The "snapshot + patches" build for games without source (areas files may include others), and the determinism test (several VICEs, RAM compared); `waitpatch.py` generates wait loop patches for games with virtual frames; `ImageGame(local_net=False)` builds the local game without `net.s` | Exploding Fist, Pitstop II, M.U.L.E., Archon, Spy vs Spy |
| `framework/release/` | Start scripts (server, VICE) and the README for `RELEASE/` | the release |
| `framework/release/Dockerfile`, `docker-compose.yml` | The server in the user's own Docker: an image built from RELEASE's `server/linux-x64` / `linux-arm64` (no registry; [docs/docker.md](docs/docker.md)) | the release |
| `games/<name>/` | One game: `game.json`, `README.md`, source, tools, docs | that game only |
| `docs/` | Architecture, protocol, adding-a-game, central images | everyone |
| `build.py` | Builds/tests the server and all games via `games/*/game.json`; `release` fills `RELEASE/` | everyone |
| `RELEASE/` | The latest ready-to-run files: server builds, disk images, start scripts. Generated, but committed | players |

## The main rule: shared changes apply to all games

**Framework or server changes are changes for every game.**

1. **Do not fork shared code into a game folder.** If a game needs different
   behaviour from the lobby, the packer, the tool lookup or the server, make the
   shared code configurable: `game.h` for the lobby, `settings` and the module for
   the server, `BotProfile` for the bots. Then use that setting in the game.
2. **After changing shared code, build and test every game.** Run `python build.py`
   and `python build.py test`, not only the game you were working on.
3. **Fix a bug where it lives.** A bug in the lobby, a driver, the protocol or the
   server is fixed in `framework/` or `server/` once, not patched per game.
4. **Protocol changes** (`docs/protocol.md`, `server/src/C64GameServer.Core/Protocol/Protocol.cs`, the C64
   drivers) must stay backward compatible, or be done for all games in the same
   change. Message types `$00-$7F` are the platform's; `$80-$FF` belong to a game.
   Byte 1 of a game message is always the session id.
5. **Keep these in sync** when a game is added or changed:
   - `games/<name>/game.json`;
   - the default games in `server/src/C64GameServer.Core/Core/ServerConfig.cs`;
   - the module in `GameRegistry.FromConfig` (`Games/GameModules.cs`);
   - the bot profile in `BotProfile.For` (`Bots/BotClient.cs`);
   - the table in `README.md` and the section in `docs/protocol.md`.
6. **Every game supports the same networks**: C64 Ultimate (UDP), WiC64 (TCP, real and in
   VICE) and VICE with RR-Net. A new game, or a new network type, is only done when all
   games have it. The standard lobby already has all three drivers.

## The lobby standard (every game)

Every OME game gives the player the same experience as Wizard of Wor:

1. **Start**: a menu (standard lobby): local game, head-to-head, online via a game server,
   change name, change server. The name and (Ultimate, WiC64) the server's IP are asked when
   first needed and saved on the disk; once a server is set, later starts go straight to the
   lobby. The player can enter any server's IP, so they can also play on someone else's server.
2. **Lobby**: a list of everyone online *for this game*, with **PERSON**/**BOT** and
   **FREE**/**BUSY**/**PLAYING** (from the PLAYERS message).
3. **Choose**: joystick/cursor up-down selects, **FIRE**/RETURN invites. The player can
   choose a person or a bot.
4. **Invited**: the bottom line shows the inviter; **FIRE** (or Y) plays, **N** declines.
5. **After a game**, or when the opponent disappears: back to the lobby.
6. **F1** in the lobby goes back to the start menu; from there the player connects again.

New games use `framework/c64/lobby` with a `games/<name>/lobby/game.h`. They do not
get their own lobby unless the lobby has to live inside the game (as in Wizard of
Wor) and the game still meets the standard above.

## The server and the dashboard

- Games are generic in the core. Game-specific logic only lives in a module
  (`IGameModule` / `RelayModule`) in `server/src/C64GameServer.Core/Games/`.
- The dashboard (`server/src/C64GameServer/Dashboard.cs`) builds **one tab per game**
  from the `games` list. Never hard-code a game in the page. Everything in the status
  JSON that belongs to a game carries a `gameId`: players, sessions, challenges and events.
- Event log entries get their game from the session or the player (`LogEvent`). Pass
  `game:` when there is neither.
- Bots are configured per game in `server.json` (`games[].bots`). A bot plays real
  lockstep as described by its game's `BotProfile`: packet length, input window, tick
  rate, idle input, and how long to wait for the first input.
- Run `dotnet test` in `server/` after every server change (`python build.py server`).

## Per-game rules

### Bubble Bobble OME (`games/bubblebobble`)

- **No byte of the original rebb64 may move.** Changes are same-size patches
  (`BB_PATCH_END`) or code in the BB-LAN areas. `tools/build.py` checks the layout
  against `tools/original-layout.json`. `python tools/build.py verify` must stay
  byte-identical to the original.
- Memory is almost full: RR build 2 bytes free, UCI 26, WiC64 37
  (`python tools/build.py` prints it). The packed PRG must stay below `$D000`.
- Determinism: `python tools/dettest.py` must PASS after every change to `src/`.
- Head-to-head without the server (lobby key H, `DIRECT_DELAY` in `lobby/game.h`):
  `python tools/directtest.py 80` (two VICEs with RR-Net, host and joiner, no server).
- The lobby ↔ game handoff block at `$03C0` and the result at `$033C` are described in
  `docs/TECHNICAL.md`; the lobby and the game must agree on them.

### The Way of the Exploding Fist OME (`games/explodingfist`)

- **No source code**: the base is `orig/fist-1158.bin`, the RAM image at the game's entry (made by
  `tools/snapshot.py` from the clean disk; its hash is in `orig/fist-1158.json`). Never edit it; all changes are
  ca65 patches in `src/main.s`. A segment `P_xxxx` lands at `$xxxx`; every patched byte must lie in an area of
  `src/areas.json` (the build checks it). Same-size patches in the original code, new code in `$F540-$FF3F`
  (the invisible floor rows of the bitmap; about 1.1 KB left).
- Our code lies under the KERNAL ROM: never switch the KERNAL in from there (`$01` must keep `$E000` as RAM);
  the framework's `net_end` copies its last part to `NET_TAIL` for that reason.
- Determinism: `python tools/dettest.py 6200` (a whole match: PAL, NTSC, 0-3 frames of jitter) must PASS. The
  IRQ's display, the music and its zero page (`$14-$33`, `$F9-$FE`) may differ; the checksum
  (`src/netgame.inc`) leaves them out.
- End to end: `python ../../framework/tools/nettest.py . 120 [--wic64|--bot]`.

### Wizard of Wor OME (`games/wizardofwor`)

- Every change to the original image is a same-size patch. The cartridge build must
  keep matching `BASELINE_CART_MD5` (checked by `tools/build.py`).
- 64tass runs in WSL (`tools/64tass.sh`).
- Determinism: `python tools/dettest.py` (PAL vs NTSC).
- The network code lives at `$5D00-$7FFF` (`src/net/`); its data ends at about `$7F58`, so only about
  170 bytes are left there. The drivers are `uci.asm`, `net_rrnet.asm` (ip65, UDP) and `wic64.asm`
  (TCP). A WiC64 sends every 4th tick and the server gives WiC64 sessions an input delay of 8.
- `python tools/servertest.py 90 [--bot]`: the server plus two VICEs with the WiC64 (or one against a bot).

### Pitstop II (`games/pitstop2`)

- Same "snapshot + patches" build as Exploding Fist (`orig/pitstop2-9403.bin`, from the tape version with
  the trainer question answered N). `python tools/build.py` is the clean original game as one PRG (`pitl`
  on the disk, loaded by the lobby's key L through `LOCAL_GAME_FILE`).
- Online builds (`ONLINE`, implied by `NET_*` and `DETTEST`) use `src/areas-online.json`. The raster IRQ
  only draws; the race logic (`$3835`-`$3EC9`, ends with RTI) runs as slots from the main loop
  (`pit_pass` at `$41A0`). Anything the display IRQ writes that the logic reads breaks lockstep: check new
  patches with a flow trace (IRQ writes vs logic/main reads) and `python tools/dettest.py 6000`.
- `python ../../framework/tools/nettest.py . 180 [--wic64|--bot]` is the end-to-end test.

### M.U.L.E. (`games/mule`)

- Two files on the disk: `m.u.l.e.` (title and options) loads `&` (the game, entry `$972B`). The snapshot
  is taken at `$972B` from the disk without the cracker's texts (`tools/crackfix.py`).
- Virtual frames: the raster IRQ `$5F17` only draws; its frame logic (clocks, inputs, count-downs, music,
  the frame task `$58`) runs as `mule_tick`, where the main program waits. `tools/waits.py` generates the
  wait loop patches (tight loops, loop heads, calls, jumps back): a new hang in the test build = a wait
  loop to add there. Find it with `hunt`-style runs: sample the PC, read the stack at `mule_tick`.
- Memory is scarce: our code fills gaps (`src/areas-online.json`; the README's table). Check every new
  "dead" area for indirect use: the raster handler `$8B3C` inside the old title is set via `JSR $8571`.
  VICE's memmap misses code above `$A000` and never sees VIC fetches below `$4000`.
- Session: slots = seats; the table's option is the level (`$E504`); `$972B` (the game's restart) ends it.
- `python tools/dettest.py <ticks> humans=N`; `python ../../framework/tools/nettest.py . 240 --players 4`.

### Archon (`games/archon`)

- One file on the tape (`$0801-$A9FF`, a block move, then `$6100`). The snapshot is taken at `$6100` from the
  file without the cracker's line (`tools/crackfix.py`); that clean file is also the lobby's key L (`archl`).
- Virtual frames as in M.U.L.E.: the raster IRQ's frame logic (through `$BCCC`) runs as `arch_tick` where the
  main program waits (`tools/waits.py`). The KERNAL's jiffy clock (`$A0-$A2`) is virtual too: 6 jiffies per
  5 ticks, the CIA timer IRQ only acknowledged. Wait stubs come first in `$C500` (same addresses in every build).
- All our code lies in `$C000-$CFFF`, which the game never touches. Slot 0 = light (port 1), slot 1 = dark.
- `python tools/dettest.py 10000 humans=1` (also `humans=2`, and no `humans=`: the demo);
  `python ../../framework/tools/nettest.py . 300 [--wic64|--bot]`. Two test bots rarely finish a game.

### Spy vs Spy (`games/spyvsspy`)

- One file on the disk; two unpackers and the cracker's mover end at `$660F`, where the snapshot is taken.
  The cracker's line on the options screen is blanked by a patch (`P_18E9`).
- A tick is one pass of the main loop (`$674E`, one spy per pass); `net_step` once per round. The clocks
  (`$9362`) run in the tick (7 virtual frames per 5 passes); the IRQ keeps drawing, sound and music, whose
  bytes the checksum and `tools/dettest.py` leave out. Anything new the IRQ writes that the game logic
  reads breaks lockstep. A desync that dettest does not show: halt both C64s of a nettest at the
  same tick (a temporary loop in `spy_tick`), save both RAMs with the monitor and compare them.
- `$C000-$CFFF` holds the demo's recorded inputs: online builds use `$C000-$C983` for our code (no demo
  there); the original game (`spyl`, `local_net=False`) keeps its demo, its entry lies in the table's
  unused ends.
- Private screen (table option bit 3): `spy_irqhalf` (at the IRQ's start of a half) and `spy_irqend` show
  the other spy's half black (ECM + bitmap, no sprites). It only writes VIC registers; keep it that way.
- `NET_TAIL` must lie outside the SPY/NET segments (`$C984`, the copy of `$0200-$03FF`): net_end copies
  its last part there while it runs.
- Head-to-head (lobby key H, `DIRECT_DELAY` in `lobby/game.h`) for every framework game:
  `python ../../framework/tools/nettest.py . 60 --direct [--option N]` (two VICEs, no server).
- `python tools/dettest.py 10000 humans=1` (also `humans=2`, `level=1-8`, `private=0|1`);
  `python ../../framework/tools/nettest.py . 300 --players 2` (`--players 1`: alone against the computer;
  `--option N`: the table's option, 8-15 private).

## Open framework work

- Bubble Bobble still uses its own copy of the network code (`games/bubblebobble/src/bbnet.s`). Move it to
  `framework/c64/net/net.s` when there is room: it has only 2 bytes free in its RR-Net build, and `net.s` counts
  frames by the raster instead of the game's IRQ.
- Bubble Bobble's `tools/nettest.py` and `screenshots.py` can move to `framework/tools/nettest.py` (needs a
  "nettest" section in its `game.json`).

## Conventions

- **Python tools** import `c64env` for VICE/cc65. Never hard-code paths to a user's machine.
- **VICE in tests** always runs with `-minimized`. For fast disk access use `+drive8truedrive -virtualdev8`.
  Feed keys by writing to `$0277`/`$C6` through the remote monitor, not with `-keybuf`.
- **cc65 pitfalls:**
  - `'\r'` is not RETURN; use `CH_ENTER`.
  - `cl65 -t c64` translates character literals to PETSCII. In `.s` files write `$52`, not `'R'`, for ASCII protocol bytes.
- **Secrets**: never write tokens, passwords or personal IP addresses into the repository. Screenshots of
  the dashboard get their IP addresses masked.
- **Generated files**: `build/`, `server/**/bin|obj|publish`, `server.json`, `server.log` and
  `paths.local.json` are not committed. `RELEASE/` is the exception: it is made by `python build.py release`
  and committed, so players can download everything in one place. Never edit files in `RELEASE/` by hand;
  change `framework/release/` or the games and run the release again.
- **Releases**: run `python build.py release` before pushing a change to a game, the lobby or the server,
  so `RELEASE/` always holds the latest version. It holds the server for win-x64 and linux-arm64
  (about 35 MB each).
- **Commits**: one logical change per commit, with an English message. Mention which games were
  rebuilt and tested.

## Commands

```bash
python build.py                 # server + all games
python build.py test            # server unit tests + all game tests
python build.py server          # server only (build + unit tests)
python build.py list            # games from games/*/game.json
python build.py release         # rebuild everything and refresh RELEASE/
cd server && dotnet run --project src/C64GameServer -c Release      # run the server (dashboard :8080)
cd games/bubblebobble && python tools/nettest.py 120 [--wic64|--bot] # end-to-end with VICE
cd games/wizardofwor && python tools/servertest.py 90 [--bot]        # end-to-end with VICE (WiC64)
```

## Definition of done for a change

- [ ] Builds: `python build.py`
- [ ] Tests: `python build.py test` (or at least `server` plus the touched games' tests)
- [ ] Protocol or lobby changed? End-to-end run (`nettest.py`) for a game that uses it
- [ ] Docs updated: the game's README, `docs/protocol.md`, the root `README.md` (game table, screenshots)
- [ ] `RELEASE/` refreshed: `python build.py release`
