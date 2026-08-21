#!/usr/bin/env bash
set -euo pipefail

START_TIME=$(date +%s)

echo "* Running Apple Remote Desktop keepalive monitor"

# Prevent macOS sleep, display sleep, and idle throttling
caffeinate -dimsu &
CAFFEINATE_PID=$!

cleanup() {
  echo "* Stopping keepalive monitor"
  kill "$CAFFEINATE_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

export PATH="/tmp:/usr/local/bin:/opt/homebrew/bin:$PATH"
BORE_BIN="$(command -v bore 2>/dev/null || echo "/tmp/bore")"

while true; do
  CURRENT_TIME=$(date +%s)
  ELAPSED=$(( CURRENT_TIME - START_TIME ))
  ELAPSED_MIN=$(( ELAPSED / 60 ))

  # Watchdog: verify raw VNC bore tunnel is alive (port 5900)
  if [[ -f /tmp/tunnel.pid ]]; then
    PID="$(cat /tmp/tunnel.pid 2>/dev/null || true)"
    if [[ -z "$PID" ]] || ! kill -0 "$PID" 2>/dev/null; then
      echo "! raw VNC bore tunnel died, restarting..."
      if command -v bore >/dev/null 2>&1 || [[ -x /tmp/bore ]]; then
        nohup "$BORE_BIN" local 5900 --to bore.pub > /tmp/tunnel.log 2>&1 &
        echo $! > /tmp/tunnel.pid
      fi
    fi
  fi

  # Watchdog: verify noVNC bore tunnel is alive (port 6080)
  if [[ -f /tmp/novnc_tunnel.pid ]]; then
    NOVNC_PID="$(cat /tmp/novnc_tunnel.pid 2>/dev/null || true)"
    if [[ -z "$NOVNC_PID" ]] || ! kill -0 "$NOVNC_PID" 2>/dev/null; then
      echo "! noVNC bore tunnel died, restarting..."
      if command -v bore >/dev/null 2>&1 || [[ -x /tmp/bore ]]; then
        nohup "$BORE_BIN" local 6080 --to bore.pub > /tmp/novnc_tunnel.log 2>&1 &
        echo $! > /tmp/novnc_tunnel.pid
      fi
    fi
  fi

  # Watchdog: verify Serveo HTTPS tunnel is alive
  if [[ -f /tmp/serveo.pid ]]; then
    SERVEO_PID="$(cat /tmp/serveo.pid 2>/dev/null || true)"
    if [[ -z "$SERVEO_PID" ]] || ! kill -0 "$SERVEO_PID" 2>/dev/null; then
      echo "! Serveo tunnel died, restarting..."
      nohup ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -R 80:localhost:6080 serveo.net > /tmp/serveo.log 2>&1 &
      echo $! > /tmp/serveo.pid
    fi
  fi

  # Watchdog: verify websockify is alive (port 6080 -> 5900)
  if [[ -f /tmp/websockify.pid ]]; then
    WS_PID="$(cat /tmp/websockify.pid 2>/dev/null || true)"
    if [[ -z "$WS_PID" ]] || ! kill -0 "$WS_PID" 2>/dev/null; then
      echo "! websockify died, restarting..."
      NOVNC_DIR="/Users/Shared/noVNC"
      if command -v websockify >/dev/null 2>&1; then
        nohup websockify --web "$NOVNC_DIR" --heartbeat 30 6080 127.0.0.1:5900 > /tmp/websockify.log 2>&1 &
        echo $! > /tmp/websockify.pid
      elif python3 -m websockify --help >/dev/null 2>&1; then
        nohup python3 -m websockify --web "$NOVNC_DIR" --heartbeat 30 6080 127.0.0.1:5900 > /tmp/websockify.log 2>&1 &
        echo $! > /tmp/websockify.pid
      fi
    fi
  fi

  # Watchdog: ensure screensharing service is loaded in launchd
  if ! sudo launchctl list com.apple.screensharing >/dev/null 2>&1; then
    echo "! screensharing service not loaded in launchd, loading..."
    sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true
  fi

  # Extract active endpoints for logging
  SERVEO_URL="$(grep -Eo 'https?://[a-zA-Z0-9.-]+\.serveousercontent\.com' /tmp/serveo.log 2>/dev/null | head -n 1 || true)"
  if [[ -z "$SERVEO_URL" ]]; then
    SERVEO_URL="$(grep -Eo 'https?://[a-zA-Z0-9.-]+\.serveo\.net' /tmp/serveo.log 2>/dev/null | grep -v 'console\.serveo\.net' | head -n 1 || true)"
  fi
  if [[ -n "$SERVEO_URL" ]]; then
    SERVEO_URL="${SERVEO_URL/http:/https:}"
    echo "- [$(date '+%Y-%m-%d %H:%M:%S')] Keepalive active (${ELAPSED_MIN}m) | noVNC: $SERVEO_URL/vnc.html?autoconnect=true&resize=scale"
  else
    echo "- [$(date '+%Y-%m-%d %H:%M:%S')] Keepalive active (${ELAPSED_MIN}m) | noVNC tunnel starting..."
  fi

  sleep 15
done
