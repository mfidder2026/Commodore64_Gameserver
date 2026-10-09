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
| `framework/c64/lobby/` | The standard C64 lobby (cc65) with Ultimate/WiC64/RR-Net drivers | every game with `"lobby": "framework"` |
| `framework/c64/packer/` | LZ packer + self-extracting loader | games that need it |
| `framework/tools/c64env.py` | Finds VICE and cc65 | every build/test script |
| `framework/release/` | Start scripts (server, VICE) and the README for `RELEASE/` | the release |
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

1. **Start**: the first start asks for the name and, for the Ultimate and the WiC64,
   the server's IP. These are saved on the disk; later starts go straight to the lobby.
   The player can enter any server's IP, so they can also play on someone else's server.
2. **Lobby**: a list of everyone online *for this game*, with **PERSON**/**BOT** and
   **FREE**/**BUSY**/**PLAYING** (from the PLAYERS message).
3. **Choose**: joystick/cursor up-down selects, **FIRE**/RETURN invites. The player can
   choose a person or a bot.
4. **Invited**: the bottom line shows the inviter; **FIRE** (or Y) plays, **N** declines.
5. **After a game**, or when the opponent disappears: back to the lobby.
6. **F1** in the lobby opens the setup (name, server); from there the player connects again.

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
- The lobby ↔ game handoff block at `$03C0` and the result at `$033C` are described in
  `docs/TECHNICAL.md`; the lobby and the game must agree on them.

### Wizard of Wor OME (`games/wizardofwor`)

- Every change to the original image is a same-size patch. The cartridge build must
  keep matching `BASELINE_CART_MD5` (checked by `tools/build.py`).
- 64tass runs in WSL (`tools/64tass.sh`).
- Determinism: `python tools/dettest.py` (PAL vs NTSC).
- The network code lives at `$5D00-$7FFF` (`src/net/`); its data ends at about `$7F58`, so only about
  170 bytes are left there. The drivers are `uci.asm`, `net_rrnet.asm` (ip65, UDP) and `wic64.asm`
  (TCP). A WiC64 sends every 4th tick and the server gives WiC64 sessions an input delay of 8.
- `python tools/servertest.py 90 [--bot]`: the server plus two VICEs with the WiC64 (or one against a bot).

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
