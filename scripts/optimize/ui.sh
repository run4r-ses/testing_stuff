#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${RUSTDESK_USERNAME:-runneradmin}"
TARGET_HOME="/Users/$TARGET_USER"

echo "* Disabling visual effects"

apply_visual_optimizations() {
  local PREFIX="${1:-}"

  # Enable Dark Mode
  echo "- Enabling Dark Mode"
  ${PREFIX} defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark"
  ${PREFIX} defaults write NSGlobalDomain AppleInterfaceStyleSwitchesAutomatically -bool false

  # Disable Transparency / Liquid Glass (massive VNC bandwidth reduction)
  echo "- Disabling Liquid Glass"
  ${PREFIX} defaults write com.apple.universalaccess reduceTransparency -bool true
  ${PREFIX} defaults write com.apple.Accessibility reduceTransparency -bool true
  ${PREFIX} defaults write -g AppleEnableMenuBarTransparency -bool false

  # Enable Reduce Motion & disable CoreAnimation delays
  echo "- Disabling motion"
  ${PREFIX} defaults write com.apple.universalaccess reduceMotion -bool true
  ${PREFIX} defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false
  ${PREFIX} defaults write NSGlobalDomain NSWindowResizeTime -float 0.001
  ${PREFIX} defaults write NSGlobalDomain QLPanelAnimationDuration -float 0

  # Disable Finder and QuickLook animations
  echo "- Disabling Finder and QuickLook animations"
  ${PREFIX} defaults write com.apple.finder DisableAllAnimations -bool true
  ${PREFIX} defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
  ${PREFIX} defaults write com.apple.finder CreateDesktop -bool true

  # Minimize Dock animations & delays
  echo "- Minimizing Dock animations & delays"
  ${PREFIX} defaults write com.apple.dock launchanim -bool false
  ${PREFIX} defaults write com.apple.dock expose-animation-duration -float 0.0
  ${PREFIX} defaults write com.apple.dock autohide-time-modifier -float 0.0
  ${PREFIX} defaults write com.apple.dock autohide-delay -float 0.0
  ${PREFIX} defaults write com.apple.dock springboard-show-duration -float 0.0
  ${PREFIX} defaults write com.apple.dock springboard-hide-duration -float 0.0

  # Disable Window Shadows & Stage Manager / Widget overhead
  echo "- Disabling shadows, stage manager, widget overhead"
  ${PREFIX} defaults write com.apple.screencapture disable-shadow -bool true
  ${PREFIX} defaults write com.apple.WindowManager StandardHideWidgets -bool true
  ${PREFIX} defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false
  ${PREFIX} defaults write com.apple.WindowManager HideDesktop -bool true

  # Font smoothing for remote displays
  echo "- Setting font smoothing"
  ${PREFIX} defaults write NSGlobalDomain AppleFontSmoothing -int 1
}

# Apply for current session user
apply_visual_optimizations ""

# Apply for target user if home exists
if [[ -d "$TARGET_HOME" ]]; then
  echo "- Applying for user $TARGET_USER"
  sudo -u "$TARGET_USER" bash -c "$(declare -f apply_visual_optimizations); apply_visual_optimizations" 2>/dev/null || true
fi

# Set global system domain defaults
echo "- Applying global system settings"
sudo defaults write /Library/Preferences/com.apple.universalaccess reduceTransparency -bool true
sudo defaults write /Library/Preferences/com.apple.universalaccess reduceMotion -bool true
sudo defaults write /Library/Preferences/.GlobalPreferences AppleInterfaceStyle -string "Dark" 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Generate a proper solid black wallpaper image (1920x1080)
# A 1x1 image gets tiled/ignored on many macOS versions.
# ────────────────────────────────────────────────────────────────────
echo "- Creating solid black wallpaper (1920x1080)"

python3 -c '
import struct, zlib

width, height = 1920, 1080

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
# Apply wallpaper via all available methods
# ────────────────────────────────────────────────────────────────────
echo "- Setting wallpaper via desktoppr"

CONSOLE_USER="$(stat -f '%Su' /dev/console 2>/dev/null || echo "runner")"
CONSOLE_UID="$(id -u "$CONSOLE_USER" 2>/dev/null || echo "501")"
TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null || echo "502")"

# Method 1: desktoppr (most reliable on modern macOS, works without GUI session)
if command -v desktoppr >/dev/null 2>&1; then
  desktoppr "/Users/Shared/black.png" 2>/dev/null || true
  sudo -u "$CONSOLE_USER" desktoppr "/Users/Shared/black.png" 2>/dev/null || true
  if [[ "$TARGET_USER" != "$CONSOLE_USER" ]]; then
    sudo -u "$TARGET_USER" desktoppr "/Users/Shared/black.png" 2>/dev/null || true
  fi
  # Also set in launchctl GUI context
  if [[ -n "$CONSOLE_UID" && "$CONSOLE_UID" != "0" ]]; then
    launchctl asuser "$CONSOLE_UID" sudo -u "$CONSOLE_USER" desktoppr "/Users/Shared/black.png" 2>/dev/null || true
  fi
  if [[ -n "$TARGET_UID" && "$TARGET_UID" != "0" && "$TARGET_UID" != "$CONSOLE_UID" ]]; then
    launchctl asuser "$TARGET_UID" sudo -u "$TARGET_USER" desktoppr "/Users/Shared/black.png" 2>/dev/null || true
  fi
else
  echo "! desktoppr not found, using fallback methods"
fi

# Method 2: Swift AppKit (needs GUI context but covers additional cases)
echo "- Setting wallpaper via AppKit"

cat << 'SWIFTEOF' > /tmp/set_wallpaper.swift
import AppKit

let path = "/Users/Shared/black.png"
let url = URL(fileURLWithPath: path)

for screen in NSScreen.screens {
    do {
        try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
            NSWorkspace.DesktopImageOptionKey.imageScaling: NSImageScaling.scaleAxesIndependently.rawValue,
            NSWorkspace.DesktopImageOptionKey.allowClipping: false
        ])
        print("* Wallpaper applied to screen: \(screen)")
    } catch {
        print("! Wallpaper error: \(error)")
    }
}
SWIFTEOF

# Run Swift AppKit wallpaper setter in console user GUI context
if [[ -n "$CONSOLE_UID" && "$CONSOLE_UID" != "0" ]]; then
  launchctl asuser "$CONSOLE_UID" sudo -u "$CONSOLE_USER" swift /tmp/set_wallpaper.swift 2>/dev/null || true
  launchctl asuser "$CONSOLE_UID" sudo -u "$CONSOLE_USER" osascript -e 'tell application "System Events" to tell every desktop to set picture to POSIX file "/Users/Shared/black.png"' 2>/dev/null || true
  launchctl asuser "$CONSOLE_UID" sudo -u "$CONSOLE_USER" osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' 2>/dev/null || true
fi

if [[ -n "$TARGET_UID" && "$TARGET_UID" != "0" && "$TARGET_UID" != "$CONSOLE_UID" ]]; then
  launchctl asuser "$TARGET_UID" sudo -u "$TARGET_USER" swift /tmp/set_wallpaper.swift 2>/dev/null || true
  launchctl asuser "$TARGET_UID" sudo -u "$TARGET_USER" osascript -e 'tell application "System Events" to tell every desktop to set picture to POSIX file "/Users/Shared/black.png"' 2>/dev/null || true
  launchctl asuser "$TARGET_UID" sudo -u "$TARGET_USER" osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' 2>/dev/null || true
fi

# Method 3: osascript fallbacks
echo "- Setting wallpaper via osascript fallbacks"
osascript -e 'tell application "Finder" to set desktop picture to POSIX file "/Users/Shared/black.png"' 2>/dev/null || true
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' 2>/dev/null || true

# Force wallpaper daemon, Dock, Finder, and SystemUIServer reload
echo "- Restarting UI daemons to apply changes"
killall WallpaperAgent 2>/dev/null || true
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true

# Give daemons time to respawn and apply
sleep 3

# Re-apply desktoppr after daemon restart (catches WallpaperAgent reset)
if command -v desktoppr >/dev/null 2>&1; then
  echo "- Re-applying wallpaper after daemon restart"
  desktoppr "/Users/Shared/black.png" 2>/dev/null || true
  sudo -u "$CONSOLE_USER" desktoppr "/Users/Shared/black.png" 2>/dev/null || true
  if [[ "$TARGET_USER" != "$CONSOLE_USER" ]]; then
    sudo -u "$TARGET_USER" desktoppr "/Users/Shared/black.png" 2>/dev/null || true
  fi
fi
