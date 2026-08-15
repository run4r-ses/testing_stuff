#!/usr/bin/env bash
set -euo pipefail

USERNAME="${VNC_USERNAME:-runneradmin}"
if [[ -z "${VNC_PASSWORD:-}" ]]; then
  echo "! VNC_PASSWORD environment variable is required"
  exit 1
fi
PASSWORD="$VNC_PASSWORD"

echo "* Starting noVNC proxy"

# Clean previous logs if any
touch /tmp/novnc.log /tmp/cloudflared.log

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

echo "* Starting Cloudflare Tunnel (HTTP/2 mode)"

# --protocol http2:      Force HTTP/2 — far more stable for WebSocket traffic
#                         than QUIC which drops with "no recent network activity"
# --post-quantum false:   Disabling post-quantum forces HTTP/2 (PQ requires QUIC)
# --ha-connections 4:     4 redundant connections — if one drops, others keep serving
# --heartbeat-interval:   5s keepalive to detect dead connections fast
# --heartbeat-count 5:    Mark connection dead after 5 missed heartbeats
# --grace-period 30s:     Allow 30s for reconnection before giving up
# --retries 10:           More retries for transient failures
#
# REMOVED: --no-chunked-encoding (breaks HTTP/2 stream multiplexing, stalls
#          WebSocket frames for noVNC)

cloudflared tunnel \
  --url http://127.0.0.1:6080 \
  --protocol http2 \
  --post-quantum false \
  --ha-connections 4 \
  --edge-ip-version 4 \
  --http-host-header 127.0.0.1:6080 \
  --heartbeat-interval 5s \
  --heartbeat-count 5 \
  --retries 10 \
  --grace-period 30s \
  --logfile /tmp/cloudflared.log \
  >/tmp/cloudflared.stdout 2>&1 &

CLOUDFLARED_PID=$!
echo "$CLOUDFLARED_PID" > /tmp/cloudflared.pid
TUNNEL_URL=""

for _ in {1..30}; do
  TUNNEL_URL="$(
    {
      cat /tmp/cloudflared.log 2>/dev/null || true
      cat /tmp/cloudflared.stdout 2>/dev/null || true
    } |
    grep -Eo 'https://[A-Za-z0-9.-]+\.trycloudflare\.com' |
    head -n 1 || true
  )"

  if [[ -n "$TUNNEL_URL" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "$TUNNEL_URL" ]]; then
  echo "! Could not obtain Cloudflare tunnel URL"
  echo "--- cloudflared.log ---"
  cat /tmp/cloudflared.log || true
  echo "--- cloudflared.stdout ---"
  cat /tmp/cloudflared.stdout || true
  exit 1
fi

# Start a lightweight keepalive that prevents idle timeouts by pinging
# the local noVNC endpoint every 30s. This keeps the tunnel connections
# warm even when no user is connected.
(
  while true; do
    curl -sf http://127.0.0.1:6080/ >/dev/null 2>&1 || true
    sleep 30
  done
) &
KEEPALIVE_PID=$!
echo "$KEEPALIVE_PID" > /tmp/keepalive.pid

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
