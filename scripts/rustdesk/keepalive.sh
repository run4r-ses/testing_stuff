#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RUSTDESK_USERNAME:-runneradmin}"
START_TIME=$(date +%s)

RUSTDESK_BIN="/Applications/RustDesk.app/Contents/MacOS/RustDesk"
if [[ ! -x "$RUSTDESK_BIN" && -x "/Applications/RustDesk.app/Contents/MacOS/rustdesk" ]]; then
  RUSTDESK_BIN="/Applications/RustDesk.app/Contents/MacOS/rustdesk"
fi

echo "* Running keepalive monitor"

cleanup() {
  echo "* Stopping keepalive monitor"
}
trap cleanup EXIT INT TERM

while true; do
  CURRENT_TIME=$(date +%s)
  ELAPSED=$(( CURRENT_TIME - START_TIME ))
  ELAPSED_MIN=$(( ELAPSED / 60 ))

  # Watchdog: verify RustDesk server is alive
  if ! pgrep -i "rustdesk" >/dev/null 2>&1; then
    echo "! RustDesk process not detected, kickstarting server"
    if [[ -x "$RUSTDESK_BIN" ]]; then
      sudo -u "$USERNAME" nohup "$RUSTDESK_BIN" --server >/tmp/rustdesk.log 2>&1 &
    fi
  fi

  echo "- [$(date '+%Y-%m-%d %H:%M:%S')] Keepalive monitor active (running for ${ELAPSED_MIN}m)"
  sleep 60
done
