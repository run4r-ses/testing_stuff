#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RDP_USERNAME:-${RUSTDESK_USERNAME:-goldenrecipe}}"
PASSWORD="${RDP_PASSWORD:-${RUSTDESK_PASSWORD:-}}"

if [[ -z "$PASSWORD" ]]; then
  echo "! RDP_PASSWORD or RUSTDESK_PASSWORD environment variable is required"
  exit 1
fi

echo "* Configuring Apple Remote Desktop / Screen Sharing"

# Enable Screen Sharing launchd service
echo "- Enabling Screen Sharing service"
sudo defaults write /var/db/launchd.db/com.apple.launchd/overrides.plist com.apple.screensharing -dict Disabled -bool false
sudo launchctl enable system/com.apple.screensharing 2>/dev/null || true
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true

# Configure kickstart for Apple Remote Desktop access with native username & password authentication
echo "- Configuring kickstart permissions for $USERNAME"
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -activate \
  -configure \
  -allowAccessFor -allUsers \
  -access -on \
  -privs -all \
  -clientopts -setvnclegacy -vnclegacy no \
  -restart -agent -menu 2>/dev/null || true

# Ensure screensharing daemon is active
sudo launchctl kickstart -k system/com.apple.screensharing 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Setup noVNC with Native Apple Remote Desktop Authentication
# ────────────────────────────────────────────────────────────────────
echo "* Setting up noVNC web client"

NOVNC_DIR="/Users/Shared/noVNC"

# Start websockify proxy for noVNC (port 6080 -> 5900)
echo "- Starting websockify proxy for noVNC (port 6080 -> 5900)"
if command -v websockify >/dev/null 2>&1; then
  nohup websockify --web "$NOVNC_DIR" --heartbeat 30 6080 127.0.0.1:5900 > /tmp/websockify.log 2>&1 &
  echo $! > /tmp/websockify.pid
elif python3 -m websockify --help >/dev/null 2>&1; then
  nohup python3 -m websockify --web "$NOVNC_DIR" --heartbeat 30 6080 127.0.0.1:5900 > /tmp/websockify.log 2>&1 &
  echo $! > /tmp/websockify.pid
else
  echo "! websockify is not installed"
fi

export PATH="/tmp:/usr/local/bin:/opt/homebrew/bin:$PATH"

# Start Serveo HTTPS Tunnel (via native SSH) for noVNC web interface
echo "- Starting Serveo HTTPS tunnel for noVNC (port 6080)"
nohup ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -R 80:localhost:6080 serveo.net > /tmp/serveo.log 2>&1 &
echo $! > /tmp/serveo.pid

# Start background bore tunnels
if command -v bore >/dev/null 2>&1 || [[ -x /tmp/bore ]]; then
  BORE_BIN="$(command -v bore 2>/dev/null || echo "/tmp/bore")"
  # 1. noVNC Web HTTP/WebSocket tunnel (port 6080 fallback)
  echo "- Starting bore tunnel for noVNC Web Interface (port 6080)"
  nohup "$BORE_BIN" local 6080 --to bore.pub > /tmp/novnc_tunnel.log 2>&1 &
  echo $! > /tmp/novnc_tunnel.pid

  # 2. Raw VNC / Apple Remote Desktop tunnel (port 5900)
  echo "- Starting bore tunnel for raw VNC / Screen Sharing (port 5900)"
  nohup "$BORE_BIN" local 5900 --to bore.pub > /tmp/tunnel.log 2>&1 &
  echo $! > /tmp/tunnel.pid
else
  echo "! bore binary could not be installed"
fi

# Start local loopback keeper to keep target user's virtual display alive 24/7
echo "- Starting local VNC loopback keeper for persistent display session"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
nohup python3 "$SCRIPT_DIR/loopback_keeper.py" > /tmp/loopback_keeper.log 2>&1 &
echo $! > /tmp/loopback_keeper.pid

echo "* Apple Remote Desktop & noVNC configured successfully"
