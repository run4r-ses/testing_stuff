#!/usr/bin/env bash
set -euo pipefail

USERNAME="${VNC_USERNAME:-runneradmin}"
if [[ -z "${VNC_PASSWORD:-}" ]]; then
  echo "! VNC_PASSWORD environment variable is required"
  exit 1
fi
PASSWORD="$VNC_PASSWORD"

echo "* Starting noVNC proxy"

/tmp/novnc/utils/novnc_proxy \
  --vnc 127.0.0.1:5900 \
  --listen 6080 \
  >/tmp/novnc.log 2>&1 &

NOVNC_PID=$!
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

echo "* Starting Cloudflare Quick Tunnel"

cloudflared tunnel \
  --url http://127.0.0.1:6080 \
  --logfile /tmp/cloudflared.log \
  >/tmp/cloudflared.stdout 2>&1 &

CLOUDFLARED_PID=$!
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


echo "* macOS web desktop is ready"
echo "*" 
echo "* Web URL:      $TUNNEL_URL/vnc.html?autoconnect=true"
echo "* VNC username: $USERNAME"
echo "* Console user: $(stat -f '%Su' /dev/console 2>/dev/null || whoami)"

echo "--- noVNC log tail ---"
tail -n 15 /tmp/novnc.log || true

echo
echo "--- Cloudflare log tail ---"
tail -n 15 /tmp/cloudflared.log || true

echo
echo "- Waiting on Cloudflare tunnel"
wait "$CLOUDFLARED_PID"
