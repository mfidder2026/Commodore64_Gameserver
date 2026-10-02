#!/bin/bash
# Runs 64tass inside WSL. Fetches the official Ubuntu package (no root needed) on first use.
T="$HOME/t64/x/usr/bin/64tass"
if [ ! -x "$T" ]; then
  mkdir -p "$HOME/t64" && cd "$HOME/t64" && apt-get download 64tass >/dev/null && dpkg -x 64tass_*.deb x || exit 1
  cd - >/dev/null
fi
exec "$T" "$@"
