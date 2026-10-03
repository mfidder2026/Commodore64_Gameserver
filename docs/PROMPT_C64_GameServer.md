# Prompt voor AI-developer: Commodore 64 Game Server (eerste game: Wizard of Wor)

> Kopieer alles onder de streep naar je AI-developer.

---

## Rol & doel

Je bent een ervaren backend-ontwikkelaar met kennis van netwerkcode voor games en van de beperkingen van 8-bit clients. Je bouwt de **Commodore 64 Game Server**: een server op **Windows** in het **LAN** waar C64's verbinding mee maken om tegen elkaar te spelen.

Aanleiding: twee C64 Ultimates kunnen niet rechtstreeks met elkaar communiceren. Ze kunnen wel allebei een **uitgaande TCP-verbinding** openen. De server zit er dus altijd tussen: beide spelers verbinden met de server en de server geeft de speldata door.

De server is een **platform voor meerdere games**. De eerste game is **Wizard of Wor** (2 spelers, deterministic lockstep). Latere games moeten toegevoegd kunnen worden zonder de kern aan te passen.

Buiten scope: de C64-code zelf. Jij levert de server, het protocol en een testclient voor de PC. Het protocoldocument is het contract voor de C64-ontwikkelaar.

## Harde randvoorwaarden

- **Geen HTTPS, TLS of andere encryptie**, nergens. De C64 kan dat niet aan. Ook geen HTTP, JSON of tekstprotocollen richting de C64: alleen een compact binair protocol over kale TCP.
- **Alleen LAN.** Geen accounts, geen wachtwoorden, geen internetfunctionaliteit. Vermeld in de README dat de server niet aan internet gehangen mag worden.
- **De clients zijn traag en klein.** Bekend van de C64 Ultimate (UCI-netwerkinterface):
  - een read zonder data kost ~42-45 ms, een read met data 4-21 ms, een write 3-7 ms;
  - de client leest nooit meer dan 512 bytes per keer;
  - de client pollt asynchroon en reageert dus niet direct.
  
  Gevolgen voor de server: berichten klein houden (maximaal 255 bytes), data bundelen in plaats van veel losse berichtjes sturen, **`TCP_NODELAY` aan**, ruime timeouts, en partial reads correct afhandelen (TCP is een stream).
- De tweede client is **VICE met RR-Net en de ip65-stack**: één TCP-verbinding tegelijk en kleine buffers.
- De server mag nooit crashen op ongeldige of onvolledige data van een client. Valideer lengte en type, en verbreek bij onzin alleen die ene verbinding.

## Technische keuzes (wijk alleen af met onderbouwing)

- **C# / .NET 8**, opgeleverd als één self-contained `.exe` voor Windows, zonder installatie van extra software.
- **Spelpoort:** TCP 6464 (instelbaar).
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

1. De speler voert op de C64 zijn **nickname** en het IP-adres van de server in, en verbindt.
2. De C64 stuurt `HELLO` (protocolversie, `game_id`, gameversie, nickname). De server antwoordt met `WELCOME` of met `REJECT` plus een reden (naam al in gebruik, versie past niet, onbekende game, server vol).
3. De speler **staat klaar** in de lobby van die game.
4. Staat er een tweede speler klaar voor dezelfde game, dan stuurt de server beiden een `CHALLENGE` met de nickname van de tegenstander.
5. **Beide** spelers moeten `ACCEPT` sturen. Weigert er één (`DECLINE`) of reageert hij niet binnen 30 seconden, dan gaan beiden terug naar de lobby. Voorkom dat dezelfde twee spelers na een weigering direct opnieuw aan elkaar gekoppeld worden.
6. Hebben beiden geaccepteerd, dan maakt de server een **sessie** en stuurt beiden `START` (spelersslot plus de startparameters van de game-module). Het spel begint.
7. Na afloop, of als een speler wegvalt (`OPPONENT_LEFT`), gaat de overgebleven speler terug naar de lobby.

## Protocol

Binair, little-endian, length-prefixed: `[len][type][payload]`.

- Types `$00-$7F` zijn van het **platform** en voor elke game gelijk: `HELLO`, `WELCOME`, `REJECT`, `CHALLENGE`, `ACCEPT`, `DECLINE`, `START`, `OPPONENT_LEFT`, `SESSION_END`, `PING`, `PONG`, `BYE`.
- Types `$80-$FF` zijn **game-specifiek**. De kern geeft ze door aan de game-module van de sessie en kijkt er zelf niet in.
- Nickname: maximaal 8 tekens, alleen `A-Z` en `0-9` in ASCII. De C64 zet zelf om van en naar PETSCII.
- Controleer de protocolversie bij `HELLO`.

Werk dit uit in `docs/protocol.md`, met per bericht de exacte bytes en een voorbeeld in hex. Dit document is leidend voor de C64-kant.

## Game-module 1: Wizard of Wor

Wizard of Wor draait op beide C64's dezelfde simulatie (deterministic lockstep). Over de lijn gaan alleen joystick-inputs. De **server is de lockstep-coördinator**, zodat beide C64's exact dezelfde clientcode draaien en er geen host/client-rol meer is.

- `START` bevat: seed (16 bit), startdungeon, tick rate, input delay en het aantal ticks per pakket. Deze waarden komen uit `server.json` en zijn in het dashboard te zien.
- Elke C64 stuurt `INPUT(tick, n, joy*n)`. Zodra de server voor een tick de input van beide spelers heeft, stuurt hij `TICKS(tick, n, {joyP1, joyP2}*n)` naar beiden.
- Beide C64's sturen periodiek `CHECKSUM(tick, sum16)`. De server vergelijkt ze. Bij een verschil stuurt hij `DESYNC` naar beiden, logt hij het en eindigt de sessie.
- `PAUSE` en `RESUME` gaan door naar de andere speler.
- Blijft de input van een speler 10 seconden uit, dan eindigt de sessie.

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

- Twee bots vinden elkaar, accepteren en spelen 30 minuten een gesimuleerde Wizard of Wor-sessie zonder fouten. Alles is live te volgen in het dashboard.
- Meerdere sessies draaien tegelijk zonder elkaar te beïnvloeden.
- Uitval van een speler, een weigering, een timeout en ongeldige data worden netjes afgehandeld en gelogd. De server blijft draaien.
- Een tweede game met transparante relay is toe te voegen met alleen een registratie. Toon dit aan met een voorbeeldgame.
- Er zit nergens encryptie in, en de C64 hoeft alleen één TCP-verbinding te openen.

Begin met **Fase 1**. Lever eerst een kort plan op met de projectstructuur, de `IGameModule`-interface en een eerste versie van `docs/protocol.md`, en wacht op akkoord voordat je gaat bouwen.
