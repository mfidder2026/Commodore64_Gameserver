# Architecture

The project has three layers: the **server**, the **framework** and the **games**.
The server and the framework are shared, so a change there applies to every game.

```
                         ┌─────────────────────── server/ (C#, .NET 8) ───────────────────────┐
 C64 Ultimate ──UDP──────┤ UdpTransport  ┐                                                    │
 WiC64 ─────────TCP──────┤ TcpTransport  ├─ MuxTransport ─ ServerCore ─ GameRegistry           │
 VICE RR-Net ──Ethernet──┤ PcapTransport ┘                 │ lobby       ├ WizardOfWorModule  │
                         │                                 │ challenges  ├ BubbleBobbleModule │
                         │  BotClient × n (per game) ─UDP──┤ sessions    └ RelayModule        │
                         │                                 │ timeouts                          │
                         │  Dashboard (HTTP + SSE) ────────┘ EventLog                          │
                         └────────────────────────────────────────────────────────────────────┘
```

## Server (`server/`)

| Part | File | Role |
|---|---|---|
| `ServerCore` | `C64GameServer.Core/Core/ServerCore.cs` | Clients, lobbies per game, invitations, challenges, sessions, pings, timeouts. It knows no game. |
| Messages | `C64GameServer.Core/Protocol/Protocol.cs` | Message types, parsing and building |
| Game modules | `C64GameServer.Core/Games/GameModules.cs` | `IGameModule`: start parameters, handling game messages, checksum compare, idle timeouts, dashboard lines |
| Config | `C64GameServer.Core/Core/ServerConfig.cs` | `server.json`, with the default games and their bots |
| Bots | `C64GameServer.Core/Bots/BotClient.cs` | A client that plays like a C64; `BotProfile` per game |
| Event log | `C64GameServer.Core/Core/EventLog.cs` | Events with player, session and game; written to `server.log` |
| Transports | `C64GameServer/Program.cs`, `TcpTransport.cs`, `PcapTransport.cs` | UDP, TCP (WiC64), raw Ethernet (pcap); `MuxTransport` sends each message over the transport its client came in on |
| Dashboard | `C64GameServer/Dashboard.cs` | Web page with one tab per game, live through Server-Sent Events; kick and end-session buttons |
| `C64Bot` | `src/C64Bot` | The bot as a separate program, for tests |

### Clients and games

A client says in its HELLO which game it plays. From then on, everything it
sees belongs to that game: the lobby list (PLAYERS), invitations, sessions.
One server hosts all games at the same time.

A client is identified by an `IPEndPoint`, whatever its transport:

- UDP: IPv4 address and port;
- TCP: an IPv4-mapped IPv6 address;
- raw Ethernet: a link-local IPv6 address made from the MAC address.

So the core does not know or care how a C64 is connected. A module can ask,
though. For example, both games get a longer input delay when a WiC64
takes part.

### Sessions

```
INVITE → challenge → all ACCEPT → module.CreateSession() → START (repeated) → START_ACK
       → game messages → module.OnGameMessage() → relay to the other players
       → SESSION_END / timeout / OPPONENT_LEFT → back to the lobby
```

The core drops a game message unless byte 1 is the sender's session id. The
module compares the checksums and can end the session (*desync*).

### Bots

`server.json` lists the bots per game (`games[].bots`). The server starts them
as normal clients over the loopback interface. They show up in their game's
lobby as BOT, accept every challenge, and play real lockstep with random
inputs, as described by `BotProfile.For(gameId)`. A bot sends no checksums,
because it does not simulate the game.

### Dashboard

`/api/status` returns everything as JSON. Players, sessions, challenges and
events each carry a `gameId`. The page builds an **All games** tab plus one
tab per entry in `games`, so a new game gets its tab without changes to the
page. `/?static` shows one snapshot without a live connection, for
screenshots.

## Framework (`framework/`)

| Part | Role |
|---|---|
| `c64/lobby` | The standard C64 lobby, configured per game with `game.h`. It hands the connection to the game through a block at `$03C0`. See its [README](../framework/c64/lobby/README.md). |
| `c64/net` | In-game network code for lockstep games: the handoff block, lockstep with an input ring, state checksums, the three drivers, back to the lobby. Configured per game with `netgame.inc` |
| `c64/packer` | An optimal-parse LZ packer with a self-extracting loader. It copies the handoff block into the game and clears the stack page, so the game starts from a known state. |
| `tools/c64env.py` | Finds VICE and cc65 for every script |
| `tools/vicemon.py`, `dis6502.py`, `nettest.py` | Driving VICE's monitor (breakpoints, RAM dumps), a 6502 disassembler, the generic end-to-end test |

## Games (`games/`)

Each game folder is self-contained (source, tools, docs, release) and
described by its `game.json`. The root `build.py` reads these files.

| | Wizard of Wor OME | Bubble Bobble OME | Exploding Fist OME |
|---|---|---|---|
| Source | dabadab's disassembly, 64tass | rebb64 reconstruction, ca65 | none: the RAM image at the game's entry + ca65 patches |
| Lobby | inside the game (`netgame.asm`) | framework lobby + `lobby/game.h` | framework lobby + `lobby/game.h` |
| C64 network | Ultimate (UCI), WiC64 (TCP), RR-Net with ip65 (UDP) | Ultimate (UCI), WiC64 (TCP), RR-Net (raw Ethernet) | the same, from `framework/c64/net` |
| Ticks | 60/s, cost model for the original pace | 25/s (one odd logical frame), virtual game time | one pass of the bout loop (about 46/s) |
| INPUT | 24 bytes, 16 inputs | 16 bytes, 8 inputs | 16 bytes, 8 inputs |
| Other modes | local, direct VICE ↔ C64 without a server | local (two joysticks) | the original game (one or two players) |
| Memory trick | code at `$5D00` and `$C000` | compressed level bitmaps free about 1.3 KB | the invisible floor rows of the bitmap (2.5 KB) |
| Layout rule | same-size patches; the cartridge build must keep its MD5 | no byte of the original moves (`original-layout.json`) | patches only in the areas of `src/areas.json` |

Both games keep the original game logic and add the same three things:

1. a deterministic tick;
2. a lockstep loop that exchanges inputs and checksums;
3. a lobby that meets the lobby standard in [AI_AGENT.md](../AI_AGENT.md).

## Testing

| Level | How |
|---|---|
| Server core | `dotnet test` (in `server/`): a fake clock and a fake transport; lobby, invitations, sessions, timeouts, checksums, modules |
| Determinism | each game's `tools/dettest.py`: two VICEs (PAL/NTSC, jitter, stalls) must produce the same checksums |
| End to end | `framework/tools/nettest.py <game>` (Exploding Fist), `games/bubblebobble/tools/nettest.py` and `games/wizardofwor/tools/servertest.py`: the server plus two VICEs over RR-Net or WiC64, or one VICE against a bot |
| Everything | `python build.py test` |
