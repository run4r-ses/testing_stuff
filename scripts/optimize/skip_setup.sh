#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${RDP_USERNAME:-${VNC_USERNAME:-goldenrecipe}}"

echo "* Skipping onboarding"

PROD_VER="$(sw_vers -productVersion 2>/dev/null || echo "14.0")"
BUILD_VER="$(sw_vers -buildVersion 2>/dev/null || echo "23A344")"

# 1. Global / System-level Setup Assistant suppression
sudo defaults write /Library/Preferences/com.apple.SetupAssistant DidSeeCloudSetup -bool true
sudo defaults write /Library/Preferences/com.apple.SetupAssistant DidSeeSiriSetup -bool true
sudo defaults write /Library/Preferences/com.apple.SetupAssistant DidSeePrivacy -bool true
sudo defaults write /Library/Preferences/com.apple.SetupAssistant DidSeeTrueTone -bool true
sudo defaults write /Library/Preferences/com.apple.SetupAssistant DidSeeScreenTime -bool true
sudo defaults write /Library/Preferences/com.apple.SetupAssistant DidSeeAvatarSetup -bool true
sudo defaults write /Library/Preferences/com.apple.SetupAssistant DidSeeAppearanceSetup -bool true
sudo defaults write /Library/Preferences/com.apple.SetupAssistant DidSeeApplePaySetup -bool true
sudo defaults write /Library/Preferences/com.apple.SetupAssistant DidSeeTouchIDSetup -bool true
sudo defaults write /Library/Preferences/com.apple.SetupAssistant DidSeeWallpaperSetup -bool true
sudo defaults write /Library/Preferences/com.apple.SetupAssistant DidSeeLockdownMode -bool true
sudo defaults write /Library/Preferences/com.apple.SetupAssistant DidSeeiCloudLoginForFindMy -bool true
sudo defaults write /Library/Preferences/com.apple.SetupAssistant GestureMovieSeen none
sudo defaults write /Library/Preferences/com.apple.SetupAssistant LastSeenCloudProductVersion "$PROD_VER"
sudo defaults write /Library/Preferences/com.apple.SetupAssistant LastSeenBuddyBuildVersion "$BUILD_VER"
sudo defaults write /Library/Preferences/com.apple.SetupAssistant RunBuddyIfAdminAtEndOfUpgrade -bool false

# System-level flags
sudo touch /var/db/.AppleSetupDone 2>/dev/null || true
sudo mkdir -p /Library/Receipts 2>/dev/null || true
sudo touch /Library/Receipts/.SetupUserFinished 2>/dev/null || true

# Loginwindow suppression
sudo defaults write /Library/Preferences/com.apple.loginwindow TALlogoutSavesState -bool false
sudo defaults write /Library/Preferences/com.apple.loginwindow AutoSubmitModelInfo -bool false
sudo defaults write /Library/Preferences/com.apple.loginwindow showInputMenu -bool false

# Helper function to apply user-level setup bypass
apply_user_setup_bypass() {
  local USER_NAME="$1"
  local USER_HOME="/Users/$USER_NAME"

  if [[ ! -d "$USER_HOME" ]]; then
    return 0
  fi

  echo "- Applying for user $USER_NAME"
  sudo mkdir -p "$USER_HOME/Library/Preferences" "$USER_HOME/Library/Preferences/ByHost" "$USER_HOME/Library/Receipts"

  # Write via user domain if user exists
  sudo -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeCloudSetup -bool true 2>/dev/null || true
  sudo -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeSiriSetup -bool true 2>/dev/null || true
  sudo -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeePrivacy -bool true 2>/dev/null || true
  sudo -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeTrueTone -bool true 2>/dev/null || true
  sudo -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeScreenTime -bool true 2>/dev/null || true
  sudo -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeAvatarSetup -bool true 2>/dev/null || true
  sudo -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeAppearanceSetup -bool true 2>/dev/null || true
  sudo -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeApplePaySetup -bool true 2>/dev/null || true
  sudo -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeTouchIDSetup -bool true 2>/dev/null || true
  sudo -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeWallpaperSetup -bool true 2>/dev/null || true
  sudo -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeLockdownMode -bool true 2>/dev/null || true
  sudo -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeiCloudLoginForFindMy -bool true 2>/dev/null || true
  sudo -u "$USER_NAME" defaults write com.apple.SetupAssistant GestureMovieSeen none 2>/dev/null || true
  sudo -u "$USER_NAME" defaults write com.apple.SetupAssistant LastSeenCloudProductVersion "$PROD_VER" 2>/dev/null || true
  sudo -u "$USER_NAME" defaults write com.apple.SetupAssistant LastSeenBuddyBuildVersion "$BUILD_VER" 2>/dev/null || true
  sudo -u "$USER_NAME" defaults write com.apple.SetupAssistant RunBuddyIfAdminAtEndOfUpgrade -bool false 2>/dev/null || true

  # Also write file directly into Library/Preferences
  sudo defaults write "$USER_HOME/Library/Preferences/com.apple.SetupAssistant.plist" DidSeeCloudSetup -bool true
  sudo defaults write "$USER_HOME/Library/Preferences/com.apple.SetupAssistant.plist" DidSeeSiriSetup -bool true
  sudo defaults write "$USER_HOME/Library/Preferences/com.apple.SetupAssistant.plist" DidSeePrivacy -bool true
  sudo defaults write "$USER_HOME/Library/Preferences/com.apple.SetupAssistant.plist" DidSeeTrueTone -bool true
  sudo defaults write "$USER_HOME/Library/Preferences/com.apple.SetupAssistant.plist" DidSeeScreenTime -bool true
  sudo defaults write "$USER_HOME/Library/Preferences/com.apple.SetupAssistant.plist" DidSeeAvatarSetup -bool true
  sudo defaults write "$USER_HOME/Library/Preferences/com.apple.SetupAssistant.plist" DidSeeAppearanceSetup -bool true
  sudo defaults write "$USER_HOME/Library/Preferences/com.apple.SetupAssistant.plist" DidSeeApplePaySetup -bool true
  sudo defaults write "$USER_HOME/Library/Preferences/com.apple.SetupAssistant.plist" DidSeeTouchIDSetup -bool true
  sudo defaults write "$USER_HOME/Library/Preferences/com.apple.SetupAssistant.plist" DidSeeWallpaperSetup -bool true
  sudo defaults write "$USER_HOME/Library/Preferences/com.apple.SetupAssistant.plist" DidSeeLockdownMode -bool true
  sudo defaults write "$USER_HOME/Library/Preferences/com.apple.SetupAssistant.plist" DidSeeiCloudLoginForFindMy -bool true
  sudo defaults write "$USER_HOME/Library/Preferences/com.apple.SetupAssistant.plist" GestureMovieSeen none
  sudo defaults write "$USER_HOME/Library/Preferences/com.apple.SetupAssistant.plist" LastSeenCloudProductVersion "$PROD_VER"
  sudo defaults write "$USER_HOME/Library/Preferences/com.apple.SetupAssistant.plist" LastSeenBuddyBuildVersion "$BUILD_VER"
  sudo defaults write "$USER_HOME/Library/Preferences/com.apple.SetupAssistant.plist" RunBuddyIfAdminAtEndOfUpgrade -bool false

  sudo touch "$USER_HOME/Library/Receipts/.SetupUserFinished" 2>/dev/null || true
  sudo chown -R "$USER_NAME":staff "$USER_HOME/Library" 2>/dev/null || true
}

# Apply for target GUI user
apply_user_setup_bypass "$TARGET_USER"
