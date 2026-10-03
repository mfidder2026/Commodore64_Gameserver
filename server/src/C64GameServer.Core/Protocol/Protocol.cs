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
        _ when type >= GameFirst => $"GAME_{type:X2}",
        _ => $"?{type:X2}",
    };
}

public enum RejectReason : byte { NameInUse = 1, Version = 2, UnknownGame = 3, ServerFull = 4, BadName = 5 }

public enum EndReason : byte { Finished = 1, Desync = 2, Timeout = 3, Admin = 4, PlayerQuit = 5 }

public enum CancelReason : byte { Declined = 1, Timeout = 2, PlayerLeft = 3 }

public static class ProtocolConst
{
    public const byte Version = 1;
    public const int MaxMessage = 255;
    public const int MaxNick = 8;
}

/// <summary>A parsed HELLO.</summary>
public sealed record Hello(byte ProtocolVersion, byte GameId, byte GameVersion, string Nick);

/// <summary>Builds and parses platform messages. Parsers never throw: invalid data gives null.</summary>
public static class Messages
{
    public static byte[] Hello(byte gameId, byte gameVersion, string nick)
    {
        var n = Encoding.ASCII.GetBytes(nick);
        var m = new byte[5 + n.Length];
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
        if (len < 1 || len > ProtocolConst.MaxNick || m.Length != 5 + len) return null;
        var nick = m.Slice(5, len);
        foreach (var c in nick)
        {
            bool ok = (c >= (byte)'A' && c <= (byte)'Z') || (c >= (byte)'0' && c <= (byte)'9');
            if (!ok) return new Hello(m[1], m[2], m[3], "");  // invalid name: caller rejects with BadName
        }
        return new Hello(m[1], m[2], m[3], Encoding.ASCII.GetString(nick));
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

    public static ushort U16(ReadOnlySpan<byte> m, int offset) => (ushort)(m[offset] | (m[offset + 1] << 8));

    public static string Hex(ReadOnlySpan<byte> m) => string.Join(" ", m.ToArray().Select(b => b.ToString("x2")));
}
