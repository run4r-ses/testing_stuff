#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${RDP_USERNAME:-${RUSTDESK_USERNAME:-goldenrecipe}}"

echo "* Skipping onboarding"

PROD_VER="$(sw_vers -productVersion 2>/dev/null || echo "14.0")"
BUILD_VER="$(sw_vers -buildVersion 2>/dev/null || echo "23A344")"
HOST_UUID="$(ioreg -d2 -c IOPlatformExpertDevice | awk -F\" '/IOPlatformUUID/{print $(NF-1)}' 2>/dev/null || true)"

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

  echo "- Applying setup bypass for user $USER_NAME"
  sudo mkdir -p "$USER_HOME/Library/Preferences" "$USER_HOME/Library/Preferences/ByHost" "$USER_HOME/Library/Receipts"

  # 1. Direct on-disk plist writes
  local USER_PLIST="$USER_HOME/Library/Preferences/com.apple.SetupAssistant.plist"
  sudo defaults write "$USER_PLIST" DidSeeCloudSetup -bool true
  sudo defaults write "$USER_PLIST" DidSeeSiriSetup -bool true
  sudo defaults write "$USER_PLIST" DidSeePrivacy -bool true
  sudo defaults write "$USER_PLIST" DidSeeTrueTone -bool true
  sudo defaults write "$USER_PLIST" DidSeeScreenTime -bool true
  sudo defaults write "$USER_PLIST" DidSeeAvatarSetup -bool true
  sudo defaults write "$USER_PLIST" DidSeeAppearanceSetup -bool true
  sudo defaults write "$USER_PLIST" DidSeeApplePaySetup -bool true
  sudo defaults write "$USER_PLIST" DidSeeTouchIDSetup -bool true
  sudo defaults write "$USER_PLIST" DidSeeWallpaperSetup -bool true
  sudo defaults write "$USER_PLIST" DidSeeLockdownMode -bool true
  sudo defaults write "$USER_PLIST" DidSeeiCloudLoginForFindMy -bool true
  sudo defaults write "$USER_PLIST" GestureMovieSeen none
  sudo defaults write "$USER_PLIST" LastSeenCloudProductVersion "$PROD_VER"
  sudo defaults write "$USER_PLIST" LastSeenBuddyBuildVersion "$BUILD_VER"
  sudo defaults write "$USER_PLIST" RunBuddyIfAdminAtEndOfUpgrade -bool false

  # 2. ByHost plist write if host UUID is known
  if [[ -n "$HOST_UUID" ]]; then
    local BYHOST_PLIST="$USER_HOME/Library/Preferences/ByHost/com.apple.SetupAssistant.$HOST_UUID.plist"
    sudo defaults write "$BYHOST_PLIST" DidSeeCloudSetup -bool true 2>/dev/null || true
    sudo defaults write "$BYHOST_PLIST" DidSeeSiriSetup -bool true 2>/dev/null || true
    sudo defaults write "$BYHOST_PLIST" DidSeePrivacy -bool true 2>/dev/null || true
    sudo defaults write "$BYHOST_PLIST" DidSeeAppearanceSetup -bool true 2>/dev/null || true
  fi

  # 3. User domain write with correct HOME environment
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeCloudSetup -bool true 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeSiriSetup -bool true 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeePrivacy -bool true 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeTrueTone -bool true 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeScreenTime -bool true 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeAvatarSetup -bool true 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeAppearanceSetup -bool true 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeApplePaySetup -bool true 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeTouchIDSetup -bool true 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeWallpaperSetup -bool true 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeLockdownMode -bool true 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.SetupAssistant DidSeeiCloudLoginForFindMy -bool true 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.SetupAssistant GestureMovieSeen none 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.SetupAssistant LastSeenCloudProductVersion "$PROD_VER" 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.SetupAssistant LastSeenBuddyBuildVersion "$BUILD_VER" 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.SetupAssistant RunBuddyIfAdminAtEndOfUpgrade -bool false 2>/dev/null || true

  sudo touch "$USER_HOME/Library/Receipts/.SetupUserFinished" 2>/dev/null || true
  sudo chown -R "$USER_NAME":staff "$USER_HOME/Library" 2>/dev/null || true
  sudo chmod -R 700 "$USER_HOME/Library/Preferences" 2>/dev/null || true
}

# Apply for User Template so new/reset profiles inherit it
TEMPLATE_DIR="/Library/User Template/Non_localized"
if [[ -d "$TEMPLATE_DIR" ]]; then
  sudo mkdir -p "$TEMPLATE_DIR/Library/Preferences" "$TEMPLATE_DIR/Library/Receipts"
  TEMPLATE_PLIST="$TEMPLATE_DIR/Library/Preferences/com.apple.SetupAssistant.plist"
  sudo defaults write "$TEMPLATE_PLIST" DidSeeCloudSetup -bool true 2>/dev/null || true
  sudo defaults write "$TEMPLATE_PLIST" DidSeeSiriSetup -bool true 2>/dev/null || true
  sudo defaults write "$TEMPLATE_PLIST" DidSeePrivacy -bool true 2>/dev/null || true
  sudo defaults write "$TEMPLATE_PLIST" DidSeeTrueTone -bool true 2>/dev/null || true
  sudo defaults write "$TEMPLATE_PLIST" DidSeeScreenTime -bool true 2>/dev/null || true
  sudo defaults write "$TEMPLATE_PLIST" DidSeeAppearanceSetup -bool true 2>/dev/null || true
  sudo defaults write "$TEMPLATE_PLIST" RunBuddyIfAdminAtEndOfUpgrade -bool false 2>/dev/null || true
  sudo touch "$TEMPLATE_DIR/Library/Receipts/.SetupUserFinished" 2>/dev/null || true
fi

# Apply for target GUI user
apply_user_setup_bypass "$TARGET_USER"

# Also apply for runner if distinct
if [[ "$TARGET_USER" != "runner" && -d "/Users/runner" ]]; then
  apply_user_setup_bypass "runner"
fi
