# The standard lobby

A small C64 program (C with [cc65](https://cc65.github.io/), drivers in
assembly) that every OME game can use as its front end. It gives each game
the same lobby (see the lobby standard in [AI_AGENT.md](../../../AI_AGENT.md)):

1. It finds the network hardware: **C64 Ultimate** (Command Interface, UDP),
   **WiC64** (TCP) or **RR-Net** (raw Ethernet, VICE).
2. The first time it asks for the name and, for the Ultimate and the WiC64, the server's IP (any server), and
   saves them on the disk. Later starts connect to the lobby at once.
3. It connects and shows **everyone online for this game**: PERSON or BOT, and FREE, BUSY or PLAYING.
4. The player invites someone (FIRE/RETURN) or accepts an invitation (FIRE/Y; N declines).
   F1 opens the setup screen: name and server, a local game (`LOCAL_GAME_TEXT`), play online.
5. When the server starts the session, the lobby writes a **handoff block** and **loads the game file**. The game takes over the network connection.
6. After the game, the game loads the lobby again. The lobby shows how the game ended and reconnects.

| Start | Lobby | Invited |
|---|---|---|
| ![](../../../games/bubblebobble/docs/images/lobby-menu.png) | ![](../../../games/bubblebobble/docs/images/lobby-players.png) | ![](../../../games/bubblebobble/docs/images/lobby-invited.png) |

## Files

| File | Contents |
|---|---|
| `main.c` | Screens, configuration file, lobby protocol, invitations, start of the game |
| `net.c`, `net.h` | Network layer: picks the driver, frames messages |
| `uci.s` | C64 Ultimate Command Interface (UDP) |
| `wic64.s` | WiC64 firmware 2.x (TCP, `[length][message]`) |
| `rrnet.s` | CS8900a / RR-Net, raw Ethernet frames with EtherType `$88B5` |
| `loader.s` | Loads the game file from a stub at `$033C` and starts it |

## Per game: `game.h`

All game-specific settings come from `games/<game>/lobby/game.h`. The game's
build compiles this folder with `-I games/<game>/lobby`:

```c
#define GAME_ID       3                   /* game id on the server */
#define GAME_VERSION  1
#define GAME_TITLE    "     BUBBLE BOBBLE  *  ONLINE"   /* max. 40 characters */
#define GAME_TAGLINE  "     two C64s, one game, one network"
#define CFG_FILE      "bblan.cfg"         /* settings file on the disk */
#define FILE_UCI      "bbu"               /* game file per network type */
#define FILE_WIC      "bbw"
#define FILE_RR       "bbr"
#define GAME_PAL_ONLY 1                   /* warn on NTSC machines */
#define LOCAL_GAME_TEXT "local game (2 joysticks)"   /* key L; leave undefined if none */
#define SLOT0_NAME    "BUB (green)"       /* slot 0 = the inviter */
#define SLOT1_NAME    "BOB (blue)"
```

Build, as in `games/bubblebobble/tools/build.py`:

```bash
cl65 -t c64 -O -I games/<game>/lobby -o lobby.prg framework/c64/lobby/main.c framework/c64/lobby/net.c \
     framework/c64/lobby/rrnet.s framework/c64/lobby/uci.s framework/c64/lobby/wic64.s framework/c64/lobby/loader.s
```

There are three game files, one per network type, so each holds only the driver
it needs. A game with room for all drivers can use the same name for all three.

## The contract between the lobby and the game

### Handoff block at `$03C0` (lobby → game, 24 bytes)

| Offset | Contents |
|---|---|
| 0-1 | `BL`: the block is valid |
| 2 | driver: 0 = none (local game), 1 = Ultimate, 2 = RR-Net, 3 = WiC64 |
| 3 | player slot (0 = the inviter) |
| 4 | session id |
| 5-6 | start parameters 0 and 1 (Bubble Bobble: the seed) |
| 7 | start parameter 2 (Bubble Bobble: the input delay) |
| 8 | UCI socket (Ultimate) |
| 9 | flags: bit 0 = test bot plays instead of the joystick |
| 10 | drive number (to load the lobby again) |
| 11 | free |
| 12-17 | RR-Net: the server's MAC |
| 18-23 | RR-Net: our own MAC |

`LOAD` does not touch `$03C0-$03FF`. A game packed with
[../packer](../packer) copies the block into the game: give `pack.py` the
address with `hb_addr`. The game must clear the `BL` marker.

The block carries the first three start parameters. A game that needs more
must extend the block **here**, for every game, and update this table.

### Result at `$033C` (game → lobby)

| Offset | Contents |
|---|---|
| 0-1 | `BR`: the game came back |
| 2 | reason (as SESSION_END): 1 game over, 2 desync, 3 timeout, 4 ended by the server, 5 a player quit, 6 the opponent left |
| 3 | UCI socket, so the lobby can close it |

Before it loads the lobby (`LOAD "<lobby>",<drive>` and `JMP $080D`), the game
resets the C64 to KERNAL state: `IOINIT`, `RAMTAS`, `RESTOR`, `CINT`. Keep the
result safe while `RAMTAS` clears the low memory, for example on the stack. See
`bb_end` in `games/bubblebobble/src/bbnet.s`.

### The connection

The lobby answers START with START_ACK (three times) before it loads the game.
The game continues on the connection the lobby opened, and sends no HELLO:

- **Ultimate:** the UDP socket in byte 8;
- **WiC64:** the TCP connection stays open;
- **RR-Net:** the two MAC addresses in the block.

The server's game module must allow a silent period while the game loads.
For Bubble Bobble that is `loadTimeoutSeconds`, through `IGameModule.IdleTimeout`.

## Configuration file

`CFG_FILE` on the disk, written by the lobby. These lines are for testing:

```
name=ALICE
server=192.168.1.10
mac=021111111101
auto=i       tests: i = invite the first free person, b = invite the first free bot, a = accept
bot=1        tests: the game's test bot plays instead of the joystick
```

## Changing the lobby

This code is shared by every game that uses it. After a change:

- build and test all of these games: `python build.py`, `python build.py test`;
- run an end-to-end test: `games/bubblebobble/tools/nettest.py 120`, plus `--wic64` and `--bot` when the drivers or the lobby flow changed;
- keep the handoff and result tables above in step with the games.
