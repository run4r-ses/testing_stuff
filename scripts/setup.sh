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

# Force-set a user's password by stripping existing auth data directly
# from the user's plist file, bypassing OpenDirectory's access controls.
# On modern macOS, `dscl . -passwd` and even `dscl . -delete AuthenticationAuthority`
# route through opendirectoryd which can refuse changes for protected users.
# By editing the plist file on disk and restarting opendirectoryd, we bypass
# all OD-level access checks.
force_set_password() {
  local user="$1"
  local pass="$2"
  local user_plist="/var/db/dslocal/nodes/Default/users/${user}.plist"

  echo "- Force-setting password for $user"

  # Strip auth data directly from the on-disk plist (bypasses OD access controls)
  if [[ -f "$user_plist" ]]; then
    sudo /usr/libexec/PlistBuddy -c "Delete :ShadowHashData" "$user_plist" 2>/dev/null || true
    sudo /usr/libexec/PlistBuddy -c "Delete :AuthenticationAuthority" "$user_plist" 2>/dev/null || true
    sudo /usr/libexec/PlistBuddy -c "Delete :_writers_passwd" "$user_plist" 2>/dev/null || true
  fi

  # Also try via dscl for any in-memory state
  sudo dscl . -delete "/Users/$user" AuthenticationAuthority 2>/dev/null || true

  # Restart opendirectoryd so it re-reads the stripped plist from disk
  sudo dscacheutil -flushcache 2>/dev/null || true
  sudo killall opendirectoryd 2>/dev/null || true
  sleep 3

  # Now set the password — succeeds because there's no existing auth to validate
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
