#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RDP_USERNAME:-${VNC_USERNAME:-goldenrecipe}}"
PASSWORD="${RDP_PASSWORD:-${VNC_PASSWORD:-}}"
if [[ -z "$PASSWORD" ]]; then
  echo "! VNC_PASSWORD or RDP_PASSWORD environment variable is required"
  exit 1
fi
ARD="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"

echo "* Configuring Apple Remote Desktop / Screen Sharing"

# Enable Screen Sharing launchd service
echo "- Enabling Screen Sharing service"
sudo defaults write /var/db/launchd.db/com.apple.launchd/overrides.plist com.apple.screensharing -dict Disabled -bool false
sudo launchctl enable system/com.apple.screensharing 2>/dev/null || true
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true

# Configure kickstart for ARD / Screen Sharing access for target user
echo "- Configuring kickstart permissions for $USERNAME"
sudo "$ARD" \
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

sleep 5

echo "* Verifying status"

echo "- Console user:"
stat -f '%Su' /dev/console 2>/dev/null || whoami

echo
echo "- Active TCP listeners on port 5900:"
sudo lsof -nP -iTCP:5900 -sTCP:LISTEN || true

echo
echo "- Checking VNC port reachability:"
if nc -z 127.0.0.1 5900; then
  echo "* VNC TCP port 5900 is reachable"
else
  echo "! VNC TCP port 5900 is not reachable"
  exit 1
fi

echo
echo "- Remote Management processes:"
ps aux | grep -Ei '[A]RDAgent|[Ss]creensharingd|[Ss]creensharingAgent|[Vv]NCPrivilegeProxy' || true
