# Netcode – ontwerpkeuzes en bevindingen

Levend document. Alles wat hier staat is gemeten of uit de broncode afgeleid. Waar dat niet zo is, staat het erbij.

## Hardware en topologie

- **Commodore 64 Ultimate** via het Ultimate Command Interface (UCI, `$DF1C-$DF1F`). Driver: `src/net/uci.asm`.
- **RR-Net (CS8900a)**, vooral voor VICE als tweede speler. Driver: ip65 (UDP) als blob, `src/net/ip65_glue.s` + `src/net/net_rrnet.asm`.
- **Geen relay of server.** Direct peer-to-peer.

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
| C64 Ultimate ↔ PC | *nog te meten* | | `docs/fase0_meten.md` |
| C64 Ultimate ↔ VICE | *nog te meten* | | |
