# Servertest: C64 Ultimate tegen de bot via de C64 Game Server

Doel: de eerste echte test van de servermodus op de C64. Je Ultimate speelt via de server op je PC tegen een bot die op dezelfde PC draait.

```
C64 Ultimate  ──UDP 6465──►  C64GameServer (PC)  ◄──  C64Bot (PC)
```

## Wat je nodig hebt

- Je PC en je C64 Ultimate in **hetzelfde netwerk**.
- De nieuwste build. Bouw eerst opnieuw:

  ```bash
  build.bat
  ```

  Zet daarna `build\wow.d64` (of `build\wow.prg`) op de Ultimate.
- Op de Ultimate: **C64 and Cartridge Settings → Command Interface: Enabled**.
- Het IP-adres van je PC. Dat staat straks ook in het servervenster; bij de vorige test was het `192.168.1.17`.

## Stap 1 – server starten (PC)

Open een terminal in de projectmap en start:

```bash
server\publish\win-x64\C64GameServer.exe
```

- Het venster toont de adressen waarmee C64's verbinden. Gebruik het adres in je thuisnetwerk (`192.168.1.x`), niet een `100.x` (Tailscale) of `172.x` (WSL).
- Vraagt Windows om firewalltoegang: kies **Privénetwerken** en sta toe.

## Stap 2 – dashboard openen (PC)

Open in je browser:

```
http://localhost:8080/
```

Hier zie je live wie verbonden is, de sessies en het gebeurtenissenlog. Laat dit open staan.

## Stap 3 – de bot als tegenstander starten (PC)

Open een **tweede** terminal in de projectmap en start:

```bash
server\publish\win-x64\C64Bot.exe --nick BOT --no-checksum --games 0 --ticks 1000000
```

- `--no-checksum`: de bot kent de echte spelstate niet. Zonder deze optie meldt de server meteen een desync.
- `--games 0`: blijven spelen, ook na een game over.
- `--ticks 1000000`: de bot beëindigt het spel niet zelf; dat doet de game over op de C64.

In het dashboard staat nu **BOT** in de lobby.

## Stap 4 – verbinden vanaf de Ultimate

1. Start `WOW` op de Ultimate. Het setupmenu verschijnt met **NETWORK: C64 ULTIMATE** en het IP-adres van de Ultimate.
2. Kies **4** (PLAY VIA A GAME SERVER).
3. **YOUR NAME:** bijvoorbeeld `ERIK` (alleen A–Z en 0–9, max. 8 tekens).
4. **IP OF THE GAME SERVER:** het IP-adres van je PC, bijvoorbeeld `192.168.1.17`.
5. Je ziet `CALLING THE SERVER` met puntjes, en daarna **CONNECTED**. Druk op een toets.

In het dashboard staat nu ook **ERIK**, en het log meldt "joined the lobby".

## Stap 5 – de uitdaging accepteren

Het titelscherm van het spel verschijnt. De **onderste regel** is de statusregel van de lobby:

| Statusregel | Betekenis |
|---|---|
| `CONNECTING TO THE SERVER` | nog geen antwoord van de server |
| `WAITING FOR AN OPPONENT  1 IN THE LOBBY` | je staat in de lobby |
| `CHALLENGE FROM BOT  FIRE PLAY  N NO` | de server koppelt je aan de bot |
| `WAITING FOR BOT` | jij hebt geaccepteerd, de bot nog niet |
| `STARTING` | het spel start |

Omdat de bot al wacht, komt de uitdaging vrijwel meteen. Druk op **FIRE** (joystick poort 2) of **SPACE**. Na `STARTING` begint het spel (GET READY).

- De bot verbond als eerste en krijgt daarom slot 0: **speler 1 (geel)**. Jij bent **speler 2 (blauw)**.
- Je bestuurt met joystick poort 2 of **W A S D + SPACE**.
- De Worrior van de bot loopt willekeurig rond en schiet af en toe.

## Stap 6 – tijdens het spel opletten

**Op de C64:**
- Loopt het spel soepel, in het tempo van het origineel?
- **Knippert de rand?** Dan wacht de C64 meer dan 1 seconde op inputs van de server. Een enkele keer kan (WiFi), vaak niet.
- Reageert je Worrior direct op de joystick? Door de input delay zit er ongeveer 67 ms vertraging in; dat hoort zo.

**In het dashboard**, bij de sessie:
- **tick:** beide getallen lopen op en liggen dicht bij elkaar (bijvoorbeeld `1520 / 1518`);
- **msgs/s:** ongeveer 120 (60 per speler);
- **checksums ok:** blijft `0`. Dat is normaal, want de bot stuurt geen checksums.
- **ping** van ERIK: een paar tot enkele tientallen ms.

## Stap 7 – na de game over

- Na de game over komt het titelscherm terug, met `WAITING FOR AN OPPONENT`, en de server ziet dat de sessie klaar is.
- Daarna daagt de bot je opnieuw uit. Druk op **FIRE** om nog een keer te spelen.

## Stap 8 – foutgevallen (optioneel, elk ~1 minuut)

| Test | Wat je doet | Wat er moet gebeuren |
|---|---|---|
| Weigeren | bij `CHALLENGE FROM BOT` op **N** drukken | `NO GAME  BACK TO THE LOBBY`; de bot daagt je 60 s niet opnieuw uit |
| Tegenstander valt weg | tijdens het spel de bot stoppen (Ctrl+C in de tweede terminal) | rand knippert, na ~10 s `YOUR OPPONENT LEFT` en terug naar het titelscherm |
| Server valt weg | in de lobby de server stoppen (Ctrl+C) | na ~13 s `NO ANSWER FROM THE SERVER`; na het herstarten van de server komt de C64 vanzelf terug |

Start de bot daarna opnieuw met het commando uit stap 3.

## Wat ik terug wil horen

- Een foto van de statusregel als iets niet klopt, of als alles goed gaat.
- Een screenshot van het dashboard **tijdens** het spel.
- Het bestand `server.log` uit de map waar je de server startte.
- Je indruk: tempo, reactie van de besturing, hoe vaak de rand knippert.

## Als het niet lukt

| Probleem | Oplossing |
|---|---|
| `NO NETWORK HARDWARE FOUND` | de Command Interface staat uit (zie "Wat je nodig hebt") |
| Blijft hangen op `CALLING THE SERVER` | firewall: sta de server toe (zie `server/README.md`); klopt het IP-adres van de PC? Staat ERIK in het dashboard? |
| `THE NAME IS IN USE` | kies een andere naam, of wacht 10 s |
| `WRONG VERSION` | bouw opnieuw met `build.bat` en zet de nieuwe `wow.d64` op de Ultimate |
| Geen uitdaging | staat de bot in het dashboard? Na een weigering duurt het 60 s |
| Rand knippert steeds | slechte WiFi-verbinding; probeer een netwerkkabel aan de Ultimate of de PC |
