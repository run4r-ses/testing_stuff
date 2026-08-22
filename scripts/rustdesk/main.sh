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

# 0. Wait for VNC loopback session to report successful connection before proceeding
echo "- Waiting for VNC loopback session to report successful connection..."
LOOPBACK_TIMEOUT=120
ELAPSED=0
LOOPBACK_SUCCESS=false

while [[ $ELAPSED -lt $LOOPBACK_TIMEOUT ]]; do
  if [[ -f /tmp/loopback_ready ]] || grep -q "Local VNC loopback session established!" /tmp/loopback_keeper.log 2>/dev/null; then
    echo "- VNC loopback connection confirmed! (after ${ELAPSED}s)"
    LOOPBACK_SUCCESS=true
    break
  fi
  sleep 1
  ELAPSED=$((ELAPSED + 1))
done

if [[ "$LOOPBACK_SUCCESS" != "true" ]]; then
  echo "! Error: VNC loopback session did not establish within ${LOOPBACK_TIMEOUT}s. Aborting RustDesk setup."
  exit 1
fi

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
USER_HOME="$(dscl . -read "/Users/$USERNAME" NFSHomeDirectory 2>/dev/null | sed 's/^NFSHomeDirectory:[[:space:]]*//' || echo "/Users/$USERNAME")"
USER_PREF_DIR="$USER_HOME/Library/Preferences/com.carriez.RustDesk"
sudo mkdir -p "$USER_PREF_DIR" /var/root/Library/Preferences/com.carriez.RustDesk
sudo chown -R "$USERNAME:staff" "$USER_PREF_DIR" 2>/dev/null || true

# 4. Install LaunchDaemon & LaunchAgent using install_service.sh
echo "- Installing RustDesk LaunchDaemon and LaunchAgent via install_service.sh for user $USERNAME..."
sudo bash "$SCRIPT_DIR/install_service.sh" -u "$USERNAME" 2>/dev/null || true

# 5. Set permanent unattended access password for target user
echo "- Setting unattended access password for RustDesk user $USERNAME..."
TARGET_UID="$(id -u "$USERNAME" 2>/dev/null || echo "502")"
if [[ -n "$TARGET_UID" && "$TARGET_UID" != "0" ]]; then
  launchctl asuser "$TARGET_UID" sudo -u "$USERNAME" env HOME="$USER_HOME" /Applications/RustDesk.app/Contents/MacOS/RustDesk --password "$PASSWORD" 2>/dev/null || \
  sudo -u "$USERNAME" env HOME="$USER_HOME" /Applications/RustDesk.app/Contents/MacOS/RustDesk --password "$PASSWORD" 2>/dev/null || true
else
  sudo -u "$USERNAME" env HOME="$USER_HOME" /Applications/RustDesk.app/Contents/MacOS/RustDesk --password "$PASSWORD" 2>/dev/null || true
fi
# Also apply to root system daemon
sudo /Applications/RustDesk.app/Contents/MacOS/RustDesk --password "$PASSWORD" 2>/dev/null || true

# Sync user configuration to root service directory and ensure proper permissions
sudo chown -R "$USERNAME:staff" "$USER_PREF_DIR" 2>/dev/null || true
if [[ -d "$USER_PREF_DIR" ]]; then
  sudo cp -a "$USER_PREF_DIR/"* /var/root/Library/Preferences/com.carriez.RustDesk/ 2>/dev/null || true
fi

# 6. Launch RustDesk in user GUI session
echo "- Launching RustDesk in GUI session for $USERNAME..."
if [[ -n "$TARGET_UID" && "$TARGET_UID" != "0" ]]; then
  launchctl asuser "$TARGET_UID" sudo -u "$USERNAME" env HOME="$USER_HOME" open -a /Applications/RustDesk.app 2>/dev/null || true
else
  sudo -u "$USERNAME" env HOME="$USER_HOME" open -a /Applications/RustDesk.app 2>/dev/null || true
fi

echo "* RustDesk service configured successfully"

