#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${RUSTDESK_USERNAME:-goldenrecipe}"
CONSOLE_USER="$(cat /tmp/rustdesk_user.txt 2>/dev/null || stat -f '%Su' /dev/console 2>/dev/null || echo "$TARGET_USER")"
if [[ -z "$CONSOLE_USER" || "$CONSOLE_USER" == "root" ]]; then
  CONSOLE_USER="$TARGET_USER"
fi

START_TIME=$(date +%s)

RUSTDESK_BIN="/Applications/RustDesk.app/Contents/MacOS/RustDesk"
if [[ ! -x "$RUSTDESK_BIN" && -x "/Applications/RustDesk.app/Contents/MacOS/rustdesk" ]]; then
  RUSTDESK_BIN="/Applications/RustDesk.app/Contents/MacOS/rustdesk"
fi

echo "* Running keepalive monitor for user $CONSOLE_USER"

cleanup() {
  echo "* Stopping keepalive monitor"
}
trap cleanup EXIT INT TERM

while true; do
  CURRENT_TIME=$(date +%s)
  ELAPSED=$(( CURRENT_TIME - START_TIME ))
  ELAPSED_MIN=$(( ELAPSED / 60 ))

  # Watchdog: verify RustDesk server is alive in the GUI session
  if ! pgrep -i "rustdesk" >/dev/null 2>&1; then
    echo "! RustDesk process not detected, kickstarting server for $CONSOLE_USER"
    if [[ -x "$RUSTDESK_BIN" ]]; then
      sudo -u "$CONSOLE_USER" nohup "$RUSTDESK_BIN" --server >/tmp/rustdesk.log 2>&1 &
    fi
  fi

  # Watchdog: verify bore tunnel is alive
  if [[ -f /tmp/tunnel.pid ]]; then
    PID="$(cat /tmp/tunnel.pid 2>/dev/null || true)"
    if [[ -z "$PID" ]] || ! kill -0 "$PID" 2>/dev/null; then
      echo "! bore tunnel died, restarting..."
      if command -v bore >/dev/null 2>&1; then
        nohup bore local 21118 --to bore.pub > /tmp/tunnel.log 2>&1 &
        echo $! > /tmp/tunnel.pid
      fi
    fi
  fi

  echo "- [$(date '+%Y-%m-%d %H:%M:%S')] Keepalive monitor active (running for ${ELAPSED_MIN}m)"
  sleep 60
done
