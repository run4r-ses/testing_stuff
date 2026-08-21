#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${RDP_USERNAME:-${RUSTDESK_USERNAME:-goldenrecipe}}"
TARGET_HOME="/Users/$TARGET_USER"

echo "* Disabling visual effects"

# Helper function to write visual preferences to a target user directory
write_user_visual_preferences() {
  local USER_NAME="$1"
  local USER_HOME="/Users/$USER_NAME"

  if [[ ! -d "$USER_HOME" ]]; then
    return 0
  fi

  echo "- Applying visual preferences for user $USER_NAME"
  sudo mkdir -p "$USER_HOME/Library/Preferences" "$USER_HOME/Library/LaunchAgents"

  local GLOBAL_PLIST="$USER_HOME/Library/Preferences/.GlobalPreferences.plist"
  local ACCESS_PLIST="$USER_HOME/Library/Preferences/com.apple.universalaccess.plist"
  local ACCESSIBILITY_PLIST="$USER_HOME/Library/Preferences/com.apple.Accessibility.plist"
  local FINDER_PLIST="$USER_HOME/Library/Preferences/com.apple.finder.plist"
  local DOCK_PLIST="$USER_HOME/Library/Preferences/com.apple.dock.plist"
  local SCREEN_PLIST="$USER_HOME/Library/Preferences/com.apple.screencapture.plist"
  local WM_PLIST="$USER_HOME/Library/Preferences/com.apple.WindowManager.plist"

  # 1. Dark Mode & Interface
  sudo defaults write "$GLOBAL_PLIST" AppleInterfaceStyle -string "Dark"
  sudo defaults write "$GLOBAL_PLIST" AppleInterfaceStyleSwitchesAutomatically -bool false
  sudo defaults write "$GLOBAL_PLIST" AppleEnableMenuBarTransparency -bool false
  sudo defaults write "$GLOBAL_PLIST" AppleFontSmoothing -int 1

  # 2. Disable Transparency & Motion
  sudo defaults write "$ACCESS_PLIST" reduceTransparency -bool true
  sudo defaults write "$ACCESS_PLIST" reduceMotion -bool true
  sudo defaults write "$ACCESSIBILITY_PLIST" reduceTransparency -bool true
  sudo defaults write "$ACCESSIBILITY_PLIST" reduceMotion -bool true

  # 3. Window & Panel animations
  sudo defaults write "$GLOBAL_PLIST" NSAutomaticWindowAnimationsEnabled -bool false
  sudo defaults write "$GLOBAL_PLIST" NSWindowResizeTime -float 0.001
  sudo defaults write "$GLOBAL_PLIST" QLPanelAnimationDuration -float 0

  # 4. Finder optimizations
  sudo defaults write "$FINDER_PLIST" DisableAllAnimations -bool true
  sudo defaults write "$FINDER_PLIST" FXEnableExtensionChangeWarning -bool false
  sudo defaults write "$FINDER_PLIST" CreateDesktop -bool true

  # 5. Dock optimizations
  sudo defaults write "$DOCK_PLIST" launchanim -bool false
  sudo defaults write "$DOCK_PLIST" expose-animation-duration -float 0.0
  sudo defaults write "$DOCK_PLIST" autohide-time-modifier -float 0.0
  sudo defaults write "$DOCK_PLIST" autohide-delay -float 0.0
  sudo defaults write "$DOCK_PLIST" springboard-show-duration -float 0.0
  sudo defaults write "$DOCK_PLIST" springboard-hide-duration -float 0.0

  # 6. Shadows & Window Manager
  sudo defaults write "$SCREEN_PLIST" disable-shadow -bool true
  sudo defaults write "$WM_PLIST" StandardHideWidgets -bool true
  sudo defaults write "$WM_PLIST" EnableStandardClickToShowDesktop -bool false
  sudo defaults write "$WM_PLIST" HideDesktop -bool true

  # 7. Write via user domain with proper HOME environment
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark" 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write NSGlobalDomain AppleInterfaceStyleSwitchesAutomatically -bool false 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.universalaccess reduceTransparency -bool true 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.universalaccess reduceMotion -bool true 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.Accessibility reduceTransparency -bool true 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.finder DisableAllAnimations -bool true 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.dock launchanim -bool false 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.screencapture disable-shadow -bool true 2>/dev/null || true

  sudo chown -R "$USER_NAME":staff "$USER_HOME/Library" 2>/dev/null || true
  sudo chmod -R 700 "$USER_HOME/Library/Preferences" 2>/dev/null || true
}

# Apply for target user
write_user_visual_preferences "$TARGET_USER"

# Apply for runner if distinct
if [[ "$TARGET_USER" != "runner" && -d "/Users/runner" ]]; then
  write_user_visual_preferences "runner"
fi

# Apply to User Template for any newly initialized users
TEMPLATE_DIR="/Library/User Template/Non_localized"
if [[ -d "$TEMPLATE_DIR" ]]; then
  sudo mkdir -p "$TEMPLATE_DIR/Library/Preferences"
  sudo defaults write "$TEMPLATE_DIR/Library/Preferences/.GlobalPreferences.plist" AppleInterfaceStyle -string "Dark" 2>/dev/null || true
  sudo defaults write "$TEMPLATE_DIR/Library/Preferences/.GlobalPreferences.plist" AppleInterfaceStyleSwitchesAutomatically -bool false 2>/dev/null || true
  sudo defaults write "$TEMPLATE_DIR/Library/Preferences/com.apple.universalaccess.plist" reduceTransparency -bool true 2>/dev/null || true
  sudo defaults write "$TEMPLATE_DIR/Library/Preferences/com.apple.universalaccess.plist" reduceMotion -bool true 2>/dev/null || true
  sudo defaults write "$TEMPLATE_DIR/Library/Preferences/com.apple.finder.plist" DisableAllAnimations -bool true 2>/dev/null || true
  sudo defaults write "$TEMPLATE_DIR/Library/Preferences/com.apple.dock.plist" launchanim -bool false 2>/dev/null || true
fi

# Set global system domain defaults
echo "- Applying global system visual settings"
sudo defaults write /Library/Preferences/com.apple.universalaccess reduceTransparency -bool true 2>/dev/null || true
sudo defaults write /Library/Preferences/com.apple.universalaccess reduceMotion -bool true 2>/dev/null || true
sudo defaults write /Library/Preferences/.GlobalPreferences AppleInterfaceStyle -string "Dark" 2>/dev/null || true
sudo defaults write /Library/Preferences/.GlobalPreferences AppleInterfaceStyleSwitchesAutomatically -bool false 2>/dev/null || true

# Restart preference daemons so global defaults take effect immediately
killall cfprefsd 2>/dev/null || true
sudo killall cfprefsd 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Generate a proper solid black wallpaper image (1280x720)
# Matches target screen resolution to prevent scaling/tiling overhead.
# ────────────────────────────────────────────────────────────────────
echo "- Creating solid black wallpaper (1280x720)"

python3 -c '
import struct, zlib

width, height = 1280, 720

def create_png(w, h):
    def chunk(ctype, data):
        c = ctype + data
        crc = struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
        return struct.pack(">I", len(data)) + c + crc

    header = b"\x89PNG\r\n\x1a\n"
    ihdr = chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))

    # Build raw image data: each row is filter_byte(0) + RGB(0,0,0)*width
    row = b"\x00" + b"\x00\x00\x00" * w
    raw = row * h
    idat = chunk(b"IDAT", zlib.compress(raw, 9))
    iend = chunk(b"IEND", b"")

    return header + ihdr + idat + iend

png = create_png(width, height)
with open("/tmp/black.png", "wb") as f:
    f.write(png)
' 2>/dev/null || true

chmod 644 /tmp/black.png 2>/dev/null || true
sudo cp /tmp/black.png /Users/Shared/black.png 2>/dev/null || true
sudo chmod 644 /Users/Shared/black.png 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Create on-login hook script and LaunchAgent for GUI sessions
# This ensures that when target user logs into GUI via ARD/VNC,
# wallpaper and Dark Mode are immediately enforced in their Aqua session.
# ────────────────────────────────────────────────────────────────────
echo "- Installing GUI session on-login optimization hook"

cat << 'EOF' | sudo tee /Users/Shared/apply_rdp_ui.sh >/dev/null
#!/usr/bin/env bash
# Suppress Setup Assistant & CloudConfigurationUI
killall "Setup Assistant" 2>/dev/null || true
killall CloudConfigurationUI 2>/dev/null || true

# Set solid black wallpaper
if command -v desktoppr >/dev/null 2>&1; then
  desktoppr "/Users/Shared/black.png" 2>/dev/null || true
fi
osascript -e 'tell application "System Events" to set picture of every desktop to "/Users/Shared/black.png"' 2>/dev/null || true

# Set Dark Mode
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' 2>/dev/null || true
EOF
sudo chmod 755 /Users/Shared/apply_rdp_ui.sh

# User-level LaunchAgent for TARGET_USER
if [[ -d "$TARGET_HOME" ]]; then
  sudo mkdir -p "$TARGET_HOME/Library/LaunchAgents"
  cat << 'EOF' | sudo tee "$TARGET_HOME/Library/LaunchAgents/com.user.rdpoptimizations.plist" >/dev/null
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.user.rdpoptimizations</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/Shared/apply_rdp_ui.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
EOF
  sudo chown -R "$TARGET_USER":staff "$TARGET_HOME/Library/LaunchAgents" 2>/dev/null || true
fi

# System-wide LaunchAgent for all GUI logins
sudo mkdir -p /Library/LaunchAgents
cat << 'EOF' | sudo tee /Library/LaunchAgents/com.user.rdpoptimizations.plist >/dev/null
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.user.rdpoptimizations</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/Shared/apply_rdp_ui.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
EOF
sudo chmod 644 /Library/LaunchAgents/com.user.rdpoptimizations.plist 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Apply wallpaper and appearance immediately to active GUI session
# ────────────────────────────────────────────────────────────────────
echo "- Setting appearance on active session"

TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null || echo "")"
CONSOLE_USER="$(stat -f '%Su' /dev/console 2>/dev/null || echo "runner")"
CONSOLE_UID="$(id -u "$CONSOLE_USER" 2>/dev/null || echo "501")"

# Execute in active console user session if available
if [[ -n "$CONSOLE_UID" && "$CONSOLE_UID" != "0" ]]; then
  launchctl asuser "$CONSOLE_UID" sudo -u "$CONSOLE_USER" /Users/Shared/apply_rdp_ui.sh 2>/dev/null || true
fi

# Also execute in target user session if already active
if [[ -n "$TARGET_UID" && "$TARGET_UID" != "0" && "$TARGET_UID" != "$CONSOLE_UID" ]]; then
  launchctl asuser "$TARGET_UID" sudo -u "$TARGET_USER" /Users/Shared/apply_rdp_ui.sh 2>/dev/null || true
fi

# Fallback direct calls
if command -v desktoppr >/dev/null 2>&1; then
  desktoppr "/Users/Shared/black.png" 2>/dev/null || true
fi
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' 2>/dev/null || true

# Restart UI daemons to apply changes
echo "- Restarting UI daemons to apply changes"
killall WallpaperAgent 2>/dev/null || true
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true


