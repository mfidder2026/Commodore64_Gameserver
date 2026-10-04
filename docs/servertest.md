# Servertest: C64 Ultimate via de C64 Game Server

Doel: spelen via de server op je PC, met het lobbyscherm. Je kiest zelf een tegenstander: een van de drie bots die de server zelf start, of een andere C64.

```
C64 Ultimate  ──UDP 6465──►  C64GameServer (PC, met 3 bots)
```

## Wat je nodig hebt

- Je PC en je C64 Ultimate in **hetzelfde netwerk**.
- De nieuwste build. Bouw eerst opnieuw:

  ```bash
  build.bat
  ```

  Zet daarna `build\wow.d64` (of `build\wow.prg`) op de Ultimate.
- Op de Ultimate: **C64 and Cartridge Settings → Command Interface: Enabled**.
- Het IP-adres van je PC. Dat staat straks ook in het servervenster.

## Stap 1 – server starten (PC)

Sluit eerst oude server- en botvensters (Ctrl+C). Open dan een terminal in de projectmap en start:

```bash
server\publish\win-x64\C64GameServer.exe
```

- Het venster toont de adressen waarmee C64's verbinden. Gebruik het adres in je thuisnetwerk (`192.168.1.x`), niet een `100.x` (Tailscale) of `172.x` (WSL).
- Het venster toont ook **Bots: WORLUK, GARWOR, THORWOR**. Een aparte `C64Bot` starten is niet meer nodig.
- Vraagt Windows om firewalltoegang: kies **Privénetwerken** en sta toe.

## Stap 2 – dashboard openen (PC)

Open in je browser:

```
http://localhost:8080/
```

Bij **Spelers** staan de drie bots, met soort **bot**. Laat dit open staan.

## Stap 3 – verbinden vanaf de Ultimate

1. Start `WOW` op de Ultimate. Het setupscherm is zwart met gele en lichtblauwe tekst, zoals het spel.
2. Kies **4** (PLAY VIA A GAME SERVER).
3. **YOUR NAME:** bijvoorbeeld `ERIK` (alleen A–Z en 0–9, max. 8 tekens).
4. **IP OF THE GAME SERVER:** het IP-adres van je PC.
5. Na `CALLING THE SERVER` met puntjes kom je direct in de lobby.

## Stap 4 – de lobby

Het lobbyscherm, in de letters en kleuren van het spel:

```
          WIZARD OF WOR LOBBY

  YOU  ERIK                   4 ONLINE

  WORLUK    BOT    FREE
  GARWOR    BOT    FREE
  THORWOR   BOT    FREE

  up down choose    fire challenge
choose your opponent
```

- Per speler: naam, **PERSON** (geel) of **BOT** (lichtblauw), en **FREE** (groen), **BUSY** (oranje) of **PLAYING** (rood).
- Mensen staan bovenaan, de bots onderaan. De gekozen regel knippert wit/cyaan.
- **Joystick omhoog/omlaag** (of **W/S**) kiest een speler, **FIRE** (of **SPACE**) daagt hem uit.

**Controleren:** staan de drie bots in de lijst, en klopt het aantal bij `ONLINE` (de bots plus jij)?

## Stap 5 – een bot uitdagen

1. Kies **WORLUK** en druk op **FIRE**.
2. De onderste regel toont kort `WAITING FOR WORLUK  N CANCEL`. Een bot accepteert meteen.
3. Het spel start. **Jij bent speler 1 (geel)**: wie uitdaagt krijgt slot 0.
4. In het dashboard staat WORLUK nu op "in game"; in een tweede lobby zou hij op **PLAYING** staan.

Speel een paar dungeons. Let op:
- Loopt het spel soepel? Knippert de rand? Een enkele keer kan (WiFi), vaak niet.
- Ook na de overgangsschermen (GET READY, DOUBLE SCORE) blijft de verbinding staan.

## Stap 6 – na de game over

- Je komt terug in de lobby; WORLUK staat weer op **FREE**.
- Daag gerust een andere bot uit.

## Stap 7 – foutgevallen (optioneel)

| Test | Wat je doet | Wat er moet gebeuren |
|---|---|---|
| Intrekken | FIRE op een bot en meteen **N** | de onderste regel gaat terug naar `CHOOSE YOUR OPPONENT` (een bot accepteert vaak sneller dan je N drukt; dat is ook goed) |
| Bezet | in het dashboard staat iemand op "in game"; kies die in de lobby en druk FIRE | `THAT PLAYER IS NOT FREE` |
| Server valt weg | in de lobby de server stoppen (Ctrl+C) | na ~13 s `NO ANSWER FROM THE SERVER`; na het herstarten van de server komt de C64 vanzelf terug |
| Speler verwijderen | tijdens het spel in het dashboard bij WORLUK op **verwijder** klikken | rand knippert, na ~10 s `YOUR OPPONENT LEFT` en terug in de lobby; WORLUK meldt zich vanzelf opnieuw aan |

## Stap 8 – met twee spelers (als je een tweede C64 hebt)

Een tweede C64 (of VICE op een andere PC) die verbindt, staat bij jou bovenaan als **PERSON**. Daag hem uit; hij ziet `CHALLENGE FROM ERIK  FIRE PLAY  N NO` knipperen en accepteert met FIRE.

## Wat ik terug wil horen

- Een foto van het lobbyscherm en van het setupscherm.
- Werkt kiezen en uitdagen met de joystick (en met W/S + SPACE)?
- Een screenshot van het dashboard **tijdens** het spel.
- Het bestand `server.log` uit de map waar je de server startte.

## Als het niet lukt

| Probleem | Oplossing |
|---|---|
| `NO NETWORK HARDWARE FOUND` | de Command Interface staat uit (zie "Wat je nodig hebt") |
| Blijft hangen op `CALLING THE SERVER` | firewall: sta de server toe (zie `server/README.md`); klopt het IP-adres van de PC? Staat ERIK in het dashboard? |
| `THE NAME IS IN USE` | kies een andere naam, of wacht 10 s |
| Geen bots in de lijst | staat er een oude `server.json` met `"bots": []`? Verwijder die regel of het bestand |
| Lege lijst, onderste regel `CONNECTING TO THE SERVER` | de server antwoordt niet: firewall of IP-adres |
| Rand knippert steeds | slechte WiFi-verbinding; probeer een netwerkkabel aan de Ultimate of de PC |
