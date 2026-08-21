#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RDP_USERNAME:-${RUSTDESK_USERNAME:-goldenrecipe}}"
OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo "macOS")"

# Helper to extract endpoint from tunnel log
resolve_endpoint() {
  local LOG_FILE="$1"
  local PID_FILE="$2"
  local ENDPOINT=""

  for _ in {1..30}; do
    if [[ -f "$LOG_FILE" ]]; then
      local CLEAN_LOG
      CLEAN_LOG="$(sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g' "$LOG_FILE" 2>/dev/null || true)"

      # Match "bore.pub:XXXXX"
      ENDPOINT="$(echo "$CLEAN_LOG" | grep -Eo 'bore\.pub:[0-9]+' | head -n 1 || true)"

      # Generic fallback matching hostname:port
      if [[ -z "$ENDPOINT" ]]; then
        ENDPOINT="$(echo "$CLEAN_LOG" | grep -Ei 'listening at' | grep -Eo '[A-Za-z0-9.-]+\.[a-zA-Z]{2,}:[0-9]+' | head -n 1 || true)"
      fi

      if [[ -n "$ENDPOINT" ]]; then
        break
      fi
    fi

    if [[ -f "$PID_FILE" ]]; then
      local PID
      PID="$(cat "$PID_FILE" 2>/dev/null || true)"
      if [[ -n "$PID" ]] && ! kill -0 "$PID" 2>/dev/null; then
        break
      fi
    fi

    sleep 1
  done

  echo "$ENDPOINT"
}

VNC_ENDPOINT="$(resolve_endpoint "/tmp/tunnel_vnc.log" "/tmp/tunnel_vnc.pid")"
WEB_ENDPOINT="$(resolve_endpoint "/tmp/tunnel_web.log" "/tmp/tunnel_web.pid")"

echo
echo "* ==================================================="
echo "* Apple Remote Desktop & noVNC Web Desktop are ready"
echo "* ==================================================="
echo "* OS Version:        $OS_VERSION"
echo "* Desktop User:      $USERNAME"
echo
if [[ -n "$WEB_ENDPOINT" ]]; then
  echo "* [1] Web Browser Access (noVNC):"
  echo "*     http://$WEB_ENDPOINT/vnc.html?autoconnect=true&resize=scale"
  echo
fi
if [[ -n "$VNC_ENDPOINT" ]]; then
  echo "* [2] Native VNC / Screen Sharing Access:"
  echo "*     vnc://$VNC_ENDPOINT"
  echo "*     Host: $(echo "$VNC_ENDPOINT" | cut -d: -f1)  |  Port: $(echo "$VNC_ENDPOINT" | cut -d: -f2)"
  echo
fi
echo "* Credentials:"
echo "*     Username: $USERNAME"
echo "*     Password: (Your configured secret password)"
echo "* ==================================================="
echo
