#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RUSTDESK_USERNAME:-runneradmin}"
if [[ -z "${RUSTDESK_PASSWORD:-}" ]]; then
  echo "! RUSTDESK_PASSWORD environment variable is required"
  exit 1
fi
PASSWORD="$RUSTDESK_PASSWORD"
USER_UID="${RUSTDESK_UID:-502}"

echo "* Creating GUI user $USERNAME"

if id "$USERNAME" >/dev/null 2>&1; then
  echo "- User $USERNAME already exists, updating password"
  # sysadminctl -resetPasswordFor requires -adminUser/-adminPassword on GitHub runners;
  # fall through to dscl which works reliably when run as root.
  sudo sysadminctl -resetPasswordFor "$USERNAME" -newPassword "$PASSWORD" 2>/dev/null || true
  # Always force-set via dscl as root — this writes directly to Open Directory
  # and doesn't require knowing the old password when run as root.
  sudo dscl . -passwd "/Users/$USERNAME" "$PASSWORD" 2>/dev/null || \
  (printf "%s\n%s\n" "$PASSWORD" "$PASSWORD" | sudo passwd "$USERNAME" 2>/dev/null) || true
else
  echo "- Creating new user account for $USERNAME"
  if sudo sysadminctl -addUser "$USERNAME" -fullName "runneradmin" -UID "$USER_UID" -password "$PASSWORD" -home "/Users/$USERNAME" -shell /bin/bash -admin 2>/dev/null; then
    echo "- User $USERNAME created via sysadminctl"
  else
    echo "! Creating user $USERNAME via dscl as fallback"
    sudo dscl . -create "/Users/$USERNAME"
    sudo dscl . -create "/Users/$USERNAME" UserShell /bin/bash
    sudo dscl . -create "/Users/$USERNAME" RealName "runneradmin"
    sudo dscl . -create "/Users/$USERNAME" UniqueID "$USER_UID"
    sudo dscl . -create "/Users/$USERNAME" PrimaryGroupID 20
    sudo dscl . -create "/Users/$USERNAME" NFSHomeDirectory "/Users/$USERNAME"
    sudo createhomedir -c -u "$USERNAME" >/dev/null 2>&1 || true
  fi

  # Harden password after creation — sysadminctl -addUser silently fails to
  # commit the password on GitHub-hosted macOS runners because it needs
  # -adminUser / -adminPassword of an existing secure-token admin, which the
  # CI environment doesn't expose. Force-set via dscl as root, which writes
  # directly to the Open Directory authentication database.
  echo "- Setting password via dscl"
  sudo dscl . -passwd "/Users/$USERNAME" "$PASSWORD" 2>/dev/null || \
  (printf "%s\n%s\n" "$PASSWORD" "$PASSWORD" | sudo passwd "$USERNAME" 2>/dev/null) || true
fi

# Ensure user is in admin group
sudo dseditgroup -o edit -a "$USERNAME" -t user admin 2>/dev/null || true

# Also sync password to default runner account
echo "- Updating default runner account password"
sudo sysadminctl -resetPasswordFor runner -newPassword "$PASSWORD" 2>/dev/null || true
# Always force-set via dscl as root (same reasoning as above)
sudo dscl . -passwd "/Users/runner" "$PASSWORD" 2>/dev/null || \
(printf "%s\n%s\n" "$PASSWORD" "$PASSWORD" | sudo passwd runner 2>/dev/null) || true
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

echo
echo "- Console user:"
stat -f '%Su' /dev/console 2>/dev/null || whoami

echo
echo "- Logged-in users:"
who || true
