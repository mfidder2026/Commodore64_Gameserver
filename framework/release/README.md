# C64 Game Server: ready to play

Everything you need, in one folder: the game server and the games as disk
images, plus scripts that start VICE with the right network set-up. More
information is in the [main README](../README.md).

| File | What |
|---|---|
| `start-server.bat` | Starts the game server (Windows) |
| `start-server.sh` | Starts the game server (Linux or a Raspberry Pi, 64-bit OS) |
| `Dockerfile`, `docker-compose.yml` | The game server in your own Docker: `docker compose up -d --build` |
| `vice-wic64.bat` | Starts VICE with the **WiC64** emulation and a game |
| `vice-rrnet.bat` | Starts VICE with an **RR-Net** cartridge and a game |
| `games/wizardofwor.d64` | Wizard of Wor OME (also head-to-head between two C64 Ultimates, without the server) |
| `games/bubblebobble.d64` | Bubble Bobble OME |
| `games/explodingfist.d64` | The Way of the Exploding Fist OME |
| `games/pitstop2.d64` | Pitstop II OME |
| `games/mule.d64` | M.U.L.E. OME (2-4 players) |
| `games/archon.d64` | Archon OME |
| `games/spyvsspy.d64` | Spy vs Spy OME |
| `server/win-x64/` | The server for Windows (no .NET installation needed) |
| `server/linux-x64/` | The server for Linux on a PC (also used by the Dockerfile) |
| `server/linux-arm64/` | The server for a Raspberry Pi with a 64-bit OS (also used by the Dockerfile) |
| `tools/linktest.d64` | The C64 Ultimate link test: two C64s directly, without the server |
| `VERSION.txt` | When and from which commit this folder was made |

## 1. Start the server

On one computer in your network, run `start-server.bat` (Windows) or
`./start-server.sh` (Linux, Raspberry Pi). In your own Docker (a PC, a NAS, a Raspberry Pi):
`docker compose up -d --build` in this folder (`Dockerfile`, `docker-compose.yml`; the
repository's docs/docker.md tells more).

- The server shows the IP addresses the C64s can use, for example `192.168.1.10`.
- The dashboard is at http://localhost:8080/. It has a tab for every game.
- Windows asks whether to allow the server on the network: allow it for private networks.
- Every game has bots, so you can play alone.

To play on someone else's server, skip this step and use their IP address.

## 2. Start a C64

### VICE (emulator)

1. Install [VICE](https://vice-emu.sourceforge.io/) 3.9 or newer.
2. Double-click **`vice-wic64.bat`** and choose a game.
   - The first time it asks where `x64sc.exe` is, if it cannot find it. The answer goes into `vice-path.txt`.
   - It plays from your own copy of the disk in `my-disks\`, which keeps your name and the server address.
3. Choose **RETURN** (online, via a game server) in the game's menu; it asks for your name and the
   server's IP address. On the PC that runs the server, use `127.0.0.1`.
   In Wizard of Wor, choose **4 PLAY VIA A GAME SERVER** in its menu.

`vice-rrnet.bat` uses an emulated RR-Net cartridge instead. It needs [Npcap](https://npcap.com/).

- **Bubble Bobble** talks raw Ethernet: it finds a server on the same network by itself, also on the same PC.
- **Wizard of Wor** uses UDP: the server must run on **another** computer, because VICE cannot reach its own PC this way.
- To pick the network adapter, put its name in `rrnet-interface.txt`. `start-server.bat --list-interfaces` shows the names.

A new version of a game? Delete its copy in `my-disks\`. You then enter your name and server again.

### C64 Ultimate / Ultimate 64

1. **Turn on the Command Interface**: Ultimate menu (F2) → *C64 and Cartridge Settings* →
   *Command Interface*: **Enabled**, and save the settings. It is off by default; without it the
   games find no network ("NO NETWORK HARDWARE FOUND" / "Network: none found").
2. Connect the Ultimate to your network and check that it has an IP address.
3. Copy the `.d64` files to a USB stick.
4. Start the disk from the Ultimate menu and choose **RETURN** (online); enter your name and the
   server's IP address. Two Ultimates whose firmware has `$0A` can also play **head-to-head**
   without a server (key **H**, Bubble Bobble).

### C64 with a WiC64

Put the `.d64` on your drive (or SD2IEC), connect the WiC64 to your Wi-Fi, and
`LOAD"*",8,1`. Choose **RETURN** (online) and enter your name and the server's IP address.

## 3. Play

The lobby shows everyone online for the game, people and bots.

1. Choose an opponent with the joystick (port 2) or the cursor keys.
2. Invite them with FIRE.
3. When someone invites you, FIRE accepts and N declines.
4. F1 goes back to the game's start menu (name, server, local game).

| | Ultimate | WiC64 (real or VICE) | VICE RR-Net |
|---|---|---|---|
| Wizard of Wor OME | yes | yes | yes, server on another PC |
| Bubble Bobble OME | yes | yes | yes |
| The Way of the Exploding Fist OME | yes | yes | yes |
| Pitstop II OME | yes | yes | yes |
| M.U.L.E. OME (2-4 players, tables) | yes | yes | yes |
| Archon OME | yes | yes | yes |
| Spy vs Spy OME (1-2 players, tables) | yes | yes | yes |

> The server is for your own network (LAN). It has no encryption or passwords: do not open its ports to the internet.

## Free fan versions

The games here are **free, non-commercial fan versions** of classic C64 games, made so that they can be
played over the network. They are not affiliated with or endorsed by the makers or current rights holders
of the original games; the original games, their names and their artwork belong to those rights holders.
Nothing here may be sold. If you are a rights holder and want something taken offline, open an issue in
the repository and it will be removed.
