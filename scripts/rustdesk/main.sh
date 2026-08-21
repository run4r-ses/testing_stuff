#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERNAME="${RDP_USERNAME:-${RUSTDESK_USERNAME:-goldenrecipe}}"
PASSWORD="${RDP_PASSWORD:-${RUSTDESK_PASSWORD:-}}"

if [[ -z "$PASSWORD" ]]; then
  echo "! RDP_PASSWORD or RUSTDESK_PASSWORD environment variable is required"
  exit 1
fi

echo "* Configuring RustDesk unattended remote access"

# 1. Verify RustDesk.app exists
if [[ ! -d "/Applications/RustDesk.app" ]]; then
  echo "! RustDesk.app not found in /Applications"
  exit 1
fi

echo "- RustDesk.app located at /Applications/RustDesk.app"

# 2. Strip Gatekeeper quarantine flags
sudo xattr -r -d com.apple.quarantine /Applications/RustDesk.app 2>/dev/null || true
sudo chmod -R 755 /Applications/RustDesk.app 2>/dev/null || true

# 3. Ensure user preference directory exists
USER_PREF_DIR="/Users/$USERNAME/Library/Preferences/com.carriez.RustDesk"
sudo mkdir -p "$USER_PREF_DIR" /var/root/Library/Preferences/com.carriez.RustDesk
sudo chown -R "$USERNAME:staff" "$USER_PREF_DIR" 2>/dev/null || true

# 4. Install LaunchDaemon & LaunchAgent using install_service.sh
echo "- Installing RustDesk LaunchDaemon and LaunchAgent via install_service.sh..."
sudo bash "$SCRIPT_DIR/install_service.sh" -u "$USERNAME" 2>/dev/null || true

# 5. Set permanent unattended access password
echo "- Setting unattended access password for RustDesk..."
sudo /Applications/RustDesk.app/Contents/MacOS/RustDesk --password "$PASSWORD" 2>/dev/null || true

# 6. Launch RustDesk in user GUI session
TARGET_UID="$(id -u "$USERNAME" 2>/dev/null || echo "502")"
if [[ -n "$TARGET_UID" ]]; then
  launchctl asuser "$TARGET_UID" sudo -u "$USERNAME" open -a /Applications/RustDesk.app 2>/dev/null || true
fi

echo "* RustDesk service configured successfully"
