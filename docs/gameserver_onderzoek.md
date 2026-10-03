# Onderzoek: is de C64 Game Server een oplossing voor Ultimate ↔ Ultimate?

Beoordeling van `docs/PROMPT_C64_GameServer.md`, getoetst aan wat we gemeten en gebouwd hebben (`docs/netcode.md`, `docs/fase2_determinisme.md`).

## Conclusie

**Ja, dit lost het probleem op.** Een Ultimate kan niet luisteren, maar wel verbinden met een vast adres en een vaste poort. Als beide Ultimates met een server verbinden en de server de speldata doorgeeft, kunnen ze tegen elkaar spelen. Dat is in test A al bewezen: de Ultimate stuurde en ontving zonder problemen via de PC.

Een paar punten in de prompt moet je wel aanpassen. Het belangrijkste is **UDP in plaats van (alleen) TCP**.

## Wat goed is

- Server in het LAN, beide C64's verbinden uitgaand: dat werkt met de huidige firmware.
- Compact binair protocol, kleine berichten, geen encryptie: past bij de C64.
- Een platform voor meerdere games, met een transparante relay als standaard.
- Een dashboard met hex-weergave, en een bot als testclient: erg nuttig.
- De waarschuwing dat VICE via pcap de eigen PC niet bereikt: klopt (zie hieronder).
- C# / .NET 8: de SDK (8.0.423) staat al op deze PC.

## Aanpassingen

### 1. UDP als speltransport (belangrijkste punt)

De prompt kiest kale TCP. Uit de metingen en de broncode blijkt dat TCP aan **beide** C64-kanten nadelen heeft:

| Client | Probleem met TCP | UDP |
|---|---|---|
| C64 Ultimate | De firmware zet geen `TCP_NODELAY` op zijn eigen sockets (`network_target.cc`). Nagle kan kleine berichten ophouden tot er een ACK binnen is. Samen met delayed ACK (Windows: tot 200 ms) geeft dat haperingen. | Werkt aantoonbaar (test A): de Ultimate verstuurt vanaf een willekeurige poort, de server antwoordt naar die poort. |
| VICE / ip65 | `tcp_send` wacht op de ACK van **elk** pakket (stop-and-wait) en blokkeert de C64 zolang. Bij ~3–5 ms per send is dat 20–30% van een tick, terwijl er maar 7–8% vrij is. `tcp_connect` blokkeert ook. | Niet-blokkerend, al gebouwd en getest. |

**Advies:** de spelpoort accepteert **UDP**. TCP mag als optie blijven (bijvoorbeeld voor de lobby), maar is niet nodig.

- De server leert per client het IP-adres en de bronpoort uit het eerste pakket, en antwoordt daarheen.
- Betrouwbaarheid regelt het protocol zelf. Voor de lockstep-inputs bestaat dat al: elk pakket herhaalt de laatste 16 inputs. Voor lobbyberichten volstaat herhalen tot er een antwoord komt.
- Keepalive: een client die 10 s niets stuurt, is weg.

### 2. Server als relay, niet als lockstep-coördinator

De prompt laat de server inputs samenvoegen (`INPUT` → `TICKS`). Dat werkt, maar de C64-lockstep is al gebouwd en getest. Elke C64 stuurt `INPUT` met de laatste 16 inputs en een checksum, en wacht op de inputs van de ander.

**Advies:** de Wizard of Wor-module gebruikt de **transparante relay**: een `INPUT`-pakket gaat ongewijzigd naar de tegenstander. De module kijkt alleen mee:

- de checksumvelden vergelijken (die zitten al in `INPUT`) en bij een verschil `DESYNC` sturen;
- de tick bijhouden voor het dashboard;
- uitval detecteren.

Wat dit oplevert:

- De C64-code blijft vrijwel gelijk. Alleen het verbinden en de lobby zijn nieuw.
- De latency is gelijk: in beide ontwerpen gaat een input via de server naar de ander.
- Er is minder servercode en minder kans op fouten.

De rollen host en join verdwijnen ook bij een relay: de server stuurt `START` met de seed en wijst de spelerslots toe (speler 1 en speler 2).

### 3. Meetwaarden in de prompt corrigeren

De prompt noemt de waarden uit de SDK. Gemeten op jouw C64 Ultimate (test A) en in de firmwarebron:

| | Prompt | Gemeten |
|---|---|---|
| Read zonder data | 42–45 ms "kost" | 36–50 ms **wachttijd**, geen CPU-tijd: de firmware wacht max. 40 ms (`SO_RCVTIMEO`), de C64 werkt asynchroon door |
| Read met data | 4–21 ms | 1,3–17 ms (komt terug zodra er data is) |
| Write | 3–7 ms | 1,3–3,3 ms (gemiddeld 1,7) |
| RTT Ultimate ↔ PC | – | minimaal 8 ms; uitschieters tot 0,7–2 s (waarschijnlijk WiFi) |
| Pakketverlies | – | ~1% |

### 4. Server ook op Linux/Raspberry Pi kunnen draaien

VICE met RR-Net bereikt via pcap meestal niet de PC waar het zelf op draait. Met **één** Ultimate en VICE op dezelfde PC kan VICE dus niet met een server op die PC praten. Er zijn twee oplossingen:

- de server draait op een andere machine: een Raspberry Pi, een NAS of een tweede PC;
- of je speelt de Ultimate tegen de **bot** van de server. Dat dekt de prompt al.

**Advies:** bouw de server als gewone .NET 8-console-app en publiceer hem zowel als `win-x64` als `linux-arm64` (Raspberry Pi). Dat kost geen extra code.

Ultimate ↔ VICE werkt overigens ook **zonder** server (direct via UDP, al gebouwd). De server is alleen nodig voor Ultimate ↔ Ultimate, en handig voor de lobby.

### 5. Kleinere punten

- **Nickname** max. 8 tekens A–Z/0–9: prima. De C64 heeft er een invoerscherm voor nodig.
- **Lobby op de C64:** wachten op een uitdaging, en accepteren met fire of weigeren. Dat is nieuw werk aan de C64-kant, en past in het bestaande setupmenu.
- **10 s timeout** voor uitval: de C64 gebruikt nu 15 s. Kies één waarde voor beide.
- **Pauze:** in lockstep pauzeert de ander vanzelf mee (hij wacht op inputs). Een apart `PAUSE`-bericht is alleen nodig om "gepauzeerd" te kunnen tonen in plaats van "wachten".
- **Poort:** gebruik voor de server een andere poort dan 6464 (bijvoorbeeld 6465). Dan blijft direct Ultimate ↔ VICE op 6464 mogelijk naast de server.

## Wat dit betekent voor de C64-kant

| Onderdeel | Wijziging |
|---|---|
| Netwerklaag (UCI + ip65) | geen: UDP naar een vast adres werkt al op beide |
| Lockstep, determinisme | geen |
| Setupmenu | nieuwe keuze "SERVER": nickname en server-IP invoeren |
| Lobby | nieuw scherm: wachten, uitdaging tonen, accepteren of weigeren |
| Protocol | `HELLO`/`WELCOME`/`START` volgens het serverprotocol; `INPUT` blijft gelijk |

Geschatte omvang: de server is het grootste werk. Aan de C64-kant gaat het om het lobbyscherm en een paar berichttypen.
