"""
PC test peer for nettest.prg (phase 0 measurements). Not a relay: it only plays the other side of the test,
so a single C64 Ultimate (or VICE with RR-Net) can be measured.

    python tools/netpeer.py udp                    answer on UDP port 6464, ping whoever talks to us
    python tools/netpeer.py udp --peer 192.168.1.50
                                                   also start pinging that C64 right away
    python tools/netpeer.py udp --reply-port 6464  answer to port 6464 instead of the sender's source port
                                                   (tests whether the Ultimate accepts that)
    python tools/netpeer.py tcp-server             wait for nettest mode 2 (TCP connect)
    python tools/netpeer.py tcp-client 192.168.1.50
                                                   connect to nettest mode 3 (TCP listen)

Packet (16 bytes): 'W' 'L' type(1=PING, 2=PONG) seq(16 bit LE) timestamp(32 bit LE) 7 bytes padding.
A PONG returns the PING's seq and timestamp unchanged, so each side measures its own round trip.
"""
from __future__ import annotations

import argparse
import select
import socket
import struct
import time

PORT = 6464
PKT = struct.Struct("<2sBHI7x")
PING, PONG = 1, 2


def now_us() -> int:
    return int(time.perf_counter() * 1_000_000) & 0xFFFFFFFF


class Stats:
    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        self.rtts: list[float] = []
        self.pings_sent = self.pongs = self.pings_rcvd = 0
        self.t0 = time.time()

    def line(self, extra: str = "") -> str:
        r = self.rtts
        rtt = f"rtt ms min {min(r):6.1f} avg {sum(r)/len(r):6.1f} max {max(r):6.1f}" if r else "rtt -"
        lost = self.pings_sent - self.pongs
        return (f"sent {self.pings_sent:5d}  pongs {self.pongs:5d}  lost/outstanding {lost:4d}  "
                f"their pings {self.pings_rcvd:5d}  {rtt}  {extra}")


def handle(data: bytes, stats: Stats, send) -> None:
    """Handle one 16 byte packet; send(bytes) answers."""
    magic, typ, seq, ts = PKT.unpack(data)
    if magic != b"WL":
        return
    if typ == PING:
        stats.pings_rcvd += 1
        send(PKT.pack(b"WL", PONG, seq, ts))
    elif typ == PONG:
        stats.pongs += 1
        stats.rtts.append(((now_us() - ts) & 0xFFFFFFFF) / 1000.0)


def run_udp(args) -> None:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(("0.0.0.0", args.port))
    print(f"UDP peer on port {args.port}")
    stats = Stats()
    target = (args.peer, args.port) if args.peer else None
    sources: set[tuple[str, int]] = set()
    seq = 0
    next_ping = next_report = time.time()
    while True:
        r, _, _ = select.select([s], [], [], 0.005)
        if r:
            try:
                data, addr = s.recvfrom(2048)
            except ConnectionResetError:
                # Windows reports an ICMP "port unreachable" of an earlier send this way - the peer went away
                continue
            if addr not in sources:
                sources.add(addr)
                print(f"packets from {addr[0]} source port {addr[1]}")
            reply_to = (addr[0], args.reply_port) if args.reply_port else addr
            if not args.peer:
                target = reply_to
            for i in range(0, len(data) - PKT.size + 1, PKT.size):
                handle(data[i:i + PKT.size], stats, lambda b: s.sendto(b, reply_to))
        t = time.time()
        if target and t >= next_ping:
            seq = (seq + 1) & 0xFFFF
            s.sendto(PKT.pack(b"WL", PING, seq, now_us()), target)
            stats.pings_sent += 1
            next_ping = t + args.interval
        if t >= next_report:
            print(stats.line(f"-> {target[0]}:{target[1]}" if target else "(waiting for the C64)"))
            next_report = t + 2


def run_tcp(sock: socket.socket, args) -> None:
    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    stats = Stats()
    buf = b""
    seq = 0
    next_ping = next_report = time.time()
    while True:
        r, _, _ = select.select([sock], [], [], 0.005)
        if r:
            data = sock.recv(4096)
            if not data:
                print("connection closed")
                return
            buf += data
            while len(buf) >= PKT.size:
                if buf[:2] != b"WL":
                    buf = buf[1:]
                    continue
                handle(buf[:PKT.size], stats, sock.sendall)
                buf = buf[PKT.size:]
        t = time.time()
        if t >= next_ping:
            seq = (seq + 1) & 0xFFFF
            sock.sendall(PKT.pack(b"WL", PING, seq, now_us()))
            stats.pings_sent += 1
            next_ping = t + args.interval
        if t >= next_report:
            print(stats.line())
            next_report = t + 2


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["udp", "tcp-server", "tcp-client"])
    ap.add_argument("host", nargs="?", help="C64 address for tcp-client")
    ap.add_argument("--port", type=int, default=PORT)
    ap.add_argument("--peer", help="udp: C64 address to ping right away")
    ap.add_argument("--reply-port", type=int, help="udp: answer to this port instead of the source port")
    ap.add_argument("--interval", type=float, default=0.2, help="seconds between our pings (default 0.2)")
    args = ap.parse_args()

    if args.mode == "udp":
        run_udp(args)
    elif args.mode == "tcp-server":
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("0.0.0.0", args.port))
        srv.listen(1)
        print(f"TCP server on port {args.port}, waiting for the C64")
        while True:
            c, addr = srv.accept()
            print(f"connection from {addr[0]}:{addr[1]}")
            run_tcp(c, args)
    else:
        if not args.host:
            ap.error("tcp-client needs the C64 address")
        c = socket.create_connection((args.host, args.port), timeout=10)
        print(f"connected to {args.host}:{args.port}")
        run_tcp(c, args)


if __name__ == "__main__":
    main()
