# Prompt voor AI-developer: Commodore 64 Game Server (eerste game: Wizard of Wor)

> Kopieer alles onder de streep naar je AI-developer.
>
> **Bijgewerkt 2026-10-03** na het onderzoek in `docs/gameserver_onderzoek.md`:
> - UDP als speltransport;
> - de server is relay plus controle, niet de lockstep-coördinator;
> - gemeten waarden in plaats van de waarden uit de SDK;
> - de server draait ook op Linux/Raspberry Pi;
> - de spelpoort is 6465.
>
> De implementatie staat in `server/`.

---

## Rol & doel

Je bent een ervaren backend-ontwikkelaar met kennis van netwerkcode voor games en van de beperkingen van 8-bit clients. Je bouwt de **Commodore 64 Game Server**: een server op **Windows** in het **LAN** waar C64's verbinding mee maken om tegen elkaar te spelen.

Aanleiding: twee C64 Ultimates kunnen niet rechtstreeks met elkaar communiceren. De firmware kan niet luisteren en geen vaste lokale poort openen. Ze kunnen wel allebei **uitgaand** verbinden met een vast adres en een vaste poort (UDP en TCP). De server zit er dus altijd tussen: beide spelers verbinden met de server en de server geeft de speldata door.

Ultimate ↔ VICE en VICE ↔ VICE werken ook zonder server (direct via UDP). De server is nodig voor Ultimate ↔ Ultimate, en biedt een lobby.

De server is een **platform voor meerdere games**. De eerste game is **Wizard of Wor** (2 spelers, deterministic lockstep). Latere games moeten toegevoegd kunnen worden zonder de kern aan te passen.

Buiten scope: de C64-code zelf. Jij levert de server, het protocol en een testclient voor de PC. Het protocoldocument is het contract voor de C64-ontwikkelaar.

## Harde randvoorwaarden

- **Geen HTTPS, TLS of andere encryptie**, nergens. De C64 kan dat niet aan. Ook geen HTTP, JSON of tekstprotocollen richting de C64: alleen een compact binair protocol over **UDP**.
- **Alleen LAN.** Geen accounts, geen wachtwoorden, geen internetfunctionaliteit. Vermeld in de README dat de server niet aan internet gehangen mag worden.
- **De clients zijn traag en klein.** Gemeten op een C64 Ultimate (UCI-netwerkinterface, firmwarebron gecontroleerd):
  - een read komt terug zodra er data is (1–17 ms), anders na de time-out van 40 ms; dat is wachttijd, geen CPU-tijd;
  - een write duurt ~1,7 ms;
  - RTT naar een PC is minimaal 8 ms, met uitschieters tot 2 s over WiFi; pakketverlies ~1%;
  - de client leest nooit meer dan 512 bytes per keer en pollt asynchroon.

  Gevolgen voor de server: berichten klein houden (maximaal 255 bytes), ruime timeouts, en verloren pakketten opvangen door te herhalen tot er een antwoord komt.
- **Waarom UDP en geen TCP:** de Ultimate zet geen `TCP_NODELAY` op zijn eigen sockets (Nagle plus delayed ACK geeft haperingen tot 200 ms), en ip65 (VICE/RR-Net) wacht bij TCP op de ACK van elk pakket en blokkeert de C64 zolang. UDP werkt op beide zonder die problemen.
- **UDP-afhandeling:** de server leert per client het IP-adres en de bronpoort uit de pakketten, en antwoordt daarheen. De Ultimate verstuurt vanaf een willekeurige poort.
- De tweede client is **VICE met RR-Net en de ip65-stack**.
- De server mag nooit crashen op ongeldige of onvolledige data van een client. Valideer lengte en type, en verbreek bij onzin alleen die ene verbinding.

## Technische keuzes (wijk alleen af met onderbouwing)

- **C# / .NET 8**, opgeleverd als één self-contained `.exe` voor Windows, zonder installatie van extra software. Ook te publiceren voor `linux-arm64` (Raspberry Pi), zodat de server op een andere machine dan VICE kan draaien.
- **Spelpoort:** UDP 6465 (instelbaar). 6464 blijft vrij voor direct spelen zonder server.
- **Serverinterface:** een ingebouwd webdashboard over gewoon **HTTP** op poort 8080 (instelbaar), te openen in een browser op de server of elders in het LAN. Live bijwerken via Server-Sent Events of een onversleutelde WebSocket.
- Configuratie in één leesbaar bestand (`server.json`): poorten, timeouts en instellingen per game.
- Geen database. De status staat in het geheugen, het log gaat naar een bestand.

## Architectuur

Drie lagen, strikt gescheiden:

1. **Kern (game-onafhankelijk):** verbindingen, het frame-formaat, nicknames, de lobby, het koppelen van spelers, sessies, keepalive, timeouts en logging.
2. **Game-modules:** per game één module achter een vaste interface (bijvoorbeeld `IGameModule`), geregistreerd met een `game_id`. Een module bepaalt het minimum en maximum aantal spelers, de startparameters en wat er met speldata gebeurt. Twee smaken:
   - **transparante relay** (standaard): de server stuurt speldata van de ene speler ongewijzigd door naar de andere(n). Een nieuwe game die hieraan genoeg heeft, vraagt alleen een registratie en geen code;
   - **serverlogica:** de module leest de speldata en stuurt zelf berichten. Wizard of Wor gebruikt dit.
3. **Dashboard:** leest de status van de kern en de modules en toont die. Het dashboard bevat geen spellogica.

Ontwerp sessies voor N spelers, ook al heeft Wizard of Wor er twee.

## Verloop voor de speler

1. De speler voert op de C64 zijn **nickname** en het IP-adres van de server in, en verbindt. De C64 herhaalt `HELLO` tot er een antwoord komt.
2. De C64 stuurt `HELLO` (protocolversie, `game_id`, gameversie, nickname). De server antwoordt met `WELCOME` of met `REJECT` plus een reden (naam al in gebruik, versie past niet, onbekende game, server vol).
3. De speler **staat klaar** in de lobby van die game.
4. Staat er een tweede speler klaar voor dezelfde game, dan stuurt de server beiden een `CHALLENGE` met de nickname van de tegenstander.
5. **Beide** spelers moeten `ACCEPT` sturen. Weigert er één (`DECLINE`) of reageert hij niet binnen 30 seconden, dan gaan beiden terug naar de lobby. Voorkom dat dezelfde twee spelers na een weigering direct opnieuw aan elkaar gekoppeld worden.
6. Hebben beiden geaccepteerd, dan maakt de server een **sessie** en stuurt beiden `START` (spelersslot plus de startparameters van de game-module). Het spel begint.
7. Na afloop, of als een speler wegvalt (`OPPONENT_LEFT`), gaat de overgebleven speler terug naar de lobby.

## Protocol

Binair en little-endian. Eén UDP-datagram is één bericht: `[type][payload]`, met maximaal 255 bytes.

- Types `$00-$7F` zijn van het **platform** en voor elke game gelijk: `HELLO`, `WELCOME`, `REJECT`, `CHALLENGE`, `ACCEPT`, `DECLINE`, `START`, `OPPONENT_LEFT`, `SESSION_END`, `PING`, `PONG`, `BYE`.
- Types `$80-$FF` zijn **game-specifiek**. De kern geeft ze door aan de game-module van de sessie en kijkt er zelf niet in.
- Nickname: maximaal 8 tekens, alleen `A-Z` en `0-9` in ASCII. De C64 zet zelf om van en naar PETSCII.
- Controleer de protocolversie bij `HELLO`.

Werk dit uit in `docs/protocol.md`, met per bericht de exacte bytes en een voorbeeld in hex. Dit document is leidend voor de C64-kant.

## Game-module 1: Wizard of Wor

Wizard of Wor draait op beide C64's dezelfde simulatie (deterministic lockstep, al gebouwd en getest). Over de lijn gaan alleen joystick-inputs. De lockstep zit op de C64; de server is een **relay met controle**. Beide C64's draaien dezelfde clientcode, zonder host/client-rol: de server wijst de spelerslots toe.

- `START` bevat: spelerslot, seed voor `random_number`, seed voor de LFSR en de input delay. Deze waarden komen uit `server.json` (seeds: willekeurig per sessie) en zijn in het dashboard te zien.
- Elke C64 stuurt `INPUT`: sessie-id, nieuwste tick, checksumtick, checksum en de inputs van de laatste 16 ticks. De server stuurt het ongewijzigd door naar de tegenstander.
- De server leest de checksumvelden mee. Hebben beide spelers een checksum voor dezelfde tick gestuurd en verschillen die, dan stuurt hij `SESSION_END` (reden desync) naar beiden, logt hij het en eindigt de sessie.
- Pauze is niet nodig: in lockstep wacht de ander vanzelf.
- Blijft de input van een speler 10 seconden uit, dan krijgt de ander `OPPONENT_LEFT` en eindigt de sessie.

## Serverinterface (dashboard)

Eén overzichtelijke pagina waarop je live ziet wat er gebeurt:

- **Serverstatus:** het IP-adres en de poort waarmee de C64's moeten verbinden (groot in beeld), uptime, aantal spelers en sessies.
- **Spelers:** nickname, IP-adres, game, status (lobby, uitgedaagd, in spel) en ping.
- **Sessies:** game, spelers, speelduur, huidige tick, verkeer (berichten en bytes per seconde) en de status van de checksums.
- **Gebeurtenissenlog:** verbinden, verbreken, uitdagingen, accepteren en weigeren, start en einde van sessies, desyncs en fouten. Met tijdstip, en te filteren op speler of sessie.
- **Beheer:** een speler verwijderen en een sessie beëindigen.
- Optioneel per sessie een **hex-weergave** van de laatste berichten. Dat is erg nuttig bij het debuggen van de C64-code.

Game-modules leveren hun eigen statusvelden aan, zodat een nieuwe game zonder aanpassing van het dashboard zichtbaar wordt.

## Testclient

Bouw een **console-testclient ("bot")** voor de PC die zich gedraagt als een C64: verbinden, nickname opgeven, uitdaging accepteren en Wizard of Wor-inputs en checksums sturen. Geef hem opties om traagheid na te bootsen (vertraging per read, zoals de UCI) en om fouten te maken (verkeerde checksum, verbinding verbreken, ongeldige data).

Hiermee is de server volledig te testen zonder C64, en kan één echte C64 tegen een bot spelen. Let op: VICE met RR-Net kan via pcap meestal **niet** praten met de PC waar het zelf op draait. Draai de server tijdens tests met VICE dus op een andere machine, en beschrijf dit in de README.

## Fasering (lever per fase op en wacht op akkoord)

- **Fase 1 – Kern:** verbindingen, protocol, lobby, uitdagen en accepteren, sessies met transparante relay, logging naar bestand, `docs/protocol.md` en de testclient.
- **Fase 2 – Dashboard:** de serverinterface met live status, log en beheer.
- **Fase 3 – Wizard of Wor-module:** lockstep-coördinatie, checksums en afhandeling van pauze, desync en uitval. Getest met twee bots.
- **Fase 4 – Echte clients:** testen met de C64 Ultimate en VICE, en timeouts en bundeling afstemmen op de gemeten vertragingen.

## Oplevering

- Broncode met een buildscript dat één `.exe` oplevert.
- `README.md`: starten, configureren, de Windows Firewall openzetten voor beide poorten, en verbinden vanaf de C64.
- `docs/protocol.md` en `docs/nieuwe-game-toevoegen.md` (stappenplan met een voorbeeldmodule).
- Geautomatiseerde tests voor het frame-formaat, de lobby en de Wizard of Wor-module.

## Acceptatiecriteria

- Twee bots vinden elkaar, accepteren en spelen 30 minuten een gesimuleerde Wizard of Wor-sessie zonder fouten (lockstep en checksums kloppen). Alles is live te volgen in het dashboard.
- Meerdere sessies draaien tegelijk zonder elkaar te beïnvloeden.
- Uitval van een speler, een weigering, een timeout en ongeldige data worden netjes afgehandeld en gelogd. De server blijft draaien.
- Een tweede game met transparante relay is toe te voegen met alleen een registratie. Toon dit aan met een voorbeeldgame.
- Er zit nergens encryptie in, en de C64 hoeft alleen één UDP-socket naar de server te openen.

Begin met **Fase 1**. Lever eerst een kort plan op met de projectstructuur, de `IGameModule`-interface en een eerste versie van `docs/protocol.md`, en wacht op akkoord voordat je gaat bouwen.
