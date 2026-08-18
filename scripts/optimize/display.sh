#!/usr/bin/env bash
set -euo pipefail

echo "* Configuring macOS display resolution"

TARGET_USER="${RUSTDESK_USERNAME:-goldenrecipe}"
CONSOLE_USER="$(stat -f '%Su' /dev/console 2>/dev/null || echo "$TARGET_USER")"
if [[ -z "$CONSOLE_USER" || "$CONSOLE_USER" == "root" ]]; then
  CONSOLE_USER="$TARGET_USER"
fi
CONSOLE_UID="$(id -u "$CONSOLE_USER" 2>/dev/null || echo "502")"

if command -v displayplacer >/dev/null 2>&1; then
  echo "- Querying display configuration..."
  
  if [[ -n "$CONSOLE_UID" && "$CONSOLE_UID" != "0" ]]; then
    DISPLAY_LIST="$(launchctl asuser "$CONSOLE_UID" sudo -u "$CONSOLE_USER" displayplacer list 2>/dev/null || displayplacer list 2>/dev/null || true)"
  else
    DISPLAY_LIST="$(displayplacer list 2>/dev/null || true)"
  fi
  
  SCREEN_ID="$(echo "$DISPLAY_LIST" | grep -E '^Persistent screen id:' | head -n1 | awk '{print $4}' || true)"
  if [[ -z "$SCREEN_ID" ]]; then
    SCREEN_ID="$(echo "$DISPLAY_LIST" | grep -E '^Contextual screen id:' | head -n1 | awk '{print $4}' || true)"
  fi

  if [[ -n "$SCREEN_ID" ]]; then
    echo "- Setting screen ($SCREEN_ID) to 720p @ 60Hz (optimized for VNC / Remote Desktop)..."
    displayplacer "id:$SCREEN_ID res:1280x720 hz:60 scaling:off" 2>/dev/null || \
    displayplacer "id:$SCREEN_ID res:1280x720 hz:60 scaling:on" 2>/dev/null || \
    displayplacer "id:$SCREEN_ID res:1280x720 hz:60" 2>/dev/null || \
    displayplacer "id:$SCREEN_ID res:1280x720 scaling:off" 2>/dev/null || \
    displayplacer "id:$SCREEN_ID res:1280x720 scaling:on" 2>/dev/null || \
    displayplacer "id:$SCREEN_ID res:1280x720" 2>/dev/null || \
    displayplacer "id:$SCREEN_ID res:1280x800 hz:60 scaling:off" 2>/dev/null || \
    displayplacer "id:$SCREEN_ID res:1280x800 scaling:off" 2>/dev/null || \
    displayplacer "id:$SCREEN_ID res:1280x800" 2>/dev/null || \
    displayplacer "id:$SCREEN_ID res:1440x900 scaling:off" 2>/dev/null || true
  else
    echo "! Could not detect screen ID from displayplacer"
  fi
else
  echo "! displayplacer is not installed"
fi
