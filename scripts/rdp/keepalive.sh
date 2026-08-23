#!/usr/bin/env bash
set -euo pipefail

log_msg() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_msg "* Running Apple Remote Desktop keepalive monitor"

# Prevent macOS sleep, display sleep, and idle throttling
caffeinate -dimsu &
CAFFEINATE_PID=$!

cleanup() {
  log_msg "* Stopping keepalive monitor"
  kill "$CAFFEINATE_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

export PATH="/tmp:/usr/local/bin:/opt/homebrew/bin:$PATH"
BORE_BIN="$(command -v bore 2>/dev/null || echo "/tmp/bore")"

LOOP_COUNT=0
while true; do
  # Periodic heartbeat to keep GitHub Actions active and prevent silent step timeout (every 60s)
  if (( LOOP_COUNT % 4 == 0 )); then
    MINUTES=$(( LOOP_COUNT / 4 ))
    TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || echo "N/A")"
    log_msg "Heartbeat [${MINUTES}m]: Screen Sharing active | Tailscale: $TAILSCALE_IP"
  fi

  # Watchdog: verify raw VNC bore tunnel is alive (port 5900)
  if [[ -f /tmp/tunnel.pid ]]; then
    PID="$(cat /tmp/tunnel.pid 2>/dev/null || true)"
    if [[ -z "$PID" ]] || ! kill -0 "$PID" 2>/dev/null; then
      log_msg "! Raw VNC bore tunnel died, restarting..."
      if command -v bore >/dev/null 2>&1 || [[ -x /tmp/bore ]]; then
        nohup "$BORE_BIN" local 5900 --to bore.pub > /tmp/tunnel.log 2>&1 &
        echo $! > /tmp/tunnel.pid
      fi
    fi
  fi

  # Watchdog: ensure screensharing service is loaded in launchd
  if ! sudo launchctl list com.apple.screensharing >/dev/null 2>&1; then
    log_msg "! Screensharing service not loaded in launchd, loading..."
    sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true
  fi

  LOOP_COUNT=$(( LOOP_COUNT + 1 ))
  sleep 15
done
