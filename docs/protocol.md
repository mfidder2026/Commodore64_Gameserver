# C64 Game Server protocol (version 1)

This is the contract between the server and the C64s, for every game. The
platform part (`$00-$7F`) is the same for all games. Each game adds its own
messages (`$80-$FF`), described at the end of this document.

## Transport

| C64 | Transport | Framing |
|---|---|---|
| C64 Ultimate (Command Interface) | UDP to port `gamePort` (6465) | one datagram = one message |
| WiC64 | TCP to port `tcpPort` (6466), NoDelay | `[length][message]` in the stream |
| VICE RR-Net (raw Ethernet) | Ethernet frames, EtherType `$88B5`, via pcap | destination MAC, source MAC, `$88B5`, `[length][message]` |
| VICE RR-Net with ip65 (Wizard of Wor) | UDP, like the Ultimate | one datagram = one message |

- A message is `[type][payload]`, at most **255 bytes**.
- 16-bit values are little-endian.
- **UDP:** the server answers to the sender's IP address and **source port**. The C64 Ultimate sends from a random port, which is fine.
- **Raw Ethernet:** the C64 broadcasts its first HELLO. The server answers from its own MAC (`pcapMac`), and from then on the C64 talks only to that MAC. The C64 accepts only frames sent from the server's MAC to its own MAC. Frames can carry padding, so a message's length comes from its length byte, not from the frame size.
- Packets can get lost (about 1% measured on UDP). **Whoever waits for an answer repeats its message until the answer comes.** Every message may arrive twice.
- No encryption, no accounts. LAN only.

Internally the server identifies a client by an `IPEndPoint`:

- UDP: the IPv4 address and port;
- TCP: the IPv4-mapped IPv6 address;
- raw Ethernet: an IPv6 link-local address (`fe80::`) made from the client's MAC (EUI-64).

## Message types

| Type | Name | Direction |
|---|---|---|
| `$01` | HELLO | C64 → server |
| `$02` | WELCOME | server → C64 |
| `$03` | REJECT | server → C64 |
| `$04` | LOBBY | server → C64 |
| `$05` | CHALLENGE | server → C64 |
| `$06` | ACCEPT | C64 → server |
| `$07` | DECLINE | C64 → server |
| `$08` | START | server → C64 |
| `$09` | START_ACK | C64 → server |
| `$0A` | OPPONENT_LEFT | server → C64 |
| `$0B` | SESSION_END | both |
| `$0C` | PING | both |
| `$0D` | PONG | both |
| `$0E` | BYE | C64 → server |
| `$0F` | CHALLENGE_CANCELLED | server → C64 |
| `$10` | PLAYERS | server → C64 |
| `$11` | INVITE | C64 → server |
| `$80-$FF` | game specific | both, only within a session |

Types `$00-$7F` belong to the platform and are the same for every game. The
server hands types `$80-$FF` to the game module of the sender's session.

**Rule for game messages:** byte 1 is always the **session id** from START.
The server drops a game message whose session id does not match the sender's
session. This way old packets never end up in a new session.

## Platform messages

### `$01` HELLO (C64 → server)

| Offset | Size | Contents |
|---|---|---|
| 0 | 1 | `$01` |
| 1 | 1 | protocol version (`$01`) |
| 2 | 1 | game id (Wizard of Wor `$01`, Bubble Bobble `$03`) |
| 3 | 1 | game version (`$01`) |
| 4 | 1 | nickname length (1-8) |
| 5 | n | nickname, ASCII `A-Z` and `0-9` (the C64 converts from PETSCII) |
| 5+n | 1 | optional: client kind, 0 = a person at a C64 (default), 1 = bot |

The kind shows in the player lists (PLAYERS) and on the dashboard. A C64 leaves the byte out.

Repeat it, for example every 0.5 s, until a WELCOME or REJECT comes.

Example, nickname `ERIK`, Wizard of Wor: `01 01 01 01 04 45 52 49 4B`

### `$02` WELCOME (server → C64)

| Offset | Size | Contents |
|---|---|---|
| 0 | 1 | `$02` |
| 1 | 1 | protocol version |
| 2 | 1 | client id (1-255) |

The player is now in the lobby of their game.

### `$03` REJECT (server → C64)

| Offset | Size | Contents |
|---|---|---|
| 0 | 1 | `$03` |
| 1 | 1 | reason: 1 = name in use, 2 = version mismatch, 3 = unknown game, 4 = server full, 5 = invalid name |

### `$04` LOBBY (server → C64)

| Offset | Size | Contents |
|---|---|---|
| 0 | 1 | `$04` |
| 1 | 1 | number of waiting players for this game, yourself included |

The server sends this to everyone in the lobby every 2 s, so the C64 knows the connection is alive.

### `$10` PLAYERS (server → C64)

The lobby list: all **other** players of the same game. The people come first, then the bots, each in order of arrival. At most 16.

| Offset | Size | Contents |
|---|---|---|
| 0 | 1 | `$10` |
| 1 | 1 | total number of players in the list |
| 2 | 1 | index of the first player in this message |
| 3 | 1 | number of players in this message (at most 6) |
| 4 | … | per player: client id (1), flags (1), nickname length (1), nickname (n) |

Flags:

- bit 0 = bot;
- bits 1-2 = status: `0` free, `2` busy (answering or waiting for a challenge), `4` playing.

A long list comes in pages of 6, because the C64 reads at most 128 bytes per packet.

The server sends the list to everyone who is not playing: shortly after each change (at most every 200 ms), and otherwise every second. Bots get no lists.

Example, 1 of 3 players, the bot `GARWOR`, playing: `10 03 00 01 04 05 06 47 41 52 57 4F 52`

### `$11` INVITE (C64 → server)

| Offset | Size | Contents |
|---|---|---|
| 0 | 1 | `$11` |
| 1 | 1 | client id of the chosen opponent (from PLAYERS) |
| 2 | 1 | sequence number: each new invitation gets a higher number |

- If the opponent is free, the server creates a challenge. The inviter has accepted it by inviting; only the opponent gets a CHALLENGE. The inviter gets player slot 0.
- If the opponent is not free (or unknown), the server answers with CHALLENGE_CANCELLED, challenge id 0, reason 4.
- Repeat INVITE, for example every 0.5 s, until START or CHALLENGE_CANCELLED comes. The server ignores repeats with the same sequence number.
- **Withdraw:** DECLINE with challenge id 0.

A bot accepts every challenge.

### `$05` CHALLENGE (server → C64)

| Offset | Size | Contents |
|---|---|---|
| 0 | 1 | `$05` |
| 1 | 1 | challenge id |
| 2 | 1 | length of the opponent's nickname |
| 3 | n | opponent's nickname (ASCII) |

- The server repeats this every 0.5 s until the C64 answers (ACCEPT or DECLINE), for at most 30 s.
- A repeated CHALLENGE with the same id: send your answer again.
- A challenge comes from another player's INVITE. With `autoPair` on, it can also come from the server itself, which then pairs waiting players.

### `$06` ACCEPT / `$07` DECLINE (C64 → server)

| Offset | Size | Contents |
|---|---|---|
| 0 | 1 | `$06` or `$07` |
| 1 | 1 | challenge id |

- The session starts only when **all** players have accepted.
- After a decline or a timeout, `autoPair` does not pair the same players again for 60 s. Inviting again works at once.
- DECLINE with challenge id 0 withdraws your own invitation.

### `$0F` CHALLENGE_CANCELLED (server → C64)

| Offset | Size | Contents |
|---|---|---|
| 0 | 1 | `$0F` |
| 1 | 1 | challenge id |
| 2 | 1 | reason: 1 = declined (or withdrawn), 2 = no answer within 30 s, 3 = a player left, 4 = not free (answer to INVITE, challenge id 0) |

The player is back in the lobby.

### `$08` START (server → C64)

| Offset | Size | Contents |
|---|---|---|
| 0 | 1 | `$08` |
| 1 | 1 | session id |
| 2 | 1 | your player slot (0, 1, …) |
| 3 | 1 | number of players |
| 4 | 1 | length of the start parameters (n) |
| 5 | n | the game's start parameters (see the game sections) |

The server repeats START every 0.25 s for at most 10 s. It stops when the C64 sends a START_ACK or its first game message.

### `$09` START_ACK (C64 → server)

| Offset | Size | Contents |
|---|---|---|
| 0 | 1 | `$09` |
| 1 | 1 | session id |

Send it for every START you receive, repeats included.

### `$0A` OPPONENT_LEFT (server → C64)

| Offset | Size | Contents |
|---|---|---|
| 0 | 1 | `$0A` |
| 1 | 1 | session id |

An opponent is gone: nothing was heard for 10 s, or the opponent sent BYE. The session is over and you are back in the lobby.

### `$0B` SESSION_END (both directions)

| Offset | Size | Contents |
|---|---|---|
| 0 | 1 | `$0B` |
| 1 | 1 | session id |
| 2 | 1 | reason: 1 = game over, 2 = desync, 3 = timeout, 4 = ended by the administrator, 5 = player quits |

- C64 → server: the game is over (reason 1), or the player quits (reason 5).
- Server → C64: the session is over. Reason 2 (desync) means the two games ran apart.

Afterwards all players are back in the lobby.

### `$0C` PING / `$0D` PONG (both directions)

| Offset | Size | Contents |
|---|---|---|
| 0 | 1 | `$0C` or `$0D` |
| 1 | 2 | token (returned unchanged) |

- Answer every PING with a PONG that has the same token.
- The server pings every 2 s and shows the round-trip time on the dashboard.
- A C64 with nothing to send (in the lobby) sends a PING every 2 s itself, as a keepalive.
- **Timeout:** a client the server has not heard from for 10 s is gone. A game module can allow longer, for example while a C64 loads the game.

### `$0E` BYE (C64 → server)

| Offset | Size | Contents |
|---|---|---|
| 0 | 1 | `$0E` |

The player leaves the server.

## Flow

```
C64 A                      server                      C64 B
HELLO  ------------------>
       <------------------ WELCOME
       <------------------ PLAYERS (empty)     <-------- HELLO
                           WELCOME --------------------->
       <------------------ PLAYERS (B)     PLAYERS (A) ---->
INVITE (B) -------------->
                           CHALLENGE (A) --------------->
                                           <------------ ACCEPT
       <------------------ START slot 0    START slot 1 --->
START_ACK --------------->                 <------------ START_ACK
INPUT  ------------------> INPUT ----------------------->
       <------------------ INPUT <---------------------- INPUT
...
SESSION_END (1) --------->                 <------------ SESSION_END (1)
       <------------------ LOBBY           LOBBY -------->
```

## The lockstep pattern (both games)

Both games use the same scheme. A new lockstep game should copy it, so the
server's checksum compare and the bots work without new code.

- At tick `t` a C64 reads its joystick and stores it as its input for tick
  `t + delay`. Then it sends an INPUT with its newest inputs.
- A tick runs only when the opponent's input for that tick is there. While
  waiting, the C64 repeats its last INPUT.
- Every INPUT repeats the last *window* inputs, so a lost packet is covered by
  the next one.
- Every 64 ticks the C64 puts a checksum of the game state at the start of
  that tick into its INPUT messages. The server compares the checksums of the
  two players for the same tick. If they differ, it sends SESSION_END with
  reason 2 (desync) to both.

```
INPUT: $80, session, newest tick (16), checksum tick (16, $FFFF = none), checksum (16), <window> inputs
```

## Game: Wizard of Wor (id `$01`, version `$01`, module `wizardofwor`)

### Start parameters (in START, 4 bytes)

| Offset | Contents |
|---|---|
| 0 | seed for `random_number` |
| 1 | seed for the LFSR `rnd_state` (never 0) |
| 2 | input delay in ticks: `inputDelay` (4), or `inputDelayWiC64` (8) when a WiC64 takes part |
| 3 | tick rate (60) |

Slot 0 controls player 1 (yellow, actor 1), slot 1 controls player 2 (blue, actor 0).

### `$80` INPUT, 24 bytes

| Offset | Size | Contents |
|---|---|---|
| 0 | 1 | `$80` |
| 1 | 1 | session id |
| 2 | 2 | newest tick in this packet |
| 4 | 2 | tick of the last checksum (`$FFFF` = none yet) |
| 6 | 2 | checksum |
| 8 | 16 | inputs of ticks newest−15 … newest (joystick format, active low) |

Waiting C64s repeat their last INPUT about every 20 ms. A WiC64 sends INPUT only every 4th tick
(each packet still carries 16 ticks) and repeats it about every 64 ms. Details:
[games/wizardofwor/docs/netcode.md](../games/wizardofwor/docs/netcode.md) (in Dutch).

## Game: Bubble Bobble (id `$03`, version `$01`, module `lockstep`, also called `bubblebobble`)

After START the C64 **loads the game file from disk**. A real 1541 needs about a
minute. Until a player's first INPUT the server waits up to
`loadTimeoutSeconds` (150) before it drops them.

### Start parameters (in START, 3 bytes)

| Offset | Contents |
|---|---|
| 0-1 | seed (16 bit, never 0) |
| 2 | input delay in ticks: `inputDelay` (2), or `inputDelayWiC64` (4) when a WiC64 takes part |

Slot 0 (the inviter) plays Bub (green), slot 1 plays Bob (blue). A tick is one
game pass: 25 ticks per second on PAL.

### `$80` INPUT, 16 bytes

| Offset | Size | Contents |
|---|---|---|
| 0 | 1 | `$80` |
| 1 | 1 | session id |
| 2 | 2 | newest tick in this packet |
| 4 | 2 | tick of the last checksum (`$FFFF` = none yet) |
| 6 | 2 | Fletcher-16 checksum |
| 8 | 8 | inputs of ticks newest−7 … newest |

Input byte:

- bits 0-4: joystick (active low, as `$DC00`);
- bit 5: `C=` (pause on both machines);
- bit 6: `Q` (quit on both machines).

A WiC64 sends only every other tick, because each transfer costs the C64 time.

Details: [games/bubblebobble/docs/TECHNICAL.md](../games/bubblebobble/docs/TECHNICAL.md).

## Game: The Way of the Exploding Fist (id `$04`, version `$01`, module `lockstep`)

The same messages and start parameters as Bubble Bobble: the game uses the framework's network code
([framework/c64/net/net.s](../framework/c64/net/net.s)), which Bubble Bobble's is a copy of. One tick
is one pass of the bout loop (about 46 per second). Slot 0 (the inviter) plays the white fighter,
slot 1 the red one. Input byte bit 6 (Q) ends the match for both. The default input delay is 3;
a WiC64 sends only every 4th tick, with an input delay of 4.

## Game: Relay demo (id `$02`, module `relay`)

No start parameters. The server forwards every game message unchanged to the
other players of the session. This is the configuration-only way to add a game
(see [adding-a-game.md](adding-a-game.md)).
