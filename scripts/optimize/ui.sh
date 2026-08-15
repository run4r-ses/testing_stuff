#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${VNC_USERNAME:-runneradmin}"
TARGET_HOME="/Users/$TARGET_USER"

echo "* Disabling visual effects and setting Dark Mode + solid black wallpaper"

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

  # Solid background configuration
  ${PREFIX} defaults write com.apple.desktop Background '{default = {Change = Never; BackgroundColor = (0, 0, 0); };}' 2>/dev/null || true
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

# Generate solid black wallpaper
echo "- Creating solid black wallpaper"
python3 -c '
import base64
data = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
with open("/tmp/black.png", "wb") as f:
    f.write(data)
' 2>/dev/null || true
chmod 777 /tmp/black.png 2>/dev/null || true
cp /tmp/black.png /Users/Shared/black.png 2>/dev/null || true
chmod 777 /Users/Shared/black.png 2>/dev/null || true

# Apply wallpaper and dark mode via native Swift AppKit and launchctl context
echo "- Setting wallpaper and interface style"

CONSOLE_USER="$(stat -f '%Su' /dev/console 2>/dev/null || echo "runner")"
CONSOLE_UID="$(id -u "$CONSOLE_USER" 2>/dev/null || echo "501")"
TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null || echo "502")"

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

# Fallbacks
osascript -e 'tell application "Finder" to set desktop picture to POSIX file "/Users/Shared/black.png"' 2>/dev/null || true
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' 2>/dev/null || true

# Force wallpaper daemon and Dock reload
killall WallpaperAgent 2>/dev/null || true
killall Dock 2>/dev/null || true

