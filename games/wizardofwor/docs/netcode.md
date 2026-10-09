# Netcode – ontwerpkeuzes en bevindingen

Levend document. Alles wat hier staat is gemeten of uit de broncode afgeleid. Waar dat niet zo is, staat het erbij.

## Hardware en topologie

- **Commodore 64 Ultimate** via het Ultimate Command Interface (UCI, `$DF1C-$DF1F`). Driver: `src/net/uci.asm`.
- **RR-Net (CS8900a)**, vooral voor VICE als tweede speler. Driver: ip65 (UDP) als blob, `src/net/ip65_glue.s` + `src/net/net_rrnet.asm`.
- **Direct peer-to-peer** waar het kan: Ultimate ↔ VICE/RR-Net, en VICE ↔ VICE.
- **Game server** (`server/`, .NET 8) voor Ultimate ↔ Ultimate: beide C64's verbinden met de server, die de speldata doorgeeft. Zie onder.

## Transport: UDP is primair

| | UCI (Ultimate) | ip65 (RR-Net) |
|---|---|---|
| UDP | `OPEN_UDP`; lezen door te pollen | niet-blokkerend, callback per datagram |
| TCP | `OPEN_TCP`, `LISTEN_*` (niet officieel gedocumenteerd) | **onbruikbaar**: `tcp_send` wacht op de ACK van elk pakket (stop-and-wait); `tcp_connect`/`tcp_listen` blokkeren |

Gevolg: het lockstep-protocol draait over **UDP** en regelt zelf zijn betrouwbaarheid (sequence numbers, redundante inputs, duplicaten negeren). TCP blijft een optie voor Ultimate↔Ultimate als UDP daar problemen geeft.

### Bronpoort bij UDP

Een UDP-socket op de Ultimate verstuurt waarschijnlijk vanaf een eigen, willekeurige bronpoort. De RR-Net-kant en `netpeer.py` antwoorden daarom naar de **bronpoort van het laatst ontvangen pakket van de peer** (geleerd), niet naar een vaste poort.

Open vraag voor fase 0: kan een Ultimate pakketten ontvangen die naar zijn vaste poort 6464 worden gestuurd? Dat is nodig voor Ultimate↔Ultimate via UDP. `netpeer.py udp --reply-port 6464` test dit.

## UCI-gedrag (bron: ultimate-uci-sdk, gemeten op U64 Elite fw 3.15)

- Read zonder data: ~42–45 ms busy aan de Ultimate-kant. Read met data: 4–21 ms. Write: 3–7 ms.
- Er kan maar één command tegelijk lopen. Daarom start de driver een read met `net_read_start` en rondt hem later af met `net_read_poll`, zodat de C64 intussen doorwerkt.
- Een send moet wachten tot de lopende read klaar is. `nettest` meet die wachttijd als "SEND WAIT".
- Vraag nooit meer dan 512 bytes per read op. Lengtes tussen 769 en 1023 kunnen de Ultimate laten vastlopen.

## Zero page en geheugen

- Spel: `$02-$E9`. Vrij voor de netwerkcode: **`$EA-$FF`**. De KERNAL draait tijdens het spel niet; de IRQ van het spel eindigt zelf met `RTI`.
- ip65-blob: 15 bytes zero page (`ptr1-4`, `tmp1-4`, `sreg`, `abort_key_disable`). Het adres kies je bij het linken (`build_ip65_blob(name, start, zp)`).
- Vrij RAM in het spel (nog te verifiëren): `$4000-$7FFF`, `$C000-$CFFF`.
- ip65 gebruikt geen eigen timer. De glue leest dezelfde 32-bit cycle-teller op CIA2 (timer A telt cycles, timer B telt de underflows van A).

## Indeling van het origineel moet exact blijven

Het spritedatablok dat `create_sprites` kopieert, bevat de code van `MV_init`. Eén extra byte daarin verschuift alle volgende sprites (de "doormidden gesplitste monsters"). Regels:

- patches binnen het originele 16K-image hebben **exact dezelfde grootte**;
- nieuwe code komt **na `$BFFF`** of in een vrij RAM-gebied;
- `tools/build.py` vergelijkt bij elke build het PRG-image met de cartridge en toont elk gepatcht gebied.

## Meetresultaten

| Opstelling | RTT min / gem / max | Verlies | Opmerking |
|---|---|---|---|
| VICE ↔ VICE (RR-Net, Npcap op WiFi-adapter) | 8,6 / 34–52 / 242–600 ms | ~2% | VICE-pcap-latency, niet representatief voor hardware |
| VICE ↔ WSL (Hyper-V-switch) | – | 100% | Hyper-V laat frames met een vreemd MAC-adres niet door; werkt niet |
| C64 Ultimate ↔ PC, UDP (beide via WiFi-netwerk, 2026-10-03) | C64: 8,2 / 65 / 733 ms; PC: 8,4 / ~100 / 2168 ms | ~1% | zie hieronder |
| C64 Ultimate ↔ VICE | *nog te meten* | | |

### C64 Ultimate ↔ PC (test A, UDP), details

| Meting | min | gem | max |
|---|---|---|---|
| READ DATA (read die data opleverde) | 1,3 ms | 17,3 ms | 174 ms |
| READ EMPTY (read zonder data) | 35,9 ms | 49,5 ms | 190 ms |
| WRITE (C64 wacht synchroon) | 1,3 ms | 1,7 ms | 3,3 ms |
| SEND WAIT (send wacht op lopende read) | 1,2 ms | 39 ms | 177 ms |

- De Ultimate verstuurt vanaf een willekeurige bronpoort (62511). Antwoorden naar de geleerde poort werkt.
- Een read komt waarschijnlijk terug zodra er data binnenkomt (READ DATA gemiddeld 17 ms), en anders na ~36–50 ms.
- Conclusies voor het spel:
  - writes worden asynchroon (1,7 ms wachten past niet in de 7–8% vrije tijd per tick);
  - na elke voltooide read eerst versturen, dan de volgende read;
  - startwaarden: 60 ticks/s, input delay 4, elk pakket herhaalt de laatste 8 inputs.
- De uitschieters (0,7–2,2 s) komen waarschijnlijk van WiFi. Met een kabel aan de Ultimate wordt dat naar verwachting minder.
- **Getest met `--reply-port 6464`: de Ultimate ontvangt UDP alleen op zijn eigen willekeurige bronpoort, niet op poort 6464** (pongs 0, terwijl de PC de pings van de C64 wel ontving).
  - Ultimate ↔ VICE/RR-Net: UDP, met VICE als vaste kant (luistert op 6464, antwoordt naar de geleerde poort).
  - Ultimate ↔ Ultimate: UDP kan niet (beide kanten hebben een onbekende poort). Daarvoor TCP: de host luistert (`LISTEN_*`), de ander verbindt. Test B moet uitwijzen of `LISTEN_*` werkt en hoe TCP zich gedraagt.

### Test B en de firmwarebron (2026-10-03)

- `LISTEN_START` op de C64 Ultimate geeft **`21,UNKNOWN COMMAND`**.
- De firmwarebron bevestigt dit (GideonZ/1541ultimate master, `software/io/network/network_target.cc`):
  - Er zijn alleen `IDENTIFY`, `GET/SET_INTERFACE`, `GET_NETADDR`, `GET/SET_IPADDR`, `OPEN_TCP`, `OPEN_UDP`, `CLOSE`, `READ` en `WRITE`. **Luisteren bestaat niet.**
  - `OPEN_UDP` en `OPEN_TCP` doen `socket()` + `connect()`, zonder `bind()`. De lokale poort is altijd willekeurig, en een UDP-socket accepteert alleen pakketten van het ene adres en de ene poort waarmee hij verbonden is.
  - `READ` gebruikt `SO_RCVTIMEO` van 40 ms en komt direct terug zodra er data is. Dat verklaart READ EMPTY (~36–50 ms) en READ DATA.
- **Gevolg: twee Ultimates met standaardfirmware kunnen niet rechtstreeks met elkaar verbinden.** Geen van beide kan luisteren of een vaste poort openen.
- Wel mogelijk:
  - Ultimate ↔ RR-Net (VICE of hardware) via UDP;
  - Ultimate ↔ Ultimate met een firmware-uitbreiding (UDP op een vaste lokale poort, of een TCP-listener);
  - Ultimate ↔ Ultimate via een derde machine.

## Game server (Ultimate ↔ Ultimate)

Twee Ultimates kunnen niet rechtstreeks verbinden (zie hierboven). Daarom is er een server in het LAN (`server/`, specificatie in `docs/PROMPT_C64_GameServer.md`, onderbouwing in `docs/gameserver_onderzoek.md`):

- UDP op poort 6465. De server leert per client het adres en de bronpoort.
- Een lobby met nicknames, uitdagen en accepteren. Daarna een sessie.
- Wizard of Wor: de lockstep blijft op de C64. De server geeft `INPUT` ongewijzigd door, controleert de checksums en meldt uitval.
- Protocol: `server/docs/protocol.md`.
- VICE kan via pcap meestal niet de eigen PC bereiken: draai de server dan op een andere machine (bijvoorbeeld een Raspberry Pi), of speel tegen de bot.
