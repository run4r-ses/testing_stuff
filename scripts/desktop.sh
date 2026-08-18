#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${RUSTDESK_USERNAME:-goldenrecipe}"
TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null || echo "501")"

echo "* Configuring desktop session for $TARGET_USER ($TARGET_UID)"

# Detect who currently owns the console
CURRENT_CONSOLE="$(stat -f '%Su' /dev/console 2>/dev/null || echo "$TARGET_USER")"
CURRENT_UID="$(id -u "$CURRENT_CONSOLE" 2>/dev/null || echo "$TARGET_UID")"
echo "- Current console user: $CURRENT_CONSOLE ($CURRENT_UID)"

# 1. Suppress only non-interactive background daemons (Siri / AirPlay telemetry)
#    ControlCenter, Dock, and Finder are explicitly preserved for interactive desktop use
echo "- Suppressing Siri and AirPlay telemetry..."
launchctl disable "gui/$CURRENT_UID/com.apple.assistantd" 2>/dev/null || true
launchctl disable "gui/$CURRENT_UID/com.apple.Siri" 2>/dev/null || true
launchctl disable "gui/$CURRENT_UID/com.apple.AirPlayXPCHelper" 2>/dev/null || true

pkill -u "$CURRENT_UID" -x "assistantd" 2>/dev/null || true
pkill -u "$CURRENT_UID" -x "Siri" 2>/dev/null || true
pkill -u "$CURRENT_UID" -x "siriknowledged" 2>/dev/null || true
pkill -u "$CURRENT_UID" -x "AirPlayXPCHelper" 2>/dev/null || true

# 2. Prioritize WindowServer compositor for optimal 60fps streaming
echo "- Prioritizing WindowServer compositor..."
WS_PID="$(pgrep -x WindowServer 2>/dev/null || true)"
if [[ -n "$WS_PID" ]]; then
  sudo renice -n -20 -p $WS_PID 2>/dev/null || true
fi

# 3. Verify GUI launchd domain readiness
echo "- Verifying GUI domains..."
if sudo launchctl print "gui/$TARGET_UID" >/dev/null 2>&1; then
  echo "  -> gui/$TARGET_UID ($TARGET_USER) domain is active"
fi

echo "* Desktop session optimization complete"
echo "  Console User: $(stat -f '%Su' /dev/console 2>/dev/null || echo "$TARGET_USER")"
echo "  Target User:  $TARGET_USER ($TARGET_UID)"

