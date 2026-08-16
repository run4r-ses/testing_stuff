#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERNAME="${RUSTDESK_USERNAME:-runneradmin}"
CONSOLE_USER="$(stat -f '%Su' /dev/console 2>/dev/null || echo "runner")"
if [[ -z "$CONSOLE_USER" || "$CONSOLE_USER" == "root" ]]; then
  CONSOLE_USER="runner"
fi
CONSOLE_UID="$(id -u "$CONSOLE_USER" 2>/dev/null || echo "501")"

if [[ -z "${RUSTDESK_PASSWORD:-}" ]]; then
  echo "! RUSTDESK_PASSWORD environment variable is required"
  exit 1
fi
PASSWORD="$RUSTDESK_PASSWORD"

echo "* Configuring RustDesk"

# Locate RustDesk binary
RUSTDESK_BIN="/Applications/RustDesk.app/Contents/MacOS/RustDesk"
if [[ ! -x "$RUSTDESK_BIN" && -x "/Applications/RustDesk.app/Contents/MacOS/rustdesk" ]]; then
  RUSTDESK_BIN="/Applications/RustDesk.app/Contents/MacOS/rustdesk"
fi

# Remove Gatekeeper quarantine
echo "- Removing Gatekeeper quarantine"
sudo xattr -cr /Applications/RustDesk.app 2>/dev/null || true
sudo xattr -rd com.apple.quarantine /Applications/RustDesk.app 2>/dev/null || true

# Pre-create preference directories and optimized config files
echo "- Initializing preference directories and configuration"
for U in "$USERNAME" "$CONSOLE_USER" "root"; do
  DIR="/Users/$U/Library/Preferences/com.carriez.RustDesk"
  [[ "$U" == "root" ]] && DIR="/var/root/Library/Preferences/com.carriez.RustDesk"
  sudo mkdir -p "$DIR"
  
  # Seed configuration with H.265 hardware encoding and direct IP access
  sudo tee "$DIR/RustDesk.toml" >/dev/null << 'EOF'
codec-preference = "h265"
custom-fps = "60"
enable-direct-ip = "Y"
direct-access-port = "21118"
allow-remote-config-modification = "true"
EOF
  sudo cp "$DIR/RustDesk.toml" "$DIR/RustDesk2.toml"

  if [[ "$U" != "root" ]]; then
    sudo chown -R "$U" "$DIR" 2>/dev/null || true
  fi

  # Bypass macOS 15+ Sequoia Screen Capture "bypass window picker" alert
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
    "/Applications/RustDesk.app" \
    "com.carriez.rustdesk" \
    "com.carriez.RustDesk"; do
    sudo defaults write "$PLIST" "$APP_KEY" -date "3024-01-01 00:00:00 +0000" 2>/dev/null || true
  done

  if [[ "$U" != "root" ]]; then
    sudo chown -R "$U:staff" "$PLIST_DIR" 2>/dev/null || true
  fi
done

sudo killall -9 replayd 2>/dev/null || true

# Run official service installer for the active GUI console session
echo "- Installing service for GUI console user $CONSOLE_USER ($CONSOLE_UID)"
sudo bash "$SCRIPT_DIR/install_service.sh" -u "$CONSOLE_USER"

# Also register preferences for target user if distinct
if [[ "$USERNAME" != "$CONSOLE_USER" ]] && id "$USERNAME" >/dev/null 2>&1; then
  sudo bash "$SCRIPT_DIR/install_service.sh" -u "$USERNAME" 2>/dev/null || true
fi

# Set password across root and console user configurations
echo "- Setting password"
sudo "$RUSTDESK_BIN" --password "$PASSWORD" 2>/dev/null || true
sudo -u "$CONSOLE_USER" "$RUSTDESK_BIN" --password "$PASSWORD" 2>/dev/null || true
if [[ "$USERNAME" != "$CONSOLE_USER" ]] && id "$USERNAME" >/dev/null 2>&1; then
  sudo -u "$USERNAME" "$RUSTDESK_BIN" --password "$PASSWORD" 2>/dev/null || true
fi
sleep 2

# Kickstart server in the active GUI domain
echo "- Starting RustDesk server"
sudo launchctl kickstart -kp "gui/$CONSOLE_UID/com.carriez.RustDesk_server" 2>/dev/null || true

# Fallback: start server in background if not already running
if ! pgrep -i "rustdesk" >/dev/null 2>&1; then
  sudo -u "$CONSOLE_USER" nohup "$RUSTDESK_BIN" --server >/tmp/rustdesk.log 2>&1 &
  sleep 3
fi

# Launch background Serveo SSH reverse tunnel for direct IP port (21118)
echo "- Starting Serveo tunnel"
SERVEO_PORT=$(( 15000 + (RANDOM % 35000) ))
echo "$SERVEO_PORT" > /tmp/serveo_port.txt

ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=10 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  -R "${SERVEO_PORT}:localhost:21118" \
  serveo.net \
  > /tmp/serveo.log 2>&1 &
echo $! > /tmp/serveo.pid

# Fetch RustDesk ID
echo "- Fetching RustDesk ID"
RUSTDESK_ID=""
for i in {1..30}; do
  if [[ -x "$RUSTDESK_BIN" ]]; then
    RUSTDESK_ID="$("$RUSTDESK_BIN" --get-id 2>/dev/null || true)"
    RUSTDESK_ID="$(echo "$RUSTDESK_ID" | tr -d '[:space:]')"
  fi

  if [[ -n "$RUSTDESK_ID" && "$RUSTDESK_ID" =~ ^[0-9a-zA-Z_-]+$ ]]; then
    break
  fi

  # Fallback: check config files
  for CONF in \
    "/Users/$CONSOLE_USER/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml" \
    "/Users/$CONSOLE_USER/Library/Preferences/com.carriez.RustDesk/RustDesk.toml" \
    "/Users/$USERNAME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml" \
    "/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml" \
    "/var/root/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"; do
    if [[ -f "$CONF" ]]; then
      ID_MATCH="$(awk -F "=" '/^[[:space:]]*id[[:space:]]*=/ {gsub(/["'\'' ]/, "", $2); print $2; exit}' "$CONF" 2>/dev/null || true)"
      if [[ -n "$ID_MATCH" ]]; then
        RUSTDESK_ID="$ID_MATCH"
        break 2
      fi
    fi
  done

  sleep 1
done

if [[ -z "$RUSTDESK_ID" ]]; then
  RUSTDESK_ID="Unavailable"
fi

# Save connection state for info.sh
echo "$RUSTDESK_ID" > /tmp/rustdesk_id.txt
echo "$CONSOLE_USER" > /tmp/rustdesk_user.txt

echo "* RustDesk configuration completed successfully"
