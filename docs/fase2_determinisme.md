# Fase 2 – deterministisch en tick-based

Doel: twee C64's die dezelfde inputs krijgen, moeten exact hetzelfde spel spelen, ongeacht PAL/NTSC, CPU-belasting of het moment waarop een interrupt valt. Dat is de basis voor lockstep-netcode.

## Waarom het origineel niet deterministisch is

| Bron | Waar | Probleem |
|---|---|---|
| Spellogica in de raster-IRQ | `irq_handler` | `random_number`, timers van spelers en kogels, onzichtbaarheid, launch, warp doors: ze lopen op het ritme van het beeld en onderbreken de hoofdlus op een willekeurig moment |
| Monstersnelheid | de drie gameplay-loops | monsters bewegen per loop-doorgang, en de loop draait zo snel als de CPU toelaat |
| Rasterlijn als toeval | 7× `LDA VIC_D012` | de waarde hangt af van timing |
| Wachten op de IRQ | `select_dungeon_layout` | de lus wacht tot de IRQ `random_number` verandert |

## Hoe het nu werkt (PRG-versie)

- **Sessie** = van "fire op het titelscherm" (`session_start`) tot het titelscherm weer verschijnt (`session_end`).
- Tijdens een sessie doet de raster-IRQ (`irq_vector`) **alleen geluid en muziek**.
- **Tick** (`tick`): wachten tot het tijd is (60 per seconde, via de CIA2-cycle-teller), inputs ophalen, en daarna de complete frame-logica uit de IRQ (`tick_frame_logic`, een één-op-één kopie).
- **Passes per tick** volgen een kostenmodel. Elke actor-pass "kost" wat dat soort pass in het origineel op een NTSC-C64 kostte. Een tick heeft het budget van één NTSC-frame (17045 cycles). Zo blijft het tempo van het origineel behouden, inclusief het effect dat monsters sneller worden als er minder over zijn.
- `random_number` blijft de framecounter van het origineel, maar loopt nu precies één keer per tick af. Rasterlijn-reads zijn vervangen door een LFSR (`rnd_d012`).
- Alle wijzigingen in het originele 16K-image zijn patches van **exact dezelfde grootte**. De build meldt nu 27 gepatchte gebieden; de cartridge-build blijft byte voor byte gelijk aan het origineel.

## Metingen

### Kosten per actor-pass in het origineel (NTSC, `tools/profile_run.py`)

| Categorie | Gem. cycles | Aandeel tijd |
|---|---|---|
| dood | 953 | 22% |
| sterft | 782 | 1,5% |
| monster stil | 1725 | 27% |
| monster beweegt | 4562 | 20% |
| speler stil | 1699 | 5,5% |
| speler beweegt | 3544 | 24% |

Gemiddeld ~8,3 passes per frame: ongeveer één ronde langs alle 8 actors.

### Determinisme (`tools/dettest.py`)

Twee VICE-instanties (PAL en NTSC, warp) spelen met een bot waarvan de input alleen van het ticknummer afhangt. Elke 32 ticks wordt een checksum van de spelstate gelogd: scherm, sprites, zero page, page 2.

| Build | Resultaat |
|---|---|
| `wow_dettest` | identiek, 4× herhaald, telkens 400–500 s spel en meerdere sessies |
| `wow_dettest_fast` (Worluk na de eerste kill) | identiek, 450–530 s spel, met 54.000 Worluk- en 26.000 Wizard-passes |

### Snelheid (`tools/speedtest.py`)

| Machine | 60 ticks/s gehaald | Vrij per tick |
|---|---|---|
| PAL | ja | ~7% (1155 van 16421 cycles) |
| NTSC | ja | ~8% (1350 van 17045 cycles) |

De marge is krap. De netwerkcode moet zuinig zijn, en zo nodig wordt de tick rate instelbaar.

## Bekende verschillen met het origineel

1. **Timers staan stil tijdens overgangsschermen** (GET READY, DOUBLE SCORE). Het origineel liet bijvoorbeeld de onzichtbaarheidstimers doorlopen. Gevolg: monsters worden iets later onzichtbaar na de start van een dungeon. Dit kan desgewenst worden gecompenseerd met een vaste voorsprong.
2. **Frame-logica draait tussen twee passes** in plaats van midden in een pass. Het effect daarvan is niet zichtbaar.
3. **Spelers en monsters hebben op PAL de NTSC-snelheid**, zoals het spel bedoeld was. Het origineel liep op PAL voor spelers trager. De muziek speelt zoals het origineel op die machine.
4. **Rasterlijn-toeval is vervangen door een LFSR.** Statistisch maakt dat geen verschil.
5. **De vertragingslus voor dode actors is ingekort**: het tempo komt nu uit het kostenmodel.
6. **Pauze (RUN/STOP)** werkt lokaal. In netwerkmodus wordt het een netwerkbericht (fase 4).

## Tests draaien

```bash
python tools/build.py dettest
```

```bash
python tools/dettest.py 30
```

```bash
python tools/dettest.py 30 wow_dettest_fast
```

```bash
python tools/build.py speedtest
```

```bash
python tools/speedtest.py 30 pal
```

```bash
python tools/build.py profile
```

```bash
python tools/profile_run.py 15 ntsc
```
