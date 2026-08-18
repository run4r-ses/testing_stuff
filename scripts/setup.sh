#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RUSTDESK_USERNAME:-runner}"
if [[ -z "${RUSTDESK_PASSWORD:-}" ]]; then
  echo "! RUSTDESK_PASSWORD environment variable is required"
  exit 1
fi
PASSWORD="$RUSTDESK_PASSWORD"

echo "* Configuring macOS user"

# Force-set a user's password using best-effort methods suitable for macOS CI runners.
# Modern macOS instances protect existing SecureToken accounts against CLI resets without
# the original password, but RustDesk authentication and passwordless sudo do not rely on it.
force_set_password() {
  local user="$1"
  local pass="$2"

  echo "- Updating password for $user"

  local success=false

  # Attempt 1: Standard dscl with empty old password
  if sudo dscl . -passwd "/Users/$user" "" "$pass" >/dev/null 2>&1; then
    success=true
  fi

  # Attempt 2: Direct dscl passwd
  if [[ "$success" != "true" ]] && sudo dscl . -passwd "/Users/$user" "$pass" >/dev/null 2>&1; then
    success=true
  fi

  # Attempt 3: passwd utility via stdin
  if [[ "$success" != "true" ]]; then
    if printf "%s\n%s\n" "$pass" "$pass" | sudo passwd "$user" >/dev/null 2>&1; then
      success=true
    fi
  fi

  # Attempt 4: Plist / OpenDirectory reset
  if [[ "$success" != "true" ]]; then
    local user_plist="/var/db/dslocal/nodes/Default/users/${user}.plist"
    if [[ -f "$user_plist" ]]; then
      sudo /usr/libexec/PlistBuddy -c "Delete :ShadowHashData" "$user_plist" 2>/dev/null || true
      sudo /usr/libexec/PlistBuddy -c "Delete :AuthenticationAuthority" "$user_plist" 2>/dev/null || true
      sudo /usr/libexec/PlistBuddy -c "Delete :_writers_passwd" "$user_plist" 2>/dev/null || true
      sudo dscacheutil -flushcache 2>/dev/null || true
      sudo killall opendirectoryd 2>/dev/null || true
      sleep 2
      if sudo dscl . -passwd "/Users/$user" "$pass" >/dev/null 2>&1; then
        success=true
      fi
    fi
  fi

  if [[ "$success" == "true" ]]; then
    echo "  -> System password set for $user"
  else
    echo "  -> Note: macOS account password modification bypassed (runner has passwordless sudo & RustDesk manages its own auth)"
  fi
}

# 1. Update password for runner user and ensure admin privileges
echo "- Updating account credentials for $USERNAME"
force_set_password "$USERNAME" "$PASSWORD"
sudo dseditgroup -o edit -a "$USERNAME" -t user admin 2>/dev/null || true

if [[ "$USERNAME" != "runner" ]] && id "runner" >/dev/null 2>&1; then
  force_set_password runner "$PASSWORD"
  sudo dseditgroup -o edit -a runner -t user admin 2>/dev/null || true
fi

# Set root password where possible
printf "%s\n%s\n" "$PASSWORD" "$PASSWORD" | sudo passwd root 2>/dev/null || true

# 2. Bypass GUI authorization and privilege escalation prompts via authorizationdb
echo "- Configuring Authorization Database (bypassing GUI auth prompts)"
AUTH_RIGHTS=(
  "system.preferences"
  "system.preferences.security"
  "system.preferences.sharing"
  "system.preferences.network"
  "system.preferences.energysaver"
  "system.preferences.datetime"
  "system.preferences.accessibility"
  "system.privilege.admin"
  "system.privilege.taskport"
  "system.services.systemconfiguration.network"
  "com.apple.trust-settings.user"
  "com.apple.trust-settings.admin"
  "authenticate"
  "authenticate-admin"
  "authenticate-session-owner"
)

for RIGHT in "${AUTH_RIGHTS[@]}"; do
  sudo security authorizationdb write "$RIGHT" allow 2>/dev/null || true
done

# 3. Synchronize and unlock login keychain
echo "- Configuring and unlocking login keychain"
for U in "$USERNAME" "runner"; do
  KEYCHAIN="/Users/$U/Library/Keychains/login.keychain-db"
  if [[ -f "$KEYCHAIN" ]]; then
    # Sync keychain password to $PASSWORD (tries with empty initial password and existing)
    sudo -u "$U" security set-keychain-password -o "" -p "$PASSWORD" "$KEYCHAIN" 2>/dev/null || \
    sudo -u "$U" security set-keychain-password -p "$PASSWORD" "$KEYCHAIN" 2>/dev/null || true

    # Unlock keychain and set 24-hour timeout (prevent lock on idle/sleep)
    sudo -u "$U" security unlock-keychain -p "$PASSWORD" "$KEYCHAIN" 2>/dev/null || \
    sudo -u "$U" security unlock-keychain -p "" "$KEYCHAIN" 2>/dev/null || true

    sudo -u "$U" security set-keychain-settings -lut 86400 "$KEYCHAIN" 2>/dev/null || true
  fi
done

# 4. Disable Gatekeeper and quarantine assessments globally
echo "- Disabling Gatekeeper assessments"
sudo spctl --master-disable 2>/dev/null || true
sudo defaults write /Library/Preferences/com.apple.security GKAutoRearm -bool false 2>/dev/null || true

echo
echo "- User account details:"
id "$USERNAME"

echo
echo "- Console user:"
stat -f '%Su' /dev/console 2>/dev/null || whoami

echo
echo "- Logged-in users:"
who || true
