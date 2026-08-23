#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="goldenrecipe"
TARGET_HOME="/Users/$TARGET_USER"

echo "* Disabling visual effects"

echo "- Applying visual preferences for user $TARGET_USER"
sudo mkdir -p "$TARGET_HOME/Library/Preferences" "$TARGET_HOME/Library/LaunchAgents"

GLOBAL_PLIST="$TARGET_HOME/Library/Preferences/.GlobalPreferences.plist"
ACCESS_PLIST="$TARGET_HOME/Library/Preferences/com.apple.universalaccess.plist"
ACCESSIBILITY_PLIST="$TARGET_HOME/Library/Preferences/com.apple.Accessibility.plist"
FINDER_PLIST="$TARGET_HOME/Library/Preferences/com.apple.finder.plist"
DOCK_PLIST="$TARGET_HOME/Library/Preferences/com.apple.dock.plist"
SCREEN_PLIST="$TARGET_HOME/Library/Preferences/com.apple.screencapture.plist"
WM_PLIST="$TARGET_HOME/Library/Preferences/com.apple.WindowManager.plist"

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

sudo chown -R "$TARGET_USER":staff "$TARGET_HOME/Library" || true
sudo chmod -R 700 "$TARGET_HOME/Library/Preferences" || true

# Set global system domain defaults
echo "- Applying global system visual settings"
sudo defaults write /Library/Preferences/com.apple.universalaccess reduceTransparency -bool true || true
sudo defaults write /Library/Preferences/com.apple.universalaccess reduceMotion -bool true || true
sudo defaults write /Library/Preferences/.GlobalPreferences AppleInterfaceStyle -string "Dark" || true
sudo defaults write /Library/Preferences/.GlobalPreferences AppleInterfaceStyleSwitchesAutomatically -bool false || true

# Restart preference daemons so global defaults take effect immediately
killall cfprefsd 2>/dev/null || true
sudo killall cfprefsd 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Generate a solid black wallpaper image (1280x720)
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
    row = b"\x00" + b"\x00\x00\x00" * w
    raw = row * h
    idat = chunk(b"IDAT", zlib.compress(raw, 9))
    iend = chunk(b"IEND", b"")
    return header + ihdr + idat + iend

png = create_png(width, height)
with open("/tmp/black.png", "wb") as f:
    f.write(png)
'
chmod 644 /tmp/black.png
sudo cp /tmp/black.png /Users/Shared/black.png
sudo chmod 644 /Users/Shared/black.png

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# ────────────────────────────────────────────────────────────────────
# Create on-login hook script and LaunchAgent for GUI sessions
# ────────────────────────────────────────────────────────────────────
echo "- Installing GUI session on-login optimization hook"

cat << 'EOF' | sudo tee /Users/Shared/apply_rdp_ui.sh >/dev/null
#!/usr/bin/env bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

WALLPAPER="/Users/Shared/black.png"

# Set Dark Mode
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' 2>/dev/null || true
defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark" 2>/dev/null || true

# Set wallpaper immediately
if command -v desktoppr >/dev/null 2>&1 && [[ -f "$WALLPAPER" ]]; then
  desktoppr "$WALLPAPER" 2>/dev/null || true
fi
osascript -e "tell application \"Finder\" to set desktop picture to POSIX file \"$WALLPAPER\"" 2>/dev/null || true
osascript -e "tell application \"System Events\" to set picture of every desktop to \"$WALLPAPER\"" 2>/dev/null || true
EOF
sudo chmod 755 /Users/Shared/apply_rdp_ui.sh

# User-level LaunchAgent for goldenrecipe
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
sudo chown -R "$TARGET_USER":staff "$TARGET_HOME/Library/LaunchAgents" || true

# Apply wallpaper and appearance immediately
echo "- Setting appearance on active session"
/Users/Shared/apply_rdp_ui.sh || true

echo "- Restarting UI daemons to apply changes"
killall WallpaperAgent 2>/dev/null || true
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true
