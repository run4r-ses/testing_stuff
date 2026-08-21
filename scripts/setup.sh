#!/usr/bin/env bash
set -euo pipefail

USERNAME="${VNC_USERNAME:-runneradmin}"
if [[ -z "${VNC_PASSWORD:-}" ]]; then
  echo "! VNC_PASSWORD environment variable is required"
  exit 1
fi
PASSWORD="$VNC_PASSWORD"
USER_UID="${VNC_UID:-502}"

echo "* Creating GUI user $USERNAME"

if id "$USERNAME" >/dev/null 2>&1; then
  echo "- User $USERNAME already exists, updating password"
  sudo dscl . -passwd "/Users/$USERNAME" "$PASSWORD"
else
  echo "- Creating new user account for $USERNAME"
  sudo dscl . -create "/Users/$USERNAME"
  sudo dscl . -create "/Users/$USERNAME" UserShell /bin/bash
  sudo dscl . -create "/Users/$USERNAME" RealName "Runner Admin"
  sudo dscl . -create "/Users/$USERNAME" UniqueID "$USER_UID"
  sudo dscl . -create "/Users/$USERNAME" PrimaryGroupID 20
  sudo dscl . -create "/Users/$USERNAME" NFSHomeDirectory "/Users/$USERNAME"
  sudo dscl . -passwd "/Users/$USERNAME" "$PASSWORD"

  sudo createhomedir -c -u "$USERNAME" >/dev/null 2>&1 || true
fi

# Ensure user is in admin group
sudo dseditgroup -o edit -a "$USERNAME" -t user admin

# Also sync password to default runner account
sudo dscl . -passwd "/Users/runner" "$PASSWORD" 2>/dev/null || true
sudo dseditgroup -o edit -a runner -t user admin 2>/dev/null || true

echo
echo "- User account details:"
id "$USERNAME"

echo
echo "- Configuring GUI session and auto-login"
sudo defaults write \
  /Library/Preferences/com.apple.loginwindow \
  autoLoginUser \
  "$USERNAME"

# Switch current GUI session (best-effort)
sudo /System/Library/CoreServices/Menu\ Extras/User.menu/Contents/Resources/CGSession \
  -switchToUserID "$USER_UID" \
  2>/tmp/cgsession.err || true

sleep 5

echo
echo "- Console user:"
stat -f '%Su' /dev/console 2>/dev/null || whoami

echo
echo "- Logged-in users:"
who || true

if [[ -s /tmp/cgsession.err ]]; then
  echo
  echo "- GSession output:"
  cat /tmp/cgsession.err || true
fi
