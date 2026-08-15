#!/usr/bin/env bash
set -euo pipefail

echo "* Configuring macOS display resolution"

if command -v displayplacer >/dev/null 2>&1; then
  DISPLAY_LIST="$(displayplacer list 2>/dev/null || true)"
  SCREEN_ID="$(echo "$DISPLAY_LIST" | grep -E '^Persistent screen id:' | head -n1 | awk '{print $4}' || true)"

  if [[ -n "$SCREEN_ID" ]]; then
    echo "- Setting screen ($SCREEN_ID) to 900p (1600x900)"
    displayplacer "id:$SCREEN_ID res:1600x900 scaling:on" 2>/dev/null || \
    displayplacer "id:$SCREEN_ID res:1600x900 scaling:off" 2>/dev/null || \
    displayplacer "id:$SCREEN_ID res:1600x900" 2>/dev/null || \
    displayplacer "id:$SCREEN_ID res:1920x1080 scaling:on" 2>/dev/null || \
    displayplacer "id:$SCREEN_ID res:1280x720 scaling:on" 2>/dev/null || true
  else
    echo "! Could not detect screen ID from displayplacer"
  fi
else
  echo "! displayplacer is not installed"
fi
