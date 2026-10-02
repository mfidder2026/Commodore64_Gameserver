# Fase 0 – meten op je C64 Ultimate

Doel: weten of lockstep-netcode haalbaar is (go/no-go), en de instellingen kiezen: tick rate, input delay en TCP of UDP.

## Wat je nodig hebt

- `build\wow.d64` (bevat `NETTEST` en `NETTEST-RRNET`), of de losse PRG's in `build\`.
- Op de Ultimate: **C64 and Cartridge Settings → Command Interface: Enabled**.
- Een PC in hetzelfde netwerk met Python (`tools\netpeer.py`).

## Test A – Ultimate ↔ PC via UDP (belangrijkste test)

1. Op de PC: `python tools\netpeer.py udp`
2. Op de Ultimate: start `NETTEST`. Kies **1**, en vul het IP-adres van de PC in.
3. Laat het ongeveer een minuut lopen. Probeer met **+** en **-** verschillende intervallen (1, 2, 5 en 10 frames).
4. Noteer de tabel op het C64-scherm (of maak een foto) en de laatste regels van `netpeer`.
   `netpeer` meldt ook vanaf welke **bronpoort** de Ultimate verstuurt.

Extra: herhaal met `python tools\netpeer.py udp --reply-port 6464`. Komen er dan nog PONGs op de C64 aan? Dan kan Ultimate↔Ultimate via UDP.

## Test B – Ultimate ↔ PC via TCP

- Ultimate verbindt: PC `python tools\netpeer.py tcp-server`, Ultimate keuze **2**.
- Ultimate luistert: Ultimate keuze **3**, PC `python tools\netpeer.py tcp-client <ip-van-de-c64>`. Dit test de niet-gedocumenteerde `LISTEN`-commando's.

## Test C – Ultimate ↔ VICE

1. VICE: **Settings → Cartridge → Ethernet cartridge**: aan, mode **RR-Net**, en kies je netwerkadapter (Npcap). Een **bekabelde** adapter werkt het best; via WiFi worden frames van het extra MAC-adres vaak geweigerd.
2. Start `NETTEST-RRNET` in VICE. Vul een vrij IP-adres in je netwerk in (bijvoorbeeld `192.168.1.201`), of druk op RETURN voor DHCP.
3. Peer-IP: het IP-adres van de Ultimate.
4. Ultimate: `NETTEST`, keuze **1**, met als peer het IP-adres dat je VICE gaf.

## Wat de kolommen betekenen

| Regel | Betekenis |
|---|---|
| RTT | round-trip tijd van een eigen PING tot de bijbehorende PONG |
| READ DATA | duur van een socket-read die data opleverde (Ultimate-kant busy) |
| READ EMPTY | duur van een read zonder data (verwacht: ~42 ms) |
| WRITE | duur van een write; de C64 wacht zolang |
| SEND WAIT | hoe lang een PING moest wachten op een lopende read |
| PINGS SENT / PONGS RCVD | verschil = verloren of onderweg |

Met deze cijfers bepaal ik in fase 2 en 3 de tick rate, de input delay en het aantal ticks per pakket.
