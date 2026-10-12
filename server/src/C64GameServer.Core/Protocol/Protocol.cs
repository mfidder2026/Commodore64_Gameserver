using System.Text;

namespace C64GameServer.Protocol;

/// <summary>Message types, see docs/protocol.md. $00-$7F platform, $80-$FF game specific.</summary>
public static class MsgType
{
    public const byte Hello = 0x01;
    public const byte Welcome = 0x02;
    public const byte Reject = 0x03;
    public const byte Lobby = 0x04;
    public const byte Challenge = 0x05;
    public const byte Accept = 0x06;
    public const byte Decline = 0x07;
    public const byte Start = 0x08;
    public const byte StartAck = 0x09;
    public const byte OpponentLeft = 0x0A;
    public const byte SessionEnd = 0x0B;
    public const byte Ping = 0x0C;
    public const byte Pong = 0x0D;
    public const byte Bye = 0x0E;
    public const byte ChallengeCancelled = 0x0F;
    public const byte Players = 0x10;
    public const byte Invite = 0x11;
    public const byte TableOpen = 0x12;
    public const byte TableJoin = 0x13;
    public const byte TableLeave = 0x14;
    public const byte TableStart = 0x15;
    public const byte Tables = 0x16;
    public const byte Table = 0x17;

    /// <summary>First game specific type. Byte 1 of every game message is the session id.</summary>
    public const byte GameFirst = 0x80;

    public static bool IsGame(byte type) => type >= GameFirst;

    public static string Name(byte type) => type switch
    {
        Hello => "HELLO",
        Welcome => "WELCOME",
        Reject => "REJECT",
        Lobby => "LOBBY",
        Challenge => "CHALLENGE",
        Accept => "ACCEPT",
        Decline => "DECLINE",
        Start => "START",
        StartAck => "START_ACK",
        OpponentLeft => "OPPONENT_LEFT",
        SessionEnd => "SESSION_END",
        Ping => "PING",
        Pong => "PONG",
        Bye => "BYE",
        ChallengeCancelled => "CHALLENGE_CANCELLED",
        Players => "PLAYERS",
        Invite => "INVITE",
        TableOpen => "TABLE_OPEN",
        TableJoin => "TABLE_JOIN",
        TableLeave => "TABLE_LEAVE",
        TableStart => "TABLE_START",
        Tables => "TABLES",
        Table => "TABLE",
        _ when type >= GameFirst => $"GAME_{type:X2}",
        _ => $"?{type:X2}",
    };
}

public enum RejectReason : byte { NameInUse = 1, Version = 2, UnknownGame = 3, ServerFull = 4, BadName = 5 }

public enum EndReason : byte { Finished = 1, Desync = 2, Timeout = 3, Admin = 4, PlayerQuit = 5 }

public enum CancelReason : byte { Declined = 1, Timeout = 2, PlayerLeft = 3, NotAvailable = 4 }

/// <summary>PLAYERS entry flags: bit 0 = bot, bits 1-2 = state.</summary>
public static class PlayerFlags
{
    public const byte Bot = 0x01;
    public const byte Free = 0x00;
    public const byte Busy = 0x02;     // answering or waiting for a challenge, or at a table
    public const byte Playing = 0x04;
}

/// <summary>One line of the lobby list.</summary>
public sealed record PlayerEntry(byte Id, byte Flags, string Nick);

public static class ProtocolConst
{
    public const byte Version = 1;
    public const int MaxMessage = 255;
    public const int MaxNick = 8;

    /// <summary>PLAYERS: at most this many entries per message (the C64 reads up to 128 bytes).</summary>
    public const int PlayersPerMessage = 6;

    /// <summary>TABLES: at most this many tables (the C64 reads up to 128 bytes).</summary>
    public const int MaxTables = 8;

    /// <summary>PLAYERS: the list holds at most this many other players.</summary>
    public const int MaxListed = 16;
}

/// <summary>A parsed HELLO.</summary>
public sealed record Hello(byte ProtocolVersion, byte GameId, byte GameVersion, string Nick, bool Bot = false);

/// <summary>Builds and parses platform messages. Parsers never throw: invalid data gives null.</summary>
public static class Messages
{
    public static byte[] Hello(byte gameId, byte gameVersion, string nick, bool bot = false)
    {
        var n = Encoding.ASCII.GetBytes(nick);
        var m = new byte[5 + n.Length + (bot ? 1 : 0)];
        if (bot) m[^1] = 1;
        m[0] = MsgType.Hello;
        m[1] = ProtocolConst.Version;
        m[2] = gameId;
        m[3] = gameVersion;
        m[4] = (byte)n.Length;
        n.CopyTo(m, 5);
        return m;
    }

    public static Hello? ParseHello(ReadOnlySpan<byte> m)
    {
        if (m.Length < 5 || m[0] != MsgType.Hello) return null;
        int len = m[4];
        // optional byte after the nickname: client kind (0 = a person at a C64, 1 = a bot)
        if (len < 1 || len > ProtocolConst.MaxNick || (m.Length != 5 + len && m.Length != 6 + len)) return null;
        bool bot = m.Length == 6 + len && m[5 + len] == 1;
        var nick = m.Slice(5, len);
        foreach (var c in nick)
        {
            bool ok = (c >= (byte)'A' && c <= (byte)'Z') || (c >= (byte)'0' && c <= (byte)'9');
            if (!ok) return new Hello(m[1], m[2], m[3], "", bot);  // invalid name: caller rejects with BadName
        }
        return new Hello(m[1], m[2], m[3], Encoding.ASCII.GetString(nick), bot);
    }

    public static bool IsValidNick(string nick) =>
        nick.Length is >= 1 and <= ProtocolConst.MaxNick && nick.All(c => c is >= 'A' and <= 'Z' or >= '0' and <= '9');

    public static byte[] Welcome(byte clientId) => [MsgType.Welcome, ProtocolConst.Version, clientId];

    public static byte[] Reject(RejectReason reason) => [MsgType.Reject, (byte)reason];

    public static byte[] Lobby(byte waiting) => [MsgType.Lobby, waiting];

    public static byte[] Challenge(byte challengeId, string opponentNick)
    {
        var n = Encoding.ASCII.GetBytes(opponentNick);
        var m = new byte[3 + n.Length];
        m[0] = MsgType.Challenge;
        m[1] = challengeId;
        m[2] = (byte)n.Length;
        n.CopyTo(m, 3);
        return m;
    }

    public static byte[] Accept(byte challengeId) => [MsgType.Accept, challengeId];

    public static byte[] Decline(byte challengeId) => [MsgType.Decline, challengeId];

    public static byte[] ChallengeCancelled(byte challengeId, CancelReason reason) =>
        [MsgType.ChallengeCancelled, challengeId, (byte)reason];

    public static byte[] Start(byte sessionId, byte slot, byte players, ReadOnlySpan<byte> parameters)
    {
        if (parameters.Length > ProtocolConst.MaxMessage - 5) throw new ArgumentException("start parameters too long");
        var m = new byte[5 + parameters.Length];
        m[0] = MsgType.Start;
        m[1] = sessionId;
        m[2] = slot;
        m[3] = players;
        m[4] = (byte)parameters.Length;
        parameters.CopyTo(m.AsSpan(5));
        return m;
    }

    public static byte[] StartAck(byte sessionId) => [MsgType.StartAck, sessionId];

    public static byte[] OpponentLeft(byte sessionId) => [MsgType.OpponentLeft, sessionId];

    public static byte[] SessionEnd(byte sessionId, EndReason reason) => [MsgType.SessionEnd, sessionId, (byte)reason];

    public static byte[] Ping(ushort token) => [MsgType.Ping, (byte)token, (byte)(token >> 8)];

    public static byte[] Pong(ushort token) => [MsgType.Pong, (byte)token, (byte)(token >> 8)];

    public static byte[] Bye() => [MsgType.Bye];

    /// <summary>PLAYERS: [total] [index of the first entry] [count], then per entry [id] [flags] [length] [nickname].</summary>
    public static byte[] Players(int total, int first, IReadOnlyList<PlayerEntry> entries)
    {
        var m = new List<byte> { MsgType.Players, (byte)total, (byte)first, (byte)entries.Count };
        foreach (var e in entries)
        {
            var n = Encoding.ASCII.GetBytes(e.Nick);
            m.Add(e.Id);
            m.Add(e.Flags);
            m.Add((byte)n.Length);
            m.AddRange(n);
        }
        return [.. m];
    }

    /// <summary>Parses PLAYERS; null if invalid.</summary>
    public static (int Total, int First, List<PlayerEntry> Entries)? ParsePlayers(ReadOnlySpan<byte> m)
    {
        if (m.Length < 4 || m[0] != MsgType.Players) return null;
        var list = new List<PlayerEntry>();
        int p = 4;
        for (int i = 0; i < m[3]; i++)
        {
            if (p + 3 > m.Length || p + 3 + m[p + 2] > m.Length) return null;
            list.Add(new PlayerEntry(m[p], m[p + 1], Encoding.ASCII.GetString(m.Slice(p + 3, m[p + 2]))));
            p += 3 + m[p + 2];
        }
        return (m[1], m[2], list);
    }

    /// <summary>INVITE: challenge the player with this client id; the sequence number tells repeats from new invites.</summary>
    public static byte[] Invite(byte targetId, byte seq) => [MsgType.Invite, targetId, seq];

    /// <summary>TABLES: the open tables of the game: [count], per table [id] [option] [seats taken]
    /// [length] [host's nickname].</summary>
    public static byte[] Tables(IReadOnlyList<(byte Id, byte Option, int Seats, string Host)> tables)
    {
        var m = new List<byte> { MsgType.Tables, (byte)tables.Count };
        foreach (var t in tables)
        {
            var n = Encoding.ASCII.GetBytes(t.Host);
            m.Add(t.Id);
            m.Add(t.Option);
            m.Add((byte)t.Seats);
            m.Add((byte)n.Length);
            m.AddRange(n);
        }
        return [.. m];
    }

    /// <summary>TABLE: your table: [id] [option] [your seat, $FF = you are at no table] [count], per seat
    /// [length] [nickname] (seat 0 is the host).</summary>
    public static byte[] Table(byte id, byte option, byte mySeat, IReadOnlyList<string> seats)
    {
        var m = new List<byte> { MsgType.Table, id, option, mySeat, (byte)seats.Count };
        foreach (var s in seats)
        {
            var n = Encoding.ASCII.GetBytes(s);
            m.Add((byte)n.Length);
            m.AddRange(n);
        }
        return [.. m];
    }

    public static ushort U16(ReadOnlySpan<byte> m, int offset) => (ushort)(m[offset] | (m[offset + 1] << 8));

    public static string Hex(ReadOnlySpan<byte> m) => string.Join(" ", m.ToArray().Select(b => b.ToString("x2")));
}
