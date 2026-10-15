#!/bin/sh
# Starts the C64 Game Server on Linux: a Raspberry Pi with a 64-bit OS (server/linux-arm64) or a
# PC (server/linux-x64). Settings: server.json in that folder. Docker: see docker-compose.yml.
#   ./start-server.sh                     run the server, dashboard at http://<this computer>:8080/
#   ./start-server.sh --list-interfaces   list the network adapters (raw Ethernet needs root or cap_net_raw)
case "$(uname -m)" in
  aarch64|arm64) rid=linux-arm64 ;;
  x86_64|amd64)  rid=linux-x64 ;;
  *) echo "No server for $(uname -m): a 64-bit OS (x86_64 or aarch64) is needed."; exit 1 ;;
esac
cd "$(dirname "$0")/server/$rid" || exit 1
chmod +x C64GameServer
exec ./C64GameServer "$@"
