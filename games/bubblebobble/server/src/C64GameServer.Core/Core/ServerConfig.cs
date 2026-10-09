using System.Text.Json;
using System.Text.Json.Serialization;

namespace C64GameServer.Core;

/// <summary>server.json</summary>
public sealed class ServerConfig
{
    public int GamePort { get; set; } = 6465;
    public int DashboardPort { get; set; } = 8080;
    public int MaxClients { get; set; } = 32;

    /// <summary>A client the server hears nothing from for this long is gone.</summary>
    public double IdleTimeoutSeconds { get; set; } = 10;

    public double ChallengeTimeoutSeconds { get; set; } = 30;
    public int ChallengeResendMs { get; set; } = 500;
    public double StartTimeoutSeconds { get; set; } = 10;
    public int StartResendMs { get; set; } = 250;

    /// <summary>After a decline or a challenge timeout the same players are not paired again for this long.</summary>
    public double DeclineCooldownSeconds { get; set; } = 60;

    public int LobbyIntervalMs { get; set; } = 2000;

    /// <summary>
    /// false (default): the players choose their opponent in the lobby (INVITE).
    /// true: the server pairs waiting players by itself (the first version of the protocol).
    /// </summary>
    public bool AutoPair { get; set; }

    /// <summary>Bots the server starts together with itself; they accept every challenge.</summary>
    public List<string> Bots { get; set; } = [];

    /// <summary>Game the built-in bots play.</summary>
    public byte BotGame { get; set; } = 1;
    public int PingIntervalMs { get; set; } = 2000;

    public string LogFile { get; set; } = "server.log";

    /// <summary>TCP port for C64s with a WiC64 (no UDP in its firmware); 0 = off.</summary>
    public int TcpPort { get; set; } = 6466;

    /// <summary>
    /// Raw Ethernet clients (RR-Net in VICE): the network interface to capture on with pcap (Npcap on
    /// Windows, libpcap on Linux); empty = off. Run the server with --list-interfaces to see the names.
    /// </summary>
    public string PcapInterface { get; set; } = "";

    /// <summary>The server's own MAC address on the raw Ethernet side (locally administered).</summary>
    public string PcapMac { get; set; } = "02:BB:4C:41:4E:01";

    public List<GameConfig> Games { get; set; } =
    [
        new GameConfig { Id = 3, Name = "Bubble Bobble", Module = "bubblebobble", Version = 1,
            Settings = new() { ["inputDelay"] = 2, ["inputDelayWiC64"] = 4, ["inputTimeoutSeconds"] = 10, ["loadTimeoutSeconds"] = 150 } },
        new GameConfig { Id = 1, Name = "Wizard of Wor", Module = "wizardofwor", Version = 1 },
        new GameConfig { Id = 2, Name = "Relay demo", Module = "relay", Version = 1, MinPlayers = 2, MaxPlayers = 4 },
    ];

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
    };

    public static ServerConfig Load(string path)
    {
        if (!File.Exists(path))
        {
            var fresh = new ServerConfig();
            File.WriteAllText(path, JsonSerializer.Serialize(fresh, JsonOptions));
            return fresh;
        }
        return JsonSerializer.Deserialize<ServerConfig>(File.ReadAllText(path), JsonOptions) ?? new ServerConfig();
    }
}

public sealed class GameConfig
{
    public byte Id { get; set; }
    public string Name { get; set; } = "";

    /// <summary>"wizardofwor" or "relay" (transparent relay, needs no code).</summary>
    public string Module { get; set; } = "relay";

    public byte Version { get; set; } = 1;
    public int MinPlayers { get; set; } = 2;
    public int MaxPlayers { get; set; } = 2;

    /// <summary>Module settings, e.g. inputDelay / tickRate for Wizard of Wor.</summary>
    public Dictionary<string, int> Settings { get; set; } = new() { ["inputDelay"] = 4, ["tickRate"] = 60, ["inputTimeoutSeconds"] = 10 };
}
