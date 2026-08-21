#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RDP_USERNAME:-${VNC_USERNAME:-goldenrecipe}}"
PASSWORD="${RDP_PASSWORD:-${VNC_PASSWORD:-}}"
if [[ -z "$PASSWORD" ]]; then
  echo "! VNC_PASSWORD or RDP_PASSWORD environment variable is required"
  exit 1
fi
USER_UID="${RDP_UID:-${VNC_UID:-502}}"

echo "* Creating GUI user $USERNAME"

if id "$USERNAME" >/dev/null 2>&1; then
  echo "- User $USERNAME already exists, updating password"
  sudo dscl . -passwd "/Users/$USERNAME" "$PASSWORD"
else
  echo "- Creating new user account for $USERNAME"
  sudo dscl . -create "/Users/$USERNAME"
  sudo dscl . -create "/Users/$USERNAME" UserShell /bin/bash
  sudo dscl . -create "/Users/$USERNAME" RealName "$USERNAME"
  sudo dscl . -create "/Users/$USERNAME" UniqueID "$USER_UID"
  sudo dscl . -create "/Users/$USERNAME" PrimaryGroupID 20
  sudo dscl . -create "/Users/$USERNAME" NFSHomeDirectory "/Users/$USERNAME"
  sudo dscl . -passwd "/Users/$USERNAME" "$PASSWORD"

  sudo createhomedir -c -u "$USERNAME" >/dev/null 2>&1 || true
fi

# Ensure user is in admin group
sudo dseditgroup -o edit -a "$USERNAME" -t user admin

echo
echo "- User account details:"
id "$USERNAME"

echo
echo "- Console user:"
stat -f '%Su' /dev/console 2>/dev/null || whoami

echo
echo "- Logged-in users:"
who || true

