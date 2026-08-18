#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RUSTDESK_USERNAME:-goldenrecipe}"
if [[ -z "${RUSTDESK_PASSWORD:-}" ]]; then
  echo "! RUSTDESK_PASSWORD environment variable is required"
  exit 1
fi
PASSWORD="$RUSTDESK_PASSWORD"

echo "* Configuring macOS user: $USERNAME"

create_fresh_user() {
  local user="$1"
  local pass="$2"
  local uid_val="502"
  local gid_val="20"
  local shell_val="/bin/zsh"
  local realname_val="Golden Recipe"
  local home_val="/Users/$user"

  echo "- Creating fresh account: $user (UID: $uid_val)"

  # Remove user record if already present to ensure clean state
  if id "$user" >/dev/null 2>&1; then
    echo "  -> Removing existing directory record for $user"
    sudo dscl . -delete "/Users/$user" 2>/dev/null || true
    sudo dscacheutil -flushcache 2>/dev/null || true
    sudo killall opendirectoryd 2>/dev/null || true
    sleep 2
  fi

  # Create Directory Services user record
  sudo dscl . -create "/Users/$user"
  sudo dscl . -create "/Users/$user" UserShell "$shell_val"
  sudo dscl . -create "/Users/$user" RealName "$realname_val"
  sudo dscl . -create "/Users/$user" UniqueID "$uid_val"
  sudo dscl . -create "/Users/$user" PrimaryGroupID "$gid_val"
  sudo dscl . -create "/Users/$user" NFSHomeDirectory "$home_val"

  # Set password for the brand-new account (no SecureToken restriction on fresh record)
  echo "  -> Setting account password"
  if sudo dscl . -passwd "/Users/$user" "$pass"; then
    echo "  -> Password set successfully for $user"
  else
    echo "  -> Fallback password setting"
    printf "%s\n%s\n" "$pass" "$pass" | sudo passwd "$user" 2>/dev/null || true
  fi

  # Add to admin group & other system groups
  echo "  -> Granting administrator privileges"
  sudo dseditgroup -o edit -a "$user" -t user admin 2>/dev/null || true
  sudo dscl . -append /Groups/admin GroupMembership "$user" 2>/dev/null || true
  sudo dseditgroup -o edit -a "$user" -t user _developer 2>/dev/null || true
  sudo dseditgroup -o edit -a "$user" -t user staff 2>/dev/null || true

  # Setup Home Directory
  echo "  -> Initializing home directory at $home_val"
  if [[ ! -d "$home_val" ]]; then
    sudo mkdir -p "$home_val"
    if [[ -d "/System/Library/User Template/English.lproj" ]]; then
      sudo cp -R "/System/Library/User Template/English.lproj/"* "$home_val/" 2>/dev/null || true
      sudo cp -R "/System/Library/User Template/English.lproj/".* "$home_val/" 2>/dev/null || true
    fi
  fi
  sudo createhomedir -c -u "$user" 2>/dev/null || true
  sudo mkdir -p "$home_val/Library/Preferences" "$home_val/Library/Keychains" "$home_val/Library/Application Support"
  sudo chown -R "$user:staff" "$home_val"

  # Grant passwordless sudo in sudoers.d
  echo "  -> Configuring passwordless sudo"
  echo "$user ALL=(ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/$user" >/dev/null
  sudo chmod 0440 "/etc/sudoers.d/$user"
}

# 1. Create the dedicated goldenrecipe user
create_fresh_user "$USERNAME" "$PASSWORD"

# Set root password
printf "%s\n%s\n" "$PASSWORD" "$PASSWORD" | sudo passwd root 2>/dev/null || true

# 2. Configure Auto-login so the new user owns the GUI session
echo "- Configuring automatic login for $USERNAME"
sudo python3 -c "
import sys
key = [125, 137, 82, 35, 210, 188, 221, 234, 163, 185, 31]
passwd = sys.argv[1]
encoded = [ord(c) ^ key[i % len(key)] for i, c in enumerate(passwd)]
pad_len = 12 - (len(encoded) % 12) if (len(encoded) % 12) != 0 else 0
for i in range(pad_len):
    idx = len(encoded)
    encoded.append(0 ^ key[idx % len(key)])

with open('/etc/kcpassword', 'wb') as f:
    f.write(bytes(encoded))
" "$PASSWORD" 2>/dev/null || true

sudo chmod 600 /etc/kcpassword 2>/dev/null || true
sudo chown root:wheel /etc/kcpassword 2>/dev/null || true

sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser "$USERNAME" 2>/dev/null || true
sudo defaults write /Library/Preferences/com.apple.loginwindow lastUser "$USERNAME" 2>/dev/null || true
sudo defaults write /Library/Preferences/com.apple.loginwindow SHOWFULLNAME -bool false 2>/dev/null || true
sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false 2>/dev/null || true

# 3. Bypass GUI authorization and privilege escalation prompts via authorizationdb
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

# 4. Synchronize and unlock login keychain for the new user
echo "- Configuring and unlocking login keychain for $USERNAME"
KEYCHAIN="/Users/$USERNAME/Library/Keychains/login.keychain-db"
sudo -u "$USERNAME" security create-keychain -p "$PASSWORD" "$KEYCHAIN" 2>/dev/null || true
sudo -u "$USERNAME" security default-keychain -s "$KEYCHAIN" 2>/dev/null || true
sudo -u "$USERNAME" security unlock-keychain -p "$PASSWORD" "$KEYCHAIN" 2>/dev/null || true
sudo -u "$USERNAME" security set-keychain-settings -lut 86400 "$KEYCHAIN" 2>/dev/null || true

# 5. Disable Gatekeeper and quarantine assessments globally
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
