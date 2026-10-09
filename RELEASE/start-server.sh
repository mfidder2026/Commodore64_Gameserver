#!/bin/sh
# Starts the C64 Game Server on a Raspberry Pi (64-bit OS). Settings: server/linux-arm64/server.json.
#   ./start-server.sh                     run the server, dashboard at http://<pi>:8080/
#   ./start-server.sh --list-interfaces   list the network adapters (raw Ethernet needs root or cap_net_raw)
cd "$(dirname "$0")/server/linux-arm64" || exit 1
chmod +x C64GameServer
exec ./C64GameServer "$@"
