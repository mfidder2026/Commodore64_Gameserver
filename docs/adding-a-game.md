# Adding a game

This guide makes a C64 game **Online Multiplayer Enabled (OME)** in this
framework. Bubble Bobble OME is the reference: it went through every step below.

## 0. Is the game suitable?

The framework uses **lockstep**. Both C64s run the full game, and only the
joystick inputs cross the network. That needs:

- **Determinism.** With the same start values and the same inputs, the game
  must compute exactly the same thing on both machines. Look for:
  - random numbers from the raster line, CIA timers or SID noise;
  - game logic that depends on how many frames really passed;
  - memory that is not initialised.
- **A tick.** One step of game logic that you can run when both inputs are
  there, and hold while they are not.
- **Room** for the network code: about 1-3 KB, depending on the drivers. The
  standard lobby is a separate program, so it costs the game no memory.

Bubble Bobble and Wizard of Wor both needed work to get there. See
[games/bubblebobble/docs/TECHNICAL.md](../games/bubblebobble/docs/TECHNICAL.md)
and `games/wizardofwor/docs/fase2_determinisme.md` (in Dutch).

## 1. The game folder

```
games/<name>/
  game.json          id, module, build command, disk image, tests (read by the root build.py)
  README.md          English: what it is, screenshots, how to play, how to build
  lobby/game.h       settings for the standard lobby
  src/               the game
  tools/build.py     builds the disk image (uses framework/tools/c64env.py)
  docs/images/       screenshots
```

`game.json`:

```json
{
  "id": 4,
  "name": "My Game",
  "short": "MG",
  "module": "relay",
  "lobby": "framework",
  "build": ["python", "tools/build.py", "disk"],
  "disk": "build/mygame.d64",
  "tests": [["python", "tools/dettest.py"]],
  "readme": "README.md"
}
```

Pick a game id that is not used yet (`python build.py list`). Then
`python build.py <name>` builds the game.

Tool lookup in a Python build script:

```python
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "framework", "tools"))
import c64env
ca65, ld65, cl65 = c64env.cc65("ca65"), c64env.cc65("ld65"), c64env.cc65("cl65")
x64sc, c1541 = c64env.vice("x64sc"), c64env.vice("c1541")
```

## 2. The lobby: use the standard one

Write `games/<name>/lobby/game.h` (see
[framework/c64/lobby/README.md](../framework/c64/lobby/README.md)) and compile
the framework lobby with `-I games/<name>/lobby`. That gives the game the same
lobby as every other OME game: start, the list of people and bots, invite,
accept, and back to the lobby after the game.

Put on the disk:

- the lobby, as the first file, so `LOAD"*",8,1` or autostart starts it;
- the game file per network type (`FILE_UCI`, `FILE_WIC`, `FILE_RR`).

Do **not** copy the lobby into the game folder. If the game needs something
the lobby cannot do yet, add an option to `game.h` and the framework. That
change then exists for every game (see [AI_AGENT.md](../AI_AGENT.md)).

## 3. The game side: lockstep

Follow the lockstep pattern in [protocol.md](protocol.md#the-lockstep-pattern-both-games).
Bubble Bobble's `src/bbnet.s` is a complete example with all three drivers:

1. **At start:** read the handoff block at `$03C0` (driver, slot, session,
   start parameters, socket or MACs). Seed the game's random generator from the
   start parameters. Initialise everything the game logic reads.
2. **Every tick:**
   - read the joystick;
   - store it for tick `t + delay`;
   - send INPUT (`$80`, session, newest tick, checksum tick, checksum, the last N inputs);
   - poll until the opponent's input for tick `t` is there, resending while waiting;
   - run the tick with both inputs.
3. **Every 64 ticks** put a checksum of the game state into the INPUT
   messages: level, random generator, positions, scores, lives.
4. **At the end:**
   - send SESSION_END (reason 1 = game over, 5 = quit);
   - write the result at `$033C`;
   - reset to KERNAL state;
   - load the lobby again.
5. **Timeouts.** If nothing comes from the opponent for 10 s, end the game.
   Wait longer at the start, while the other C64 may still be loading.

Choose the input window, so that a lost packet costs nothing:

| Game | Ticks/s | Inputs per INPUT |
|---|---|---|
| Wizard of Wor | 60 | 16 |
| Bubble Bobble | 25 | 8 |

## 4. The server

### a) No server code: the `relay` module

If the server only has to pass the messages on, add the game to the defaults
in `server/src/C64GameServer.Core/Core/ServerConfig.cs` (and to your
`server.json`):

```json
{ "id": 4, "name": "My Game", "module": "relay", "version": 1, "bots": [] }
```

Rules for the C64 side:

- HELLO with game id 4 and version 1;
- game messages use the types `$80-$FF`;
- **byte 1 of every game message is the session id** from START;
- START has no start parameters (length 0). Decide who does what from the player slot;
- at the end: SESSION_END with reason 1.

The test `A_relay_game_from_the_configuration_needs_no_code` shows this works.

### b) A module: start parameters, checksums, timeouts

A lockstep game wants a module: it picks the seed and the delay, and compares
checksums. Copy `BubbleBobbleModule` in
`server/src/C64GameServer.Core/Games/GameModules.cs`:

```csharp
public sealed class MyGameModule(GameConfig config) : RelayModule(config)
{
    // start parameters in START (the same for all players)
    public override byte[] CreateSession(Session session, Random random) =>
        [(byte)random.Next(256), (byte)random.Next(256), 2];

    // a game message ($80-$FF, session id already checked)
    public override void OnGameMessage(ISessionContext ctx, Session session, Client from, ReadOnlySpan<byte> m)
    {
        ctx.SendToOthers(session, from, m);
        // compare checksums; on a mismatch:
        // ctx.EndSession(session, EndReason.Desync, "reason");
    }

    // how long a player may stay silent (e.g. while the game loads)
    public override TimeSpan IdleTimeout(Session session, Client player, TimeSpan normal) => normal;

    // extra lines for the dashboard
    public override IReadOnlyList<(string Name, string Value)> Status(Session session) =>
        [("tick", "123")];
}
```

Register it in `GameRegistry.FromConfig`:

```csharp
"mygame" => new MyGameModule(g),
```

Settings from `server.json` (`"settings": { "inputDelay": 2 }`) are read
with `config.Settings.GetValueOrDefault("inputDelay", 2)`.

Write tests modelled on `BubbleBobbleTests` in
`server/tests/C64GameServer.Tests/ServerTests.cs`. The harness has a fake clock
and a fake network.

### c) Bots

Players should always find an opponent. Give the game bots in its defaults
(`"bots": ["NAME1", "NAME2"]`, A-Z and 0-9, at most 8 characters) and a
`BotProfile` in `server/src/C64GameServer.Core/Bots/BotClient.cs`:

```csharp
4 => MyGame,
...
public static readonly BotProfile MyGame = new(
    InputLength: 16, Window: 8, TickRate: 25, IdleInput: 0x1F, FirstInputTimeoutSeconds: 150,
    Input: (tick, slot, seed) => /* a random but plausible joystick byte */ 0x1F);
```

A bot plays real lockstep with random inputs and sends no checksums. Test it
against a real (emulated) C64. For Bubble Bobble that is
`python tools/nettest.py 120 --bot`, with `auto=b` in the lobby's
configuration file.

### d) The dashboard

Nothing to do: every game in the `games` list gets its own tab, with its
players, sessions, challenges and events. The lines from `Status()` show with
each session.

## 5. Documentation and checks

- [ ] `games/<name>/README.md` in English, with screenshots (lobby, game)
- [ ] A row and a section in the root [README.md](../README.md)
- [ ] The game's messages and start parameters in [protocol.md](protocol.md)
- [ ] `game.json`, the `ServerConfig` defaults, `GameRegistry` and `BotProfile` agree
- [ ] `python build.py` and `python build.py test` pass
- [ ] The game runs on every network: Ultimate, WiC64 (real and VICE) and VICE RR-Net
- [ ] An end-to-end session between two emulated C64s, and one against a bot
- [ ] `python build.py release`: the game's disk is in `RELEASE/games/`, and `vice-wic64.bat` offers it
  (add it to the menu in `framework/release/_vice.cmd`)
