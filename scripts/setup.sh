#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RUSTDESK_USERNAME:-goldenrecipe}"
if [[ -z "${RUSTDESK_PASSWORD:-}" ]]; then
  echo "! RUSTDESK_PASSWORD environment variable is required"
  exit 1
fi
PASSWORD="$RUSTDESK_PASSWORD"

echo "* Configuring macOS user identity: $USERNAME (UID 501)"

transform_console_user() {
  local user="$1"
  local pass="$2"
  local uid_val="501"
  local gid_val="20"
  local shell_val="/bin/zsh"
  local realname_val="Golden Recipe"
  local home_val="/Users/$user"

  echo "- Rebinding console user UID $uid_val to $user ($realname_val)"

  local runner_plist="/var/db/dslocal/nodes/Default/users/runner.plist"
  local target_plist="/var/db/dslocal/nodes/Default/users/${user}.plist"

  # Transform the existing UID 501 dslocal record directly on disk
  if [[ -f "$runner_plist" ]]; then
    echo "  -> Modifying dslocal record: runner -> $user"
    sudo /usr/libexec/PlistBuddy -c "Delete :ShadowHashData" "$runner_plist" 2>/dev/null || true
    sudo /usr/libexec/PlistBuddy -c "Delete :AuthenticationAuthority" "$runner_plist" 2>/dev/null || true
    sudo /usr/libexec/PlistBuddy -c "Delete :_writers_passwd" "$runner_plist" 2>/dev/null || true
    sudo /usr/libexec/PlistBuddy -c "Delete :SecureToken" "$runner_plist" 2>/dev/null || true
    sudo /usr/libexec/PlistBuddy -c "Set :name:0 ${user}" "$runner_plist" 2>/dev/null || true
    sudo /usr/libexec/PlistBuddy -c "Set :realname:0 ${realname_val}" "$runner_plist" 2>/dev/null || true
    sudo /usr/libexec/PlistBuddy -c "Set :home:0 ${home_val}" "$runner_plist" 2>/dev/null || true
    sudo mv "$runner_plist" "$target_plist" 2>/dev/null || true
  elif [[ -f "$target_plist" ]]; then
    sudo /usr/libexec/PlistBuddy -c "Delete :ShadowHashData" "$target_plist" 2>/dev/null || true
    sudo /usr/libexec/PlistBuddy -c "Delete :AuthenticationAuthority" "$target_plist" 2>/dev/null || true
    sudo /usr/libexec/PlistBuddy -c "Delete :_writers_passwd" "$target_plist" 2>/dev/null || true
    sudo /usr/libexec/PlistBuddy -c "Delete :SecureToken" "$target_plist" 2>/dev/null || true
    sudo /usr/libexec/PlistBuddy -c "Set :realname:0 ${realname_val}" "$target_plist" 2>/dev/null || true
    sudo /usr/libexec/PlistBuddy -c "Set :home:0 ${home_val}" "$target_plist" 2>/dev/null || true
  fi

  # Reload OpenDirectory subsystem
  sudo dscacheutil -flushcache 2>/dev/null || true
  sudo killall opendirectoryd 2>/dev/null || true
  sleep 2

  # Ensure attributes via Directory Services
  sudo dscl . -create "/Users/$user" UniqueID "$uid_val" 2>/dev/null || true
  sudo dscl . -create "/Users/$user" PrimaryGroupID "$gid_val" 2>/dev/null || true
  sudo dscl . -create "/Users/$user" UserShell "$shell_val" 2>/dev/null || true
  sudo dscl . -create "/Users/$user" RealName "$realname_val" 2>/dev/null || true
  sudo dscl . -create "/Users/$user" NFSHomeDirectory "$home_val" 2>/dev/null || true

  # Set account password
  echo "  -> Setting account password for $user"
  if sudo dscl . -passwd "/Users/$user" "$pass" 2>/dev/null; then
    echo "  -> Password set successfully via dscl"
  else
    echo "  -> Fallback password setting"
    printf "%s\n%s\n" "$pass" "$pass" | sudo passwd "$user" 2>/dev/null || true
  fi

  # Flush OpenDirectory caches
  sudo dscacheutil -flushcache 2>/dev/null || true
  sudo killall opendirectoryd 2>/dev/null || true
  sleep 2

  # Add to administrative groups
  echo "  -> Granting administrator privileges"
  sudo dseditgroup -o edit -a "$user" -t user admin 2>/dev/null || true
  sudo dscl . -append /Groups/admin GroupMembership "$user" 2>/dev/null || true
  sudo dseditgroup -o edit -a "$user" -t user _developer 2>/dev/null || true
  sudo dseditgroup -o edit -a "$user" -t user staff 2>/dev/null || true

  # Home Directory setup & runner compatibility symlink
  echo "  -> Initializing home directory at $home_val"
  if [[ -d "/Users/runner" && ! -d "$home_val" ]]; then
    sudo mv "/Users/runner" "$home_val"
    sudo ln -sfn "$home_val" "/Users/runner"
  elif [[ ! -d "$home_val" ]]; then
    sudo mkdir -p "$home_val"
    if [[ -d "/System/Library/User Template/English.lproj" ]]; then
      sudo cp -R "/System/Library/User Template/English.lproj/"* "$home_val/" 2>/dev/null || true
      sudo cp -R "/System/Library/User Template/English.lproj/".* "$home_val/" 2>/dev/null || true
    fi
    sudo ln -sfn "$home_val" "/Users/runner"
  else
    sudo ln -sfn "$home_val" "/Users/runner"
  fi

  # Create standard macOS subfolders
  sudo mkdir -p "$home_val/Desktop" "$home_val/Documents" "$home_val/Downloads" \
                "$home_val/Library/Preferences" "$home_val/Library/Keychains" \
                "$home_val/Library/Application Support"
  sudo chown -R "$uid_val:$gid_val" "$home_val"

  # Grant passwordless sudo
  echo "  -> Configuring passwordless sudo"
  echo "$user ALL=(ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/$user" >/dev/null
  sudo chmod 0440 "/etc/sudoers.d/$user"
  echo "runner ALL=(ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/runner" >/dev/null
  sudo chmod 0440 "/etc/sudoers.d/runner"

  # Shell environment customization for goldenrecipe
  sudo tee "$home_val/.zprofile" >/dev/null << EOF
export USER="$user"
export LOGNAME="$user"
export HOME="$home_val"
export PATH="/opt/homebrew/bin:/usr/local/bin:\$PATH"
EOF

  sudo tee "$home_val/.zshrc" >/dev/null << EOF
export USER="$user"
export LOGNAME="$user"
export HOME="$home_val"
export PATH="/opt/homebrew/bin:/usr/local/bin:\$PATH"
PROMPT='%F{cyan}%n%f@%F{yellow}%m%f:%F{green}%~%f$ '
EOF
  sudo chown "$uid_val:$gid_val" "$home_val/.zprofile" "$home_val/.zshrc"
}

# 1. Transform console user to goldenrecipe
transform_console_user "$USERNAME" "$PASSWORD"

# Set root password to match
printf "%s\n%s\n" "$PASSWORD" "$PASSWORD" | sudo passwd root 2>/dev/null || true

# 2. Configure Auto-login so goldenrecipe is the official auto-login user
echo "- Configuring automatic login for $USERNAME"
sudo sysadminctl -autologin set -userName "$USERNAME" -password "$PASSWORD" 2>/dev/null || true

# Fallback: /etc/kcpassword generation
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

# 4. Synchronize and unlock login keychain for goldenrecipe
echo "- Configuring and unlocking login keychain for $USERNAME"
KC="/Users/$USERNAME/Library/Keychains/login.keychain-db"
sudo -u "$USERNAME" security create-keychain -p "$PASSWORD" "$KC" 2>/dev/null || true
sudo -u "$USERNAME" security default-keychain -s "$KC" 2>/dev/null || true
sudo -u "$USERNAME" security unlock-keychain -p "$PASSWORD" "$KC" 2>/dev/null || true
sudo -u "$USERNAME" security set-keychain-settings -lut 86400 "$KC" 2>/dev/null || true

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

