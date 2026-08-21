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

# Resolve Serveo HTTPS tunnel URL (https://*.serveousercontent.com or https://*.serveo.net)
resolve_serveo_endpoint() {
  local ENDPOINT=""
  for _ in {1..35}; do
    if [[ -f /tmp/serveo.log ]]; then
      local CLEAN_LOG
      CLEAN_LOG="$(sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g' /tmp/serveo.log 2>/dev/null || true)"

      # 1. Match *.serveousercontent.com (standard Serveo forward URL)
      ENDPOINT="$(echo "$CLEAN_LOG" | grep -Eo 'https?://[a-zA-Z0-9.-]+\.serveousercontent\.com' | head -n 1 || true)"

      # 2. Fallback to *.serveo.net (excluding console.serveo.net)
      if [[ -z "$ENDPOINT" ]]; then
        ENDPOINT="$(echo "$CLEAN_LOG" | grep -Eo 'https?://[a-zA-Z0-9.-]+\.serveo\.net' | grep -v 'console\.serveo\.net' | head -n 1 || true)"
      fi

      if [[ -n "$ENDPOINT" ]]; then
        ENDPOINT="${ENDPOINT/http:/https:}"
        echo "$ENDPOINT"
        return 0
      fi
    fi
    sleep 1
  done
  echo ""
}

echo "- Resolving tunnel endpoints..."
SERVEO_URL="$(resolve_serveo_endpoint)"
NOVNC_ENDPOINT="$(resolve_bore_endpoint "/tmp/novnc_tunnel.log" "/tmp/novnc_tunnel.pid")"
VNC_ENDPOINT="$(resolve_bore_endpoint "/tmp/tunnel.log" "/tmp/tunnel.pid")"

echo
echo "* ==================================================="
echo "* Apple Remote Desktop & noVNC Web Interface Ready"
echo "* ==================================================="
echo "* OS Version:      $OS_VERSION"
echo "* RDP/VNC User:    $USERNAME"
echo "* Auth Protocol:   Apple Remote Desktop (Username + Password)"
echo "*"
if [[ -n "$SERVEO_URL" ]]; then
  echo "* [1] noVNC Web Browser Access (Serveo HTTPS - Recommended):"
  echo "*     URL:         $SERVEO_URL/vnc.html?autoconnect=true&resize=scale"
  echo "*     Username:    $USERNAME"
  echo "*     Password:    (your configured secret password)"
  echo "*"
elif [[ -n "$NOVNC_ENDPOINT" ]]; then
  echo "* [1] noVNC Web Browser Access (Bore HTTP Fallback):"
  echo "*     URL:         http://$NOVNC_ENDPOINT/vnc.html?autoconnect=true&resize=scale"
  echo "*     Username:    $USERNAME"
  echo "*     Password:    (your configured secret password)"
  echo "*"
fi
if [[ -n "$VNC_ENDPOINT" ]]; then
  echo "* [2] Native VNC / Screen Sharing App Access:"
  echo "*     URL:         vnc://$VNC_ENDPOINT"
  echo "*     Direct Host: $VNC_ENDPOINT"
  echo "*     Username:    $USERNAME"
  echo "*     Password:    (your configured secret password)"
  echo "*"
fi
if [[ -z "$SERVEO_URL" && -z "$NOVNC_ENDPOINT" && -z "$VNC_ENDPOINT" ]]; then
  echo "! Tunnel endpoints could not be established"
fi
echo "* ==================================================="
echo
