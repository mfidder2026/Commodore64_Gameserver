# C64 Ultimate link test

> Part of the **[Commodore 64 Game Server](../../../README.md)**.

A test program for two C64s that talk to each other **directly**, without the game server:
two C64 Ultimates on the LAN or WiFi, or two VICEs with an RR-Net cartridge. It shows the
network of the C64, finds the other C64, and measures the link: round trip, loss, the time a
write and a read through the Command Interface take, and the speed of a burst of data.

The disk: `RELEASE/tools/linktest.d64` (`LOAD"*",8,1` / `RUN`).

## What it needs

On the Ultimate: firmware with the Command Interface command **OPEN_UDP_LOCAL (`$0A`)**, a UDP
socket from a fixed local port ([GideonZ/1541ultimate#962](https://github.com/GideonZ/1541ultimate/issues/962),
pull request #1016; a test build is linked in the issue). With it, two Ultimates each open a socket
from port 6464 to the other's port 6464 and can talk without a server. The program checks for it at
the start (on older firmware it says "NOT IN THIS FIRMWARE"). Turn on LAN or WiFi in the Ultimate's
menu: the first screen lists every interface with its MAC, IP address, netmask and gateway.

In VICE (no Command Interface): an RR-Net cartridge on a host network adapter. The two C64s then
send raw Ethernet frames (EtherType `$88B5`) to each other's MAC address.

## Use

1. Start the program on both C64s.
2. On one press **C** (CLIENT: wait to be found), on the other **H** (HOST: search).
   Or press **I** on both and type the other C64's IP address.
3. The link screen updates four times a second. Keys: `+`/`-` the ping rate, `T` sends 100
   messages of 200 bytes as fast as possible (the other C64 shows what arrived and the speed),
   `R` resets the counters, `Q` goes back.

## How the two find each other

A `$0A` socket is *connected*: it only receives from the address and port it was opened to. That
rules out a normal LAN scan. The search therefore tries two things that the firmware's network
stack (lwIP) may allow; the screen shows each step with the firmware's status, so the test also
tells which of them works:

- the CLIENT opens `$0A` to **0.0.0.0**, remote port 6465, local port 6464 (lwIP matches a connected
  socket whose remote address is "any" against every sender);
- the HOST sends HELLO (with its own IP) from port 6465 to the subnet's **broadcast address**,
  port 6464, and listens itself on 0.0.0.0:6464;
- the CLIENT answers with ACK (its IP); then both open `$0A` to each other, 6464 to 6464, and the
  HOST starts pinging. Without pings within 3 seconds the HELLO was an old one and the CLIENT waits
  again.

When a step fails, use **I** (the IP address by hand) on both C64s: that needs nothing but `$0A`.

## Messages

`'L' 'T' type seq(2) time(4) ip(4) name(8) [data]`: 21 bytes before the data. Types: 1 HELLO,
2 ACK, 3 PING, 4 PONG (the PING's time comes back), 5 BYE, 6 DATA. Time is a 32-bit cycle counter
(CIA 2 timers A and B chained); round trips are measured on the sender's own clock.

## Building

```bash
python build.py          # build/linktest.prg and build/linktest.d64 (cc65)
python build.py run      # and start it in VICE with an RR-Net cartridge ($NPCAP_IF)
```

It uses the standard lobby's drivers (`../lobby/uci.s`, `../lobby/rrnet.s`). Tested on two real
C64 Ultimates with the `$0A` test firmware and in VICE (two RR-Net instances). Also published on its
own: [mfidder2026/C64U-H2H](https://github.com/mfidder2026/C64U-H2H).
