#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RDP_USERNAME:-${RUSTDESK_USERNAME:-goldenrecipe}}"
PASSWORD="${RDP_PASSWORD:-${RUSTDESK_PASSWORD:-}}"

echo "- Retrieving RustDesk connection details..."

get_rustdesk_id() {
  local ID=""
  for _ in {1..30}; do
    # 1. Try CLI --get-id
    if [[ -x /Applications/RustDesk.app/Contents/MacOS/RustDesk ]]; then
      ID="$(/Applications/RustDesk.app/Contents/MacOS/RustDesk --get-id 2>/dev/null | tr -d '[:space:]' || true)"
      if [[ -n "$ID" && "$ID" =~ ^[0-9]+$ ]]; then
        echo "$ID"
        return 0
      fi
    fi

    # 2. Try reading from toml preference files
    for toml in \
      "/Users/$USERNAME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml" \
      "/Users/$USERNAME/Library/Preferences/com.carriez.RustDesk/RustDesk.toml" \
      "/var/root/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml" \
      "/var/root/Library/Preferences/com.carriez.RustDesk/RustDesk.toml"; do
      if [[ -f "$toml" ]]; then
        ID="$(grep -E '^[[:space:]]*id[[:space:]]*=' "$toml" 2>/dev/null | sed -E "s/^[[:space:]]*id[[:space:]]*=[[:space:]]*['\"]?([0-9]+)['\"]?/\1/" | head -n 1 || true)"
        if [[ -n "$ID" && "$ID" =~ ^[0-9]+$ ]]; then
          echo "$ID"
          return 0
        fi
      fi
    done

    sleep 1
  done

  echo ""
}

RUSTDESK_ID="$(get_rustdesk_id)"

echo
echo "* ==================================================="
echo "* RustDesk Unattended Remote Access Ready"
echo "* ==================================================="
if [[ -n "$RUSTDESK_ID" ]]; then
  echo "* RustDesk ID:     $RUSTDESK_ID"
  echo "* Password:        $PASSWORD"
  echo "*"
  echo "* Connect using the official RustDesk client by entering"
  echo "* the RustDesk ID and configured password above."
else
  echo "! RustDesk ID is generating, check ~/.config/rustdesk or log"
  echo "* Password:        $PASSWORD"
fi
echo "* ==================================================="
echo
