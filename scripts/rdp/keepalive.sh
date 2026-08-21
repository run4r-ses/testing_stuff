#!/usr/bin/env bash
set -euo pipefail

START_TIME=$(date +%s)

echo "* Running Apple Remote Desktop & noVNC keepalive monitor"

cleanup() {
  echo "* Stopping keepalive monitor"
}
trap cleanup EXIT INT TERM

while true; do
  CURRENT_TIME=$(date +%s)
  ELAPSED=$(( CURRENT_TIME - START_TIME ))
  ELAPSED_MIN=$(( ELAPSED / 60 ))

  # 1. Watchdog: verify screensharing service
  sudo launchctl kickstart -k system/com.apple.screensharing 2>/dev/null || true

  # 2. Watchdog: verify noVNC proxy
  if [[ -f /tmp/novnc.pid ]]; then
    PID="$(cat /tmp/novnc.pid 2>/dev/null || true)"
    if [[ -z "$PID" ]] || ! kill -0 "$PID" 2>/dev/null; then
      echo "! noVNC proxy died, restarting..."
      if [[ -x /opt/noVNC/utils/novnc_proxy ]]; then
        nohup /opt/noVNC/utils/novnc_proxy --vnc 127.0.0.1:5900 --listen 8080 --web /opt/noVNC > /tmp/novnc.log 2>&1 &
        echo $! > /tmp/novnc.pid
      fi
    fi
  fi

  # 3. Watchdog: verify VNC bore tunnel
  if [[ -f /tmp/tunnel_vnc.pid ]]; then
    PID="$(cat /tmp/tunnel_vnc.pid 2>/dev/null || true)"
    if [[ -z "$PID" ]] || ! kill -0 "$PID" 2>/dev/null; then
      echo "! bore VNC tunnel died, restarting..."
      if command -v bore >/dev/null 2>&1; then
        nohup bore local 5900 --to bore.pub > /tmp/tunnel_vnc.log 2>&1 &
        echo $! > /tmp/tunnel_vnc.pid
      fi
    fi
  fi

  # 4. Watchdog: verify Web bore tunnel
  if [[ -f /tmp/tunnel_web.pid ]]; then
    PID="$(cat /tmp/tunnel_web.pid 2>/dev/null || true)"
    if [[ -z "$PID" ]] || ! kill -0 "$PID" 2>/dev/null; then
      echo "! bore Web tunnel died, restarting..."
      if command -v bore >/dev/null 2>&1; then
        nohup bore local 8080 --to bore.pub > /tmp/tunnel_web.log 2>&1 &
        echo $! > /tmp/tunnel_web.pid
      fi
    fi
  fi

  echo "- [$(date '+%Y-%m-%d %H:%M:%S')] Keepalive monitor active (running for ${ELAPSED_MIN}m)"
  sleep 60
done
