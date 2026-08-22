#!/usr/bin/env bash
set -euo pipefail

echo "* Configuring macOS display resolution"

export PATH="/tmp:/usr/local/bin:/opt/homebrew/bin:$PATH"

TARGET_USER="${RDP_USERNAME:-${RUSTDESK_USERNAME:-goldenrecipe}}"
TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null || echo "")"
CONSOLE_USER="$(stat -f '%Su' /dev/console 2>/dev/null || echo "runner")"
CONSOLE_UID="$(id -u "$CONSOLE_USER" 2>/dev/null || echo "501")"

# Ensure displayplacer binary is available
DISPLAYPLACER_BIN=""
if command -v displayplacer >/dev/null 2>&1; then
  DISPLAYPLACER_BIN="$(command -v displayplacer)"
elif [[ -x /opt/homebrew/bin/displayplacer ]]; then
  DISPLAYPLACER_BIN="/opt/homebrew/bin/displayplacer"
elif [[ -x /usr/local/bin/displayplacer ]]; then
  DISPLAYPLACER_BIN="/usr/local/bin/displayplacer"
elif [[ -x /tmp/displayplacer ]]; then
  DISPLAYPLACER_BIN="/tmp/displayplacer"
else
  echo "- displayplacer binary not found in standard paths, downloading fallback..."
  ARCH="$(uname -m)"
  if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
    curl -fsSL "https://github.com/jakehilborn/displayplacer/releases/download/v1.4.0/displayplacer-apple" -o /tmp/displayplacer 2>/dev/null || \
    curl -fsSL "https://github.com/jakehilborn/displayplacer/releases/latest/download/displayplacer-apple" -o /tmp/displayplacer 2>/dev/null || true
  else
    curl -fsSL "https://github.com/jakehilborn/displayplacer/releases/download/v1.4.0/displayplacer-intel" -o /tmp/displayplacer 2>/dev/null || \
    curl -fsSL "https://github.com/jakehilborn/displayplacer/releases/latest/download/displayplacer-intel" -o /tmp/displayplacer 2>/dev/null || true
  fi

  if [[ ! -s /tmp/displayplacer ]] && command -v clang >/dev/null 2>&1; then
    echo "- Compiling displayplacer via clang..."
    curl -fsSL "https://raw.githubusercontent.com/jakehilborn/displayplacer/master/src/displayplacer.c" -o /tmp/displayplacer.c 2>/dev/null || \
    curl -fsSL "https://raw.githubusercontent.com/jakehilborn/displayplacer/master/displayplacer.c" -o /tmp/displayplacer.c 2>/dev/null || true
    if [[ -f /tmp/displayplacer.c ]]; then
      clang -framework Foundation -framework CoreGraphics -framework IOKit -framework ApplicationServices -O2 /tmp/displayplacer.c -o /tmp/displayplacer 2>/dev/null || true
    fi
  fi

  if [[ -s /tmp/displayplacer ]]; then
    chmod +x /tmp/displayplacer
    DISPLAYPLACER_BIN="/tmp/displayplacer"
  fi
fi

if [[ -n "$DISPLAYPLACER_BIN" && -x "$DISPLAYPLACER_BIN" ]]; then
  echo "- Querying display configuration via $DISPLAYPLACER_BIN..."
  
  DISPLAY_LIST=""
  if [[ -n "$CONSOLE_UID" && "$CONSOLE_UID" != "0" ]]; then
    DISPLAY_LIST="$(launchctl asuser "$CONSOLE_UID" sudo -u "$CONSOLE_USER" "$DISPLAYPLACER_BIN" list 2>/dev/null || true)"
  fi
  if [[ -z "$DISPLAY_LIST" && -n "$TARGET_UID" && "$TARGET_UID" != "0" ]]; then
    DISPLAY_LIST="$(launchctl asuser "$TARGET_UID" sudo -u "$TARGET_USER" "$DISPLAYPLACER_BIN" list 2>/dev/null || true)"
  fi
  if [[ -z "$DISPLAY_LIST" ]]; then
    DISPLAY_LIST="$("$DISPLAYPLACER_BIN" list 2>/dev/null || true)"
  fi
  
  SCREEN_ID="$(echo "$DISPLAY_LIST" | grep -E '^Persistent screen id:' | head -n1 | awk '{print $4}' || true)"
  if [[ -z "$SCREEN_ID" ]]; then
    SCREEN_ID="$(echo "$DISPLAY_LIST" | grep -E '^Contextual screen id:' | head -n1 | awk '{print $4}' || true)"
  fi

  if [[ -n "$SCREEN_ID" ]]; then
    echo "- Setting screen ($SCREEN_ID) to 720p @ 60Hz (optimized for VNC / Remote Desktop)..."
    "$DISPLAYPLACER_BIN" "id:$SCREEN_ID res:1280x720 hz:60 scaling:off" 2>/dev/null || \
    "$DISPLAYPLACER_BIN" "id:$SCREEN_ID res:1280x720 hz:60 scaling:on" 2>/dev/null || \
    "$DISPLAYPLACER_BIN" "id:$SCREEN_ID res:1280x720 hz:60" 2>/dev/null || \
    "$DISPLAYPLACER_BIN" "id:$SCREEN_ID res:1280x720 scaling:off" 2>/dev/null || \
    "$DISPLAYPLACER_BIN" "id:$SCREEN_ID res:1280x720 scaling:on" 2>/dev/null || \
    "$DISPLAYPLACER_BIN" "id:$SCREEN_ID res:1280x720" 2>/dev/null || \
    "$DISPLAYPLACER_BIN" "id:$SCREEN_ID res:1280x800 hz:60 scaling:off" 2>/dev/null || \
    "$DISPLAYPLACER_BIN" "id:$SCREEN_ID res:1280x800 scaling:off" 2>/dev/null || \
    "$DISPLAYPLACER_BIN" "id:$SCREEN_ID res:1280x800" 2>/dev/null || \
    "$DISPLAYPLACER_BIN" "id:$SCREEN_ID res:1440x900 scaling:off" 2>/dev/null || true
  else
    echo "! Could not detect screen ID from displayplacer"
  fi
else
  echo "! displayplacer could not be installed or executed"
fi

