#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RUSTDESK_USERNAME:-goldenrecipe}"
if [[ -z "${RUSTDESK_PASSWORD:-}" ]]; then
  echo "! RUSTDESK_PASSWORD environment variable is required"
  exit 1
fi
PASSWORD="$RUSTDESK_PASSWORD"

echo "* Configuring macOS user identity: $USERNAME (UID 501)"

create_admin_user() {
  local user="$1"
  local pass="$2"
  local realname_val="Golden Recipe"
  local home_val="/Users/$user"

  # 1. Create or ensure user using Apple's official sysadminctl CLI
  if ! id "$user" >/dev/null 2>&1; then
    echo "- Creating administrator account: $user via sysadminctl"
    sudo sysadminctl -addUser "$user" -fullName "$realname_val" -password "$pass" -admin 2>/dev/null || {
      echo "  -> Fallback account creation via dscl"
      local next_uid="502"
      sudo dscl . -create "/Users/$user"
      sudo dscl . -create "/Users/$user" UserShell "/bin/zsh"
      sudo dscl . -create "/Users/$user" RealName "$realname_val"
      sudo dscl . -create "/Users/$user" UniqueID "$next_uid"
      sudo dscl . -create "/Users/$user" PrimaryGroupID "20"
      sudo dscl . -create "/Users/$user" NFSHomeDirectory "$home_val"
      sudo dscl . -passwd "/Users/$user" "$pass" 2>/dev/null || true
    }
  else
    echo "- Account already exists: $user"
  fi

  # 2. Grant administrator group memberships
  echo "  -> Ensuring administrator privileges"
  sudo dseditgroup -o edit -a "$user" -t user admin 2>/dev/null || true
  sudo dscl . -append /Groups/admin GroupMembership "$user" 2>/dev/null || true
  sudo dseditgroup -o edit -a "$user" -t user _developer 2>/dev/null || true
  sudo dseditgroup -o edit -a "$user" -t user staff 2>/dev/null || true

  # 3. Setup home directory structure
  echo "  -> Initializing home directory at $home_val"
  sudo mkdir -p "$home_val" "$home_val/Desktop" "$home_val/Documents" "$home_val/Downloads" \
                "$home_val/Library/Preferences" "$home_val/Library/Keychains" \
                "$home_val/Library/Application Support"
  sudo chown -R "$user:staff" "$home_val" 2>/dev/null || true

  # 4. Grant passwordless sudo
  echo "  -> Configuring passwordless sudo"
  echo "$user ALL=(ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/$user" >/dev/null
  sudo chmod 0440 "/etc/sudoers.d/$user"
  echo "runner ALL=(ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/runner" >/dev/null
  sudo chmod 0440 "/etc/sudoers.d/runner"

  # 5. Shell environment customization for goldenrecipe
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
  sudo chown -R "$user:staff" "$home_val/.zprofile" "$home_val/.zshrc" 2>/dev/null || true
}

# 1. Create the dedicated goldenrecipe user
create_admin_user "$USERNAME" "$PASSWORD"

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

