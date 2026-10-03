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
    public int PingIntervalMs { get; set; } = 2000;

    public string LogFile { get; set; } = "server.log";

    public List<GameConfig> Games { get; set; } =
    [
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
