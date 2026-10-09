# C64 Game Server (BB-LAN)

A server on the LAN that C64s connect to for two-player network games. In
BB-LAN it runs the lobby for **Bubble Bobble** (game id 3). It:

- pairs the players;
- relays their joystick inputs;
- compares the state checksums of the two C64s.

It is not authoritative: both C64s run the game in lockstep.

It started as the server of the WoW-LAN project (Wizard of Wor, game id 1) and can host both games at once.

> **LAN only.** There is no encryption, account or password. Never forward
> its ports to the internet.

## Running

```bash
dotnet run --project src/C64GameServer -c Release            # .NET 8 SDK
publish.bat                                                    # stand-alone builds: publish\win-x64, publish\linux-arm64
```

At the first start the server writes `server.json` with the defaults and prints the IP addresses the C64s can use.

- The dashboard is at `http://localhost:8080/`.
- Ctrl+C stops the server.
- `--list-interfaces` lists the network adapters for raw Ethernet (VICE RR-Net, see below).

## Transports

| C64 | Transport | Port |
|---|---|---|
| C64 Ultimate / Ultimate 64 | UDP | `gamePort` (6465) |
| WiC64 (firmware 2.x, real or VICE) | TCP, messages framed as `[length][message]` | `tcpPort` (6466) |
| VICE with RR-Net | raw Ethernet, EtherType `0x88B5`, via pcap (Npcap / libpcap) | `pcapInterface` |

The raw Ethernet transport exists because VICE's pcap networking usually cannot reach a UDP server on the same PC. With `pcapInterface` set to the adapter VICE uses, the server answers on that adapter with its own MAC address (`pcapMac`).

## Windows Firewall

Allow private networks when Windows asks, or add the rules yourself (as administrator):

```bash
netsh advfirewall firewall add rule name="C64 Game Server (UDP)" dir=in action=allow protocol=UDP localport=6465
```

```bash
netsh advfirewall firewall add rule name="C64 Game Server (TCP)" dir=in action=allow protocol=TCP localport=6466,8080
```

## Configuration

See the [BB-LAN manual](../docs/MANUAL.md#serverjson) for `server.json`.

Each game in the `games` list has a `module`:

| Module | Game |
|---|---|
| `bubblebobble` | BB-LAN |
| `wizardofwor` | WoW-LAN |
| `relay` | any other game: a transparent relay, no code needed |

## Tests

```bash
dotnet test tests/C64GameServer.Tests
```

The tests drive the core with a fake clock and a fake transport (lobby, invitations, sessions, timeouts, checksums, the Bubble Bobble module).

## Further documentation

These documents come from the WoW-LAN project and are in Dutch:

- [docs/protocol.md](docs/protocol.md): the message protocol.
- [docs/nieuwe-game-toevoegen.md](docs/nieuwe-game-toevoegen.md): adding a game.

The Bubble Bobble messages are described in [../docs/TECHNICAL.md](../docs/TECHNICAL.md).
