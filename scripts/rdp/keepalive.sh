#!/usr/bin/env bash
set -euo pipefail

START_TIME=$(date +%s)

echo "* Running Apple Remote Desktop keepalive monitor"

cleanup() {
  echo "* Stopping keepalive monitor"
}
trap cleanup EXIT INT TERM

while true; do
  CURRENT_TIME=$(date +%s)
  ELAPSED=$(( CURRENT_TIME - START_TIME ))
  ELAPSED_MIN=$(( ELAPSED / 60 ))

  # Watchdog: verify bore tunnel is alive
  if [[ -f /tmp/tunnel.pid ]]; then
    PID="$(cat /tmp/tunnel.pid 2>/dev/null || true)"
    if [[ -z "$PID" ]] || ! kill -0 "$PID" 2>/dev/null; then
      echo "! bore tunnel died, restarting..."
      if command -v bore >/dev/null 2>&1; then
        nohup bore local 5900 --to bore.pub > /tmp/tunnel.log 2>&1 &
        echo $! > /tmp/tunnel.pid
      fi
    fi
  fi

  # Watchdog: verify screensharing service
  sudo launchctl kickstart -k system/com.apple.screensharing 2>/dev/null || true

  # Watchdog: suppress any rogue onboarding / Setup Assistant popups
  sudo killall "Setup Assistant" mbuseragent CloudConfigurationUI 2>/dev/null || true

  echo "- [$(date '+%Y-%m-%d %H:%M:%S')] Keepalive monitor active (running for ${ELAPSED_MIN}m)"
  sleep 15
done
