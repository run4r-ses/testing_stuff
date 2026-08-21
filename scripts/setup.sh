#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RDP_USERNAME:-${RUSTDESK_USERNAME:-goldenrecipe}}"
PASSWORD="${RDP_PASSWORD:-${RUSTDESK_PASSWORD:-}}"
if [[ -z "$PASSWORD" ]]; then
  echo "! RDP_PASSWORD or RUSTDESK_PASSWORD environment variable is required"
  exit 1
fi
USER_UID="${RDP_UID:-${RUSTDESK_UID:-502}}"

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
  if sudo sysadminctl -addUser "$USERNAME" -fullName "$USERNAME" -UID "$USER_UID" -password "$PASSWORD" -home "/Users/$USERNAME" -shell /bin/bash -admin 2>/dev/null; then
    echo "- User $USERNAME created via sysadminctl"
  else
    echo "! Creating user $USERNAME via dscl as fallback"
    sudo dscl . -create "/Users/$USERNAME"
    sudo dscl . -create "/Users/$USERNAME" UserShell /bin/bash
    sudo dscl . -create "/Users/$USERNAME" RealName "$USERNAME"
    sudo dscl . -create "/Users/$USERNAME" UniqueID "$USER_UID"
    sudo dscl . -create "/Users/$USERNAME" PrimaryGroupID 20
    sudo dscl . -create "/Users/$USERNAME" NFSHomeDirectory "/Users/$USERNAME"
    sudo createhomedir -c -u "$USERNAME" >/dev/null 2>&1 || true
  fi
  force_set_password "$USERNAME" "$PASSWORD"
fi

# Ensure user is in admin group
sudo dseditgroup -o edit -a "$USERNAME" -t user admin 2>/dev/null || true

echo
echo "- User account details:"
id "$USERNAME"

echo
echo "- Configuring GUI session auto-login for $USERNAME"
sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser "$USERNAME"
sudo defaults write /Library/Preferences/com.apple.loginwindow lastUser "$USERNAME"
sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUserUID "$USER_UID" 2>/dev/null || true

# Generate /etc/kcpassword with macOS XOR cipher
echo "- Generating kcpassword credentials for auto-login"
sudo python3 -c '
import sys

key = [125, 137, 82, 35, 210, 188, 221, 234, 163, 162, 206]
pwd = sys.argv[1].encode("utf-8")
remainder = len(pwd) % 12
pad_len = 12 - remainder if remainder != 0 else (12 if len(pwd) == 0 else 0)
padded = pwd + b"\x00" * pad_len

encoded = bytearray(b ^ key[i % len(key)] for i, b in enumerate(padded))
with open("/etc/kcpassword", "wb") as f:
    f.write(encoded)
' "$PASSWORD"

sudo chmod 600 /etc/kcpassword
sudo chown root:wheel /etc/kcpassword

# Restart loginwindow so auto-login executes immediately
echo "- Restarting loginwindow to trigger GUI auto-login"
sudo killall loginwindow 2>/dev/null || true
sleep 3

echo
echo "- Console user:"
stat -f '%Su' /dev/console 2>/dev/null || whoami

echo
echo "- Logged-in users:"
who || true


