# C64 Game Server – protocol v1

Dit document is het contract tussen de server en de C64 (C64 Ultimate via UCI, VICE/RR-Net via ip65).

## Transport

- **UDP**, serverpoort **6465** (instelbaar in `server.json`).
- Eén datagram = één bericht: `[type][payload]`, maximaal **255 bytes**.
- Little-endian voor waarden van 16 bit.
- De server antwoordt naar het IP-adres en de **bronpoort** van de afzender. De C64 Ultimate verstuurt vanaf een willekeurige poort; dat is geen probleem.
- UDP kan pakketten verliezen (~1% gemeten). Regel: wie op een antwoord wacht, **herhaalt** zijn bericht tot het antwoord er is. Alle berichten mogen dubbel aankomen.
- Geen encryptie, geen accounts. Alleen voor het LAN.

## Typen

| Type | Naam | Richting |
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
| `$0B` | SESSION_END | beide |
| `$0C` | PING | beide |
| `$0D` | PONG | beide |
| `$0E` | BYE | C64 → server |
| `$0F` | CHALLENGE_CANCELLED | server → C64 |
| `$80-$FF` | game-specifiek | beide, alleen in een sessie |

Typen `$00-$7F` zijn van het platform en voor elke game gelijk. Typen `$80-$FF` geeft de server door aan de game-module van de sessie.

**Regel voor game-berichten:** byte 1 is altijd het **sessie-id** uit START. De server gooit een game-bericht weg als het sessie-id niet klopt met de sessie van de afzender. Zo komen oude pakketten nooit in een nieuwe sessie terecht.

## Platformberichten

### `$01` HELLO (C64 → server)

| Offset | Grootte | Inhoud |
|---|---|---|
| 0 | 1 | `$01` |
| 1 | 1 | protocolversie (`$01`) |
| 2 | 1 | game-id (Wizard of Wor: `$01`) |
| 3 | 1 | gameversie (Wizard of Wor: `$01`) |
| 4 | 1 | lengte nickname (1–8) |
| 5 | n | nickname, ASCII `A-Z` en `0-9` (de C64 zet om van PETSCII) |

Herhalen (bijvoorbeeld elke 0,5 s) tot er een WELCOME of REJECT komt.

Voorbeeld, nickname `ERIK`: `01 01 01 01 04 45 52 49 4B`

### `$02` WELCOME (server → C64)

| Offset | Grootte | Inhoud |
|---|---|---|
| 0 | 1 | `$02` |
| 1 | 1 | protocolversie |
| 2 | 1 | client-id (1–255) |

De speler staat nu in de lobby van zijn game.

Voorbeeld: `02 01 07`

### `$03` REJECT (server → C64)

| Offset | Grootte | Inhoud |
|---|---|---|
| 0 | 1 | `$03` |
| 1 | 1 | reden: 1 = naam al in gebruik, 2 = versie past niet, 3 = onbekende game, 4 = server vol, 5 = ongeldige naam |

### `$04` LOBBY (server → C64)

| Offset | Grootte | Inhoud |
|---|---|---|
| 0 | 1 | `$04` |
| 1 | 1 | aantal wachtende spelers voor deze game (inclusief jezelf) |

De server stuurt dit elke 2 s naar iedereen in de lobby. Zo weet de C64 dat de verbinding leeft.

### `$05` CHALLENGE (server → C64)

| Offset | Grootte | Inhoud |
|---|---|---|
| 0 | 1 | `$05` |
| 1 | 1 | uitdaging-id |
| 2 | 1 | lengte nickname tegenstander |
| 3 | n | nickname tegenstander (ASCII) |

De server herhaalt dit elke 0,5 s tot de C64 antwoordt (ACCEPT of DECLINE), maximaal 30 s. Een herhaalde CHALLENGE met hetzelfde id: stuur je antwoord opnieuw.

Voorbeeld, tegenstander `ANNA`: `05 03 04 41 4E 4E 41`

### `$06` ACCEPT / `$07` DECLINE (C64 → server)

| Offset | Grootte | Inhoud |
|---|---|---|
| 0 | 1 | `$06` of `$07` |
| 1 | 1 | uitdaging-id |

Pas als **alle** spelers geaccepteerd hebben, start de sessie. Na een weigering of time-out worden dezelfde spelers 60 s niet opnieuw aan elkaar gekoppeld.

### `$0F` CHALLENGE_CANCELLED (server → C64)

| Offset | Grootte | Inhoud |
|---|---|---|
| 0 | 1 | `$0F` |
| 1 | 1 | uitdaging-id |
| 2 | 1 | reden: 1 = geweigerd, 2 = geen antwoord binnen 30 s, 3 = een speler is weg |

De speler staat weer in de lobby.

### `$08` START (server → C64)

| Offset | Grootte | Inhoud |
|---|---|---|
| 0 | 1 | `$08` |
| 1 | 1 | sessie-id |
| 2 | 1 | jouw spelerslot (0, 1, …) |
| 3 | 1 | aantal spelers |
| 4 | 1 | lengte startparameters (n) |
| 5 | n | startparameters van de game (zie de game-module) |

De server herhaalt START elke 0,25 s tot de C64 een START_ACK stuurt (of zijn eerste game-bericht), maximaal 10 s.

### `$09` START_ACK (C64 → server)

| Offset | Grootte | Inhoud |
|---|---|---|
| 0 | 1 | `$09` |
| 1 | 1 | sessie-id |

Stuur dit bij elke START die je ontvangt, ook bij een herhaalde.

### `$0A` OPPONENT_LEFT (server → C64)

| Offset | Grootte | Inhoud |
|---|---|---|
| 0 | 1 | `$0A` |
| 1 | 1 | sessie-id |

Een tegenstander is weg (10 s niets ontvangen, of BYE). De sessie is voorbij, je staat weer in de lobby.

### `$0B` SESSION_END (beide richtingen)

| Offset | Grootte | Inhoud |
|---|---|---|
| 0 | 1 | `$0B` |
| 1 | 1 | sessie-id |
| 2 | 1 | reden: 1 = spel afgelopen, 2 = desync, 3 = time-out, 4 = beëindigd door de beheerder, 5 = speler stopt |

- C64 → server: het spel is afgelopen (game over, reden 1) of de speler stopt (reden 5).
- Server → C64: de sessie is voorbij. Bij reden 2 (desync) liepen de spellen uit elkaar.

Daarna staan alle spelers weer in de lobby.

### `$0C` PING / `$0D` PONG (beide richtingen)

| Offset | Grootte | Inhoud |
|---|---|---|
| 0 | 1 | `$0C` of `$0D` |
| 1 | 2 | token (wordt ongewijzigd teruggestuurd) |

- Beantwoord elke PING met een PONG met hetzelfde token.
- De server pingt elke 2 s en toont de round-trip tijd in het dashboard.
- Een C64 die niets te sturen heeft (in de lobby), stuurt zelf elke 2 s een PING, als keepalive.
- **Time-out:** een client waarvan de server 10 s niets hoort, is weg.

### `$0E` BYE (C64 → server)

| Offset | Grootte | Inhoud |
|---|---|---|
| 0 | 1 | `$0E` |

De speler verlaat de server.

## Game-module: Wizard of Wor (game-id `$01`, versie `$01`)

De lockstep draait op de C64's (zie `docs/fase2_determinisme.md` in het hoofdproject). De server geeft de inputs ongewijzigd door en controleert de checksums.

### Startparameters (in START, 4 bytes)

| Offset | Inhoud |
|---|---|
| 0 | seed voor `random_number` |
| 1 | seed voor de LFSR `rnd_state` (nooit 0) |
| 2 | input delay in ticks (standaard 4) |
| 3 | tick rate (60) |

Spelerslot 0 bestuurt speler 1 (geel, actor 1), slot 1 bestuurt speler 2 (blauw, actor 0).

### `$80` INPUT (C64 → server → tegenstander)

| Offset | Grootte | Inhoud |
|---|---|---|
| 0 | 1 | `$80` |
| 1 | 1 | sessie-id |
| 2 | 2 | nieuwste tick in dit pakket |
| 4 | 2 | tick van de laatste checksum (`$FFFF` = nog geen) |
| 6 | 2 | checksum |
| 8 | 16 | inputs van de ticks nieuwste−15 … nieuwste (joystickformaat, actief laag) |

Totaal 24 bytes.

- Een input voor tick t wordt bepaald bij tick t − input delay en meteen verstuurd. Elk pakket herhaalt de laatste 16 inputs, dus een verloren pakket wordt gedekt door het volgende.
- Wachtende C64's herhalen hun laatste INPUT ongeveer elke 20 ms.
- De C64 maakt elke 64 ticks een checksum van de spelstate aan het begin van die tick.
- **De server** stuurt INPUT ongewijzigd door naar de tegenstander. Hebben beide spelers een checksum voor dezelfde tick gestuurd en verschillen die, dan stuurt hij SESSION_END met reden 2 (desync) naar beiden.

## Verloop

```
C64 A                      server                      C64 B
HELLO  ------------------>
       <------------------ WELCOME
       <------------------ LOBBY (1)          <-------- HELLO
                           WELCOME --------------------->
       <------------------ CHALLENGE (B)   CHALLENGE (A) -->
ACCEPT ------------------>                 <------------ ACCEPT
       <------------------ START slot 0    START slot 1 --->
START_ACK --------------->                 <------------ START_ACK
INPUT  ------------------> INPUT ----------------------->
       <------------------ INPUT <---------------------- INPUT
...
SESSION_END (1) --------->                 <------------ SESSION_END (1)
       <------------------ LOBBY           LOBBY -------->
```
