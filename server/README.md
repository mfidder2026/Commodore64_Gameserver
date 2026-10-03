# C64 Game Server

Een server in het LAN waar C64's verbinding mee maken om tegen elkaar te spelen. De eerste game is **Wizard of Wor** (2 spelers, lockstep). De server is nodig voor **C64 Ultimate ↔ C64 Ultimate**: de Ultimate-firmware kan niet luisteren, maar wel verbinden met een vast adres.

> ⚠️ **Alleen voor het LAN.** Er is geen encryptie, geen account en geen wachtwoord. Zet de server **nooit** open naar het internet (geen port forwarding op je router).

## Starten

1. Bouw de server (eenmalig), of gebruik de bestanden in `publish\`:

   ```bash
   publish.bat
   ```

   Dat levert op:
   - `publish\win-x64\C64GameServer.exe` en `C64Bot.exe` (Windows, zonder installatie);
   - `publish\linux-arm64\C64GameServer` en `C64Bot` (Raspberry Pi met 64-bit OS).

2. Start de server:

   ```bash
   publish\win-x64\C64GameServer.exe
   ```

   Bij de eerste start maakt hij `server.json` aan. Het venster toont de IP-adressen waarmee de C64's moeten verbinden.

3. Open het dashboard in een browser: `http://localhost:8080/`, of vanaf een andere computer `http://<ip-van-de-server>:8080/`.

4. Ctrl+C stopt de server.

### Windows Firewall

Windows vraagt bij de eerste start om toegang. Sta **privénetwerken** toe. Gebeurt dat niet, geef dan zelf toestemming (als administrator):

```bash
netsh advfirewall firewall add rule name="C64 Game Server (UDP)" dir=in action=allow protocol=UDP localport=6465
```

```bash
netsh advfirewall firewall add rule name="C64 Game Server (dashboard)" dir=in action=allow protocol=TCP localport=8080
```

### VICE en de server op dezelfde PC

VICE met RR-Net (Npcap) kan meestal **niet** praten met de PC waarop het zelf draait. Draai de server dan op een andere machine (bijvoorbeeld een Raspberry Pi), of laat de C64 tegen de bot spelen. Voor Ultimate ↔ VICE is de server niet nodig: dat werkt direct (in het C64-programma: VICE kiest HOST, de Ultimate JOIN).

## Configuratie (`server.json`)

| Instelling | Standaard | Betekenis |
|---|---|---|
| `gamePort` | 6465 | UDP-poort voor de C64's |
| `dashboardPort` | 8080 | HTTP-poort van het dashboard |
| `maxClients` | 32 | maximaal aantal verbonden C64's |
| `idleTimeoutSeconds` | 10 | een client waarvan niets komt, is weg |
| `challengeTimeoutSeconds` | 30 | tijd om een uitdaging te accepteren |
| `declineCooldownSeconds` | 60 | na een weigering worden dezelfde spelers zolang niet gekoppeld |
| `logFile` | `server.log` | gebeurtenissenlog |
| `games` | Wizard of Wor (1), Relay demo (2) | zie `docs/nieuwe-game-toevoegen.md` |

Instellingen van Wizard of Wor (`games[].settings`): `inputDelay` (4), `tickRate` (60) en `inputTimeoutSeconds` (10).

## Testen zonder C64: de bot

`C64Bot` gedraagt zich als een C64 die Wizard of Wor speelt:

```bash
publish\win-x64\C64Bot.exe --nick ANNA --ticks 3600
```

Twee bots in twee vensters vinden elkaar, accepteren en spelen. `--help` toont alle opties. De belangrijkste:

| Optie | Doel |
|---|---|
| `--server IP[:POORT]` | server elders in het LAN |
| `--read-delay 40` | traag lezen zoals de C64 Ultimate |
| `--loss 2` | 2% van de pakketten weggooien |
| `--bad-checksum-at 300` | de server moet een desync melden |
| `--quit-at 300` | wegvallen; de tegenstander moet OPPONENT_LEFT krijgen |
| `--decline` | elke uitdaging weigeren |
| `--no-checksum` | tegen een echte C64 spelen (de bot kent de echte spelstate niet) |

## Verbinden vanaf de C64

De C64 stuurt `HELLO` met zijn nickname naar `<ip-van-de-server>:6465` (UDP), wacht in de lobby, accepteert een uitdaging en speelt. Het protocol staat in [`docs/protocol.md`](docs/protocol.md).

## Ontwikkeling

```bash
dotnet test tests\C64GameServer.Tests
```

- `src/C64GameServer.Core`: protocol, kern (lobby, uitdagingen, sessies) en game-modules;
- `src/C64GameServer`: UDP, hoofdlus en dashboard;
- `src/C64Bot`: testclient;
- `tests/C64GameServer.Tests`: geautomatiseerde tests (nepklok en nep-transport).
