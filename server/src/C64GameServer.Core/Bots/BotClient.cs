using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using C64GameServer.Protocol;

namespace C64GameServer.Bots;

/// <summary>
/// Test client that behaves like a C64: connects, accepts challenges and plays Wizard of Wor in lockstep
/// (input delay, 16 inputs per packet, resend while waiting, a checksum every 64 ticks).
/// The bot does not simulate the game itself: its "state" is a hash over all inputs, which is the same on both
/// bots exactly when the lockstep works.
/// </summary>
public sealed class BotOptions
{
    public IPEndPoint Server = new(IPAddress.Loopback, 6465);
    public string Nick = "BOT";
    public byte Game = 1;
    public int Games = 1;            // sessions to play, 0 = forever
    public int Ticks = 3600;         // ticks per session (60 s at 60 Hz), then game over
    public int ReadDelayMs;          // handle received packets only every n ms (the UCI read waits up to 40 ms)
    public double LossPercent;       // drop this share of the outgoing packets
    public int BadChecksumAt = -1;   // from this tick on send wrong checksums
    public int QuitAt = -1;          // at this tick stop sending (drop out)
    public bool Garbage;             // now and then send random bytes
    public bool Decline;             // decline every challenge
    public bool NoChecksum;          // send no checksums (for playing against a real C64)
    public bool Quiet;
    public bool IsBot = true;        // tell the server in the HELLO that this is a bot (shown in the lobby lists)
    public string? Invite;           // challenge this player as soon as it is free (the lobby without auto pairing)
    public Action<string>? Output;   // where the messages go (default: the console)

    public static BotOptions Parse(string[] args)
    {
        var o = new BotOptions();
        for (int i = 0; i < args.Length; i++)
        {
            string Next() => i + 1 < args.Length ? args[++i] : throw new ArgumentException($"{args[i]} needs a value");
            switch (args[i])
            {
                case "--server":
                    var v = Next();
                    var parts = v.Split(':');
                    var ip = Dns.GetHostAddresses(parts[0]).First(a => a.AddressFamily == AddressFamily.InterNetwork);
                    o.Server = new IPEndPoint(ip, parts.Length > 1 ? int.Parse(parts[1]) : 6465);
                    break;
                case "--nick": o.Nick = Next().ToUpperInvariant(); break;
                case "--game": o.Game = byte.Parse(Next()); break;
                case "--games": o.Games = int.Parse(Next()); break;
                case "--ticks": o.Ticks = int.Parse(Next()); break;
                case "--read-delay": o.ReadDelayMs = int.Parse(Next()); break;
                case "--loss": o.LossPercent = double.Parse(Next(), System.Globalization.CultureInfo.InvariantCulture); break;
                case "--bad-checksum-at": o.BadChecksumAt = int.Parse(Next()); break;
                case "--quit-at": o.QuitAt = int.Parse(Next()); break;
                case "--garbage": o.Garbage = true; break;
                case "--decline": o.Decline = true; break;
                case "--no-checksum": o.NoChecksum = true; break;
                case "--quiet": o.Quiet = true; break;
                case "--invite": o.Invite = Next().ToUpperInvariant(); break;
                case "--human": o.IsBot = false; break;
                default: throw new ArgumentException($"unknown option {args[i]}");
            }
        }
        return o;
    }
}

public sealed class BotClient
{
    private readonly BotOptions _o;
    private readonly Socket _socket;
    private readonly ConcurrentQueue<byte[]> _inbox = new();
    private readonly Random _random = new();
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private long _lastRead;
    private int _sent, _dropped;

    // results
    public int SessionsPlayed, SessionsFailed;
    public readonly List<string> Results = [];

    public BotClient(BotOptions o)
    {
        _o = o;
        _socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            _socket.IOControl(-1744830452, [0, 0, 0, 0], null); // SIO_UDP_CONNRESET off
        _socket.Bind(new IPEndPoint(IPAddress.Any, 0));
        new Thread(ReceiveLoop) { IsBackground = true }.Start();
    }

    private void Say(string s)
    {
        if (_o.Quiet) return;
        var line = $"[{_o.Nick} {_clock.Elapsed:mm\\:ss\\.ff}] {s}";
        if (_o.Output != null) _o.Output(line);
        else Console.WriteLine(line);
    }

    private void ReceiveLoop()
    {
        var buf = new byte[2048];
        EndPoint any = new IPEndPoint(IPAddress.Any, 0);
        while (true)
        {
            try
            {
                int n = _socket.ReceiveFrom(buf, ref any);
                _inbox.Enqueue(buf.AsSpan(0, n).ToArray());
            }
            catch (SocketException) { }
            catch (ObjectDisposedException) { return; }
        }
    }

    private bool _silent;
    private long _lastInputRx;

    private void Send(byte[] m)
    {
        if (_silent) return;
        if (_o.LossPercent > 0 && _random.NextDouble() * 100 < _o.LossPercent)
        {
            _dropped++;
            return;
        }
        _socket.SendTo(m, _o.Server);
        _sent++;
        if (_o.Garbage && _random.Next(50) == 0)
        {
            var junk = new byte[_random.Next(1, 40)];
            _random.NextBytes(junk);
            _socket.SendTo(junk, _o.Server);
        }
    }

    /// <summary>Received packets, but - like the UCI - only every ReadDelayMs.</summary>
    private IEnumerable<byte[]> Receive()
    {
        long now = _clock.ElapsedMilliseconds;
        if (_o.ReadDelayMs > 0 && now - _lastRead < _o.ReadDelayMs) yield break;
        _lastRead = now;
        while (_inbox.TryDequeue(out var m)) yield return m;
    }

    private bool HandleCommon(byte[] m)
    {
        if (m.Length == 3 && m[0] == MsgType.Ping)
        {
            Send(Messages.Pong(Messages.U16(m, 1)));
            return true;
        }
        return false;
    }

    private long _lastRx;
    private byte _inviteSeq;

    public int Run(CancellationToken ct = default)
    {
        try
        {
            while (!ct.IsCancellationRequested)
            {
                int r = Connect(ct);
                if (r != 0) return r;
                if (Lobby(ct)) break; // done; false: the server forgot us (restart, kicked): connect again
                Say("nothing from the server: connecting again");
            }
        }
        finally
        {
            Send(Messages.Bye());
        }
        Say($"done: {SessionsPlayed} played, {SessionsFailed} failed; sent {_sent}, dropped {_dropped}");
        return SessionsFailed == 0 ? 0 : 1;
    }

    private int Connect(CancellationToken ct)
    {
        Say($"connecting to {_o.Server} as {_o.Nick}");
        long lastHello = -1000;
        long started = _clock.ElapsedMilliseconds;
        while (!ct.IsCancellationRequested)
        {
            if (_clock.ElapsedMilliseconds - lastHello > 500)
            {
                Send(Messages.Hello(_o.Game, 1, _o.Nick, _o.IsBot));
                lastHello = _clock.ElapsedMilliseconds;
            }
            foreach (var m in Receive())
            {
                if (m[0] == MsgType.Welcome) { Say($"welcome, client id {m[2]}"); _lastRx = _clock.ElapsedMilliseconds; return 0; }
                if (m[0] == MsgType.Reject) { Say($"rejected, reason {m[1]}"); return 2; }
            }
            Thread.Sleep(5);
            if (_clock.ElapsedMilliseconds - started > 15000) { Say("no answer from the server"); return 2; }
        }
        return 0;
    }

    /// <summary>Waits for challenges and plays the sessions. true: finished, false: the server went silent.</summary>
    private bool Lobby(CancellationToken ct)
    {
        long lastPing = 0, lastInvite = -1000;
        bool inviting = false;
        while (_o.Games == 0 || SessionsPlayed + SessionsFailed < _o.Games)
        {
            if (ct.IsCancellationRequested) return true;
            long now = _clock.ElapsedMilliseconds;
            if (now - lastPing > 2000)
            {
                Send(Messages.Ping(1));
                lastPing = now;
            }
            if (now - _lastRx > 8000) return false; // the server pings every 2 s
            foreach (var m in Receive())
            {
                _lastRx = _clock.ElapsedMilliseconds;
                if (HandleCommon(m)) continue;
                switch (m[0])
                {
                    case MsgType.Challenge:
                        var opp = Encoding.ASCII.GetString(m, 3, m[2]);
                        Say($"challenge {m[1]} from {opp}: {(_o.Decline ? "decline" : "accept")}");
                        Send(_o.Decline ? Messages.Decline(m[1]) : Messages.Accept(m[1]));
                        break;
                    case MsgType.ChallengeCancelled:
                        Say($"challenge {m[1]} cancelled, reason {m[2]}");
                        inviting = false;
                        break;
                    case MsgType.Players when _o.Invite != null && !inviting:
                        // invite the wanted player as soon as the list shows it free
                        var list = Messages.ParsePlayers(m);
                        var target = list?.Entries.FirstOrDefault(e => e.Nick == _o.Invite && (e.Flags & 0x06) == PlayerFlags.Free);
                        if (target != null)
                        {
                            inviting = true;
                            _inviteSeq++;
                            lastInvite = -1000;
                            _inviteTarget = target.Id;
                            Say($"inviting {target.Nick}");
                        }
                        break;
                    case MsgType.Start:
                        inviting = false;
                        PlaySession(m);
                        lastPing = _clock.ElapsedMilliseconds;
                        _lastRx = lastPing;
                        break;
                }
            }
            if (inviting && _clock.ElapsedMilliseconds - lastInvite > 500)
            {
                Send(Messages.Invite(_inviteTarget, _inviteSeq)); // repeated until START or CHALLENGE_CANCELLED
                lastInvite = _clock.ElapsedMilliseconds;
            }
            Thread.Sleep(5);
        }
        return true;
    }

    private byte _inviteTarget;

    private static byte BotInput(int tick, int slot, byte seed)
    {
        // a new direction / fire state every 16 ticks, different per slot
        uint x = (uint)(tick >> 4) * 2654435761u ^ (uint)(slot * 0x9E3779B9) ^ seed;
        x ^= x >> 13;
        x *= 0x5bd1e995;
        x ^= x >> 15;
        byte[] dirs = [0xEE, 0xED, 0xEB, 0xE7];
        byte v = dirs[x & 3];
        if ((x & 0x80) != 0) v |= 0x10; // release fire
        return v;
    }

    private void PlaySession(byte[] start)
    {
        byte session = start[1], slot = start[2];
        int nParams = start[4];
        byte seedRandom = nParams > 0 ? start[5] : (byte)0;
        int delay = nParams > 2 ? start[7] : 4;
        int rate = nParams > 3 && start[8] > 0 ? start[8] : 60;
        Say($"START session {session}, slot {slot}, input delay {delay}, {rate} ticks/s");
        Send(Messages.StartAck(session));

        var local = new byte[65536];
        var remote = new byte[65536];
        Array.Fill(local, (byte)0xFF);
        Array.Fill(remote, (byte)0xFF);
        int localNewest = delay - 1, remoteNewest = delay - 1;
        uint state = 0x1234;
        ushort chkTick = 0xFFFF, chk = 0;
        long periodTicks = Stopwatch.Frequency / rate;
        long next = Stopwatch.GetTimestamp();
        int stalls = 0;
        double maxWait = 0;
        string? ended = null;

        byte[] InputPacket()
        {
            var p = new byte[24];
            p[0] = 0x80;
            p[1] = session;
            p[2] = (byte)localNewest; p[3] = (byte)(localNewest >> 8);
            p[4] = (byte)chkTick; p[5] = (byte)(chkTick >> 8);
            p[6] = (byte)chk; p[7] = (byte)(chk >> 8);
            for (int i = 0; i < 16; i++) p[8 + i] = local[(localNewest - 15 + i) & 0xFFFF];
            return p;
        }

        bool Pump()
        {
            foreach (var m in Receive())
            {
                if (HandleCommon(m)) continue;
                if (m[0] == MsgType.Start && m[1] == session) Send(Messages.StartAck(session));
                else if (m[0] == 0x80 && m.Length == 24 && m[1] == session)
                {
                    _lastInputRx = Stopwatch.GetTimestamp();
                    int newest = Messages.U16(m, 2);
                    int first = newest - 15;
                    if (first > remoteNewest + 1) continue; // hole (cannot happen)
                    for (int i = 0; i < 16; i++) remote[(first + i) & 0xFFFF] = m[8 + i];
                    if (newest > remoteNewest) remoteNewest = newest;
                }
                else if (m[0] == MsgType.SessionEnd && m[1] == session) { ended = $"session end, reason {m[2]}"; return false; }
                else if (m[0] == MsgType.OpponentLeft && m[1] == session) { ended = "opponent left"; return false; }
            }
            return true;
        }

        for (int t = 0; t < _o.Ticks; t++)
        {
            // pacing
            while (Stopwatch.GetTimestamp() < next) { if (!Pump()) break; Thread.Sleep(1); }
            next += periodTicks;
            if (ended != null) break;

            if (_o.QuitAt >= 0 && t >= _o.QuitAt)
            {
                // like a C64 that hangs: send nothing at all any more (no input, no pongs)
                Say($"tick {t}: dropping out (--quit-at), silent from now on");
                _silent = true;
                Thread.Sleep(15000);
                ended = "dropped out on purpose";
                break;
            }

            // checksum of the state at the start of this tick
            if ((t & 63) == 0 && !_o.NoChecksum)
            {
                chkTick = (ushort)t;
                chk = (ushort)(state ^ (state >> 16));
                if (_o.BadChecksumAt >= 0 && t >= _o.BadChecksumAt) chk ^= 0x5555;
            }

            // our input for t + delay
            localNewest = t + delay;
            local[localNewest & 0xFFFF] = BotInput(localNewest, slot, seedRandom);
            Send(InputPacket());

            // wait for the opponent's input of tick t; give up only when nothing at all came for 15 s
            // (a C64 shows its transition screens between the dungeons for many seconds without new ticks,
            // but keeps repeating its last INPUT meanwhile)
            var waitStart = Stopwatch.GetTimestamp();
            long lastSend = waitStart;
            while (remoteNewest < t)
            {
                if (!Pump()) break;
                long now = Stopwatch.GetTimestamp();
                if ((now - lastSend) * 1000 / Stopwatch.Frequency >= 20) { Send(InputPacket()); lastSend = now; }
                if ((now - Math.Max(waitStart, _lastInputRx)) / Stopwatch.Frequency >= 15) { ended = "nothing from the opponent for 15 s"; break; }
                Thread.Sleep(1);
            }
            if (ended != null) break;
            double waited = (Stopwatch.GetTimestamp() - waitStart) * 1000.0 / Stopwatch.Frequency;
            if (waited > 100) stalls++;
            maxWait = Math.Max(maxWait, waited);

            // "simulate": the state depends on both inputs in slot order
            byte p0 = slot == 0 ? local[t & 0xFFFF] : remote[t & 0xFFFF];
            byte p1 = slot == 0 ? remote[t & 0xFFFF] : local[t & 0xFFFF];
            state = (state * 31 + p0) * 31 + p1;
        }

        if (ended == null)
        {
            Send(Messages.SessionEnd(session, EndReason.Finished));
            SessionsPlayed++;
            var r = $"session {session}: {_o.Ticks} ticks played, {stalls} waits > 100 ms, longest wait {maxWait:0} ms";
            Results.Add(r);
            Say(r);
            // drain until the server confirms (its SESSION_END) or a moment passes
            var until = _clock.ElapsedMilliseconds + 1000;
            while (_clock.ElapsedMilliseconds < until && Pump()) Thread.Sleep(5);
        }
        else
        {
            if (ended.Contains("reason 1") || ended.StartsWith("dropped out")) SessionsPlayed++; // finished first / on purpose
            else SessionsFailed++;
            Results.Add($"session {session}: {ended}");
            Say($"session {session}: {ended}");
        }
    }
}
