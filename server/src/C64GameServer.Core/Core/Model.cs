using System.Net;

namespace C64GameServer.Core;

/// <summary>Sends datagrams. The UDP implementation lives in the server executable; tests use a fake.</summary>
public interface ITransport
{
    void Send(IPEndPoint to, ReadOnlySpan<byte> message);
}

public enum ClientState { Lobby, Challenged, InSession }

public sealed class Client
{
    public required byte Id { get; init; }
    public required IPEndPoint EndPoint { get; init; }
    public required string Nick { get; init; }
    public required byte GameId { get; init; }
    public required byte GameVersion { get; init; }

    /// <summary>The client said in its HELLO that it is a bot.</summary>
    public bool IsBot { get; init; }

    /// <summary>Sequence number of the last INVITE handled (-1: none), so repeated INVITEs are ignored.</summary>
    public int LastInviteSeq { get; set; } = -1;
    public ClientState State { get; set; } = ClientState.Lobby;
    public DateTime Connected { get; init; }
    public DateTime LastSeen { get; set; }

    /// <summary>When the client entered the lobby (pairing order).</summary>
    public DateTime LobbySince { get; set; }

    public Challenge? Challenge { get; set; }
    public Session? Session { get; set; }

    public double? PingMs { get; set; }
    public ushort PingToken { get; set; }
    public DateTime PingSent { get; set; }
    public DateTime LastPing { get; set; }
    public DateTime LastLobby { get; set; }
    public DateTime LastPlayers { get; set; }

    public long MessagesIn { get; set; }
    public long BytesIn { get; set; }
}

public sealed class Challenge
{
    public required byte Id { get; init; }
    public required byte GameId { get; init; }
    public required List<Client> Players { get; init; }
    public HashSet<Client> Accepted { get; } = [];
    public DateTime Created { get; init; }
    public DateTime LastSent { get; set; }
}

public sealed class Session
{
    public required byte Id { get; init; }
    public required byte GameId { get; init; }

    /// <summary>Players by slot.</summary>
    public required List<Client> Players { get; init; }

    public DateTime Started { get; init; }
    public byte[] StartParameters { get; set; } = [];
    public HashSet<Client> StartAcked { get; } = [];
    public DateTime LastStartSent { get; set; }

    /// <summary>State of the game module for this session.</summary>
    public object? ModuleState { get; set; }

    public long MessagesRelayed { get; set; }
    public long BytesRelayed { get; set; }

    /// <summary>The last messages of this session (for the hex view in the dashboard).</summary>
    public LinkedList<(DateTime Time, string From, byte[] Data)> Recent { get; } = new();

    public int SlotOf(Client c) => Players.IndexOf(c);
}
