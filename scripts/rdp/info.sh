#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RDP_USERNAME:-${RUSTDESK_USERNAME:-goldenrecipe}}"
OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo "macOS")"

resolve_bore_endpoint() {
  local LOG_FILE="$1"
  local PID_FILE="$2"
  local ENDPOINT=""

  for _ in {1..30}; do
    if [[ -f "$LOG_FILE" ]]; then
      local CLEAN_LOG
      CLEAN_LOG="$(sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g' "$LOG_FILE" 2>/dev/null || true)"

      ENDPOINT="$(echo "$CLEAN_LOG" | grep -Eo 'bore\.pub:[0-9]+' | head -n 1 || true)"
      if [[ -z "$ENDPOINT" ]]; then
        ENDPOINT="$(echo "$CLEAN_LOG" | grep -Ei 'listening at' | grep -Eo '[A-Za-z0-9.-]+\.[a-zA-Z]{2,}:[0-9]+' | head -n 1 || true)"
      fi

      if [[ -n "$ENDPOINT" ]]; then
        echo "$ENDPOINT"
        return 0
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

  echo ""
}

echo "- Resolving tunnel and Tailscale endpoints"
VNC_ENDPOINT="$(resolve_bore_endpoint "/tmp/tunnel.log" "/tmp/tunnel.pid")"
TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || true)"

echo
echo "* macOS desktop is ready"
echo "* OS version:      $OS_VERSION"
echo "* Username:        $USERNAME"
echo "*"

if [[ -n "$TAILSCALE_IP" ]]; then
  echo "* [1] Tailscale connection:"
  echo "*     Tailscale IP: $TAILSCALE_IP"
  echo "*     VNC server:   $TAILSCALE_IP:5900"
  echo "*"
fi

if [[ -n "$VNC_ENDPOINT" ]]; then
  echo "* [2] VNC tunnel:"
  echo "*     VNC server:         $VNC_ENDPOINT"
  echo "*"
fi

if [[ -z "$TAILSCALE_IP" && -z "$VNC_ENDPOINT" ]]; then
  echo "! No endpoints could be established"
fi
echo "*"
echo
