using System.Net;
using C64GameServer.Games;
using C64GameServer.Protocol;

namespace C64GameServer.Core;

/// <summary>
/// The game independent core: clients, lobby, challenges, sessions, keepalive and timeouts.
/// Not thread safe: the host calls HandleDatagram and Tick from one thread (or under a lock).
/// Time is passed in, so tests can use a fake clock.
/// </summary>
public sealed class ServerCore
{
    private readonly ServerConfig _config;
    private readonly ITransport _transport;
    private readonly GameRegistry _games;
    private readonly EventLog _log;
    private readonly Random _random;

    private readonly Dictionary<IPEndPoint, Client> _clients = [];
    private readonly List<Challenge> _challenges = [];
    private readonly List<Session> _sessions = [];
    private readonly Dictionary<(string, string), DateTime> _cooldown = [];

    private byte _nextClientId, _nextChallengeId, _nextSessionId;
    private ushort _nextPingToken;
    private DateTime _now;
    private bool _playersChanged; // the lobby lists must be sent again

    public DateTime StartedAt { get; }
    public long UnknownDatagrams { get; private set; }
    public long InvalidDatagrams { get; private set; }

    public ServerCore(ServerConfig config, ITransport transport, GameRegistry games, EventLog log, DateTime now,
        Random? random = null)
    {
        _config = config;
        _transport = transport;
        _games = games;
        _log = log;
        _random = random ?? new Random();
        StartedAt = _now = now;
    }

    public IReadOnlyCollection<Client> Clients => _clients.Values;
    public IReadOnlyList<Challenge> Challenges => _challenges;
    public IReadOnlyList<Session> Sessions => _sessions;
    public GameRegistry Games => _games;
    public EventLog Log => _log;

    // ------------------------------------------------------------------ input

    public void HandleDatagram(IPEndPoint from, ReadOnlySpan<byte> data, DateTime now)
    {
        _now = now;
        if (data.Length == 0 || data.Length > ProtocolConst.MaxMessage)
        {
            InvalidDatagrams++;
            return;
        }
        byte type = data[0];
        if (type == MsgType.Hello)
        {
            HandleHello(from, data);
            return;
        }
        if (!_clients.TryGetValue(from, out var client))
        {
            UnknownDatagrams++; // not (or no longer) connected: the C64 has to say HELLO again
            return;
        }
        client.LastSeen = now;
        client.MessagesIn++;
        client.BytesIn += data.Length;

        switch (type)
        {
            case MsgType.Ping when data.Length == 3:
                Send(client, Messages.Pong(Messages.U16(data, 1)));
                break;
            case MsgType.Pong when data.Length == 3:
                if (Messages.U16(data, 1) == client.PingToken)
                    client.PingMs = (now - client.PingSent).TotalMilliseconds;
                break;
            case MsgType.Accept when data.Length == 2:
                HandleAnswer(client, data[1], accept: true);
                break;
            case MsgType.Decline when data.Length == 2:
                HandleAnswer(client, data[1], accept: false);
                break;
            case MsgType.Invite when data.Length == 3:
                HandleInvite(client, data[1], data[2]);
                break;
            case MsgType.StartAck when data.Length == 2:
                if (client.Session is { } s && s.Id == data[1] && s.StartAcked.Add(client))
                    LogEvent("session", $"{client.Nick} confirmed the start", client, s);
                break;
            case MsgType.SessionEnd when data.Length == 3:
                if (client.Session is { } se && se.Id == data[1])
                {
                    var reason = data[2] == (byte)EndReason.Finished ? EndReason.Finished : EndReason.PlayerQuit;
                    EndSession(se, reason, $"{client.Nick}: {(reason == EndReason.Finished ? "game over" : "quit")}");
                }
                break;
            case MsgType.Bye when data.Length == 1:
                RemoveClient(client, "said BYE");
                break;
            default:
                if (MsgType.IsGame(type))
                    HandleGameMessage(client, data);
                else
                {
                    InvalidDatagrams++;
                    LogEvent("error", $"unexpected {MsgType.Name(type)} ({data.Length} bytes) from {client.Nick}", client);
                }
                break;
        }
    }

    private void HandleHello(IPEndPoint from, ReadOnlySpan<byte> data)
    {
        var hello = Messages.ParseHello(data);
        if (hello == null)
        {
            InvalidDatagrams++;
            return;
        }
        if (hello.ProtocolVersion != ProtocolConst.Version)
        {
            Reject(from, RejectReason.Version, $"protocol version {hello.ProtocolVersion}");
            return;
        }
        var game = _games.Get(hello.GameId);
        if (game == null)
        {
            Reject(from, RejectReason.UnknownGame, $"unknown game {hello.GameId}");
            return;
        }
        if (hello.GameVersion != game.Version)
        {
            Reject(from, RejectReason.Version, $"{game.Name} version {hello.GameVersion}, server has {game.Version}");
            return;
        }
        if (!Messages.IsValidNick(hello.Nick))
        {
            Reject(from, RejectReason.BadName, "invalid nickname");
            return;
        }

        if (_clients.TryGetValue(from, out var existing))
        {
            if (existing.Nick == hello.Nick && existing.GameId == hello.GameId && existing.State != ClientState.InSession)
            {
                existing.LastSeen = _now;
                Send(existing, Messages.Welcome(existing.Id)); // the WELCOME got lost: repeat it
                return;
            }
            RemoveClient(existing, "said HELLO again (restarted)");
        }

        // the same nickname from the same machine with a new port (the C64 opened a new socket): take over
        var sameNick = _clients.Values.FirstOrDefault(c => c.Nick == hello.Nick);
        if (sameNick != null)
        {
            if (!sameNick.EndPoint.Address.Equals(from.Address))
            {
                Reject(from, RejectReason.NameInUse, $"name {hello.Nick} is in use");
                return;
            }
            RemoveClient(sameNick, "reconnected from a new port");
        }
        if (_clients.Count >= _config.MaxClients)
        {
            Reject(from, RejectReason.ServerFull, "server full");
            return;
        }

        var client = new Client
        {
            Id = NextId(ref _nextClientId, _clients.Values.Select(c => c.Id)),
            EndPoint = from,
            Nick = hello.Nick,
            GameId = hello.GameId,
            GameVersion = hello.GameVersion,
            IsBot = hello.Bot,
            Connected = _now,
            LastSeen = _now,
            LobbySince = _now,
            LastLobby = DateTime.MinValue,
        };
        _clients[from] = client;
        _playersChanged = true;
        Send(client, Messages.Welcome(client.Id));
        LogEvent("connect", $"{client.Nick} ({from}){(client.IsBot ? " (bot)" : "")} joined the lobby of {game.Name}", client);
    }

    private void Reject(IPEndPoint to, RejectReason reason, string why)
    {
        _transport.Send(to, Messages.Reject(reason));
        LogEvent("reject", $"{to}: {why}");
    }

    private void HandleAnswer(Client client, byte challengeId, bool accept)
    {
        var ch = client.Challenge;
        if (ch == null) return;
        if (challengeId == 0 && !accept && ch.Accepted.Contains(client))
        {
            // DECLINE with id 0: the player withdraws the invitation he sent
            LogEvent("challenge", $"{client.Nick} withdrew the challenge", client);
            CancelChallenge(ch, CancelReason.Declined, cooldown: false);
            return;
        }
        if (ch.Id != challengeId) return; // an old or repeated answer
        if (!accept)
        {
            LogEvent("challenge", $"{client.Nick} declined", client);
            CancelChallenge(ch, CancelReason.Declined, cooldown: true);
            return;
        }
        if (!ch.Accepted.Add(client)) return;
        LogEvent("challenge", $"{client.Nick} accepted", client);
        if (ch.Accepted.Count == ch.Players.Count)
            StartSession(ch);
    }

    private void HandleInvite(Client client, byte targetId, byte seq)
    {
        if (seq == client.LastInviteSeq) return; // a repeated INVITE (the C64 repeats it until it sees the outcome)
        client.LastInviteSeq = seq;
        var target = _clients.Values.FirstOrDefault(c => c.Id == targetId);
        var game = _games.Get(client.GameId)!;
        if (client.State != ClientState.Lobby || target == null || target == client || target.GameId != client.GameId ||
            target.State != ClientState.Lobby || game.MinPlayers != 2)
        {
            LogEvent("challenge", $"{client.Nick} invited {target?.Nick ?? "#" + targetId}: not available", client);
            Send(client, Messages.ChallengeCancelled(0, CancelReason.NotAvailable));
            return;
        }
        LogEvent("challenge", $"{client.Nick} invites {target.Nick}{(target.IsBot ? " (bot)" : "")}", client);
        CreateChallenge(game, [client, target], acceptedBy: client);
    }

    private void HandleGameMessage(Client client, ReadOnlySpan<byte> data)
    {
        var s = client.Session;
        if (s == null || data.Length < 2 || data[1] != s.Id)
        {
            InvalidDatagrams++; // a game message outside its session (e.g. still from the previous one)
            return;
        }
        s.StartAcked.Add(client); // game data counts as a start confirmation
        s.MessagesRelayed++;
        s.BytesRelayed += data.Length;
        s.Recent.AddLast((_now, client.Nick, data.ToArray()));
        while (s.Recent.Count > 50) s.Recent.RemoveFirst();
        var module = _games.Get(s.GameId)!;
        module.OnGameMessage(new Context(this), s, client, data);
    }

    // ------------------------------------------------------------------ time

    public void Tick(DateTime now)
    {
        _now = now;
        var idle = TimeSpan.FromSeconds(_config.IdleTimeoutSeconds);
        foreach (var c in _clients.Values.ToList())
        {
            var limit = c.Session is { } cs && _games.Get(cs.GameId) is { } gm ? gm.IdleTimeout(cs, c, idle) : idle;
            if (now - c.LastSeen > limit)
                RemoveClient(c, $"nothing heard for {limit.TotalSeconds:0} s");
        }

        foreach (var c in _clients.Values)
        {
            if (now - c.LastPing >= TimeSpan.FromMilliseconds(_config.PingIntervalMs))
            {
                c.LastPing = now;
                c.PingToken = ++_nextPingToken;
                c.PingSent = now;
                Send(c, Messages.Ping(c.PingToken));
            }
            if (c.State == ClientState.Lobby && now - c.LastLobby >= TimeSpan.FromMilliseconds(_config.LobbyIntervalMs))
            {
                c.LastLobby = now;
                int waiting = _clients.Values.Count(o => o.GameId == c.GameId && o.State == ClientState.Lobby);
                Send(c, Messages.Lobby((byte)Math.Min(waiting, 255)));
            }
        }
        SendPlayerLists(now);

        foreach (var ch in _challenges.ToList())
        {
            if (now - ch.Created > TimeSpan.FromSeconds(_config.ChallengeTimeoutSeconds))
            {
                LogEvent("challenge", $"no answer within {_config.ChallengeTimeoutSeconds:0} s");
                CancelChallenge(ch, CancelReason.Timeout, cooldown: true);
            }
            else if (now - ch.LastSent >= TimeSpan.FromMilliseconds(_config.ChallengeResendMs))
                SendChallenge(ch);
        }

        foreach (var s in _sessions.ToList())
        {
            if (s.StartAcked.Count < s.Players.Count)
            {
                if (now - s.Started > TimeSpan.FromSeconds(_config.StartTimeoutSeconds))
                {
                    EndSession(s, EndReason.Timeout, "the start was not confirmed in time");
                    continue;
                }
                if (now - s.LastStartSent >= TimeSpan.FromMilliseconds(_config.StartResendMs))
                    SendStart(s, onlyUnconfirmed: true);
            }
            _games.Get(s.GameId)?.OnTick(new Context(this), s);
        }

        foreach (var key in _cooldown.Where(kv => kv.Value < now).Select(kv => kv.Key).ToList())
            _cooldown.Remove(key);

        if (_config.AutoPair) PairPlayers();
    }

    // ------------------------------------------------------------------ lobby list

    /// <summary>
    /// Everyone who is not playing gets the list of the other players of his game: soon after a change
    /// (at most every 200 ms) and else every second (UDP: a lost list is replaced by the next one).
    /// </summary>
    private void SendPlayerLists(DateTime now)
    {
        bool changed = _playersChanged;
        _playersChanged = false;
        foreach (var c in _clients.Values.Where(c => c.State != ClientState.InSession && !c.IsBot))
        {
            if (now - c.LastPlayers < TimeSpan.FromMilliseconds(changed ? 200 : 1000))
            {
                if (changed) _playersChanged = true; // send it as soon as the 200 ms are over
                continue;
            }
            c.LastPlayers = now;
            var list = PlayerList(c);
            const int per = ProtocolConst.PlayersPerMessage;
            int pages = Math.Max(1, (list.Count + per - 1) / per);
            for (int i = 0; i < pages; i++)
                Send(c, Messages.Players(list.Count, i * per, list.Skip(i * per).Take(per).ToList()));
        }
    }

    /// <summary>The other players of the client's game for its lobby screen: people first, then the bots.</summary>
    public List<PlayerEntry> PlayerList(Client c) =>
        _clients.Values.Where(o => o != c && o.GameId == c.GameId)
            .OrderBy(o => o.IsBot).ThenBy(o => o.Connected).ThenBy(o => o.Id)
            .Take(ProtocolConst.MaxListed)
            .Select(o => new PlayerEntry(o.Id, (byte)((o.IsBot ? PlayerFlags.Bot : 0) | o.State switch
            {
                ClientState.Lobby => PlayerFlags.Free,
                ClientState.Challenged => PlayerFlags.Busy,
                _ => PlayerFlags.Playing,
            }), o.Nick))
            .ToList();

    private void PairPlayers()
    {
        foreach (var game in _games.All)
        {
            var waiting = _clients.Values
                .Where(c => c.GameId == game.GameId && c.State == ClientState.Lobby)
                .OrderBy(c => c.LobbySince).ThenBy(c => c.Id).ToList();
            while (waiting.Count >= game.MinPlayers)
            {
                var group = FindGroup(waiting, game.MinPlayers);
                if (group == null) break;
                foreach (var c in group) waiting.Remove(c);
                CreateChallenge(game, group);
            }
        }
    }

    private List<Client>? FindGroup(List<Client> waiting, int size)
    {
        // greedy in lobby order: the first players that are not in cooldown with each other
        var group = new List<Client>();
        foreach (var c in waiting)
        {
            if (group.All(g => !InCooldown(g, c))) group.Add(c);
            if (group.Count == size) return group;
        }
        return null;
    }

    private static (string, string) PairKey(Client a, Client b) =>
        string.CompareOrdinal(a.Nick, b.Nick) < 0 ? (a.Nick, b.Nick) : (b.Nick, a.Nick);

    private bool InCooldown(Client a, Client b) => _cooldown.TryGetValue(PairKey(a, b), out var until) && until > _now;

    // ------------------------------------------------------------------ challenges and sessions

    private Challenge CreateChallenge(IGameModule game, List<Client> players, Client? acceptedBy = null)
    {
        var ch = new Challenge
        {
            Id = NextId(ref _nextChallengeId, _challenges.Select(c => c.Id)),
            GameId = game.GameId,
            Players = players,
            Created = _now,
        };
        foreach (var p in players)
        {
            p.State = ClientState.Challenged;
            p.Challenge = ch;
        }
        if (acceptedBy != null) ch.Accepted.Add(acceptedBy); // the inviting player
        _challenges.Add(ch);
        _playersChanged = true;
        LogEvent("challenge", $"{game.Name}: {string.Join(" vs ", players.Select(p => p.Nick))}");
        SendChallenge(ch);
        return ch;
    }

    private void SendChallenge(Challenge ch)
    {
        ch.LastSent = _now;
        foreach (var p in ch.Players.Where(p => !ch.Accepted.Contains(p)))
        {
            var opponents = ch.Players.Where(o => o != p).Select(o => o.Nick).ToList();
            string shown = opponents.Count == 1 ? opponents[0] : $"{opponents.Count} PLAYERS";
            Send(p, Messages.Challenge(ch.Id, shown));
        }
    }

    private void CancelChallenge(Challenge ch, CancelReason reason, bool cooldown)
    {
        _challenges.Remove(ch);
        _playersChanged = true;
        foreach (var p in ch.Players)
        {
            p.Challenge = null;
            if (_clients.ContainsKey(p.EndPoint))
            {
                p.State = ClientState.Lobby;
                p.LobbySince = _now;
                Send(p, Messages.ChallengeCancelled(ch.Id, reason));
            }
        }
        if (cooldown)
        {
            var until = _now + TimeSpan.FromSeconds(_config.DeclineCooldownSeconds);
            for (int i = 0; i < ch.Players.Count; i++)
                for (int j = i + 1; j < ch.Players.Count; j++)
                    _cooldown[PairKey(ch.Players[i], ch.Players[j])] = until;
        }
    }

    private void StartSession(Challenge ch)
    {
        _challenges.Remove(ch);
        _playersChanged = true;
        var game = _games.Get(ch.GameId)!;
        var s = new Session
        {
            Id = NextId(ref _nextSessionId, _sessions.Select(x => x.Id)),
            GameId = ch.GameId,
            Players = ch.Players,
            Started = _now,
        };
        s.StartParameters = game.CreateSession(s, _random);
        foreach (var p in s.Players)
        {
            p.Challenge = null;
            p.Session = s;
            p.State = ClientState.InSession;
        }
        _sessions.Add(s);
        LogEvent("session", $"session {s.Id} started: {game.Name}, {string.Join(" vs ", s.Players.Select(p => p.Nick))}",
            session: s);
        SendStart(s, onlyUnconfirmed: false);
    }

    private void SendStart(Session s, bool onlyUnconfirmed)
    {
        s.LastStartSent = _now;
        for (int slot = 0; slot < s.Players.Count; slot++)
        {
            var p = s.Players[slot];
            if (onlyUnconfirmed && s.StartAcked.Contains(p)) continue;
            Send(p, Messages.Start(s.Id, (byte)slot, (byte)s.Players.Count, s.StartParameters));
        }
    }

    /// <summary>Ends a session: every player still connected gets SESSION_END and goes back to the lobby.</summary>
    public void EndSession(Session s, EndReason reason, string why)
    {
        if (!_sessions.Remove(s)) return;
        _playersChanged = true;
        foreach (var p in s.Players)
        {
            if (p.Session != s) continue;
            p.Session = null;
            if (!_clients.ContainsKey(p.EndPoint)) continue;
            p.State = ClientState.Lobby;
            p.LobbySince = _now;
            p.LastLobby = DateTime.MinValue;
            Send(p, Messages.SessionEnd(s.Id, reason));
        }
        LogEvent(reason == EndReason.Desync ? "desync" : "session", $"session {s.Id} ended ({reason}): {why}", session: s);
    }

    private void RemoveClient(Client c, string why)
    {
        if (!_clients.Remove(c.EndPoint)) return;
        _playersChanged = true;
        LogEvent("disconnect", $"{c.Nick} left: {why}", c);
        if (c.Challenge is { } ch)
            CancelChallenge(ch, CancelReason.PlayerLeft, cooldown: false);
        if (c.Session is { } s)
        {
            c.Session = null;
            foreach (var p in s.Players.Where(p => p != c && p.Session == s))
                Send(p, Messages.OpponentLeft(s.Id));
            EndSession(s, EndReason.Timeout, $"{c.Nick} is gone");
        }
    }

    // ------------------------------------------------------------------ admin (dashboard)

    public bool Kick(byte clientId, DateTime now)
    {
        _now = now;
        var c = _clients.Values.FirstOrDefault(x => x.Id == clientId);
        if (c == null) return false;
        RemoveClient(c, "removed by the administrator");
        return true;
    }

    public bool AdminEndSession(byte sessionId, DateTime now)
    {
        _now = now;
        var s = _sessions.FirstOrDefault(x => x.Id == sessionId);
        if (s == null) return false;
        EndSession(s, EndReason.Admin, "ended by the administrator");
        return true;
    }

    // ------------------------------------------------------------------ helpers

    private void Send(Client c, ReadOnlySpan<byte> message) => _transport.Send(c.EndPoint, message);

    private void LogEvent(string category, string text, Client? player = null, Session? session = null) =>
        _log.Add(_now, category, text, player?.Nick, session?.Id);

    private static byte NextId(ref byte counter, IEnumerable<byte> inUse)
    {
        var used = inUse.ToHashSet();
        for (int i = 0; i < 255; i++)
        {
            counter = (byte)(counter % 255 + 1); // 1..255
            if (!used.Contains(counter)) return counter;
        }
        throw new InvalidOperationException("no free id");
    }

    private sealed class Context(ServerCore core) : ISessionContext
    {
        public DateTime Now => core._now;

        public void Send(Client to, ReadOnlySpan<byte> message) => core.Send(to, message);

        public void SendToOthers(Session session, Client? except, ReadOnlySpan<byte> message)
        {
            foreach (var p in session.Players)
                if (p != except && p.Session == session)
                    core.Send(p, message);
        }

        public void EndSession(Session session, EndReason reason, string why) => core.EndSession(session, reason, why);

        public void Log(string category, string text, Client? player = null, Session? session = null) =>
            core.LogEvent(category, text, player, session);
    }
}
