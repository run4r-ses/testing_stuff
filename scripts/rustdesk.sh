#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RUSTDESK_USERNAME:-runneradmin}"
if [[ -z "${RUSTDESK_PASSWORD:-}" ]]; then
  echo "! RUSTDESK_PASSWORD environment variable is required"
  exit 1
fi
PASSWORD="$RUSTDESK_PASSWORD"

echo "* Configuring RustDesk"

RUSTDESK_BIN="/Applications/RustDesk.app/Contents/MacOS/RustDesk"
if [[ ! -x "$RUSTDESK_BIN" ]]; then
  # Check alternative lowercase binary name
  if [[ -x "/Applications/RustDesk.app/Contents/MacOS/rustdesk" ]]; then
    RUSTDESK_BIN="/Applications/RustDesk.app/Contents/MacOS/rustdesk"
  else
    echo "! RustDesk binary not found at /Applications/RustDesk.app"
    exit 1
  fi
fi

echo "- Installing and starting service"
sudo "$RUSTDESK_BIN" --install-service 2>/dev/null || true
sleep 3

echo "- Launching GUI session"
open -a /Applications/RustDesk.app 2>/dev/null || true
sleep 3

echo "- Setting password"
sudo "$RUSTDESK_BIN" --password "$PASSWORD" 2>/dev/null || "$RUSTDESK_BIN" --password "$PASSWORD" 2>/dev/null || true
sleep 2

echo "- Fetching RustDesk ID"
RUSTDESK_ID=""
for i in {1..30}; do
  RUSTDESK_ID="$("$RUSTDESK_BIN" --get-id 2>/dev/null || true)"
  RUSTDESK_ID="$(echo "$RUSTDESK_ID" | tr -d '[:space:]')"

  if [[ -n "$RUSTDESK_ID" && "$RUSTDESK_ID" =~ ^[0-9a-zA-Z_-]+$ ]]; then
    break
  fi

  # Fallback: Check RustDesk config files
  for CONF in \
    "/Users/$USERNAME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml" \
    "/Users/$USERNAME/Library/Preferences/com.carriez.RustDesk/RustDesk.toml" \
    "/Users/runner/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml" \
    "/Users/runner/Library/Preferences/com.carriez.RustDesk/RustDesk.toml" \
    "/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"; do
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
  echo "! RustDesk is running, check client window or config if needed"
  RUSTDESK_ID="Unavailable (check RustDesk client)"
fi

echo
echo "* macOS web desktop is ready"
echo "* RustDesk ID:   $RUSTDESK_ID"
echo "* Console user:  $(stat -f '%Su' /dev/console 2>/dev/null || whoami)"
echo "* OS version:    $(sw_vers -productVersion 2>/dev/null || echo 'macOS')"
echo "*"
echo "* For web, you can connect via https://rustdesk.com/web/"
echo
