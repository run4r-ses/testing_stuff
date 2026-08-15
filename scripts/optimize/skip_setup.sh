#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${VNC_USERNAME:-runneradmin}"
TARGET_HOME="/Users/$TARGET_USER"

echo "* Skipping onboarding"

# Define SetupAssistant keys to suppress
suppress_setup() {
  local DOMAIN="$1"
  local PROD_VER
  local BUILD_VER
  PROD_VER="$(sw_vers -productVersion 2>/dev/null || echo "14.0")"
  BUILD_VER="$(sw_vers -buildVersion 2>/dev/null || echo "23A344")"

  defaults write "$DOMAIN" DidSeeCloudSetup -bool true
  defaults write "$DOMAIN" DidSeeSiriSetup -bool true
  defaults write "$DOMAIN" DidSeePrivacy -bool true
  defaults write "$DOMAIN" DidSeeTrueTone -bool true
  defaults write "$DOMAIN" DidSeeScreenTime -bool true
  defaults write "$DOMAIN" DidSeeAvatarSetup -bool true
  defaults write "$DOMAIN" DidSeeAppearanceSetup -bool true
  defaults write "$DOMAIN" DidSeeApplePaySetup -bool true
  defaults write "$DOMAIN" DidSeeTouchIDSetup -bool true
  defaults write "$DOMAIN" DidSeeWallpaperSetup -bool true
  defaults write "$DOMAIN" DidSeeLockdownMode -bool true
  defaults write "$DOMAIN" GestureMovieSeen none
  defaults write "$DOMAIN" LastSeenCloudProductVersion "$PROD_VER"
  defaults write "$DOMAIN" LastSeenBuddyBuildVersion "$BUILD_VER"
  defaults write "$DOMAIN" RunBuddyIfAdminAtEndOfUpgrade -bool false
}

# 1. Global / System-level Setup Assistant suppression
sudo defaults write /Library/Preferences/com.apple.SetupAssistant DidSeeCloudSetup -bool true
sudo defaults write /Library/Preferences/com.apple.SetupAssistant DidSeeSiriSetup -bool true
sudo defaults write /Library/Preferences/com.apple.SetupAssistant DidSeePrivacy -bool true
sudo defaults write /Library/Preferences/com.apple.SetupAssistant RunBuddyIfAdminAtEndOfUpgrade -bool false
sudo touch /var/db/.AppleSetupDone 2>/dev/null || true

# 2. Current Runner user defaults
suppress_setup com.apple.SetupAssistant

# 3. Suppress iCloud login & diagnostics popups globally
sudo defaults write /Library/Preferences/com.apple.loginwindow TALlogoutSavesState -bool false
sudo defaults write /Library/Preferences/com.apple.loginwindow AutoSubmitModelInfo -bool false

# 4. Target User Setup Assistant suppression (if user directory exists or prepare for creation)
echo "- Applying for user $TARGET_USER"
if [[ -d "$TARGET_HOME" ]]; then
  sudo mkdir -p "$TARGET_HOME/Library/Preferences" "$TARGET_HOME/Library/Receipts"
  suppress_setup "$TARGET_HOME/Library/Preferences/com.apple.SetupAssistant"
  sudo touch "$TARGET_HOME/Library/Receipts/.SetupUserFinished" 2>/dev/null || true
  sudo chown -R "$TARGET_USER":staff "$TARGET_HOME/Library" 2>/dev/null || true
fi
