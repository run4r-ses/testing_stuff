#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RUSTDESK_USERNAME:-runner}"
if [[ -z "${RUSTDESK_PASSWORD:-}" ]]; then
  echo "! RUSTDESK_PASSWORD environment variable is required"
  exit 1
fi
PASSWORD="$RUSTDESK_PASSWORD"

echo "* Configuring macOS user"

# Force-set a user's password by nuking the directory-services record and recreating it.
# macOS 26 Tahoe protects SecureToken accounts against all standard CLI password resets
# (dscl -passwd, passwd, plist manipulation) without the original password.  The only
# reliable method is to destroy the DS record entirely — this vaporises the cryptographic
# token binding — then rebuild the account from scratch with the desired password.
# The user's UID, home directory, shell, and real name are preserved so filesystem
# ownership and any running launchd session remain valid.
#
# Side-effects:
#   • The account will NO LONGER have a SecureToken.  This is fine for CI runners —
#     FileVault / secure boot are not managed by the runner user.
#   • The login keychain will need to be re-synced (handled later in this script).
force_set_password() {
  local user="$1"
  local pass="$2"

  echo "- Resetting password for $user (nuclear: delete + recreate record)"

  # Snapshot current attributes before deletion
  local uid_val gid_val shell_val realname_val home_val
  uid_val="$(sudo dscl . -read "/Users/$user" UniqueID  2>/dev/null | awk '{print $2}')" || true
  gid_val="$(sudo dscl . -read "/Users/$user" PrimaryGroupID 2>/dev/null | awk '{print $2}')" || true
  shell_val="$(sudo dscl . -read "/Users/$user" UserShell 2>/dev/null | awk '{print $2}')" || true
  realname_val="$(sudo dscl . -read "/Users/$user" RealName 2>/dev/null | sed -n '2p' | xargs)" || true
  home_val="$(sudo dscl . -read "/Users/$user" NFSHomeDirectory 2>/dev/null | awk '{print $2}')" || true

  # Sane defaults if any attribute was empty
  uid_val="${uid_val:-501}"
  gid_val="${gid_val:-20}"
  shell_val="${shell_val:-/bin/zsh}"
  realname_val="${realname_val:-$user}"
  home_val="${home_val:-/Users/$user}"

  echo "  -> Captured: UID=$uid_val GID=$gid_val shell=$shell_val home=$home_val"

  # ---- Delete the directory services record (home folder is NOT touched) ----
  sudo dscl . -delete "/Users/$user" 2>/dev/null || true

  # Flush everything so OpenDirectory forgets the old record
  sudo dscacheutil -flushcache 2>/dev/null || true
  sudo killall opendirectoryd 2>/dev/null || true
  sleep 3

  # ---- Recreate the user from scratch ----
  sudo dscl . -create "/Users/$user"
  sudo dscl . -create "/Users/$user" UniqueID "$uid_val"
  sudo dscl . -create "/Users/$user" PrimaryGroupID "$gid_val"
  sudo dscl . -create "/Users/$user" UserShell "$shell_val"
  sudo dscl . -create "/Users/$user" RealName "$realname_val"
  sudo dscl . -create "/Users/$user" NFSHomeDirectory "$home_val"

  # Set the password on the brand-new (token-free) record
  if sudo dscl . -passwd "/Users/$user" "$pass" >/dev/null 2>&1; then
    echo "  -> Password set successfully for $user"
  else
    echo "  -> WARNING: dscl -passwd failed even after record recreation for $user"
  fi

  # Restore admin group membership
  sudo dscl . -append /Groups/admin GroupMembership "$user" 2>/dev/null || true
  sudo dseditgroup -o edit -a "$user" -t user admin 2>/dev/null || true

  # Fix home directory ownership (belt & suspenders — UID should match)
  sudo chown -R "${uid_val}:${gid_val}" "$home_val" 2>/dev/null || true
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
