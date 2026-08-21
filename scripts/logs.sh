#!/usr/bin/env bash
set -euo pipefail

echo "* Streaming live tunnel and noVNC logs"

NOVNC_PID="$(cat /tmp/novnc.pid 2>/dev/null || echo "")"
TUNNEL_PID="$(cat /tmp/tunnel.pid 2>/dev/null || echo "")"

# Start following all logs live in the background
tail -n +1 -F /tmp/novnc.log /tmp/tunnel.log &
TAIL_PID=$!

cleanup() {
  kill "$TAIL_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Monitor processes while streaming logs in real time
while true; do
  if [[ -n "$NOVNC_PID" ]] && ! kill -0 "$NOVNC_PID" 2>/dev/null; then
    echo
    echo "! noVNC proxy process ($NOVNC_PID) exited unexpectedly"
    sleep 2
    exit 1
  fi

  if [[ -n "$TUNNEL_PID" ]] && ! kill -0 "$TUNNEL_PID" 2>/dev/null; then
    echo
    echo "! Serveo tunnel process ($TUNNEL_PID) exited unexpectedly"
    sleep 2
    exit 1
  fi

  sleep 2
done
