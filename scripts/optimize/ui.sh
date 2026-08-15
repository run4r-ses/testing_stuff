#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${VNC_USERNAME:-runneradmin}"
TARGET_HOME="/Users/$TARGET_USER"

echo "* Disabling visual effects"

apply_visual_optimizations() {
  local PREFIX="${1:-}"

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

  # Optimize Font Smoothing for remote displays
  echo "- Applying font smoothing"
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
echo "- Applying global settings"
sudo defaults write /Library/Preferences/com.apple.universalaccess reduceTransparency -bool true
sudo defaults write /Library/Preferences/com.apple.universalaccess reduceMotion -bool true

# Restart Dock and Finder to apply changes immediately
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true

