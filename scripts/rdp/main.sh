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

# Configure kickstart for ARD / Screen Sharing access for target user
echo "- Configuring kickstart permissions for $USERNAME"
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -activate \
  -configure \
  -allowAccessFor -specifiedUsers \
  -access -on \
  -privs -all \
  -users "$USERNAME" \
  -clientopts -setvncpw -vncpw "$PASSWORD" \
  -clientopts -setvnclegacy -vnclegacy yes \
  -restart -agent -menu 2>/dev/null || true

# Ensure screensharing daemon is active
sudo launchctl kickstart -k system/com.apple.screensharing 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Setup noVNC & websockify (HTML5 Web Client)
# ────────────────────────────────────────────────────────────────────
echo "* Setting up noVNC web client"
if [[ ! -d /opt/noVNC ]]; then
  echo "- Cloning noVNC and websockify"
  sudo git clone --depth 1 https://github.com/novnc/noVNC.git /opt/noVNC 2>/dev/null || true
  sudo git clone --depth 1 https://github.com/novnc/websockify.git /opt/noVNC/utils/websockify 2>/dev/null || true
  sudo chmod -R 755 /opt/noVNC 2>/dev/null || true
fi

# Create default index.html redirecting to vnc.html with autoconnect
sudo cp /opt/noVNC/vnc.html /opt/noVNC/index.html 2>/dev/null || true

# Start noVNC proxy / websockify on port 8080
echo "- Starting noVNC proxy on port 8080"
if [[ -x /opt/noVNC/utils/novnc_proxy ]]; then
  nohup /opt/noVNC/utils/novnc_proxy --vnc 127.0.0.1:5900 --listen 8080 --web /opt/noVNC > /tmp/novnc.log 2>&1 &
  echo $! > /tmp/novnc.pid
elif command -v websockify >/dev/null 2>&1; then
  nohup websockify --web /opt/noVNC 8080 127.0.0.1:5900 > /tmp/novnc.log 2>&1 &
  echo $! > /tmp/novnc.pid
fi

# ────────────────────────────────────────────────────────────────────
# Start bore TCP tunnels for both raw VNC and noVNC Web
# ────────────────────────────────────────────────────────────────────
echo "* Starting bore tunnels"
if command -v bore >/dev/null 2>&1; then
  # 1. Native VNC Socket (Port 5900)
  echo "- Starting tunnel for Native VNC (port 5900)"
  nohup bore local 5900 --to bore.pub > /tmp/tunnel_vnc.log 2>&1 &
  echo $! > /tmp/tunnel_vnc.pid

  # 2. noVNC Web (Port 8080)
  echo "- Starting tunnel for noVNC Web (port 8080)"
  nohup bore local 8080 --to bore.pub > /tmp/tunnel_web.log 2>&1 &
  echo $! > /tmp/tunnel_web.pid
else
  echo "! bore-cli is not installed"
fi

echo "* Apple Remote Desktop, noVNC, and tunnels configured successfully"
