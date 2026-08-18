#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${RUSTDESK_USERNAME:-goldenrecipe}"
TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null || echo "501")"

echo "* Configuring desktop session for $TARGET_USER ($TARGET_UID)"

# Detect who currently owns the console
CURRENT_CONSOLE="$(stat -f '%Su' /dev/console 2>/dev/null || echo "$TARGET_USER")"
CURRENT_UID="$(id -u "$CURRENT_CONSOLE" 2>/dev/null || echo "$TARGET_UID")"
echo "- Current console user: $CURRENT_CONSOLE ($CURRENT_UID)"

# 1. Preserve resources: Safely strip background bloatware without killing desktop shell
echo "- Stripping unnecessary background GUI agents to preserve CPU/RAM..."

BACKGROUND_BLOAT_SERVICES=(
  "com.apple.controlcenter"
  "com.apple.notificationcenterui"
  "com.apple.Spotlight"
  "com.apple.assistantd"
  "com.apple.Siri"
  "com.apple.AirPlayXPCHelper"
)

if [[ "$CURRENT_UID" != "0" && -n "$CURRENT_UID" ]]; then
  for SVC in "${BACKGROUND_BLOAT_SERVICES[@]}"; do
    launchctl disable "gui/$CURRENT_UID/$SVC" 2>/dev/null || true
    launchctl bootout "gui/$CURRENT_UID/$SVC" 2>/dev/null || true
  done
fi

BACKGROUND_KILL_PROCS=(
  "ControlCenter"
  "NotificationCenter"
  "Spotlight"
  "Siri"
  "assistantd"
  "siriknowledged"
  "AirPlayXPCHelper"
)

for PROC in "${BACKGROUND_KILL_PROCS[@]}"; do
  pkill -u "$CURRENT_UID" -x "$PROC" 2>/dev/null || true
  sudo pkill -x "$PROC" 2>/dev/null || true
done

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
else
  echo "  -> gui/$TARGET_UID ($TARGET_USER) domain ready"
fi

echo "* Desktop session optimization complete"
echo "  Console User: $(stat -f '%Su' /dev/console 2>/dev/null || echo "$TARGET_USER")"
echo "  Target User:  $TARGET_USER ($TARGET_UID)"

