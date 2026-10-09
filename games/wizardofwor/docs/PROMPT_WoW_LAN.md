# Prompt voor AI-developer: Wizard of Wor – 2-speler netwerkversie (Commodore 64 Ultimate)

> Kopieer alles onder de streep naar je AI-developer. De prompt bevat alle context uit het vooronderzoek.

---

## Rol & doel

Je bent een ervaren 6502/C64-assemblyontwikkelaar met kennis van netwerkcode voor games (deterministic lockstep). Je bouwt een **netwerkversie van Wizard of Wor (C64, 1983)**: twee spelers spelen **tegelijk op twee aparte C64's** die rechtstreeks via het LAN verbonden zijn, **zonder server of relay**.

Ondersteunde netwerkhardware:
1. **Commodore 64 Ultimate** (primair doelplatform) via het **Ultimate Command Interface (UCI)**. Dezelfde UCI zit in de Ultimate 64 en de 1541 Ultimate-II+, dus die werken waarschijnlijk ook, maar dat is geen eis.
2. **RR-Net (CS8900a)**, met name **zoals geëmuleerd in VICE**. Dit is nodig omdat de ontwikkelaar maar **één** C64 Ultimate heeft: de tweede speler draait in VICE op de PC. RR-Net op echte hardware (bijvoorbeeld een RR-Net-cartridge of een 64NIC+) is mooi meegenomen, maar geen eis.

De belangrijkste testopstelling is dus **C64 Ultimate ↔ VICE (RR-Net)** op hetzelfde LAN. WiC64 en andere hardware vallen buiten scope.

Uitgangspunt is de gedisassembleerde en uitgebreid becommentarieerde broncode: https://github.com/dabadab/wizardofwor (assembleert met **64tass**: `64tass -a wizard_of_wor.asm -b -o wow.bin`).

Het spel moet zo dicht mogelijk bij het origineel blijven (gameplay, graphics, geluid, snelheid). Daarnaast moet de bestaande lokale modus (1 of 2 spelers op één C64) blijven werken.

## Wat al bekend is over de originele code

- **Bestanden:** `wizard_of_wor.asm` (~6800 regels) plus `inc.sprites_*.asm`. Geen originele broncode maar een disassembly; labels en commentaar zijn van de reverse engineer.
- **Formaat:** 16K cartridge op `$8000-$BFFF` (CBM80-header, bootvector `start`). Sprites en charset worden bij het opstarten naar RAM gekopieerd. Het scherm staat op `$0400`, VIC-bank 0. De NMI-handler wordt naar `$1F47` gekopieerd. De IRQ loopt via `$0314` (de KERNAL blijft dus ingeschakeld).
- **Zero page `$02-$E9` en page 2 `$0200-$0271`** worden door het spel gebruikt (zie de variabelensectie rond regel 360-540).
- **Alleen NTSC:** de code gaat uit van 60 frames per seconde. Op PAL lopen spelers en muziek langzamer, maar monsters niet.
- **Spelstructuur:**
  - De **raster-IRQ** (`irq_handler`, ~regel 3161) doet niet alleen geluid, maar ook **spellogica**:
    - `DEC random_number` (de "random generator" is een framecounter);
    - de animatie- en bewegingstimers van de spelers (`animation_timer_tbl`, `+1`) en `bullet_move_counter`;
    - de onzichtbaarheidstimers van garwors/thorwors (`one_second_wait_tbl`, `time_to_invis_counter`, `actor_speed_tbl`). Deze timers schrijven ook direct naar `VIC_D015` en lezen `VIC_D027`;
    - `irq_timer_frame`: de launch-countdown uit de cage (`launch_counters`, roept `move_actor.start_launch` aan);
    - `irq_timer_sec`: het openen van de warp doors (`open_warp_door`) en `music_speed`;
    - daarnaast `sfx.play` en `jingles.play`.
  - De **busy loop** heeft drie varianten: `normal_gameplay_loop`, de Worluk-loop en de Wizard-loop. Die lopen per actor zo snel als de CPU toelaat en zijn **niet aan frames gekoppeld**. De monstersnelheid hangt daardoor af van de looptijd van de loop. De animatietimer van monsters wordt in de loop verlaagd (~regel 939).
  - `irq_timer_frame` wordt ook in de loop gebruikt als random waarde ("monster turns towards a random player", ~regel 1020).
  - `SID_Osc` (`$D41B`) wordt als random waarde gebruikt in de SFX-code (~regel 3974). Verifieer dat dit alleen het geluid beïnvloedt.
  - **Collision detection** werkt via karakters en coördinaten (`check_actor_collision`), niet via de VIC-hardwarecollisieregisters. Dat is gunstig voor determinisme.
- **Invoer:** `read_joy_direction` (~regel 2962) leest `CIA1_JOY_KEY1,X` (`$DC00/$DC01`). Joystick en vuurknop worden ook direct gelezen rond de regels 1801, 2084, 5216-5243 (pauze) en 5531 (titelscherm). Het toetsenbord wordt gebruikt voor pauze en de easter egg.
- **Magic Voice:** ondersteuning voor de spraakcartridge (`MV_*`, `$C003-$C018`). **Schakel dit uit** (`is_MV_missing = 1`) en laat de code weg.

## Wat bekend is over het Ultimate Command Interface (UCI)

- **Bronnen:**
  - officiële documentatie: https://1541u-documentation.readthedocs.io/ (sectie "Command Interface" / UCI);
  - praktische, op hardware gemeten SDK met ASM/C-bindings: https://github.com/barryw/ultimate-uci-sdk (zie `docs/uci.md` en `src/uci/net.s`). Gebruik deze als referentie, of port of include de relevante delen naar 64tass (let op de licentie).
- De UCI moet in het Ultimate-menu worden ingeschakeld ("Command Interface: Enabled"). Detecteer de UCI via `$DF1D == $C9`. Is die waarde er niet, toon dan een duidelijke melding.
- De registers staan op `$DF1C-$DF1F`: `$DF1C` W=control / R=status, `$DF1D` W=command data / R=ID, `$DF1E` response data, `$DF1F` status data.
- Control-bits: `PUSH_CMD=1`, `DATA_ACC=2`, `ABORT=4`. Status-bits: `CMD_BUSY=1`, `DATA_ACC=2`, `ABORT_P=4`, `ERROR=8`, `STAT_AV=$40`, `DATA_AV=$80`. **Doe nooit read-modify-write op `$DF1C`** (een read geeft het statusregister terug).
- Command-flow:
  1. command bytes naar `$DF1D` schrijven;
  2. `PUSH_CMD` geven;
  3. wachten tot de state niet meer busy is;
  4. `DATA_AV` en `STAT_AV` uitlezen;
  5. `DATA_ACC` geven.
- Network target `$03`:
  - `GET_IPADDR $05`, `OPEN_TCP $07 <port16><host>`, `OPEN_UDP $08 <port16><host>`, `CLOSE_SOCKET $09 <handle>`, `READ_SOCKET $10 <handle><len16>`, `WRITE_SOCKET $11 <handle><data>`;
  - de TCP-listener: `LISTEN_START $12 <port16>`, `LISTEN_STOP $13`, `LISTEN_STATE $14`, `LISTEN_SOCKET $15`. **Deze vier staan niet in de officiële spec** (afgeleid uit de firmware en `ultimateii-dos-lib`). Verifieer ze in fase 0 op de C64 Ultimate-firmware.
- Gemeten op een U64 Elite met firmware 3.15 (bron: ultimate-uci-sdk):
  - een read zonder data duurt **~42-45 ms**;
  - een read met data 4-21 ms;
  - een write 3-7 ms;
  - een connect naar een host die bereikbaar is 48-75 ms, naar een adres waar niets op draait **~30 s**.
  - Een read antwoordt met `<count16 LE><bytes>`; `$FFFF` betekent dat er niets is. De device code `02` betekent geen data, `01` betekent dat de verbinding gesloten is. Na `01` is de handle al vrijgegeven, dus **niet meer sluiten**.
  - **Vraag nooit meer dan 512 bytes per read op.** Een length tussen 769 en 1023 kan de Ultimate laten vastlopen tot een power cycle nodig is.
- **Consequentie:** synchroon pollen per frame is niet haalbaar (42 ms is meer dan 2 frames). De UCI-driver moet **asynchroon** werken, als state machine: een command pushen, terugkeren naar het spel en status en data in een volgende frame/tick ophalen. Meet in fase 0 of de 42 ms busy-tijd van de Ultimate is (dan kan de C64 intussen doorrekenen) of echte CPU-tijd. Meet ook of UDP sneller reageert dan TCP.

## Wat bekend is over RR-Net in VICE

- VICE (`x64sc`, 3.9+) emuleert een **ethernetcartridge met de CS8900a** in de modi TFE en **RR-Net**, op I/O1 rond `$DE00`. Stel dit in via Settings → Cartridge → Ethernet cartridge. Op Windows is **Npcap** nodig; kies daarna in VICE de netwerkadapter.
- De emulatie werkt op **raw ethernet**: de geëmuleerde C64 krijgt een eigen MAC-adres en moet zelf **ARP, IP, DHCP (of een statisch IP), TCP en/of UDP** doen. Gebruik daarvoor **ip65** (https://github.com/cc65/ip65). Dat is een volwassen TCP/IP-stack voor de 6502 met drivers voor de CS8900a (RR-Net/TFE) en ondersteuning voor DHCP, ARP, UDP en TCP (één verbinding, zowel connect als listen).
- ip65 is geschreven voor **ca65/ld65 (cc65)**, niet voor 64tass. Bouw ip65 met ld65 als **losse binary blob op een vast adres met een eigen jump table** (bijvoorbeeld `ip65_init`, `dhcp_init`, `tcp_connect`, `tcp_listen`, `tcp_send`, `ip65_process`, en de UDP-varianten). De 64tass-gamecode roept alleen die jump table aan.
- ip65 is polling-based: `ip65_process` moet regelmatig (elke frame/tick) worden aangeroepen. Meet de cycles per aanroep.
- **Bekende valkuilen** (documenteer ze in de README):
  - pcap op een **WiFi-adapter** werkt vaak niet goed, omdat access points frames met een onbekend MAC-adres weggooien. Gebruik bij voorkeur een **bekabelde ethernetadapter** op de PC.
  - Verkeer tussen VICE en de eigen PC-host wordt via pcap meestal niet doorgelust. Dat is geen probleem, want de tegenspeler is de C64 Ultimate.
  - Onderzoek of **twee VICE-instanties** via pcap op dezelfde adapter met elkaar kunnen praten. Lukt dat, dan kan veel getest worden zonder de echte C64 Ultimate.
- Geheugen: ip65 met TCP, UDP, DHCP en ARP plus buffers is waarschijnlijk 6-8 KB. Maak daarom **twee buildtargets**: `wow-net-u64.prg` (UCI, compact) en `wow-net-rrnet.prg` (ip65). De game-code is gelijk en alleen de netwerkbackend verschilt. Is er genoeg vrij geheugen, dan mag het ook één PRG met runtime-detectie worden (UCI via `$DF1D == $C9`, CS8900a via het chip-ID-register).

## Architectuur (vast besluit, wijk alleen af met onderbouwing)

### 1. Topologie: direct peer-to-peer, één C64 is host. **Geen relay of server.**
- Speler 1 kiest **HOST GAME**: zijn C64 luistert op een vaste poort (bijvoorbeeld 6464), toont zijn eigen IP-adres en wacht.
  - Op de Ultimate gaat dat via `LISTEN_START`/`LISTEN_STATE`/`LISTEN_SOCKET`.
  - Op RR-Net via ip65 `tcp_listen`.
- Speler 2 kiest **JOIN GAME**, voert het IP-adres van de host in (laatst gebruikte onthouden) en verbindt (UCI `OPEN_TCP`, of ip65 `tcp_connect`).
- **Elke rol moet op elk platform werken:** de Ultimate kan hosten of joinen, en VICE/RR-Net ook.
- **De host is ook de lockstep-coördinator:** hij voegt de inputs samen en stuurt START, seed en settings.
- **Terugvaloptie zonder server:** werken `LISTEN_*` niet betrouwbaar op de C64 Ultimate, gebruik dan **UDP peer-to-peer**. Beide spelers voeren het IP-adres van de ander in, en beide openen een UDP-socket naar elkaar op een vaste poort (UCI `OPEN_UDP`, ip65 UDP). Zoek in fase 0 uit of `OPEN_UDP` op de Ultimate ook pakketten ontvangt die de peer naar die lokale poort stuurt. Ontwerp de C64-code zo dat TCP en UDP dezelfde protocolberichten gebruiken.
- Een relay- of serveroplossing is **uitdrukkelijk niet gewenst**.

### 2. Netcode: deterministic lockstep met input delay
- Beide C64's draaien **exact dezelfde simulatie**. Over het netwerk gaan alleen **inputs** (1 byte joystick per speler per tick) plus control messages.
- Elke machine plant zijn lokale input voor tick `N + D` (D = input delay, default 3, instelbaar in het hostmenu).
- De client stuurt zijn inputs naar de host. De host stuurt het samengevoegde `(tick, joyP1, joyP2)` terug. Beide voeren tick `N` pas uit als de input van beide spelers voor `N` bekend is.
- Pakketten mogen **meerdere ticks bundelen** (configureerbaar 1-3 ticks per pakket) om de UCI-pollkosten te dragen.
- Bij UDP: stuur in elk pakket ook de laatste K inputs mee (redundantie tegen pakketverlies) en negeer duplicaten.
- Komt er geen data, dan pauzeert het spel ("WAITING FOR PARTNER" na 1 s, terug naar het menu na 10 s).
- **Tick rate** wordt door de host bepaald (default 50 Hz; test ook 60). De C64 voert maximaal één tick per tickperiode uit (CIA-timer of raster) en loopt bij achterstand maximaal 2 ticks per frame in. Zo werken een PAL- en een NTSC-machine samen. De C64 Ultimate kan beide.
- **Desync-detectie:** elke 16 ticks stuurt de client een 16-bit checksum van de spelstate (actorposities, `actor_type_tbl`, headings, bullets, lives, scores, RNG-state, tick). De host vergelijkt die met zijn eigen checksum. Bij een mismatch tonen beide "DESYNC" en gaan terug naar het menu (v1). In v2: een state snapshot van host naar client.

### 3. Protocol (binair, length-prefixed: TCP is een stream, dus handel partial reads af)
`[len][type][payload]`. Minimaal:
- `HELLO(protoversion, name)`
- `WELCOME(slot)`
- `START(seed16, start_dungeon, tickrate, input_delay, ticks_per_packet)`
- `INPUT(tick16, n, joy*n)`
- `TICKS(tick16, n, {joyP1, joyP2}*n)`
- `CHECKSUM(tick16, sum16)`
- `PAUSE/RESUME`
- `PING/PONG(timestamp)`
- `DESYNC`
- `BYE`

Controleer de protocolversie bij `HELLO` en weiger bij een mismatch. Documenteer het protocol in `docs/protocol.md`.

## Benodigde aanpassingen aan het spel

1. **Build als PRG in plaats van cartridge.** De code draait dan in RAM op `$8000-$BFFF`. Voeg een loader/BASIC-stub toe en crunch eventueel met exomizer naar één `.prg`. Controleer welke waarde naar `$01` wordt geschreven.
2. **Inventariseer het vrije geheugen** (waarschijnlijk `$C000-$CFFF` en delen van `$4000-$7FFF`; verifieer dit met een memory map uit VICE). Zet daar de netwerklaag (UCI-driver of ip65-blob), buffers en de menu/lobby-code. Let op het zero page-gebruik van ip65: het spel gebruikt `$02-$E9`. Laat ip65 een eigen ZP-gebied gebruiken, of save/restore het rond ip65-aanroepen.
3. **Maak het spel deterministisch en tick-based:**
   - Verplaats alle spellogica uit `irq_handler` naar een `game_tick`-routine in de main loop: RNG, de timers van spelers en bullets, onzichtbaarheid, launch countdown, warp door timer en `music_speed`-wijzigingen. In de IRQ blijven alleen `sfx.play`, `jingles.play` en eventueel een tick-request flag.
   - Vervang `random_number` door een **LFSR met een seed van de host** die alleen in de tick doorschuift. Gebruik nooit SID-, raster- of CIA-waarden in spellogica.
   - De busy loops (normal/Worluk/Wizard) moeten per tick een **vast aantal actor passes** doen. **Kalibreer** dit eerst: meet in VICE (origineel, NTSC) het gemiddelde aantal passes per frame per situatie (aantal monsters, Worluk, Wizard). Kies daarna tickgedrag en snelheidstabellen zo dat spelers- en monstersnelheid binnen ±5% van het origineel blijven.
   - Alle joystick- en vuurknopreads lezen uit `net_joy[0/1]` in plaats van uit de CIA. Lokaal leest elke speler **joystick in poort 2** (instelbaar). Die waarde wordt verstuurd en daarna pas toegepast in tick `N + D`, ook voor de lokale speler.
   - Toetsenbordacties (pauze) worden netwerkmessages. Laat de easter egg lokaal of verwijder hem.
   - De spellogica gebruikt VIC-registers als state (`VIC_D015`, `VIC_D027`). Dat mag, maar de netwerkcode mag deze registers nooit aanraken.
   - `update_radar` is cosmetisch. Het flikkeren mag blijven.
4. **Menu en lobby** (vóór het titelscherm):
   - netwerkdetectie (UCI of CS8900a), plus een duidelijke foutmelding als er niets gevonden wordt of de Command Interface uit staat;
   - eigen IP tonen (UCI `GET_IPADDR`; bij RR-Net via DHCP, of handmatig een statisch IP/netmask/gateway invullen);
   - menukeuzes: **LOCAL GAME / HOST GAME / JOIN GAME**;
   - IP-invoer bij JOIN, met het laatst gebruikte IP onthouden (optioneel opslaan op disk via de KERNAL);
   - hostinstellingen: input delay, tick rate en optioneel TCP of UDP;
   - lobbystatus en een ping-weergave.
   - Tijdens het spel: optioneel een kleine latency/tick-indicator (aan/uit).
   - Een JOIN naar een IP waar niets draait kan 30 s blokkeren. Toon "CONNECTING..." en maak het via RUN/STOP afbreekbaar met UCI `ABORT` als dat technisch kan. Documenteer het anders.
5. **Netwerk-HAL** met één API en twee backends: `net_uci.asm` (Ultimate) en `net_rrnet.asm` (wrapper rond de ip65-blob).
   API: `net_init`, `net_get_ip`, `net_listen(port)`, `net_accept_poll`, `net_connect(host,port)`, `net_send(buf,len)`, `net_poll()` (non-blocking state machine), `net_recv_available`, `net_close`. De game-code gebruikt alleen deze API en weet niet welke backend actief is.

## Fasering (lever per fase op en wacht op akkoord)

**Fase 0 – Haalbaarheidsmeting (go/no-go), C64 Ultimate ↔ VICE/RR-Net:**
- Een losse test-PRG in twee varianten (UCI en ip65/RR-Net) die host of join kan doen, over TCP en UDP.
- Verifieer `LISTEN_START/STATE/SOCKET` op de actuele C64 Ultimate-firmware, en het ontvangstgedrag van `OPEN_UDP`.
- Verifieer de RR-Net-setup in VICE onder Windows (Npcap, adapterkeuze, DHCP) en of twee VICE-instanties elkaar kunnen bereiken.
- Meet over 1000+ pings, in beide richtingen (Ultimate als host en VICE als host):
  - RTT min/avg/max/jitter, over TCP en over UDP;
  - het verschil tussen de busy-tijd van de Ultimate en de cycles die de C64 kwijt is per send/poll (rasterbalk);
  - de kosten van `ip65_process`;
  - het effect van het bundelen van ticks.
- Let op: VICE draait niet cycle-synchroon met een echte machine en kan bij host-load haperen. Meet ook met VICE in warp uit, met "sound sync" aan en met de juiste PAL/NTSC-instelling.
- Rapporteer de resultaten en adviseer het transport (TCP/UDP), de tick rate, de input delay en het aantal ticks per pakket.
- **Stop als de RTT-piek of de CPU-kosten lockstep onspeelbaar maken.** Stel dan een alternatief zonder server voor, bijvoorbeeld host-authoritative met een state stream van host naar client.

**Fase 1 – Baseline:** bouw het origineel als PRG zonder Magic Voice en zonder functionele verandering. Verifieer dat het in VICE en op de C64 Ultimate speelt zoals de cartridge.

**Fase 2 – Determinisme (offline, in VICE):** de tick-refactor, input-abstractie en LFSR. Bouw een **replay-test**: neem inputs op, speel ze twee keer af (of op twee VICE-instanties) en controleer dat de checksums per tick identiek zijn. Speel lokaal 2-speler en vergelijk het gevoel en de snelheid met het origineel.

**Fase 3 – Netwerklaag:** de HAL met de asynchrone UCI-driver en de ip65/RR-Net-backend, het protocol, het menu/de lobby en host/join. Test alle combinaties: Ultimate-host ↔ VICE-join, VICE-host ↔ Ultimate-join, en VICE ↔ VICE als dat werkt. Voeg een debugoptie toe die kunstmatige latency/jitter toevoegt (inputs extra ticks vasthouden), zodat slechte netwerken gesimuleerd kunnen worden zonder externe tools.

**Fase 4 – Integratie:** lockstep in het spel, plus afhandeling van desync, pauze, disconnect, game over en terugkeer naar het menu.

**Fase 5 – Afwerking/optioneel:** high scores per machine, de instelbare joystickpoort, `.d64`-distributie, eventueel één gecombineerde PRG met runtime-detectie en eventueel een `.crt` (test dan of de UCI beschikbaar blijft met die cartridge actief).

## Ontwikkelomgeving & test

- **64tass** voor de game en **cc65 (ca65/ld65)** voor de ip65-blob. Een Makefile of build-script (Windows-compatibel) levert `wow-net-u64.prg`, `wow-net-rrnet.prg` en een `.d64`.
- **VICE 3.9+** (`x64sc`) voor fase 1-2 (baseline, determinisme, replay-tests) en, met RR-Net en Npcap, als **tweede speler** in alle netwerktests. VICE emuleert de UCI niet: de UCI-backend wordt alleen op de echte C64 Ultimate getest.
- Eén script doet build → deploy:
  - de PRG naar de C64 Ultimate via de REST API van de Ultimate (bijvoorbeeld `run_prg` via HTTP) of de DMA-load socket;
  - tegelijk VICE starten met de RR-Net-PRG (`x64sc -autostart ...` met de juiste ethernet- en cartridge-opties op de command line).
- Hardware: één C64 Ultimate en één Windows-PC met VICE op hetzelfde LAN (PC bij voorkeur bekabeld). Test de Ultimate zowel via ethernet als via WiFi, en zowel in PAL als in NTSC.

## Codeerrichtlijnen

- Behoud de originele labels en het commentaar. Markeer elke wijziging met `; NET:` en een korte uitleg. Nieuwe modules komen in aparte bestanden (`net_uci.asm`, `lockstep.asm`, `tick.asm`, `menu.asm`).
- Geen zelfmodificerende code in de netwerklaag. Documenteer zero page-gebruik (vrije ZP-adressen inventariseren).
- Houd een `docs/memory_map.md` en een `docs/protocol.md` bij, plus een `README.md` met build-, setup- en speelinstructies (Command Interface aanzetten, netwerk configureren op de Ultimate, host/join).

## Acceptatiecriteria

- 30 minuten spelen tussen de C64 Ultimate en VICE (RR-Net) op een LAN **zonder desync**, met elk van beide als host. Twee C64 Ultimates moeten volgens hetzelfde ontwerp werken (zelfde UCI-backend).
- Snelheid van spelers en monsters binnen ±5% van het origineel. Input-latency voelt acceptabel (doel ≤ 100 ms end-to-end bij LAN-RTT < 20 ms).
- Netwerkuitval geeft een nette melding en terugkeer naar het menu, zonder crash of vastgelopen UCI.
- De lokale 1- en 2-spelermodus werken nog.
- Beide spelers zien op elk moment hetzelfde dungeon, dezelfde monsters, scores en levens.

## Juridische noot

Wizard of Wor is auteursrechtelijk beschermd (Midway/CBS; nu bij de rechthebbende van Midway). De disassembly is reverse engineering. Behandel dit project als **privé/hobby** en verspreid geen binaries van het spel zonder toestemming. Houd de netwerkcode (UCI-driver, lockstep, protocol) als losse, herbruikbare modules, zodat die eventueel in een eigen "Wor-achtige" clone gebruikt kan worden.

Begin met **Fase 0**: lever het meetprogramma (UCI- en RR-Net-variant), een setupbeschrijving voor VICE/RR-Net/Npcap en een kort plan op, inclusief een memory map van het origineel en een lijst van alle plekken in de code die voor determinisme moeten worden aangepast (met regelnummers/labels).
