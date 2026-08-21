#!/usr/bin/env bash
set -euo pipefail

echo "* Configuring macOS display resolution"

CONSOLE_USER="$(stat -f '%Su' /dev/console 2>/dev/null || echo "runner")"
CONSOLE_UID="$(id -u "$CONSOLE_USER" 2>/dev/null || echo "501")"

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
    echo "- Setting screen ($SCREEN_ID) to 720p (optimized for VNC)..."
    displayplacer "id:$SCREEN_ID res:1280x720 scaling:on" 2>/dev/null || \
    displayplacer "id:$SCREEN_ID res:1280x720 scaling:off" 2>/dev/null || \
    displayplacer "id:$SCREEN_ID res:1280x720" 2>/dev/null || \
    displayplacer "id:$SCREEN_ID res:1280x800 scaling:on" 2>/dev/null || \
    displayplacer "id:$SCREEN_ID res:1280x800" 2>/dev/null || \
    displayplacer "id:$SCREEN_ID res:1440x900 scaling:on" 2>/dev/null || \
    displayplacer "id:$SCREEN_ID res:1440x900" 2>/dev/null || true
  else
    echo "! Could not detect screen ID from displayplacer"
  fi
else
  echo "! displayplacer is not installed"
fi
