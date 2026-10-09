using C64GameServer.Core;
using C64GameServer.Protocol;

namespace C64GameServer.Games;

/// <summary>What a game module may do with its session.</summary>
public interface ISessionContext
{
    DateTime Now { get; }

    /// <summary>Sends a message to one player of the session.</summary>
    void Send(Client to, ReadOnlySpan<byte> message);

    /// <summary>Sends a message to every player except one (null: to all).</summary>
    void SendToOthers(Session session, Client? except, ReadOnlySpan<byte> message);

    /// <summary>Ends the session: every player gets SESSION_END(reason) and goes back to the lobby.</summary>
    void EndSession(Session session, EndReason reason, string why);

    void Log(string category, string text, Client? player = null, Session? session = null);
}

/// <summary>
/// One game on the platform. The core handles connections, lobby, challenges and sessions;
/// a module decides the start parameters and what happens with the game messages ($80-$FF).
/// </summary>
public interface IGameModule
{
    byte GameId { get; }
    string Name { get; }
    byte Version { get; }
    int MinPlayers { get; }
    int MaxPlayers { get; }

    /// <summary>Called once when a session starts; returns the start parameters sent in START (same for all players).</summary>
    byte[] CreateSession(Session session, Random random);

    /// <summary>A game message from a player of the session (byte 1 = session id, already checked by the core).</summary>
    void OnGameMessage(ISessionContext ctx, Session session, Client from, ReadOnlySpan<byte> message);

    /// <summary>Called regularly (about every 20 ms).</summary>
    void OnTick(ISessionContext ctx, Session session) { }

    /// <summary>Extra status fields for the dashboard.</summary>
    IReadOnlyList<(string Name, string Value)> Status(Session session) => [];

    /// <summary>How long a player of a session may stay silent before the server drops him
    /// (a game can allow more, e.g. while the C64 loads the game from disk).</summary>
    TimeSpan IdleTimeout(Session session, Client player, TimeSpan normal) => normal;
}

/// <summary>Transparent relay: every game message goes unchanged to the other players. Needs no code per game.</summary>
public class RelayModule(GameConfig config) : IGameModule
{
    public byte GameId => config.Id;
    public string Name => config.Name;
    public byte Version => config.Version;
    public int MinPlayers => config.MinPlayers;
    public int MaxPlayers => config.MaxPlayers;

    public virtual byte[] CreateSession(Session session, Random random) => [];

    public virtual void OnGameMessage(ISessionContext ctx, Session session, Client from, ReadOnlySpan<byte> message) =>
        ctx.SendToOthers(session, from, message);

    public virtual void OnTick(ISessionContext ctx, Session session) { }

    public virtual IReadOnlyList<(string Name, string Value)> Status(Session session) => [];

    public virtual TimeSpan IdleTimeout(Session session, Client player, TimeSpan normal) => normal;
}

/// <summary>
/// Wizard of Wor: the lockstep runs on the C64s. The server relays INPUT unchanged and checks the state
/// checksums both players put into their INPUT packets.
/// INPUT: $80, session, newest tick (16), checksum tick (16, $FFFF = none), checksum (16), 16 inputs.
/// </summary>
public sealed class WizardOfWorModule(GameConfig config) : RelayModule(config)
{
    public const byte Input = 0x80;
    public const int InputLength = 24;
    public const int ChecksumHistory = 16;

    private readonly int _inputDelay = config.Settings.GetValueOrDefault("inputDelay", 4);
    private readonly int _tickRate = config.Settings.GetValueOrDefault("tickRate", 60);
    private readonly int _inputTimeout = config.Settings.GetValueOrDefault("inputTimeoutSeconds", 10);

    private sealed class State
    {
        public byte SeedRandom;
        public byte SeedRnd;
        public int[] NewestTick = [];
        public Dictionary<ushort, ushort>[] Checksums = [];
        public int ChecksumsCompared;
        public ushort? LastCompared;
        public DateTime[] LastInput = [];
    }

    public override byte[] CreateSession(Session session, Random random)
    {
        var st = new State
        {
            SeedRandom = (byte)random.Next(256),
            SeedRnd = (byte)(random.Next(255) + 1), // an LFSR state of 0 would stay 0
            NewestTick = new int[session.Players.Count],
            Checksums = session.Players.Select(_ => new Dictionary<ushort, ushort>()).ToArray(),
            LastInput = new DateTime[session.Players.Count],
        };
        Array.Fill(st.NewestTick, -1);
        session.ModuleState = st;
        return [st.SeedRandom, st.SeedRnd, (byte)_inputDelay, (byte)_tickRate];
    }

    public override void OnGameMessage(ISessionContext ctx, Session session, Client from, ReadOnlySpan<byte> m)
    {
        if (m[0] != Input || m.Length != InputLength)
        {
            ctx.Log("game", $"unknown or malformed message {MsgType.Name(m[0])} ({m.Length} bytes) ignored", from, session);
            return;
        }
        ctx.SendToOthers(session, from, m);

        var st = (State)session.ModuleState!;
        int slot = session.SlotOf(from);
        int newest = Messages.U16(m, 2);
        st.NewestTick[slot] = newest;
        st.LastInput[slot] = ctx.Now;

        ushort chkTick = Messages.U16(m, 4);
        if (chkTick == 0xFFFF) return;
        ushort chk = Messages.U16(m, 6);
        var mine = st.Checksums[slot];
        if (mine.ContainsKey(chkTick)) return;
        mine[chkTick] = chk;
        if (mine.Count > ChecksumHistory)
            mine.Remove(mine.Keys.Min());

        // compare with every other player that already sent a checksum for this tick
        for (int other = 0; other < st.Checksums.Length; other++)
        {
            if (other == slot || !st.Checksums[other].TryGetValue(chkTick, out var theirs)) continue;
            if (theirs != chk)
            {
                ctx.EndSession(session, EndReason.Desync,
                    $"desync at tick {chkTick}: slot {slot} {chk:X4}, slot {other} {theirs:X4}");
                return;
            }
            st.ChecksumsCompared++;
            st.LastCompared = chkTick;
        }
    }

    public override void OnTick(ISessionContext ctx, Session session)
    {
        // a player that sends no input for inputTimeoutSeconds is gone, even if it still answers pings
        if (session.ModuleState is not State st) return;
        for (int slot = 0; slot < st.LastInput.Length; slot++)
        {
            if (st.LastInput[slot] == default) st.LastInput[slot] = ctx.Now; // the clock starts with the session
            if (ctx.Now - st.LastInput[slot] <= TimeSpan.FromSeconds(_inputTimeout)) continue;
            var silent = session.Players[slot];
            ctx.SendToOthers(session, silent, Messages.OpponentLeft(session.Id));
            ctx.EndSession(session, EndReason.Timeout, $"{silent.Nick} sent no input for {_inputTimeout} s");
            return;
        }
    }

    public override IReadOnlyList<(string Name, string Value)> Status(Session session)
    {
        if (session.ModuleState is not State st) return [];
        return
        [
            ("tick", string.Join(" / ", st.NewestTick.Select(t => t < 0 ? "-" : t.ToString()))),
            ("checksums ok", st.LastCompared is { } t ? $"{st.ChecksumsCompared} (last tick {t})" : "0"),
            ("seeds", $"{st.SeedRandom:X2} {st.SeedRnd:X2}"),
            ("input delay", _inputDelay.ToString()),
        ];
    }
}

/// <summary>
/// Bubble Bobble (BB-LAN): lockstep on the C64s like Wizard of Wor. After START the C64 loads the game
/// from disk (up to a minute on a 1541), so a player may stay silent for loadTimeoutSeconds until his
/// first INPUT; after that the normal idle and input timeouts apply.
/// START params: seed lo, seed hi, input delay (1-4).
/// INPUT: $80, session, newest tick (16), checksum tick (16, $FFFF = none), checksum (16), 8 inputs.
/// </summary>
public sealed class BubbleBobbleModule(GameConfig config) : RelayModule(config)
{
    public const byte Input = 0x80;
    public const int InputLength = 16;
    public const int ChecksumHistory = 16;

    private readonly int _inputDelay = Math.Clamp(config.Settings.GetValueOrDefault("inputDelay", 2), 1, 4);

    // a WiC64 spends a lot of C64 time per transfer: a longer delay lets one poll bring several ticks
    private readonly int _inputDelayWiC64 = Math.Clamp(config.Settings.GetValueOrDefault("inputDelayWiC64", 4), 1, 4);
    private readonly int _inputTimeout = config.Settings.GetValueOrDefault("inputTimeoutSeconds", 10);
    private readonly int _loadTimeout = config.Settings.GetValueOrDefault("loadTimeoutSeconds", 150);

    private sealed class State
    {
        public ushort Seed;
        public int[] NewestTick = [];
        public Dictionary<ushort, ushort>[] Checksums = [];
        public int ChecksumsCompared;
        public ushort? LastCompared;
        public DateTime[] LastInput = [];
        public DateTime Started;
        public int InputDelay;
    }

    public override byte[] CreateSession(Session session, Random random)
    {
        var st = new State
        {
            Seed = (ushort)(random.Next(0xFFFF) + 1), // a PRNG state of 0 would stay 0
            NewestTick = new int[session.Players.Count],
            Checksums = session.Players.Select(_ => new Dictionary<ushort, ushort>()).ToArray(),
            LastInput = new DateTime[session.Players.Count],
        };
        Array.Fill(st.NewestTick, -1);
        st.InputDelay = session.Players.Any(p => p.EndPoint.Address.IsIPv4MappedToIPv6) ? _inputDelayWiC64 : _inputDelay;
        session.ModuleState = st;
        return [(byte)st.Seed, (byte)(st.Seed >> 8), (byte)st.InputDelay];
    }

    public override TimeSpan IdleTimeout(Session session, Client player, TimeSpan normal)
    {
        if (session.ModuleState is not State st) return normal;
        int slot = session.SlotOf(player);
        return slot >= 0 && st.NewestTick[slot] < 0
            ? TimeSpan.FromSeconds(Math.Max(_loadTimeout, normal.TotalSeconds))
            : normal;
    }

    public override void OnGameMessage(ISessionContext ctx, Session session, Client from, ReadOnlySpan<byte> m)
    {
        if (m[0] != Input || m.Length < InputLength)
        {
            ctx.Log("game", $"unknown or malformed message {MsgType.Name(m[0])} ({m.Length} bytes) ignored", from, session);
            return;
        }
        m = m[..InputLength]; // raw Ethernet frames can carry padding
        ctx.SendToOthers(session, from, m);

        var st = (State)session.ModuleState!;
        int slot = session.SlotOf(from);
        st.NewestTick[slot] = Messages.U16(m, 2);
        st.LastInput[slot] = ctx.Now;

        ushort chkTick = Messages.U16(m, 4);
        if (chkTick == 0xFFFF) return;
        ushort chk = Messages.U16(m, 6);
        var mine = st.Checksums[slot];
        if (mine.ContainsKey(chkTick)) return;
        mine[chkTick] = chk;
        if (mine.Count > ChecksumHistory)
            mine.Remove(mine.Keys.Min());
        for (int other = 0; other < st.Checksums.Length; other++)
        {
            if (other == slot || !st.Checksums[other].TryGetValue(chkTick, out var theirs)) continue;
            if (theirs != chk)
            {
                ctx.EndSession(session, EndReason.Desync,
                    $"desync at tick {chkTick}: slot {slot} {chk:X4}, slot {other} {theirs:X4}");
                return;
            }
            st.ChecksumsCompared++;
            st.LastCompared = chkTick;
        }
    }

    public override void OnTick(ISessionContext ctx, Session session)
    {
        if (session.ModuleState is not State st) return;
        if (st.Started == default) st.Started = ctx.Now;
        for (int slot = 0; slot < st.LastInput.Length; slot++)
        {
            bool loading = st.NewestTick[slot] < 0;
            var since = loading ? st.Started : st.LastInput[slot];
            var limit = TimeSpan.FromSeconds(loading ? _loadTimeout : _inputTimeout);
            if (ctx.Now - since <= limit) continue;
            var silent = session.Players[slot];
            ctx.SendToOthers(session, silent, Messages.OpponentLeft(session.Id));
            ctx.EndSession(session, EndReason.Timeout,
                loading ? $"{silent.Nick} did not start the game within {_loadTimeout} s"
                        : $"{silent.Nick} sent no input for {_inputTimeout} s");
            return;
        }
    }

    public override IReadOnlyList<(string Name, string Value)> Status(Session session)
    {
        if (session.ModuleState is not State st) return [];
        return
        [
            ("tick", string.Join(" / ", st.NewestTick.Select(t => t < 0 ? "loading" : t.ToString()))),
            ("checksums ok", st.LastCompared is { } t ? $"{st.ChecksumsCompared} (last tick {t})" : "0"),
            ("seed", $"{st.Seed:X4}"),
            ("input delay", st.InputDelay.ToString()),
        ];
    }
}

/// <summary>The registered games by id.</summary>
public sealed class GameRegistry
{
    private readonly Dictionary<byte, IGameModule> _games = [];

    public void Register(IGameModule module) => _games[module.GameId] = module;

    public IGameModule? Get(byte id) => _games.GetValueOrDefault(id);

    public IEnumerable<IGameModule> All => _games.Values;

    /// <summary>Creates the modules from server.json: "wizardofwor" or "relay" (a new relay game needs only an entry there).</summary>
    public static GameRegistry FromConfig(ServerConfig config)
    {
        var r = new GameRegistry();
        foreach (var g in config.Games)
        {
            IGameModule module = g.Module.ToLowerInvariant() switch
            {
                "wizardofwor" => new WizardOfWorModule(g),
                "bubblebobble" => new BubbleBobbleModule(g),
                "relay" => new RelayModule(g),
                _ => throw new InvalidDataException($"server.json: unknown module '{g.Module}' for game {g.Id}"),
            };
            r.Register(module);
        }
        return r;
    }
}
