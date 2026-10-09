using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Threading.Channels;

namespace C64GameServer;

/// <summary>
/// TCP transport for C64s with a WiC64 (its firmware has no UDP). One TCP connection per C64;
/// the stream carries the same messages as UDP, each framed as [length][message].
/// A TCP client's end point is its remote address as an IPv4-mapped IPv6 address, so it never
/// collides with a UDP client (plain IPv4) or a raw Ethernet client (link-local IPv6).
/// Closing the connection counts as a BYE.
/// </summary>
internal sealed class TcpTransport : IDisposable
{
    private readonly TcpListener _listener;
    private readonly ConcurrentDictionary<IPEndPoint, NetworkStream> _clients = new();
    public long Sent { get; private set; }
    public int Port { get; }

    public TcpTransport(int port)
    {
        Port = port;
        _listener = new TcpListener(IPAddress.Any, port);
        _listener.Start();
    }

    public static IPEndPoint EndPointOf(IPEndPoint remote) =>
        new(remote.Address.MapToIPv6(), remote.Port);

    public static bool IsTcp(IPEndPoint ep) => ep.AddressFamily == AddressFamily.InterNetworkV6 && ep.Address.IsIPv4MappedToIPv6;

    public void Send(IPEndPoint to, ReadOnlySpan<byte> message)
    {
        if (!_clients.TryGetValue(to, out var stream) || message.Length > 255) return;
        var frame = new byte[message.Length + 1];
        frame[0] = (byte)message.Length;
        message.CopyTo(frame.AsSpan(1));
        try
        {
            lock (stream) stream.Write(frame);
            Sent++;
        }
        catch (Exception e) when (e is IOException or ObjectDisposedException) { }
    }

    public async Task AcceptLoop(ChannelWriter<(IPEndPoint, byte[])> output, CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            TcpClient client;
            try { client = await _listener.AcceptTcpClientAsync(ct); }
            catch (OperationCanceledException) { break; }
            catch (SocketException) { continue; }
            client.NoDelay = true;  // every input counts: no Nagle
            _ = Serve(client, output, ct);
        }
    }

    private async Task Serve(TcpClient client, ChannelWriter<(IPEndPoint, byte[])> output, CancellationToken ct)
    {
        var ep = EndPointOf((IPEndPoint)client.Client.RemoteEndPoint!);
        var stream = client.GetStream();
        _clients[ep] = stream;
        var buf = new byte[512];
        int have = 0;
        try
        {
            while (!ct.IsCancellationRequested)
            {
                int n = await stream.ReadAsync(buf.AsMemory(have), ct);
                if (n == 0) break;
                have += n;
                int pos = 0;
                while (have - pos >= 1 && have - pos >= 1 + buf[pos])
                {
                    int len = buf[pos];
                    if (len > 0) await output.WriteAsync((ep, buf.AsSpan(pos + 1, len).ToArray()), ct);
                    pos += 1 + len;
                }
                Array.Copy(buf, pos, buf, 0, have - pos);
                have -= pos;
            }
        }
        catch (Exception e) when (e is IOException or OperationCanceledException or ObjectDisposedException) { }
        finally
        {
            _clients.TryRemove(ep, out _);
            client.Dispose();
            output.TryWrite((ep, [Protocol.MsgType.Bye]));
        }
    }

    public void Dispose() => _listener.Stop();
}
