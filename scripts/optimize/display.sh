#!/usr/bin/env bash
set -euo pipefail

echo "* Configuring macOS display resolution"

TARGET_USER="${RDP_USERNAME:-${RUSTDESK_USERNAME:-goldenrecipe}}"
TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null || echo "")"
CONSOLE_USER="$(stat -f '%Su' /dev/console 2>/dev/null || echo "runner")"
CONSOLE_UID="$(id -u "$CONSOLE_USER" 2>/dev/null || echo "501")"

echo "- Querying display configuration"

DISPLAY_LIST=""
if [[ -n "$CONSOLE_UID" && "$CONSOLE_UID" != "0" ]]; then
  DISPLAY_LIST="$(launchctl asuser "$CONSOLE_UID" sudo -u "$CONSOLE_USER" displayplacer list 2>&1 || true)"
fi
if [[ -z "$DISPLAY_LIST" && -n "$TARGET_UID" && "$TARGET_UID" != "0" ]]; then
  DISPLAY_LIST="$(launchctl asuser "$TARGET_UID" sudo -u "$TARGET_USER" displayplacer list 2>&1 || true)"
fi
if [[ -z "$DISPLAY_LIST" ]]; then
  DISPLAY_LIST="$(displayplacer list 2>&1 || true)"
fi

echo "$DISPLAY_LIST"

SCREEN_ID="$(echo "$DISPLAY_LIST" | grep -E '^Persistent screen id:' | head -n1 | awk '{print $4}' || true)"
if [[ -z "$SCREEN_ID" ]]; then
  SCREEN_ID="$(echo "$DISPLAY_LIST" | grep -E '^Contextual screen id:' | head -n1 | awk '{print $4}' || true)"
fi

if [[ -n "$SCREEN_ID" ]]; then
  echo "- Setting screen ($SCREEN_ID) to 720p @ 60Hz"
  displayplacer "id:$SCREEN_ID res:1280x720 hz:60 scaling:off" || \
  displayplacer "id:$SCREEN_ID res:1280x720 hz:60 scaling:on" || \
  displayplacer "id:$SCREEN_ID res:1280x720 hz:60" || \
  displayplacer "id:$SCREEN_ID res:1280x720 scaling:off" || \
  displayplacer "id:$SCREEN_ID res:1280x720 scaling:on" || \
  displayplacer "id:$SCREEN_ID res:1280x720" || \
  displayplacer "id:$SCREEN_ID res:1280x800 hz:60 scaling:off" || \
  displayplacer "id:$SCREEN_ID res:1280x800 scaling:off" || \
  displayplacer "id:$SCREEN_ID res:1280x800" || \
  displayplacer "id:$SCREEN_ID res:1440x900 scaling:off" || true
else
  echo "! Could not detect screen ID from displayplacer"
fi
