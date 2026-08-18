#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${RUSTDESK_USERNAME:-goldenrecipe}"
TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null || echo "502")"

echo "* Switching GUI desktop session to $TARGET_USER ($TARGET_UID)"

# Detect who currently owns the console
CURRENT_CONSOLE="$(stat -f '%Su' /dev/console 2>/dev/null || echo "unknown")"
CURRENT_UID="$(id -u "$CURRENT_CONSOLE" 2>/dev/null || echo "0")"
echo "- Current console user: $CURRENT_CONSOLE ($CURRENT_UID)"

if [[ "$CURRENT_CONSOLE" == "$TARGET_USER" ]]; then
  echo "- $TARGET_USER already owns the console — nothing to do"
  exit 0
fi

# 1. Ensure auto-login is set for the target user (belt & suspenders)
echo "- Ensuring auto-login is configured for $TARGET_USER"
sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser "$TARGET_USER" 2>/dev/null || true
sudo defaults write /Library/Preferences/com.apple.loginwindow lastUser "$TARGET_USER" 2>/dev/null || true

# 2. Boot out the current GUI user's session
#    This destroys runner's GUI domain. The GHA shell process survives because
#    it runs in the system domain, not the GUI domain.
echo "- Booting out GUI session for $CURRENT_CONSOLE ($CURRENT_UID)"
if [[ "$CURRENT_UID" != "0" && -n "$CURRENT_UID" ]]; then
  sudo launchctl bootout "gui/$CURRENT_UID" 2>/dev/null || true
fi

# 3. Restart loginwindow — macOS will auto-login the configured user
echo "- Restarting loginwindow to trigger auto-login for $TARGET_USER"
sudo killall loginwindow 2>/dev/null || true
sleep 5

# 4. Wait for the target user to appear on the console
echo "- Waiting for $TARGET_USER to claim the console..."
MAX_WAIT=60
WAITED=0
while [[ $WAITED -lt $MAX_WAIT ]]; do
  CONSOLE_NOW="$(stat -f '%Su' /dev/console 2>/dev/null || echo "none")"
  if [[ "$CONSOLE_NOW" == "$TARGET_USER" ]]; then
    echo "  -> $TARGET_USER is now the console user"
    break
  fi
  sleep 2
  WAITED=$((WAITED + 2))
  if (( WAITED % 10 == 0 )); then
    echo "  -> Still waiting... console=$CONSOLE_NOW (${WAITED}s)"
  fi
done

FINAL_CONSOLE="$(stat -f '%Su' /dev/console 2>/dev/null || echo "unknown")"
FINAL_UID="$(id -u "$FINAL_CONSOLE" 2>/dev/null || echo "0")"
echo "- Console user is now: $FINAL_CONSOLE ($FINAL_UID)"

if [[ "$FINAL_CONSOLE" != "$TARGET_USER" ]]; then
  echo "! WARNING: $TARGET_USER did not claim the console after ${MAX_WAIT}s"
  echo "  Attempting manual GUI session bootstrap..."

  # Force-create a GUI session for the target user
  sudo launchctl bootstrap "gui/$TARGET_UID" /System/Library/LaunchAgents/com.apple.WindowServer.plist 2>/dev/null || true
  sudo launchctl bootstrap "gui/$TARGET_UID" /System/Library/LaunchDaemons/com.apple.WindowServer.plist 2>/dev/null || true

  # Another loginwindow restart
  sudo killall loginwindow 2>/dev/null || true
  sleep 10

  FINAL_CONSOLE="$(stat -f '%Su' /dev/console 2>/dev/null || echo "unknown")"
  echo "- Console user after retry: $FINAL_CONSOLE"
fi

# 5. Ensure the target user's GUI launchd domain is alive
echo "- Verifying GUI domain for $TARGET_USER ($TARGET_UID)"
if sudo launchctl print "gui/$TARGET_UID" >/dev/null 2>&1; then
  echo "  -> gui/$TARGET_UID domain is active"
else
  echo "  -> gui/$TARGET_UID domain not found — attempting bootstrap"
  # loginwindow should handle this, but try a nudge
  sudo killall loginwindow 2>/dev/null || true
  sleep 5
fi

echo "* Desktop session switch complete"
echo "  Console: $(stat -f '%Su' /dev/console 2>/dev/null || echo 'unknown')"
echo "  GUI UID: $(id -u "$(stat -f '%Su' /dev/console 2>/dev/null || echo 'unknown')" 2>/dev/null || echo 'unknown')"
