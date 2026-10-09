using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Threading.Channels;
using C64GameServer.Bots;
using C64GameServer.Core;
using C64GameServer.Games;

namespace C64GameServer;

/// <summary>UDP transport: one socket on the game port.</summary>
internal sealed class UdpTransport : ITransport, IDisposable
{
    private readonly Socket _socket;
    public long Sent { get; private set; }

    public UdpTransport(int port)
    {
        _socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            // without this, an ICMP "port unreachable" (a C64 that went away) makes the next receive fail
            const int SIO_UDP_CONNRESET = -1744830452;
            _socket.IOControl(SIO_UDP_CONNRESET, [0, 0, 0, 0], null);
        }
        _socket.Bind(new IPEndPoint(IPAddress.Any, port));
    }

    public void Send(IPEndPoint to, ReadOnlySpan<byte> message)
    {
        try
        {
            _socket.SendTo(message, SocketFlags.None, to);
            Sent++;
        }
        catch (SocketException) { /* a send error must never stop the server */ }
    }

    public async Task ReceiveLoop(ChannelWriter<(IPEndPoint, byte[])> output, CancellationToken ct)
    {
        var buffer = new byte[2048];
        EndPoint any = new IPEndPoint(IPAddress.Any, 0);
        while (!ct.IsCancellationRequested)
        {
            try
            {
                var r = await _socket.ReceiveFromAsync(buffer, SocketFlags.None, any, ct);
                await output.WriteAsync(((IPEndPoint)r.RemoteEndPoint, buffer.AsSpan(0, r.ReceivedBytes).ToArray()), ct);
            }
            catch (OperationCanceledException) { break; }
            catch (SocketException) { /* see SIO_UDP_CONNRESET; keep receiving */ }
        }
    }

    public void Dispose() => _socket.Dispose();
}

internal static class Program
{
    private static async Task<int> Main(string[] args)
    {
        if (args.Contains("--list-interfaces"))
        {
            try
            {
                Console.WriteLine("Network interfaces for \"pcapInterface\" in server.json (raw Ethernet / VICE RR-Net):");
                foreach (var (name, desc) in PcapTransport.ListInterfaces())
                    Console.WriteLine($"  {name}\n      {desc}");
            }
            catch (Exception e)
            {
                Console.Error.WriteLine($"pcap is not available ({e.Message}). Windows: install Npcap; Linux: libpcap.");
                return 1;
            }
            return 0;
        }
        string configPath = args.Length > 0 ? args[0] : "server.json";
        var config = ServerConfig.Load(configPath);
        var log = new EventLog(config.LogFile, console: true);
        GameRegistry games;
        try { games = GameRegistry.FromConfig(config); }
        catch (InvalidDataException e)
        {
            Console.Error.WriteLine(e.Message);
            return 1;
        }

        UdpTransport transportOrNull;
        try { transportOrNull = new UdpTransport(config.GamePort); }
        catch (System.Net.Sockets.SocketException e)
        {
            Console.Error.WriteLine($"UDP port {config.GamePort} cannot be used ({e.Message}). Is the server already running?");
            return 1;
        }
        using var transport = transportOrNull;
        PcapTransport? pcap = null;
        if (!string.IsNullOrWhiteSpace(config.PcapInterface))
        {
            try { pcap = new PcapTransport(config.PcapInterface, config.PcapMac); }
            catch (Exception e)
            {
                Console.Error.WriteLine($"Raw Ethernet (pcapInterface) cannot be used: {e.Message}");
                Console.Error.WriteLine("Windows: install Npcap. List the interfaces with: C64GameServer --list-interfaces");
                return 1;
            }
        }
        using var pcapDispose = pcap;
        TcpTransport? tcp = null;
        if (config.TcpPort > 0)
        {
            try { tcp = new TcpTransport(config.TcpPort); }
            catch (SocketException e)
            {
                Console.Error.WriteLine($"TCP port {config.TcpPort} cannot be used ({e.Message}).");
                return 1;
            }
        }
        using var tcpDispose = tcp;
        var core = new ServerCore(config, new MuxTransport(transport, pcap, tcp), games, log, DateTime.UtcNow);
        var host = new ServerHost(core, transport, pcap, tcp);

        PrintBanner(config, games);
        using var cts = new CancellationTokenSource();
        Console.CancelKeyPress += (_, e) => { e.Cancel = true; cts.Cancel(); };

        Dashboard.SetGamePort(config.GamePort);
        var dashboard = new Dashboard(host, config.DashboardPort);
        var dashboardTask = dashboard.Run(cts.Token);
        StartBots(config, log, cts.Token);
        await host.Run(cts.Token);
        await dashboardTask;
        log.Add(DateTime.UtcNow, "server", "stopped");
        return 0;
    }

    /// <summary>
    /// The built-in bots (server.json "bots"): normal clients over the loopback interface that accept every challenge,
    /// so a player always finds an opponent. They play random moves; the real game runs on the C64.
    /// </summary>
    private static void StartBots(ServerConfig config, EventLog log, CancellationToken ct)
    {
        foreach (var nick in config.Bots.Select(b => b.ToUpperInvariant()).Distinct())
        {
            if (!Protocol.Messages.IsValidNick(nick))
            {
                log.Add(DateTime.UtcNow, "error", $"bot name {nick} is invalid (A-Z, 0-9, max 8)");
                continue;
            }
            var bot = new BotClient(new BotOptions
            {
                Server = new IPEndPoint(IPAddress.Loopback, config.GamePort),
                Nick = nick,
                Game = config.BotGame,
                Games = 0,
                Ticks = int.MaxValue, // the game over comes from the C64
                NoChecksum = true,    // the bot does not know the real game state
                Quiet = true,
            });
            new Thread(() => bot.Run(ct)) { IsBackground = true, Name = "bot " + nick }.Start();
        }
    }

    private static void PrintBanner(ServerConfig config, GameRegistry games)
    {
        Console.WriteLine("==============================================================");
        Console.WriteLine(" C64 Game Server - LAN only, no encryption: do NOT expose it to the internet");
        Console.WriteLine("==============================================================");
        Console.WriteLine($" C64s connect to UDP port {config.GamePort} on:");
        foreach (var ip in LocalAddresses())
            Console.WriteLine($"     {ip}");
        if (config.TcpPort > 0)
            Console.WriteLine($" WiC64 (TCP) on port {config.TcpPort}");
        if (!string.IsNullOrWhiteSpace(config.PcapInterface))
            Console.WriteLine($" Raw Ethernet (VICE RR-Net) on {config.PcapInterface}, MAC {config.PcapMac}");
        Console.WriteLine($" Dashboard: http://localhost:{config.DashboardPort}/");
        Console.WriteLine(" Games: " + string.Join(", ", games.All.Select(g => $"{g.GameId} = {g.Name}")));
        if (config.Bots.Count > 0) Console.WriteLine(" Bots: " + string.Join(", ", config.Bots));
        Console.WriteLine(" Ctrl+C stops the server.");
        Console.WriteLine();
    }

    public static IEnumerable<IPAddress> LocalAddresses() =>
        NetworkInterface.GetAllNetworkInterfaces()
            .Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback)
            .SelectMany(n => n.GetIPProperties().UnicastAddresses)
            .Select(a => a.Address)
            .Where(a => a.AddressFamily == AddressFamily.InterNetwork);
}

/// <summary>Runs the core on one logical thread: datagrams and a 20 ms tick, all under one lock (the dashboard reads under it too).</summary>
internal sealed class ServerHost(ServerCore core, UdpTransport transport, PcapTransport? pcap = null,
    TcpTransport? tcp = null)
{
    public ServerCore Core => core;
    public UdpTransport Transport => transport;
    public PcapTransport? Pcap => pcap;
    public object Lock { get; } = new();

    public async Task Run(CancellationToken ct)
    {
        var channel = Channel.CreateUnbounded<(IPEndPoint, byte[])>();
        var receiver = transport.ReceiveLoop(channel.Writer, ct);
        var rawReceiver = pcap?.ReceiveLoop(channel.Writer, ct) ?? Task.CompletedTask;
        var tcpReceiver = tcp?.AcceptLoop(channel.Writer, ct) ?? Task.CompletedTask;
        var nextTick = DateTime.UtcNow;
        while (!ct.IsCancellationRequested)
        {
            var wait = nextTick - DateTime.UtcNow;
            if (wait > TimeSpan.Zero)
            {
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
                timeout.CancelAfter(wait);
                try
                {
                    if (await channel.Reader.WaitToReadAsync(timeout.Token))
                        while (channel.Reader.TryRead(out var d))
                            lock (Lock) core.HandleDatagram(d.Item1, d.Item2, DateTime.UtcNow);
                }
                catch (OperationCanceledException) { }
            }
            if (DateTime.UtcNow >= nextTick)
            {
                lock (Lock) core.Tick(DateTime.UtcNow);
                nextTick = DateTime.UtcNow.AddMilliseconds(20);
            }
        }
        await receiver;
        await rawReceiver;
        await tcpReceiver;
    }
}
