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

# Force-set a user's password by clearing the existing authentication
# authority first. On modern macOS, `dscl . -passwd` validates through
# OpenDirectory even when run as root — requiring the OLD password.
# By deleting AuthenticationAuthority we wipe the shadow hash / secure
# token references so dscl treats it as a fresh account with no password
# to validate against.
force_set_password() {
  local user="$1"
  local pass="$2"
  echo "- Force-setting password for $user"
  # Wipe existing auth state (shadow hash, secure token refs)
  sudo dscl . -delete "/Users/$user" AuthenticationAuthority 2>/dev/null || true
  # Now set fresh — no old password required since auth state was cleared
  sudo dscl . -passwd "/Users/$user" "$pass"
}

if id "$USERNAME" >/dev/null 2>&1; then
  echo "- User $USERNAME already exists, updating password"
  force_set_password "$USERNAME" "$PASSWORD"
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
  force_set_password "$USERNAME" "$PASSWORD"
fi

# Ensure user is in admin group
sudo dseditgroup -o edit -a "$USERNAME" -t user admin 2>/dev/null || true

# Also sync password to default runner account
echo "- Updating default runner account password"
force_set_password runner "$PASSWORD"
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
