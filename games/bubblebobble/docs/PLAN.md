# BB-LAN — Bubble Bobble voor 2 spelers over het LAN

Plan om rebb64 (de gereconstrueerde C64-broncode van Bubble Bobble) om te bouwen naar een
2-spelergame. Elke speler heeft een eigen C64: VICE, een C64 met WiC64, of een C64 Ultimate / Ultimate 64.
Beide C64's worden via een gameserver op het LAN gekoppeld.

Bronnen:
- origineel: https://github.com/zaidka/rebb64 (commit c487b86, ca65-assembly, ~23.5k regels)
- tooling: `C:\Users\aegwh\OneDrive\dev\c64` (cc65 2.19 met ca65/ld65, VICE, KickAssembler, Node.js; Python 3.12 staat los op de machine)
- server en netcode om te hergebruiken: `C:\Users\aegwh\OneDrive\dev\WoW-LAN`
- doelrepo: https://github.com/mfidder2026/BB-Lan

---

## 1. Architectuur in één oogopslag

```
 C64 #1 (Bub)                     PC: C64GameServer (.NET 8)              C64 #2 (Bob)
 ┌──────────────────┐   UDP 6465   ┌─────────────────────────┐   UDP/TCP   ┌──────────────────┐
 │ Bubble Bobble     │◄───────────►│ lobby / challenge       │◄───────────►│ Bubble Bobble     │
 │ volledige sim     │             │ BubbleBobbleModule:     │             │ volledige sim     │
 │ lockstep per tick │             │  - seed + startparams   │             │ lockstep per tick │
 │ net-driver:       │             │  - INPUT relay          │             │ net-driver:       │
 │  UCI / RR-Net /   │             │  - checksum-vergelijk   │             │  UCI / RR-Net /   │
 │  WiC64            │             │  - timeouts, dashboard  │             │  WiC64            │
 └──────────────────┘             └─────────────────────────┘             └──────────────────┘
```

**Model: deterministische lockstep, net als bij WoW-LAN.**
- Beide C64's draaien de complete simulatie.
- Over het netwerk gaan alleen de joystick- en toetsbytes per tick, plus af en toe een checksum.
- De server is een relay met controles en is niet authoritative. De bestaande `C64GameServer` krijgt hiervoor een nieuwe game-module.
- Waarom geen state-sync: een C64 kan per frame geen 18 entities, bubbels en score versturen, en via WiC64 al helemaal niet.

**Tick = één pass van de hoofdloop (25 Hz).**
- Bubble Bobble draait zijn logica nu al op 25 Hz, dus één tick per 2 frames.
- Dat geeft 25 pakketjes per seconde per speler, de helft van WoW-LAN. Dat is gunstig voor WiC64.
- Input delay start op 2 ticks (80 ms) en wordt instelbaar via de server.

---

## 2. Belangrijkste bevindingen uit de analyse

### rebb64

| Onderwerp | Bevinding | Gevolg |
|---|---|---|
| Timing | Een deel van de game-logica (joystick plus player/entity-statemachine, `D_1CBD`) draait in een **raster-IRQ** (`irq-handlers.s:150`). Die loopt asynchroon met de 25 Hz-hoofdloop. | **Grootste klus.** Alle logica moet uit de IRQ naar een deterministische tick. |
| Timers | Seconde- en hurry-up-timers en de framecounter `$08` worden in de IRQ afgeteld en door gameplay gelezen. | Deze moeten tick-gebaseerd worden. |
| RNG | `prng_update` XOR't CIA1-timer `$DC06` in elk random getal (`sprite-composer.s:601`). De seed komt uit `$D012`/`$DC04`. | XOR verwijderen. De server levert de seed `$26/$27`. |
| Input | Eén centraal punt: `joystick-input.s:19-28` vult `D_85E8` (Bub) en `D_85E9` (Bob). Daarnaast lezen nog `$DC00`/`$DC01` rechtstreeks: join (`player-state.s:158`), pauze/quit (SPACE/RUN-STOP) en het titelscherm. | Alle reads omleiden naar gesynchroniseerde inputbytes. |
| 2 spelers | Bub en Bob tegelijk wordt al volledig ondersteund. Speler 2 kan op elk moment met fire joinen. | Er hoeft geen gameplay herschreven te worden. Alleen de input moet gemapt worden. |
| PAL/NTSC | Geen detectie. De timers gaan uit van 50 Hz. | Besluit: **alleen PAL tegen PAL.** Bij het opstarten wordt NTSC gedetecteerd en geweigerd. |
| Geheugen | RAM is vrijwel vol van `$0200` tot `$FFFA`. Ook de cassettebuffer is in gebruik, al zegt de documentatie anders. | Ruimte voor netcode moet worden vrijgemaakt (zie §4, fase 2). |
| I/O tijdens het spel | Geen disk of tape. I/O is normaal ingebankt (`$01=$35`). De level-renderer gebruikt tijdelijk `$01=$30`. | Netwerk-I/O mag niet tijdens de renderer gebeuren. |
| Build | Makefile met `python3`, ca65/ld65 en een SHA256-verify. Alle assets staan als TGA/tekst in de repo. | Er komt een `build.py` (geen `make` op deze machine), met behoud van de byte-identieke verify. |
| Licentie | Geen LICENSE. "Educational purposes", copyright Taito/Firebird. | Besluit: publiek project, net als upstream rebb64. Credits en upstream-vermelding in de README. |

### WoW-LAN

**Direct herbruikbaar:**
- de volledige C# gameserver: lobby, challenges, sessies, dashboard, bots en 32 unit tests
- de UCI-driver voor de Ultimate (`src/net/uci.asm`)
- de RR-Net/ip65-driver voor VICE (`ip65_glue.s`, `net_rrnet.asm`), met de ip65-buildpipeline
- de netio-laag, het lockstep-protocol (INPUT-pakket met een venster van 16 inputs, resend, checksum elke 64 ticks), keepalive tijdens overgangsschermen, config-bestand, CIA2-cyclecounter-pacing en PAL/NTSC-detectie
- de VICE-testtools (`vicemon.py`, de determinisme-test, de twee-VICE-netgametest)

**Niet aanwezig: WiC64-ondersteuning.** WoW-LAN heeft die expliciet buiten scope gehouden. Driver en servertransport moeten dus nieuw gebouwd worden.

**Toolchain-verschil.** WoW-LAN is in 64tass geschreven, rebb64 in ca65. **Keuze:** de net-code naar ca65 porten.
- Voordeel: één assembler.
- Voordeel: ip65 is al ca65, dus het kan direct mee-linken zonder blob-truc.
- Voordeel: de build is native Windows, zonder WSL.

---

## 3. Netwerk per platform

| Platform | Hardware/driver | Transport naar server | Status |
|---|---|---|---|
| VICE | RR-Net (CS8900a-emulatie) + ip65 | UDP 6465 | Port van WoW-LAN |
| C64 Ultimate / U64 | Ultimate Command Interface `$DF1C-$DF1F` | UDP 6465 (Ultimate kan niet listenen, vandaar de server) | Port van WoW-LAN |
| WiC64 | Userport (CIA2 port B + handshake via PA2/FLAG), firmware 2.x commando's | **TCP** (of UDP als de firmware dat goed ondersteunt, zie §6) | **Nieuw** |

**Server-uitbreiding voor WiC64:**
- een TCP-listener naast de UDP-socket, bijvoorbeeld op poort 6466
- framing `[len][bericht]` met exact dezelfde berichten als via UDP
- `TCP_NODELAY` aan
- intern wordt een TCP-client een gewone `Client` in `ServerCore`

Daardoor kan een WiC64-speler gewoon tegen een Ultimate- of VICE-speler spelen.

---

## Status (2026-10-08): alle fases uitgevoerd

| Fase | Status | Afwijkingen van het plan |
|---|---|---|
| 0 Basis | ✅ | `tools/build.py`, eigen packer |
| 1 Determinisme | ✅ | virtuele speltijd (`vframe`). Les: geen byte van het origineel mag verschuiven (zie `docs/TECHNICAL.md`) |
| 2 Geheugen | ✅ | gecomprimeerde levels geven ~1,3 KB. Eén gamebestand per netwerktype. Raw Ethernet voor RR-Net, in plaats van ip65 in het spel |
| 3 Netlaag | ✅ | Ultimate (UCI) en RR-Net, in ca65 |
| 4 Lockstep | ✅ | elke sessie start met een vers geladen spel, zodat beide C64's identiek beginnen |
| 5 Server | ✅ | Bubble Bobble-module, laadtijd-tolerantie, pcap-transport (VICE op dezelfde pc), TCP-transport (WiC64), 44 unit tests |
| 6 Lobby/UI | ✅ | aparte lobby-PRG in C (cc65), tekstmodus. `BBLAN.CFG`. AUTO-modus voor tests |
| 7 Tests/release | ✅ VICE | `tools/nettest.py`: complete sessies via RR-Net en WiC64-emulatie, checksums identiek. Release: `release/bblan.d64` |
| 8 WiC64 | ✅ VICE | firmware 2.x via TCP. Input delay 4 en om de tick zenden, omdat elke WiC64-overdracht C64-tijd kost |

**Nog te doen op echte hardware** (kon hier niet):
- C64 Ultimate / Ultimate 64: de UCI-code is nagekeken tegen de werkende WoW-LAN-driver, maar niet gedraaid.
- Een echte WiC64.

## 4. Fasering

### Fase 0 — Basis en baseline
- Repo opzetten:
  - rebb64 importeren met behoud van de upstream-historie, als git subtree of als eerste commit
  - de WoW-LAN-server als map `server/` kopiëren
- `tools/build.py` maken: dezelfde stappen als de Makefile, met ca65/ld65 uit `dev\c64\cc65` en `python`.
- `verify` moet groen zijn: dezelfde SHA256 als upstream.
- Een release-PRG met autostart maken. tscrunch komt later, of er komt een eenvoudige BASIC-SYS-loader.
- VICE-automatisering uit WoW-LAN overnemen (remote monitor, screenshots).
- **Klaar wanneer:** byte-identieke build plus een opstartbare PRG in VICE.

### Fase 1 — Deterministische tick (single machine, nog geen netwerk) ★ kritisch pad
1. Introduceer `tick_input[2]`: één byte per speler met joystick plus extra bits voor fire, pauze en quit.
2. Verplaats `D_1CBD` (joystick plus player/entity-statemachine) en alle timer-decrements uit de IRQ naar een vaste plek in de hoofdloop.
   - In de IRQ blijven alleen display (sprite-posities), sound en de framecounter voor wachtlussen over.
3. Vervang de gameplay-reads van `$08` door een tick-teller.
4. Laat de seconde-timers op ticks lopen: 25 ticks is 1 s.
5. `prng_update`: haal de XOR met `$DC06` weg. Zet de seed via `net_seed`.
6. Maak de overgangsschermen (level klaar, GET READY, game over, bonus, level 100) tick-gebaseerd, zodat beide machines exact gelijk weer instappen. Anders volgt WoW-LAN's keepalive-aanpak met een expliciete "ready"-sync per level.
7. Leid alle directe input-reads om naar `tick_input`:
   - join: `player-state.s:158`
   - pauze en quit: `D_7E80`/`D_7EC1`
   - Pauze wordt een gesynchroniseerde actie: wie pauzeert, pauzeert beide machines.
8. Pacing: alleen PAL. De tick loopt op de bestaande 2-frame-hoofdloop (25 Hz). Een NTSC-machine wordt bij het opstarten gedetecteerd (`detect_pal`) en geweigerd met een melding.
9. Determinisme-test met de tool `dettest.py`:
   - Speel een opgenomen inputreeks af op twee PAL-VICE-instanties.
   - Geef één van de twee een kunstmatige vertraging per tick, die netwerkwachttijd nabootst.
   - Vergelijk de checksums per tick.
- **Klaar wanneer:** 10+ levels met een opgenomen input geven identieke checksums, met en zonder vertraging.

#### Status fase 1 (2026-10-08)

**Gedaan**
- **Virtuele speltijd** (`src/bblan.s`):
  - De IRQ telt alleen nog echte frames.
  - Elke frame-wacht in het spel roept `vframe` aan. Die voert precies één logisch frame uit: timers, framecounter, en op oneven frames de oude IRQ-logica (`D_1805`, `D_1B40`, `D_1CBD`).
  - `vframe` wordt afgestemd op echte frames en mag tot 4 frames achterstand inhalen.
- **Tick = oneven logisch frame (25 Hz).**
  - `bb_sample` levert de input van beide spelers in `bb_in0`/`bb_in1`/`bb_key`.
  - Alle input-reads (speler, join, pauze/quit, titel, eindscherm) gaan daar doorheen.
- **PRNG:**
  - De CIA-timer zit er niet meer in.
  - De seed wordt bij de start van een spel gezet (`bb_game_start`), net als de frame- en tick-teller.
- **Geluid:** het starten van een liedje en `sound_init` vanuit de hoofdthread gebeuren met de IRQ uitgeschakeld.
- **Ruimte:** de build gebruikt gecomprimeerde levels. `build.py` kiest de verdeling tussen PRG_MID en I/O-shadow automatisch. Er is nu ~1070 bytes vrij in `BBLAN_CODE`.
- **Testtools:**
  - `tools/dettest.py`: PAL, PAL+jitter, NTSC en NTSC+jitter geven **identieke checksums** over 12.800 ticks (512 s speltijd). `--break` bewijst dat de test afwijkingen ziet.
  - `tools/soak.py`: crash/hang-detectie.
  - `tools/watch.py`, `tools/crashtrace.py` (VICE-breakpoints + CPU-historie) en `tools/startdiff.py`.

**Belangrijke les: geen enkele byte van het originele spel mag verschuiven.**
- Elke patch die code langer of korter maakte, verschoof de code erachter. Het spel liep dan vast rond level 9/13, met een band rommeltekens op het scherm.
  - Oorzaak: een entity kreeg een ongeldig type. De dispatch sprong daardoor naar willekeurige code en tekende over de zero page en de geluidsvariabelen heen.
  - Een build met de originele layout en dezelfde bot crashte niet.
- **Regel:**
  - Patches zijn even groot als de originele code (`BB_PATCH_END`-macro, opvullen met NOP's). Nieuwe code komt in `BBLAN_CODE`.
  - `build.py` controleert tegen `tools/original-layout.json` dat elk origineel segment op zijn plek staat.
  - De 23 bytes die de compressie in de renderer bespaart worden opgevuld.
- `ORIGLAYOUT=1` is een referentiebuild: het origineel met de bot, code byte voor byte op zijn plek.

**Open punt → oplossen in fase 4 (sessiestart)**
- Een potje dat start nadat de machine al eerder speelde, begint niet in exact dezelfde toestand als een vers potje. `PREGAME`-variant van dettest; `tools/startdiff.py` toont de verschillen: entity-tabellen, schermbuffers, geluidsstatus, enzovoort.
- Voor LAN-spel moeten beide machines identiek starten. Opties:
  - (a) bij de sessiestart de spelstatus van de host naar de joiner sturen;
  - (b) elke sessie vanaf een verse load starten: lobby-PRG → game laden;
  - (c) de minimale set te resetten variabelen bepalen met `startdiff`.
- Voorkeur: (a) of (b). Dat wordt bepaald in fase 4.
- Nog niet gedaan: NTSC-weigering (komt met de lobby in fase 6) en de gesynchroniseerde pauze over het netwerk (fase 4).

### Fase 2 — Geheugenbudget
Nodig is ongeveer 3.3 KB voor ip65 (alleen RR-Net), ongeveer 1 KB voor UCI, ongeveer 1 KB voor WiC64, 2–3 KB voor lockstep/protocol/lobby, en buffers (2×256 B input-ring + 128 B rx).

Opties, in volgorde van voorkeur:
1. `COMPRESS_LEVELS=1` maakt ~1.2 KB vrij in IO_SHADOW. Alleen geschikt voor buffers en data, niet voor I/O-code.
2. **Attract mode/demo verwijderen** (akkoord). Cheat code eventueel ook.
3. Pas als het nodig is: de titelmuziek of de eind-sequence. Daarvoor is eerst overleg nodig.
4. **Per platform een eigen build**: `bb-vice.prg`, `bb-u64.prg`, `bb-wic64.prg`. Dan hoeft maar één driver tegelijk in RAM.
   - Dit is de aanbevolen route.
   - Daarnaast blijft het mogelijk om met een kleine bootloader de juiste driver te laden en dan te detecteren, net als `netio_detect` in WoW-LAN.
5. Zeropage: `$02-$FF` is volledig in gebruik. Netcode krijgt een paar bytes door de opgeslagen ZP te swappen bij binnenkomst en vertrek, zoals `rr_enter/rr_leave`.
- **Klaar wanneer:** een memory-map-document met bewezen vrije ranges (`check-gaps.py` groen), en de game draait nog identiek.

### Fase 3 — Netlaag porten (VICE + Ultimate)
- `uci.asm`, `net_rrnet.asm` en de netio-laag van 64tass naar ca65 vertalen.
- ip65 direct linken in `c64-prg.cfg`.
- Netwerk-I/O alleen in de hoofdloop, buiten de level-renderer (`$01=$30`). Tijdens lange overgangen houdt een IRQ-keepalive de verbinding in leven, zoals `net_session_irq`.
- Een netwerktest-PRG bouwen: ping/pong naar de server en round-trip-meting op VICE en U64.

### Fase 4 — Lockstep-integratie
- `proto_tick` overnemen:
  - lokale input voor tick+delay versturen
  - wachten op de remote input
  - resend elke ~20 ms
  - border flash na 1 s, abort na 15 s
- Spelertoewijzing:
  - de speler die de challenge stuurt is Bub (slot 0, `D_85E8`)
  - de tegenspeler is Bob (slot 1, `D_85E9`)
  - op elke C64 bestuurt de lokale speler zijn eigen draak met de joystick in poort 2
- Start: de server stuurt START met seed, input delay en tickrate. Beide C64's starten direct een 2-spelergame met identieke beginstate.
  - **Fix van het bekende WoW-LAN-gat:** de C64 moet de input delay uit START ook echt gebruiken.
- Checksum elke 64 ticks over:
  - PRNG `$26/$27`, level `$10` en timers
  - entity-type/X/Y `$B2-$D1`, bubbels en scores/levens `$0400-$045B`
  - `$8480-$88FF`
  - geselecteerde sprite-padding-variabelen
- Bij een desync stuurt de server SESSION_END reason 2 en toont de C64 "DESYNC".
- Game over (beide spelers dood): beide machines gaan terug naar de lobby. Rematch via een challenge.
- Test: `netgame_test.py` met twee VICE-instanties via de server, met bot-scenario's voor packet loss, vertraging en afbreken.

### Fase 5 — Server
- `server.json`: game id 3 `bubblebobble`, 2 spelers, `inputDelay 2`, `tickRate 25`.
- `BubbleBobbleModule`:
  - afgeleid van `WizardOfWorModule`
  - seed-generatie en checksum-vergelijking
  - input-timeout, met een tolerantie voor de lange level-overgangen
- `C64Bot` uitbreiden met BB-INPUT, zodat je solo tegen een bot kunt testen. Die bot speelt niet slim maar stuurt alleen input.

### Fase 6 — Lobby, configuratie en UI
- Setup-menu vóór de game:
  - netwerkdetectie (DHCP of vast IP)
  - spelernaam
  - server-IP
- Opslaan:
  - in `BB.CFG` op disk 8, dat wordt geladen vóór het spel start (I/O tijdens het spel is niet nodig)
  - bij de Ultimate kan dit via de virtuele drive
- Lobbyscherm met spelerslijst, challenge/accept/decline en de foutmeldingen (DESYNC, TIMEOUT, OPPONENT LEFT). Het moet de Bubble Bobble-charset gebruiken, want de WoW-lobby gebruikt een 2×1-charset.
- In-game: kleine status-indicator bij een haperende verbinding (border flash zoals in WoW).

### Fase 7 — Hardware-tests en release (VICE + Ultimate)
Testmatrix: VICE↔VICE, VICE↔U64, U64↔U64 (allemaal PAL). WiC64 volgt in fase 8.

Meten:
- latency en packet loss
- het aantal ticks waarin gewacht moest worden
- desyncs over volledige runs van 100 levels, via bots die opgenomen input afspelen

Documentatie:
- installatie van de server
- VICE-ethernetinstellingen (Npcap, bekabeld)
- Ultimate-instellingen
- WiC64-firmware

### Fase 8 — WiC64-driver (geparkeerd: laatste fase)
- Server: TCP-transport erbij (zie §3), met unit tests in de bestaande testharness.
- Research eerst:
  - firmwareversie van de WiC64
  - beschikbare commando's in 2.x: TCP open/read/write, en of er een bruikbare UDP-variant is
  - meting van de latency per transactie
- Driver: userport-transfer met handshake. Geen conflict met de CIA2-timers die de pacing gebruikt (andere registers), maar wel controleren dat de game `$DD00` (VIC-bank) niet onbedoeld overschrijft. Read-modify-write op PA2 is nodig.
- Polling non-blocking maken: de netio-contract C=0 betekent "pakket klaar". Transfers zo kort mogelijk, ongeveer 26 bytes per tick.
- **Risico:** als een WiC64-transactie te veel tijd per tick kost, gaat de input delay voor WiC64-sessies omhoog (instelbaar per sessie) of komt er een WiC64-specifieke tickrate.

---

## 5. Risico's

| Risico | Impact | Mitigatie |
|---|---|---|
| IRQ-logica laat zich niet zuiver naar de hoofdloop verplaatsen (zelfmodificerende code, timing-afhankelijke effecten) | Hoog | Fase 1 eerst en volledig afronden met dettest, vóór er netwerkcode komt |
| Te weinig geheugen | Hoog | Per-platform-builds, levels comprimeren, attract en eind-sequence schrappen |
| CPU-budget: de hoofdloop overschrijdt al soms 2 frames | Middel | Dat is in lockstep geen desync, alleen vertraging. Wachttijd aftrekken van de tick, profileren zoals WoW-LAN's `profile` |
| WiC64-latency of geen bruikbare UDP | Middel | TCP met NODELAY via de server, hogere input delay voor WiC64-sessies |
| Ultimate-firmware-eigenaardigheden (willekeurige bronpoort, reads van max 512 B, geen listen) | Laag | Al opgelost in de WoW-LAN-driver |
| Licentie/copyright van de originele game | Juridisch | Bewust publiek, zoals upstream. Credits en disclaimer in de README |

## 6. Besluiten (2026-10-08)

1. Het project is publiek. De repo mfidder2026/BB-Lan is openbaar.
2. WiC64 is geparkeerd tot de laatste fase (fase 8).
3. De demo/attract mode mag eruit.
4. Alleen PAL tegen PAL.
5. Spelvorm: coöperatief, zoals het origineel.

## 7. Grove inschatting

| Fase | Omvang |
|---|---|
| 0 Baseline | klein |
| 1 Determinisme | **groot** (kritisch pad) |
| 2 Geheugen | middel |
| 3 Netlaag-port | middel |
| 4 Lockstep | middel |
| 5 Server | klein–middel |
| 6 Lobby/UI | middel |
| 7 Test/release | middel |
| 8 WiC64 | middel (plus hardware-afhankelijke research) |

Fase 3 en 5 kunnen parallel aan fase 1 lopen. WiC64 (fase 8) komt pas na een werkende release voor VICE en de Ultimate.
