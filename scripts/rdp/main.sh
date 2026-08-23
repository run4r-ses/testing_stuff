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

# Disable macOS Application Firewall and Packet Filter to allow inbound connections
echo "- Ensuring macOS firewall allows incoming remote connections"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off 2>/dev/null || true
sudo pfctl -d 2>/dev/null || true

# Configure Screen Sharing preferences for unattended access & High Performance bypass
echo "- Setting Screen Sharing unattended preferences"
for plist in \
  "/Library/Preferences/com.apple.ScreenSharing" \
  "/Library/Preferences/com.apple.ScreenSharing.agent" \
  "/Library/Preferences/com.apple.RemoteManagement" \
  "/Users/$USERNAME/Library/Preferences/com.apple.ScreenSharing" \
  "/Users/$USERNAME/Library/Preferences/com.apple.ScreenSharing.agent" \
  "/Users/runner/Library/Preferences/com.apple.ScreenSharing" \
  "/Users/runner/Library/Preferences/com.apple.ScreenSharing.agent"; do
  sudo defaults write "$plist" AskToShare -bool false 2>/dev/null || true
  sudo defaults write "$plist" AcceptUnattendedRequests -bool true 2>/dev/null || true
  sudo defaults write "$plist" Authentication -int 1 2>/dev/null || true
  sudo defaults write "$plist" AllowDirectControl -bool true 2>/dev/null || true
  sudo defaults write "$plist" AskUser -bool false 2>/dev/null || true
  sudo defaults write "$plist" GuestAccess -bool false 2>/dev/null || true
  sudo defaults write "$plist" SkipLocalVNC -bool false 2>/dev/null || true
  sudo defaults write "$plist" BlankScreen -bool false 2>/dev/null || true
done

# Ensure screensharing daemon is active and reloaded with new preferences
sudo launchctl kickstart -k system/com.apple.screensharing 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Start raw VNC tunnel (port 5900) and loopback session keeper
# ────────────────────────────────────────────────────────────────────
export PATH="/tmp:/usr/local/bin:/opt/homebrew/bin:$PATH"

# Start background bore tunnel for raw VNC / Screen Sharing (port 5900)
if command -v bore >/dev/null 2>&1 || [[ -x /tmp/bore ]]; then
  BORE_BIN="$(command -v bore 2>/dev/null || echo "/tmp/bore")"
  echo "- Starting bore tunnel for raw VNC / Screen Sharing (port 5900)"
  nohup "$BORE_BIN" local 5900 --to bore.pub > /tmp/tunnel.log 2>&1 &
  echo $! > /tmp/tunnel.pid
else
  echo "! bore binary could not be installed"
fi

echo "* Apple Remote Desktop / Screen Sharing configured successfully"

