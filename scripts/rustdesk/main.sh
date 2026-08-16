#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERNAME="${RUSTDESK_USERNAME:-runneradmin}"
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

# Run official service installer for runneradmin
echo "- Installing service for $USERNAME"
sudo bash "$SCRIPT_DIR/install_service.sh" -u "$USERNAME"

# Set password
echo "- Setting password"
sudo -u "$USERNAME" "$RUSTDESK_BIN" --password "$PASSWORD" 2>/dev/null || true
sudo "$RUSTDESK_BIN" --password "$PASSWORD" 2>/dev/null || true
sleep 2

# Start server process for user
echo "- Starting RustDesk server"
sudo -u "$USERNAME" nohup "$RUSTDESK_BIN" --server >/tmp/rustdesk.log 2>&1 &
sleep 2

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

  # Fallback: check user config files
  for CONF in \
    "/Users/$USERNAME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml" \
    "/Users/$USERNAME/Library/Preferences/com.carriez.RustDesk/RustDesk.toml" \
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
  echo "! Could not automatically detect RustDesk ID via CLI"
  RUSTDESK_ID="Unavailable"
fi

echo
echo "* macOS web desktop is ready"
echo "* RustDesk ID:   $RUSTDESK_ID"
echo "* Console user:  $USERNAME"
echo "* OS version:    $(sw_vers -productVersion 2>/dev/null || echo 'macOS')"
echo "*"
echo "* For web, you can connect via https://rustdesk.com/web/"
echo
