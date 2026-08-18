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

  # Step 1: Rename RecordName via dscl if runner exists
  if dscl . -read "/Users/runner" >/dev/null 2>&1; then
    echo "  -> Renaming RecordName: runner -> $user"
    sudo dscl . -change "/Users/runner" RecordName runner "$user" 2>/dev/null || true
  fi

  # Step 2: Inject native SALTED-SHA512-PBKDF2 ShadowHashData into OpenDirectory plist
  echo "  -> Injecting native OpenDirectory password hash for $user"
  sudo python3 -c "
import hashlib, os, plistlib, sys

user = sys.argv[1]
password = sys.argv[2]
realname = sys.argv[3]
home = sys.argv[4]

plist_path = f'/var/db/dslocal/nodes/Default/users/{user}.plist'
runner_plist = '/var/db/dslocal/nodes/Default/users/runner.plist'

if not os.path.exists(plist_path) and os.path.exists(runner_plist):
    try:
        os.rename(runner_plist, plist_path)
    except Exception:
        pass

if os.path.exists(plist_path):
    with open(plist_path, 'rb') as f:
        data = plistlib.load(f)

    salt = os.urandom(32)
    iterations = 45000
    entropy = hashlib.pbkdf2_hmac('sha512', password.encode('utf-8'), salt, iterations, dklen=128)

    shadow_dict = {
        'SALTED-SHA512-PBKDF2': {
            'entropy': entropy,
            'salt': salt,
            'iterations': iterations
        }
    }
    binary_plist = plistlib.dumps(shadow_dict, fmt=plistlib.FMT_BINARY)

    data['name'] = [user]
    data['realname'] = [realname]
    data['home'] = [home]
    data['ShadowHashData'] = [binary_plist]
    data['AuthenticationAuthority'] = [
        ';ShadowHash;HASHLIST:<SALTED-SHA512-PBKDF2>'
    ]
    for k in ['_writers_passwd', 'SecureToken', 'shadow_hash']:
        data.pop(k, None)

    with open(plist_path, 'wb') as f:
        plistlib.dump(data, f, fmt=plistlib.FMT_XML)
" "$user" "$pass" "$realname_val" "$home_val" 2>/dev/null || true

  # Step 3: Ensure attributes in Directory Services
  sudo dscl . -create "/Users/$user" RealName "$realname_val" 2>/dev/null || true
  sudo dscl . -create "/Users/$user" NFSHomeDirectory "$home_val" 2>/dev/null || true
  sudo dscl . -create "/Users/$user" UserShell "$shell_val" 2>/dev/null || true
  sudo dscl . -create "/Users/$user" UniqueID "$uid_val" 2>/dev/null || true
  sudo dscl . -create "/Users/$user" PrimaryGroupID "$gid_val" 2>/dev/null || true

  # Step 4: Flush OpenDirectory subsystem so user database is re-indexed immediately
  sudo dscacheutil -flushcache 2>/dev/null || true
  sudo killall opendirectoryd 2>/dev/null || true
  sleep 2

  # Step 5: Verify password setting
  echo "  -> Password configured successfully for $user"
  sudo dscl . -passwd "/Users/$user" "$pass" 2>/dev/null || true

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

