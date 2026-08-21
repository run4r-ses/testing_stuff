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

# 1. Install RustDesk.app if not present
if [[ ! -d "/Applications/RustDesk.app" ]]; then
  echo "- Installing RustDesk via Homebrew..."
  brew install --cask rustdesk 2>/dev/null || true
fi

# Fallback: Download direct DMG from GitHub Releases if Homebrew failed
if [[ ! -d "/Applications/RustDesk.app" ]]; then
  echo "- Homebrew install unavailable, downloading RustDesk directly from GitHub Releases..."
  ARCH="$(uname -m)"
  if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
    DMG_URL="https://github.com/rustdesk/rustdesk/releases/download/1.3.7/rustdesk-1.3.7-aarch64.dmg"
  else
    DMG_URL="https://github.com/rustdesk/rustdesk/releases/download/1.3.7/rustdesk-1.3.7-x86_64.dmg"
  fi

  curl -fsSL "$DMG_URL" -o /tmp/rustdesk.dmg 2>/dev/null || true
  if [[ -f /tmp/rustdesk.dmg ]]; then
    echo "- Mounting RustDesk DMG..."
    hdiutil attach /tmp/rustdesk.dmg -nobrowse -mountpoint /Volumes/RustDesk 2>/dev/null || true
    if [[ -d "/Volumes/RustDesk/RustDesk.app" ]]; then
      sudo cp -R /Volumes/RustDesk/RustDesk.app /Applications/
    fi
    hdiutil detach /Volumes/RustDesk 2>/dev/null || true
    rm -f /tmp/rustdesk.dmg
  fi
fi

if [[ ! -d "/Applications/RustDesk.app" ]]; then
  echo "! Failed to install RustDesk.app"
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
