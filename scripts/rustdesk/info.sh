#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RDP_USERNAME:-${RUSTDESK_USERNAME:-goldenrecipe}}"
PASSWORD="${RDP_PASSWORD:-${RUSTDESK_PASSWORD:-}}"
TARGET_UID="$(id -u "$USERNAME" 2>/dev/null || echo "")"
USER_HOME="$(dscl . -read "/Users/$USERNAME" NFSHomeDirectory 2>/dev/null | sed 's/^NFSHomeDirectory:[[:space:]]*//' || echo "/Users/$USERNAME")"

echo "- Retrieving RustDesk connection details for user $USERNAME..."

format_rustdesk_id() {
  local raw="$1"
  if [[ "$raw" =~ ^([0-9]{3})([0-9]{3})([0-9]{3})$ ]]; then
    echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
  elif [[ "$raw" =~ ^([0-9]{3})([0-9]{3})([0-9]{4})$ ]]; then
    echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
  elif [[ "$raw" =~ ^([0-9]{3})([0-9]{3})([0-9]{3})([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]}"
  else
    echo "$raw"
  fi
}

get_rustdesk_id() {
  local ID=""
  for _ in {1..30}; do
    # 1. Try CLI --get-id running under target user context
    if [[ -x /Applications/RustDesk.app/Contents/MacOS/RustDesk ]]; then
      if [[ -n "$TARGET_UID" && "$TARGET_UID" != "0" ]]; then
        ID="$(launchctl asuser "$TARGET_UID" sudo -u "$USERNAME" env HOME="$USER_HOME" /Applications/RustDesk.app/Contents/MacOS/RustDesk --get-id 2>/dev/null | tr -d '[:space:]' || true)"
      fi
      if [[ -z "$ID" || ! "$ID" =~ ^[0-9]+$ ]]; then
        ID="$(sudo -u "$USERNAME" env HOME="$USER_HOME" /Applications/RustDesk.app/Contents/MacOS/RustDesk --get-id 2>/dev/null | tr -d '[:space:]' || true)"
      fi
      if [[ -z "$ID" || ! "$ID" =~ ^[0-9]+$ ]]; then
        ID="$(/Applications/RustDesk.app/Contents/MacOS/RustDesk --get-id 2>/dev/null | tr -d '[:space:]' || true)"
      fi
      if [[ -n "$ID" && "$ID" =~ ^[0-9]+$ ]]; then
        echo "$ID"
        return 0
      fi
    fi

    # 2. Try reading from toml preference files in target user directory first
    for toml in \
      "$USER_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml" \
      "$USER_HOME/Library/Preferences/com.carriez.RustDesk/RustDesk.toml" \
      "$USER_HOME/.config/rustdesk/RustDesk2.toml" \
      "$USER_HOME/.config/rustdesk/RustDesk.toml" \
      "/var/root/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml" \
      "/var/root/Library/Preferences/com.carriez.RustDesk/RustDesk.toml"; do
      if [[ -f "$toml" ]]; then
        ID="$(sudo grep -E '^[[:space:]]*id[[:space:]]*=' "$toml" 2>/dev/null | sed -E "s/^[[:space:]]*id[[:space:]]*=[[:space:]]*['\"]?([0-9]+)['\"]?/\1/" | head -n 1 || true)"
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
FORMATTED_ID="$(format_rustdesk_id "$RUSTDESK_ID")"

echo
echo "* ==================================================="
echo "* RustDesk Unattended Remote Access Ready"
echo "* ==================================================="
if [[ -n "$FORMATTED_ID" ]]; then
  echo "* RustDesk ID:     $FORMATTED_ID"
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

