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

echo "- Resolving tunnel and Tailscale endpoints..."
VNC_ENDPOINT="$(resolve_bore_endpoint "/tmp/tunnel.log" "/tmp/tunnel.pid")"
TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || true)"

echo
echo "* ==================================================="
echo "* macOS Screen Sharing & Remote Access Ready"
echo "* ==================================================="
echo "* OS Version:      $OS_VERSION"
echo "* Username:        $USERNAME"
echo "* Password:        (your configured secret password)"
echo "*"

if [[ -n "$TAILSCALE_IP" ]]; then
  echo "* [1] Tailscale High-Performance Mode (Recommended):"
  echo "*     Tailscale IP: $TAILSCALE_IP"
  echo "*     Hostname:     macos-runner"
  echo "*     Port:         5900 (TCP/UDP), 5901 (UDP Video)"
  echo "*"
  echo "*     - iShareScreen (iss CLI):"
  echo "*       iss --host $TAILSCALE_IP -u $USERNAME --alt-session"
  echo "*"
  echo "*     - TigerVNC / Native VNC (Direct WireGuard):"
  echo "*       Server:     $TAILSCALE_IP:5900"
  echo "*"
  echo "*     - Mac Screen Sharing App (High Performance):"
  echo "*       URL:        vnc://$TAILSCALE_IP"
  echo "*"
fi

if [[ -n "$VNC_ENDPOINT" ]]; then
  echo "* [2] Public VNC Tunnel (TigerVNC Fallback - No Tailscale needed):"
  echo "*     Direct Host:  $VNC_ENDPOINT"
  echo "*     URL:          vnc://$VNC_ENDPOINT"
  echo "*     Username:     $USERNAME"
  echo "*"
fi

if [[ -z "$TAILSCALE_IP" && -z "$VNC_ENDPOINT" ]]; then
  echo "! Warning: No endpoints could be established"
fi
echo "* ==================================================="
echo
