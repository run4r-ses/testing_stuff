#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERNAME="${RDP_USERNAME:-${RUSTDESK_USERNAME:-goldenrecipe}}"
PASSWORD="${RDP_PASSWORD:-${RUSTDESK_PASSWORD:-}}"
TARGET_UID="$(id -u "$USERNAME" 2>/dev/null || echo "502")"
USER_HOME="$(dscl . -read "/Users/$USERNAME" NFSHomeDirectory 2>/dev/null | sed 's/^NFSHomeDirectory:[[:space:]]*//' || echo "/Users/$USERNAME")"

if [[ -z "$PASSWORD" ]]; then
  echo "! RDP_PASSWORD or RUSTDESK_PASSWORD environment variable is required"
  exit 1
fi

echo "* Configuring RustDesk unattended remote access for user $USERNAME"

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
  echo "! Warning: VNC loopback session was not established within ${LOOPBACK_TIMEOUT}s, proceeding..."
fi

# Locate RustDesk binary
RUSTDESK_BIN="/Applications/RustDesk.app/Contents/MacOS/RustDesk"
if [[ ! -x "$RUSTDESK_BIN" && -x "/Applications/RustDesk.app/Contents/MacOS/rustdesk" ]]; then
  RUSTDESK_BIN="/Applications/RustDesk.app/Contents/MacOS/rustdesk"
fi

if [[ ! -x "$RUSTDESK_BIN" ]]; then
  echo "! RustDesk executable not found"
  exit 1
fi

echo "- RustDesk binary located at $RUSTDESK_BIN"

# 1. Strip Gatekeeper quarantine flags
echo "- Removing Gatekeeper quarantine"
sudo xattr -cr /Applications/RustDesk.app 2>/dev/null || true
sudo xattr -rd com.apple.quarantine /Applications/RustDesk.app 2>/dev/null || true
sudo chmod -R 755 /Applications/RustDesk.app 2>/dev/null || true

# 2. Pre-create preference directories and optimized config files for target user and root
echo "- Initializing preference directories and configuration for user $USERNAME"
for U in "$USERNAME" "root"; do
  if [[ "$U" == "root" ]]; then
    DIR="/var/root/Library/Preferences/com.carriez.RustDesk"
  else
    DIR="/Users/$U/Library/Preferences/com.carriez.RustDesk"
  fi
  sudo mkdir -p "$DIR"
  
  # Seed configuration with full keyboard, mouse, and remote control permissions enabled
  sudo tee "$DIR/RustDesk.toml" >/dev/null << 'EOF'
[options]
direct-server = 'Y'
direct-access-port = '21118'
codec-preference = 'h264'
image-quality = '2'
custom-fps = '60'
allow-remote-config-modification = 'true'
verification-method = 'use-permanent-password'
allow-keyboard = 'Y'
allow-mouse = 'Y'
enable-keyboard = 'Y'
enable-mouse = 'Y'
allow-clipboard = 'Y'
allow-file-transfer = 'Y'
allow-audio = 'Y'
EOF
  sudo cp "$DIR/RustDesk.toml" "$DIR/RustDesk2.toml"

  if [[ "$U" != "root" ]]; then
    sudo chown -R "$U:staff" "$DIR" 2>/dev/null || true
  fi

  # Bypass macOS Screen Capture alerts
  if [[ "$U" == "root" ]]; then
    PLIST_DIR="/var/root/Library/Group Containers/group.com.apple.replayd"
  else
    PLIST_DIR="/Users/$U/Library/Group Containers/group.com.apple.replayd"
  fi
  sudo mkdir -p "$PLIST_DIR"
  PLIST="$PLIST_DIR/ScreenCaptureApprovals.plist"

  for APP_KEY in \
    "/Applications/RustDesk.app/Contents/MacOS/RustDesk" \
    "/Applications/RustDesk.app/Contents/MacOS/rustdesk" \
    "/Applications/RustDesk.app/Contents/MacOS/RustDesk_server" \
    "/Applications/RustDesk.app/Contents/MacOS/RustDesk_service" \
    "/Applications/RustDesk.app" \
    "com.carriez.rustdesk" \
    "com.carriez.RustDesk" \
    "com.carriez.RustDesk_service" \
    "com.carriez.RustDesk_server" \
    "com.carriez.rustdesk_service" \
    "com.carriez.rustdesk_server"; do
    sudo defaults write "$PLIST" "$APP_KEY" -date "3024-01-01 00:00:00 +0000" 2>/dev/null || true
  done

  if [[ "$U" != "root" ]]; then
    sudo chown -R "$U:staff" "$PLIST_DIR" 2>/dev/null || true
  fi
done

sudo killall -9 replayd 2>/dev/null || true

# 3. Install LaunchDaemon & LaunchAgent using install_service.sh exclusively for target user
echo "- Installing RustDesk LaunchDaemon and LaunchAgent via install_service.sh for $USERNAME..."
sudo bash "$SCRIPT_DIR/install_service.sh" -u "$USERNAME" 2>/dev/null || true

# 4. Set permanent unattended access password for target user and root daemon
echo "- Setting unattended access password for RustDesk user $USERNAME..."
if [[ -n "$TARGET_UID" && "$TARGET_UID" != "0" ]]; then
  launchctl asuser "$TARGET_UID" sudo -u "$USERNAME" env HOME="$USER_HOME" "$RUSTDESK_BIN" --password "$PASSWORD" 2>/dev/null || \
  sudo -u "$USERNAME" env HOME="$USER_HOME" "$RUSTDESK_BIN" --password "$PASSWORD" 2>/dev/null || true
else
  sudo -u "$USERNAME" env HOME="$USER_HOME" "$RUSTDESK_BIN" --password "$PASSWORD" 2>/dev/null || true
fi
sudo "$RUSTDESK_BIN" --password "$PASSWORD" 2>/dev/null || true
sleep 2

# Ensure permissions are correct on user preference directory
if [[ -d "/Users/$USERNAME/Library/Preferences/com.carriez.RustDesk" ]]; then
  sudo chown -R "$USERNAME:staff" "/Users/$USERNAME/Library/Preferences/com.carriez.RustDesk" 2>/dev/null || true
fi

# 5. Kickstart RustDesk server in target user's active GUI domain
echo "- Kickstarting RustDesk server for user $USERNAME (UID $TARGET_UID)..."
if [[ -n "$TARGET_UID" && "$TARGET_UID" != "0" ]]; then
  sudo launchctl kickstart -kp "gui/$TARGET_UID/com.carriez.RustDesk_server" 2>/dev/null || true
  launchctl asuser "$TARGET_UID" sudo -u "$USERNAME" env HOME="$USER_HOME" open -a /Applications/RustDesk.app 2>/dev/null || true
else
  sudo -u "$USERNAME" env HOME="$USER_HOME" open -a /Applications/RustDesk.app 2>/dev/null || true
fi

# Prioritize RustDesk process
sudo renice -n -15 -p $(pgrep -i rustdesk) 2>/dev/null || true

echo "* RustDesk service configured successfully for user $USERNAME"
