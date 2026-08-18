#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${RUSTDESK_USERNAME:-goldenrecipe}"
TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null || echo "502")"
PASSWORD="${RUSTDESK_PASSWORD:-}"

echo "* Configuring desktop session for $TARGET_USER ($TARGET_UID)"

# Detect who currently owns the console
CURRENT_CONSOLE="$(stat -f '%Su' /dev/console 2>/dev/null || echo "unknown")"
CURRENT_UID="$(id -u "$CURRENT_CONSOLE" 2>/dev/null || echo "0")"
echo "- Current console user: $CURRENT_CONSOLE ($CURRENT_UID)"

# 1. Ensure auto-login configuration is synced for $TARGET_USER
echo "- Ensuring auto-login is configured for $TARGET_USER"
if [[ -n "$PASSWORD" ]]; then
  sudo sysadminctl -autologin set -userName "$TARGET_USER" -password "$PASSWORD" 2>/dev/null || true
fi
sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser "$TARGET_USER" 2>/dev/null || true
sudo defaults write /Library/Preferences/com.apple.loginwindow lastUser "$TARGET_USER" 2>/dev/null || true

# 2. Preserve resources: Safely strip heavy GUI bloat from runner (501) session
#    CRITICAL: Never run 'launchctl bootout gui/501' or 'killall loginwindow', as the GHA
#    runner agent (Runner.Listener / Runner.Worker) lives within that domain.
echo "- Stripping unnecessary GUI services to preserve resources..."

GUI_BLOAT_SERVICES=(
  "com.apple.Finder"
  "com.apple.Dock"
  "com.apple.controlcenter"
  "com.apple.notificationcenterui"
  "com.apple.systemuiserver"
  "com.apple.Spotlight"
  "com.apple.WallpaperAgent"
  "com.apple.assistantd"
  "com.apple.Siri"
  "com.apple.AirPlayXPCHelper"
)

# Disable individual GUI agent plists in the current console/runner domain so they don't respawn
if [[ "$CURRENT_UID" != "0" && -n "$CURRENT_UID" ]]; then
  for SVC in "${GUI_BLOAT_SERVICES[@]}"; do
    launchctl disable "gui/$CURRENT_UID/$SVC" 2>/dev/null || true
    launchctl bootout "gui/$CURRENT_UID/$SVC" 2>/dev/null || true
  done
fi

# Selectively terminate GUI consumers (explicitly protecting runner and CI processes)
GUI_KILL_PROCS=(
  "Finder"
  "Dock"
  "ControlCenter"
  "NotificationCenter"
  "SystemUIServer"
  "Spotlight"
  "WallpaperAgent"
  "Siri"
  "assistantd"
  "siriknowledged"
  "AirPlayXPCHelper"
)

for PROC in "${GUI_KILL_PROCS[@]}"; do
  # Terminate only GUI app instances, never touching Runner, Worker, bash, node, or ssh
  pkill -u "$CURRENT_UID" -x "$PROC" 2>/dev/null || true
  sudo pkill -x "$PROC" 2>/dev/null || true
done

# 3. Prioritize WindowServer compositor for optimal 60fps streaming
echo "- Prioritizing WindowServer compositor..."
WS_PID="$(pgrep -x WindowServer 2>/dev/null || true)"
if [[ -n "$WS_PID" ]]; then
  sudo renice -n -20 -p $WS_PID 2>/dev/null || true
fi

# 4. Verify GUI launchd domain readiness for target & console users
echo "- Verifying GUI domains..."
for U in "$TARGET_USER" "$CURRENT_CONSOLE"; do
  if id "$U" >/dev/null 2>&1; then
    UID_VAL="$(id -u "$U")"
    if sudo launchctl print "gui/$UID_VAL" >/dev/null 2>&1; then
      echo "  -> gui/$UID_VAL ($U) domain is active"
    else
      echo "  -> gui/$UID_VAL ($U) domain is ready for on-demand attachment"
    fi
  fi
done

echo "* Desktop session optimization complete"
echo "  Console User: $(stat -f '%Su' /dev/console 2>/dev/null || echo 'unknown')"
echo "  Target User:  $TARGET_USER ($TARGET_UID)"
