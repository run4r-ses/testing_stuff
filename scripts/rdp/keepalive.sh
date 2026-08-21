#!/usr/bin/env bash
set -euo pipefail

log_msg() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_msg "* Running Apple Remote Desktop & tunnel keepalive monitor"

# Prevent macOS sleep, display sleep, and idle throttling
caffeinate -dimsu &
CAFFEINATE_PID=$!

# Stream Serveo SSH logs and loopback keeper logs in real-time to stdout
touch /tmp/serveo.log /tmp/loopback_keeper.log
tail -n +1 -F /tmp/serveo.log 2>/dev/null &
TAIL_SERVEO_PID=$!
tail -n +1 -F /tmp/loopback_keeper.log 2>/dev/null &
TAIL_LOOPBACK_PID=$!

cleanup() {
  log_msg "* Stopping keepalive monitor"
  kill "$CAFFEINATE_PID" "$TAIL_SERVEO_PID" "$TAIL_LOOPBACK_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

export PATH="/tmp:/usr/local/bin:/opt/homebrew/bin:$PATH"
BORE_BIN="$(command -v bore 2>/dev/null || echo "/tmp/bore")"

while true; do
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

  # Watchdog: verify noVNC bore tunnel is alive (port 6080)
  if [[ -f /tmp/novnc_tunnel.pid ]]; then
    NOVNC_PID="$(cat /tmp/novnc_tunnel.pid 2>/dev/null || true)"
    if [[ -z "$NOVNC_PID" ]] || ! kill -0 "$NOVNC_PID" 2>/dev/null; then
      log_msg "! noVNC bore tunnel died, restarting..."
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
      log_msg "! Serveo SSH tunnel died, restarting..."
      nohup ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -R 80:localhost:6080 serveo.net >> /tmp/serveo.log 2>&1 &
      echo $! > /tmp/serveo.pid
    fi
  fi

  # Watchdog: verify websockify is alive (port 6080 -> 5900)
  if [[ -f /tmp/websockify.pid ]]; then
    WS_PID="$(cat /tmp/websockify.pid 2>/dev/null || true)"
    if [[ -z "$WS_PID" ]] || ! kill -0 "$WS_PID" 2>/dev/null; then
      log_msg "! Websockify died, restarting..."
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
    log_msg "! Screensharing service not loaded in launchd, loading..."
    sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true
  fi

  # Watchdog: ensure RustDesk service is loaded in launchd if installed
  if [[ -f "/Library/LaunchDaemons/com.carriez.RustDesk_service.plist" ]]; then
    if ! sudo launchctl list com.carriez.RustDesk_service >/dev/null 2>&1; then
      log_msg "! RustDesk service not loaded in launchd, reloading..."
      sudo launchctl load -w /Library/LaunchDaemons/com.carriez.RustDesk_service.plist 2>/dev/null || true
    fi
  fi

  # Watchdog: verify local VNC loopback keeper is alive
  if [[ -f /tmp/loopback_keeper.pid ]]; then
    LK_PID="$(cat /tmp/loopback_keeper.pid 2>/dev/null || true)"
    if [[ -z "$LK_PID" ]] || ! kill -0 "$LK_PID" 2>/dev/null; then
      log_msg "! Local VNC loopback keeper died, restarting..."
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      nohup python3 "$SCRIPT_DIR/loopback_keeper.py" >> /tmp/loopback_keeper.log 2>&1 &
      echo $! > /tmp/loopback_keeper.pid
    fi
  fi

  sleep 15
done
