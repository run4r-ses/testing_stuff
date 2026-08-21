#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RDP_USERNAME:-${VNC_USERNAME:-goldenrecipe}}"
PASSWORD="${RDP_PASSWORD:-${VNC_PASSWORD:-}}"
if [[ -z "$PASSWORD" ]]; then
  echo "! VNC_PASSWORD or RDP_PASSWORD environment variable is required"
  exit 1
fi

echo "* Starting noVNC proxy"

# Clean previous logs if any
touch /tmp/novnc.log /tmp/tunnel.log

/tmp/novnc/utils/novnc_proxy \
  --vnc 127.0.0.1:5900 \
  --listen 6080 \
  --heartbeat 10 \
  --web /tmp/novnc \
  >/tmp/novnc.log 2>&1 &

NOVNC_PID=$!
echo "$NOVNC_PID" > /tmp/novnc.pid
sleep 4

if ! kill -0 "$NOVNC_PID" 2>/dev/null; then
  echo "! noVNC proxy failed to start"
  cat /tmp/novnc.log || true
  exit 1
fi

if ! nc -z 127.0.0.1 6080; then
  echo "! noVNC is not listening on port 6080"
  cat /tmp/novnc.log || true
  exit 1
fi

echo "* noVNC is listening on http://127.0.0.1:6080"

echo "* Starting Serveo tunnel"

# Serveo uses plain SSH remote port forwarding — no client to install.
# -R 80:localhost:6080  → forward Serveo's port 80 to our local noVNC
# -o StrictHostKeyChecking=no  → auto-accept host key
# -o ServerAliveInterval=10   → SSH keepalive every 10s (prevents idle drop)
# -o ServerAliveCountMax=3    → disconnect after 3 missed keepalives (30s)
# -o ExitOnForwardFailure=yes → exit immediately if port forwarding fails

ssh \
  -o StrictHostKeyChecking=no \
  -o ServerAliveInterval=10 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  -R 80:localhost:6080 \
  serveo.net \
  >/tmp/tunnel.log 2>&1 &

TUNNEL_PID=$!
echo "$TUNNEL_PID" > /tmp/tunnel.pid
TUNNEL_URL=""

for _ in {1..30}; do
  TUNNEL_URL="$(
    grep -Eo 'https?://[A-Za-z0-9.-]+\.serveo\.net' /tmp/tunnel.log 2>/dev/null |
    head -n 1 || true
  )"

  if [[ -n "$TUNNEL_URL" ]]; then
    break
  fi

  # Check if ssh process died early
  if ! kill -0 "$TUNNEL_PID" 2>/dev/null; then
    echo "! Serveo SSH tunnel process died during startup"
    echo "--- tunnel.log ---"
    cat /tmp/tunnel.log || true
    exit 1
  fi

  sleep 1
done

if [[ -z "$TUNNEL_URL" ]]; then
  echo "! Could not obtain Serveo tunnel URL"
  echo "--- tunnel.log ---"
  cat /tmp/tunnel.log || true
  exit 1
fi

echo
echo "* macOS web desktop is ready"
echo "*" 
echo "* Web URL:      $TUNNEL_URL/vnc.html?autoconnect=true"
echo "* VNC username: $USERNAME"
echo "* Console user: $(stat -f '%Su' /dev/console 2>/dev/null || whoami)"
echo "*"
echo "* IMPORTANT NOTE!!!"
echo "* Using GitHub Actions as interactive remote desktops unless"
echo "* for debugging purposes is strictly forbidden by the Acceptable"
echo "* Use Policies. You must fully comply with GitHub's terms while"
echo "* using this script. YOU ARE FULLY RESPONSIBLE FOR YOUR ACTIONS!"
echo
