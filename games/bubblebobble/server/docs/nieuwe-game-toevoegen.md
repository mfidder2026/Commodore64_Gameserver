# Een nieuwe game toevoegen

De kern (verbindingen, lobby, uitdagen, sessies, time-outs) is voor elke game gelijk. Een game is een **module** met een `game_id`. Er zijn twee soorten.

## 1. Transparante relay: alleen configuratie

Heeft je game genoeg aan "wat de ene speler stuurt, krijgt de andere ongewijzigd", dan hoef je geen code te schrijven. Voeg een regel toe aan `games` in `server.json`:

```json
{ "id": 3, "name": "Mijn game", "module": "relay", "version": 1, "minPlayers": 2, "maxPlayers": 2 }
```

Start de server opnieuw. Dat is alles.

Regels voor de C64-kant:

- `HELLO` met game-id 3 en versie 1;
- game-berichten gebruiken typen `$80-$FF`;
- **byte 1 van elk game-bericht is het sessie-id** uit `START`. De server gooit berichten met een verkeerd sessie-id weg;
- `START` bevat geen startparameters (lengte 0). Spreek zelf af wie wat doet op basis van het spelerslot;
- aan het eind: `SESSION_END` met reden 1.

Het voorbeeld "Relay demo" (game 2) staat al in de standaardconfiguratie. De test `A_relay_game_from_the_configuration_needs_no_code` laat zien dat het werkt.

## 2. Een module met serverlogica

Wil de server zelf iets met de speldata doen (controleren, samenvoegen, startparameters kiezen), schrijf dan een module.

1. Maak een klasse in `src/C64GameServer.Core/Games/`. Erf van `RelayModule` (dan heb je het doorsturen al) of implementeer `IGameModule`:

   ```csharp
   public sealed class MijnGameModule(GameConfig config) : RelayModule(config)
   {
       // startparameters voor START (voor alle spelers gelijk)
       public override byte[] CreateSession(Session session, Random random) =>
           [(byte)random.Next(256)];

       // een game-bericht van een speler ($80-$FF, sessie-id al gecontroleerd)
       public override void OnGameMessage(ISessionContext ctx, Session session, Client from, ReadOnlySpan<byte> m)
       {
           ctx.SendToOthers(session, from, m);  // doorsturen
           // ... eigen controles; bij een fout:
           // ctx.EndSession(session, EndReason.Desync, "reden");
       }

       // regelmatig (~20 ms), bijvoorbeeld voor time-outs
       public override void OnTick(ISessionContext ctx, Session session) { }

       // extra velden voor het dashboard
       public override IReadOnlyList<(string Name, string Value)> Status(Session session) =>
           [("stand", "3-1")];
   }
   ```

2. Registreer de module in `GameRegistry.FromConfig` (`src/C64GameServer.Core/Games/GameModules.cs`):

   ```csharp
   "mijngame" => new MijnGameModule(g),
   ```

3. Voeg de game toe aan `server.json` met `"module": "mijngame"`. Eigen instellingen gaan in `settings`:

   ```json
   { "id": 4, "name": "Mijn game", "module": "mijngame", "version": 1, "settings": { "rondes": 3 } }
   ```

   In de module: `config.Settings.GetValueOrDefault("rondes", 3)`.

4. Schrijf tests naar het voorbeeld van `WizardOfWorTests` in `tests/C64GameServer.Tests/ServerTests.cs`. De `Harness` heeft een nepklok en een nep-transport, dus je test zonder netwerk.

5. Beschrijf de game-berichten in `docs/protocol.md`.

Het dashboard toont de nieuwe game en de velden uit `Status()` zonder verdere aanpassingen.
