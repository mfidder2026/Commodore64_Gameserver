# The C64 Game Server in your own Docker: an image built from the ready-made server in this
# folder (server/linux-x64 for a PC or NAS, server/linux-arm64 for a Raspberry Pi with a 64-bit OS).
# No registry, no account: everything it needs is in this folder.
#
#   docker compose up -d --build        (docker-compose.yml in this folder)
#   docker build -t c64gameserver .     (or by hand, then see docker-compose.yml for the options)
#
# /data holds server.json (written with the defaults at the first start) and server.log.
# Ports: UDP 6465 (C64 Ultimate), TCP 6466 (WiC64), TCP 8080 (dashboard).

# --- the server for this machine's architecture ------------------------------------------------
FROM mcr.microsoft.com/dotnet/runtime-deps:8.0 AS pick
ARG TARGETARCH
COPY server/linux-x64/C64GameServer /amd64
COPY server/linux-arm64/C64GameServer /arm64
RUN arch="${TARGETARCH:-$(dpkg --print-architecture)}" \
 && case "$arch" in amd64|arm64) cp "/$arch" /C64GameServer ;; *) echo "no server for $arch"; exit 1 ;; esac \
 && chmod +x /C64GameServer

# --- the image ---------------------------------------------------------------------------------
FROM mcr.microsoft.com/dotnet/runtime-deps:8.0
# libpcap: raw Ethernet for VICE's RR-Net (server.json "pcapInterface"; host network only)
RUN apt-get update \
 && apt-get install -y --no-install-recommends libpcap0.8 \
 && rm -rf /var/lib/apt/lists/*
COPY --from=pick /C64GameServer /usr/local/bin/C64GameServer
WORKDIR /data
VOLUME /data
EXPOSE 6465/udp 6466/tcp 8080/tcp
# the arguments: the config file (default), or --list-interfaces (the names for pcapInterface)
ENTRYPOINT ["/usr/local/bin/C64GameServer"]
CMD ["/data/server.json"]
