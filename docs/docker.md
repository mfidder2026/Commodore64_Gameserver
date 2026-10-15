# The game server in your own Docker

> Part of the **[Commodore 64 Game Server](../README.md)**.

The [RELEASE](../RELEASE) folder has everything to run the game server in your own Docker:
a `Dockerfile` and a `docker-compose.yml` that build the image from the ready-made server in that
folder (`server/linux-x64` for a PC or a NAS, `server/linux-arm64` for a Raspberry Pi with a 64-bit
OS). No registry and no account are needed: download the repository (*Code → Download ZIP*), or
copy the RELEASE folder, and build it there.

The image only contains the server. The C64 side (the disk images, the lobby) is in
[RELEASE/games](../RELEASE/games).

> The server is for your own network (LAN). It has no encryption or passwords: never forward
> its ports to the internet.

## Start it

In the RELEASE folder:

```bash
docker compose up -d --build
```

Then open the dashboard: `http://<the computer's address>:8080/`. It shows the address the C64s
connect to (enter it in the lobby's setup, F1).

| Port | What |
|---|---|
| UDP 6465 | C64 Ultimate / Ultimate 64 |
| TCP 6466 | WiC64 |
| TCP 8080 | the dashboard |

Without Compose:

```bash
docker build -t c64gameserver .
docker run -d --name c64gameserver --restart unless-stopped --network host -v c64gs:/data c64gameserver
```

## Host network or ports

**Linux (Raspberry Pi, NAS, PC): the host network** (`network_mode: host` in the compose file,
`--network host` with `docker run`). The server then sees the LAN directly: the dashboard shows the
right address, and VICE's RR-Net (raw Ethernet through libpcap) works.

**Docker Desktop (Windows, macOS)** has no host network on the LAN. Publish the ports and tell the
server the computer's LAN address, which it cannot see from inside the container (in the compose
file: remove `network_mode` and `cap_add`, uncomment `ports` and `environment`):

```bash
docker run -d --name c64gameserver -p 6465:6465/udp -p 6466:6466 -p 8080:8080 -e C64GS_ADDRESSES=192.168.1.10 -v c64gs:/data c64gameserver
```

On Windows the server's own program (`start-server.bat`) is simpler, and it can do RR-Net with Npcap.

## Settings

The volume `/data` holds `server.json` (written with the defaults at the first start: every game,
with its bots) and `server.log`. To change a setting, edit `server.json` and restart:

```bash
docker compose cp c64gameserver:/data/server.json .       # copy it out, edit it ...
docker compose cp server.json c64gameserver:/data/        # ... and back
docker compose restart
```

All settings: [server/README.md](../server/README.md). Two that matter in Docker:

| Setting | Meaning |
|---|---|
| `addresses` | What the dashboard shows as "C64s connect to" (default: the container's own addresses). The environment variable `C64GS_ADDRESSES` (comma separated) overrides it |
| `pcapInterface` | Raw Ethernet for VICE's RR-Net, e.g. `eth0` (host network only; the compose file adds the capabilities `NET_RAW` and `NET_ADMIN`). The names: `docker run --rm --network host --cap-add NET_RAW c64gameserver --list-interfaces` |

## Update

Replace the RELEASE folder with the new one (your settings stay in the volume), then again:

```bash
docker compose up -d --build
```
