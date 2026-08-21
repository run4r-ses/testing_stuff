#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RDP_USERNAME:-${RUSTDESK_USERNAME:-goldenrecipe}}"
OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo "macOS")"

# Resolve direct tunnel host/port (bore.pub)
TUNNEL_ENDPOINT=""
for _ in {1..30}; do
  if [[ -f /tmp/tunnel.log ]]; then
    # Strip ANSI color/control codes
    CLEAN_LOG="$(sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g' /tmp/tunnel.log 2>/dev/null || true)"

    # 1. Match "bore.pub:XXXXX"
    TUNNEL_ENDPOINT="$(
      echo "$CLEAN_LOG" |
      grep -Eo 'bore\.pub:[0-9]+' |
      head -n 1 || true
    )"

    # 2. Generic fallback matching hostname:port from "listening at ..."
    if [[ -z "$TUNNEL_ENDPOINT" ]]; then
      TUNNEL_ENDPOINT="$(
        echo "$CLEAN_LOG" |
        grep -Ei 'listening at' |
        grep -Eo '[A-Za-z0-9.-]+\.[a-zA-Z]{2,}:[0-9]+' |
        head -n 1 || true
      )"
    fi

    if [[ -n "$TUNNEL_ENDPOINT" ]]; then
      break
    fi
  fi

  # Check if tunnel process died early
  if [[ -f /tmp/tunnel.pid ]]; then
    PID="$(cat /tmp/tunnel.pid 2>/dev/null || true)"
    if [[ -n "$PID" ]] && ! kill -0 "$PID" 2>/dev/null; then
      echo "! bore tunnel process died during startup (PID $PID)"
      if [[ -f /tmp/tunnel.log ]]; then
        echo "--- tunnel.log ---"
        cat /tmp/tunnel.log || true
        echo "------------------"
      fi
      break
    fi
  fi

  sleep 1
done

if [[ -z "$TUNNEL_ENDPOINT" && -f /tmp/tunnel.log ]]; then
  echo "! Could not detect direct tunnel endpoint"
  echo "--- tunnel.log ---"
  cat /tmp/tunnel.log || true
  echo "------------------"
fi

echo
echo "* ==================================================="
echo "* Apple Remote Desktop / Screen Sharing is ready"
echo "* ==================================================="
echo "* OS Version:      $OS_VERSION"
echo "* RDP/VNC User:    $USERNAME"
if [[ -n "$TUNNEL_ENDPOINT" ]]; then
  echo "* Direct host:     $TUNNEL_ENDPOINT"
  echo "*"
  echo "* Connection URLs:"
  echo "*   vnc://$TUNNEL_ENDPOINT"
  echo "*"
  echo "* How to connect:"
  echo "*   1. Open Screen Sharing / VNC client"
  echo "*   2. Connect to: $TUNNEL_ENDPOINT"
  echo "*   3. Authenticate with user: $USERNAME and your configured secret password"
  echo "*   4. macOS will start a dedicated desktop session for $USERNAME"
else
  echo "! Tunnel endpoint could not be established"
fi
echo "* ==================================================="
echo
