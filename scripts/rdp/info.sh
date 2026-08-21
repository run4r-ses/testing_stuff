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

# Resolve Cloudflare tunnel URL (https://*.trycloudflare.com)
resolve_cloudflared_endpoint() {
  local ENDPOINT=""
  for _ in {1..35}; do
    if [[ -f /tmp/cloudflared.log ]]; then
      local CLEAN_LOG
      CLEAN_LOG="$(sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g' /tmp/cloudflared.log 2>/dev/null || true)"
      ENDPOINT="$(echo "$CLEAN_LOG" | grep -Eo 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' | head -n 1 || true)"
      if [[ -n "$ENDPOINT" ]]; then
        echo "$ENDPOINT"
        return 0
      fi
    fi
    sleep 1
  done
  echo ""
}

echo "- Resolving tunnel endpoints..."
CLOUDFLARE_URL="$(resolve_cloudflared_endpoint)"
NOVNC_ENDPOINT="$(resolve_bore_endpoint "/tmp/novnc_tunnel.log" "/tmp/novnc_tunnel.pid")"
VNC_ENDPOINT="$(resolve_bore_endpoint "/tmp/tunnel.log" "/tmp/tunnel.pid")"

echo
echo "* ==================================================="
echo "* Apple Remote Desktop & noVNC Web Interface Ready"
echo "* ==================================================="
echo "* OS Version:      $OS_VERSION"
echo "* RDP/VNC User:    $USERNAME"
echo "* Auth Protocol:   Legacy VncAuth (Password Only)"
echo "*"
if [[ -n "$CLOUDFLARE_URL" ]]; then
  echo "* [1] noVNC Web Browser Access (HTTPS - Recommended):"
  echo "*     URL:         $CLOUDFLARE_URL/vnc.html?autoconnect=true&resize=scale"
  echo "*     Prompt:      Password only (enter your configured secret password)"
  echo "*"
elif [[ -n "$NOVNC_ENDPOINT" ]]; then
  echo "* [1] noVNC Web Browser Access (HTTP Fallback):"
  echo "*     URL:         http://$NOVNC_ENDPOINT/vnc.html?autoconnect=true&resize=scale"
  echo "*     Prompt:      Password only (enter your configured secret password)"
  echo "*"
fi
if [[ -n "$VNC_ENDPOINT" ]]; then
  echo "* [2] Native VNC / Screen Sharing App Access:"
  echo "*     URL:         vnc://$VNC_ENDPOINT"
  echo "*     Direct Host: $VNC_ENDPOINT"
  echo "*     User:        $USERNAME (or legacy password authentication)"
  echo "*"
fi
if [[ -z "$CLOUDFLARE_URL" && -z "$NOVNC_ENDPOINT" && -z "$VNC_ENDPOINT" ]]; then
  echo "! Tunnel endpoints could not be established"
fi
echo "* ==================================================="
echo
