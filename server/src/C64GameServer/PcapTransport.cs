using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading.Channels;
using C64GameServer.Core;

namespace C64GameServer;

/// <summary>
/// Raw Ethernet transport for C64s with an RR-Net (CS8900a) cartridge, in practice VICE.
/// VICE puts its emulated network card on a host interface with pcap; it usually cannot reach a
/// UDP server on the same PC that way. So the server speaks raw Ethernet itself, on the same interface,
/// with its own (locally administered) MAC address:
///
///   frame = destination MAC, source MAC, EtherType $88B5, length, message, padding
///
/// The C64 finds the server by sending its HELLO to the broadcast address; everything after that is
/// unicast. A raw client gets a synthetic IPv6 link-local end point (made from its MAC), so the core
/// treats it like any other client.
/// </summary>
internal sealed class PcapTransport : IDisposable
{
    public const ushort EtherType = 0x88B5;
    private const int MinFrame = 60;

    private IntPtr _handle;
    private readonly byte[] _mac;
    private readonly Dictionary<IPEndPoint, byte[]> _macs = [];
    private readonly object _sendLock = new();
    public long Sent { get; private set; }
    public long Received { get; private set; }
    public string Interface { get; }

    static PcapTransport()
    {
        NativeLibrary.SetDllImportResolver(Assembly.GetExecutingAssembly(), (name, asm, path) =>
        {
            if (name != Native.Lib) return IntPtr.Zero;
            string[] candidates = RuntimeInformation.IsOSPlatform(OSPlatform.Windows)
                ? [Path.Combine(Environment.SystemDirectory, "Npcap", "wpcap.dll"), "wpcap.dll"]
                : ["libpcap.so.1", "libpcap.so", "libpcap.dylib"];
            foreach (var c in candidates)
                if (NativeLibrary.TryLoad(c, out var h)) return h;
            return IntPtr.Zero;
        });
    }

    public PcapTransport(string iface, string mac)
    {
        Interface = iface;
        _mac = ParseMac(mac);
        var err = new byte[256];
        // promiscuous: frames to our own made-up MAC must reach us. Immediate mode: deliver every
        // frame at once instead of buffering (the lockstep waits for each input).
        _handle = Native.pcap_create(iface, err);
        if (_handle != IntPtr.Zero)
        {
            Native.pcap_set_snaplen(_handle, 1600);
            Native.pcap_set_promisc(_handle, 1);
            Native.pcap_set_timeout(_handle, 1);
            Native.pcap_set_immediate_mode(_handle, 1);
            if (Native.pcap_activate(_handle) < 0)
            {
                Native.pcap_close(_handle);
                _handle = IntPtr.Zero;
            }
        }
        if (_handle == IntPtr.Zero)
            _handle = Native.pcap_open_live(iface, 1600, 1, 1, err);
        if (_handle == IntPtr.Zero)
            throw new InvalidOperationException($"pcap: cannot open {iface}: {Text(err)}");
    }

    public static byte[] ParseMac(string s)
    {
        var parts = s.Split(':', '-');
        if (parts.Length != 6) throw new FormatException($"invalid MAC address '{s}'");
        return parts.Select(p => Convert.ToByte(p, 16)).ToArray();
    }

    /// <summary>The end point the core sees for a raw client: fe80::/64 + EUI-64 of its MAC.</summary>
    public static IPEndPoint EndPointOf(ReadOnlySpan<byte> mac)
    {
        var b = new byte[16];
        b[0] = 0xFE; b[1] = 0x80;
        b[8] = (byte)(mac[0] ^ 2); b[9] = mac[1]; b[10] = mac[2];
        b[11] = 0xFF; b[12] = 0xFE;
        b[13] = mac[3]; b[14] = mac[4]; b[15] = mac[5];
        return new IPEndPoint(new IPAddress(b), 0);
    }

    public static bool IsRaw(IPEndPoint ep) => ep.AddressFamily == AddressFamily.InterNetworkV6 && ep.Address.IsIPv6LinkLocal;

    public void Send(IPEndPoint to, ReadOnlySpan<byte> message)
    {
        byte[]? dest;
        lock (_macs) _macs.TryGetValue(to, out dest);
        if (dest == null || message.Length > 255) return;
        var frame = new byte[Math.Max(MinFrame, 15 + message.Length)];
        dest.CopyTo(frame, 0);
        _mac.CopyTo(frame, 6);
        frame[12] = EtherType >> 8;
        frame[13] = EtherType & 0xFF;
        frame[14] = (byte)message.Length;
        message.CopyTo(frame.AsSpan(15));
        lock (_sendLock)
        {
            if (Native.pcap_sendpacket(_handle, frame, frame.Length) == 0) Sent++;
        }
    }

    public Task ReceiveLoop(ChannelWriter<(IPEndPoint, byte[])> output, CancellationToken ct) =>
        Task.Factory.StartNew(() =>
        {
            while (!ct.IsCancellationRequested)
            {
                int r = Native.pcap_next_ex(_handle, out var hdrPtr, out var dataPtr);
                if (r == 0) continue;           // timeout
                if (r < 0) { Thread.Sleep(100); continue; }
                var hdr = Marshal.PtrToStructure<Native.PcapPktHdr>(hdrPtr);
                int len = (int)hdr.caplen;
                if (len < 15) continue;
                var f = new byte[len];
                Marshal.Copy(dataPtr, f, 0, len);
                if (f[12] != EtherType >> 8 || f[13] != (EtherType & 0xFF)) continue;
                var src = f.AsSpan(6, 6);
                if (src.SequenceEqual(_mac)) continue;            // our own frame, looped back
                var dst = f.AsSpan(0, 6);
                bool broadcast = dst.SequenceEqual(new byte[] { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF });
                if (!broadcast && !dst.SequenceEqual(_mac)) continue;
                int mlen = f[14];
                if (mlen == 0 || 15 + mlen > len) continue;
                var ep = EndPointOf(src);
                lock (_macs) _macs[ep] = src.ToArray();
                Received++;
                output.TryWrite((ep, f.AsSpan(15, mlen).ToArray()));
            }
        }, ct, TaskCreationOptions.LongRunning, TaskScheduler.Default);

    public static List<(string Name, string Description)> ListInterfaces()
    {
        var list = new List<(string, string)>();
        var err = new byte[256];
        if (Native.pcap_findalldevs(out var all, err) != 0)
            throw new InvalidOperationException("pcap: " + Text(err));
        for (var p = all; p != IntPtr.Zero;)
        {
            var dev = Marshal.PtrToStructure<Native.PcapIf>(p);
            list.Add((Marshal.PtrToStringAnsi(dev.name) ?? "", Marshal.PtrToStringAnsi(dev.description) ?? ""));
            p = dev.next;
        }
        Native.pcap_freealldevs(all);
        return list;
    }

    private static string Text(byte[] err) => System.Text.Encoding.ASCII.GetString(err).TrimEnd('\0');

    public void Dispose() => Native.pcap_close(_handle);

    private static class Native
    {
        public const string Lib = "wpcap";

        [StructLayout(LayoutKind.Sequential)]
        public struct PcapIf
        {
            public IntPtr next;
            public IntPtr name;
            public IntPtr description;
            public IntPtr addresses;
            public uint flags;
        }

        // struct timeval is two longs: 32 bit on Windows, 64 bit on 64 bit Linux
        [StructLayout(LayoutKind.Sequential)]
        public struct PcapPktHdr
        {
            public CLong tv_sec;
            public CLong tv_usec;
            public uint caplen;
            public uint len;
        }

        [DllImport(Lib, CharSet = CharSet.Ansi)]
        public static extern IntPtr pcap_open_live(string device, int snaplen, int promisc, int to_ms, byte[] errbuf);

        [DllImport(Lib, CharSet = CharSet.Ansi)]
        public static extern IntPtr pcap_create(string device, byte[] errbuf);

        [DllImport(Lib)] public static extern int pcap_set_snaplen(IntPtr p, int snaplen);
        [DllImport(Lib)] public static extern int pcap_set_promisc(IntPtr p, int promisc);
        [DllImport(Lib)] public static extern int pcap_set_timeout(IntPtr p, int ms);
        [DllImport(Lib)] public static extern int pcap_set_immediate_mode(IntPtr p, int on);
        [DllImport(Lib)] public static extern int pcap_activate(IntPtr p);

        [DllImport(Lib)]
        public static extern int pcap_next_ex(IntPtr p, out IntPtr pktHeader, out IntPtr pktData);

        [DllImport(Lib)]
        public static extern int pcap_sendpacket(IntPtr p, byte[] buf, int size);

        [DllImport(Lib)]
        public static extern void pcap_close(IntPtr p);

        [DllImport(Lib)]
        public static extern int pcap_findalldevs(out IntPtr alldevs, byte[] errbuf);

        [DllImport(Lib)]
        public static extern void pcap_freealldevs(IntPtr alldevs);
    }
}

/// <summary>Sends to each client over the transport it came in on: UDP, raw Ethernet (pcap) or TCP.</summary>
internal sealed class MuxTransport(UdpTransport udp, PcapTransport? pcap, TcpTransport? tcp) : ITransport
{
    public void Send(IPEndPoint to, ReadOnlySpan<byte> message)
    {
        if (pcap != null && PcapTransport.IsRaw(to)) pcap.Send(to, message);
        else if (tcp != null && TcpTransport.IsTcp(to)) tcp.Send(to, message);
        else udp.Send(to, message);
    }
}
