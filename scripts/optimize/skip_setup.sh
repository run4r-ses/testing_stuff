#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${RDP_USERNAME:-${RUSTDESK_USERNAME:-goldenrecipe}}"
TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null || echo "")"
CONSOLE_USER="$(stat -f '%Su' /dev/console 2>/dev/null || echo "runner")"
CONSOLE_UID="$(id -u "$CONSOLE_USER" 2>/dev/null || echo "501")"

echo "* Skipping onboarding"

PROD_VER="$(sw_vers -productVersion 2>/dev/null || echo "14.0")"
BUILD_VER="$(sw_vers -buildVersion 2>/dev/null || echo "23A344")"
HOST_UUID="$(ioreg -d2 -c IOPlatformExpertDevice | awk -F\" '/IOPlatformUUID/{print $(NF-1)}' 2>/dev/null || true)"

# System-level flags & receipts
sudo touch /var/db/.AppleSetupDone 2>/dev/null || true
sudo touch /var/db/.AppleSetupUser 2>/dev/null || true
sudo mkdir -p /Library/Receipts 2>/dev/null || true
sudo touch /Library/Receipts/.SetupUserFinished 2>/dev/null || true

# Loginwindow suppression
sudo defaults write /Library/Preferences/com.apple.loginwindow TALlogoutSavesState -bool false 2>/dev/null || true
sudo defaults write /Library/Preferences/com.apple.loginwindow AutoSubmitModelInfo -bool false 2>/dev/null || true
sudo defaults write /Library/Preferences/com.apple.loginwindow showInputMenu -bool false 2>/dev/null || true

# Python helper to write comprehensive SetupAssistant preferences directly to plist files
sudo python3 -c '
import plistlib, sys, os

prod_ver = sys.argv[1]
build_ver = sys.argv[2]
host_uuid = sys.argv[3]
target_user = sys.argv[4]

skip_items = [
    "Privacy",
    "Siri",
    "iCloudStorage",
    "iCloudDiagnostics",
    "AppleID",
    "Intelligence",
    "Accessibility",
    "AppStore",
    "Biometric",
    "TouchID",
    "FileVault",
    "Location",
    "Passcode",
    "ScreenTime",
    "SoftwareUpdate",
    "TermsOfAddress",
    "TOS",
    "Wallpaper",
    "Welcome",
    "DisplayTone",
    "Appearance",
    "LockdownMode",
    "UnlockWithWatch"
]

setup_data = {
    # Cloud & AppleID
    "DidSeeCloudSetup": True,
    "DidSeeiCloudLoginForFindMy": True,
    "DidSeeSyncSetup": True,
    "DidSeeAccountSetup": True,
    "DidSeeAppleID": True,
    "SkipCloudSetup": True,
    "SkipAppleID": True,
    # Siri
    "DidSeeSiriSetup": True,
    "SkipSiriSetup": True,
    # Privacy & Terms
    "DidSeePrivacy": True,
    "DidSeeTerms": True,
    "DidSeeTOS": True,
    "SkipPrivacySetup": True,
    # TrueTone & Appearance & Wallpaper
    "DidSeeTrueTone": True,
    "DidSeeDisplayTone": True,
    "DidSeeAppearanceSetup": True,
    "DidSeeWallpaperSetup": True,
    "SkipAppearanceSetup": True,
    "SkipWallpaperSetup": True,
    # ScreenTime
    "DidSeeScreenTime": True,
    "SkipScreenTime": True,
    # TouchID & ApplePay & Biometrics
    "DidSeeTouchIDSetup": True,
    "DidSeeApplePaySetup": True,
    "DidSeeAvatarSetup": True,
    "DidSeePasscodeSetup": True,
    "SkipTouchIDSetup": True,
    "SkipBiometric": True,
    # Accessibility
    "DidSeeAccessibility": True,
    "SkipAccessibility": True,
    # Security & Lockdown
    "DidSeeLockdownMode": True,
    "DidSeeFileVault": True,
    "DidSeeLocation": True,
    "SkipFileVault": True,
    # Intelligence (macOS 15 / Sequoia)
    "DidSeeIntelligence": True,
    "DidSeeAppleIntelligence": True,
    "SkipAppleIntelligence": True,
    # Welcome & Movies
    "GestureMovieSeen": "none",
    "DidSeeWelcome": True,
    "DidSeeTermsOfAddress": True,
    # Version checks
    "LastSeenCloudProductVersion": prod_ver,
    "LastSeenBuddyBuildVersion": build_ver,
    "LastSeenSyncProductVersion": prod_ver,
    "LastPreLoginSync": prod_ver,
    "RunBuddyIfAdminAtEndOfUpgrade": False,
    "RunBuddyIfAdminAtEndOfUpgrade2": False,
    "PreviousSystemVersion": prod_ver,
    "PreviousBuildVersion": build_ver,
    # Managed / Modern array
    "SkipSetupItems": skip_items
}

managed_data = {
    "SkipCloudSetup": True,
    "SkipSiriSetup": True,
    "SkipPrivacySetup": True,
    "SkipTouchIDSetup": True,
    "SkipScreenTime": True,
    "SkipAppearanceSetup": True,
    "SkipWallpaperSetup": True,
    "SkipAppleIntelligence": True,
    "SkipAccessibility": True,
    "SkipFileVault": True,
    "SkipBiometric": True,
    "SkipAppleID": True,
    "SkipSetupItems": skip_items
}

def write_plist(filepath, data):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, "wb") as f:
        plistlib.dump(data, f, fmt=plistlib.FMT_BINARY)

# 1. System / Global
write_plist("/Library/Preferences/com.apple.SetupAssistant.plist", setup_data)
if host_uuid:
    write_plist(f"/Library/Preferences/ByHost/com.apple.SetupAssistant.{host_uuid}.plist", setup_data)

# 2. Managed Preferences (System + User)
write_plist("/Library/Managed Preferences/com.apple.SetupAssistant.managed.plist", managed_data)
write_plist("/Library/Managed Preferences/com.apple.SetupAssistant.plist", setup_data)
if target_user:
    write_plist(f"/Library/Managed Preferences/{target_user}/com.apple.SetupAssistant.managed.plist", managed_data)
    write_plist(f"/Library/Managed Preferences/{target_user}/com.apple.SetupAssistant.plist", setup_data)

# 3. User Template
template_dir = "/Library/User Template/Non_localized"
if os.path.isdir(template_dir):
    write_plist(f"{template_dir}/Library/Preferences/com.apple.SetupAssistant.plist", setup_data)
    if host_uuid:
        write_plist(f"{template_dir}/Library/Preferences/ByHost/com.apple.SetupAssistant.{host_uuid}.plist", setup_data)
    try:
        os.makedirs(f"{template_dir}/Library/Receipts", exist_ok=True)
        open(f"{template_dir}/Library/Receipts/.SetupUserFinished", "a").close()
    except Exception:
        pass

# 4. User Directories
for u in [target_user, "runner", "root"]:
    if not u:
        continue
    user_home = "/var/root" if u == "root" else f"/Users/{u}"
    if not os.path.isdir(user_home):
        continue
    write_plist(f"{user_home}/Library/Preferences/com.apple.SetupAssistant.plist", setup_data)
    if host_uuid:
        write_plist(f"{user_home}/Library/Preferences/ByHost/com.apple.SetupAssistant.{host_uuid}.plist", setup_data)
    try:
        os.makedirs(f"{user_home}/Library/Receipts", exist_ok=True)
        open(f"{user_home}/Library/Receipts/.SetupUserFinished", "a").close()
    except Exception:
        pass
' "$PROD_VER" "$BUILD_VER" "$HOST_UUID" "$TARGET_USER" 2>/dev/null || true

# Fix ownership and permissions for users
for U in "$TARGET_USER" "runner"; do
  if [[ -d "/Users/$U" ]]; then
    sudo chown -R "$U:staff" "/Users/$U/Library" 2>/dev/null || true
    sudo chmod -R 755 "/Users/$U/Library" 2>/dev/null || true
    sudo chmod 644 "/Users/$U/Library/Preferences/com.apple.SetupAssistant.plist" 2>/dev/null || true
    if [[ -n "$HOST_UUID" ]]; then
      sudo chmod 644 "/Users/$U/Library/Preferences/ByHost/com.apple.SetupAssistant.$HOST_UUID.plist" 2>/dev/null || true
    fi
  fi
done

# Disable Setup Assistant LaunchAgents (excluding mbuseragent which is required for login session bootstrap)
SETUP_AGENTS=(
  "com.apple.SetupAssistant.launcher"
  "com.apple.CloudConfigurationUI"
)

TARGET_UIDS=()
if [[ -n "$CONSOLE_UID" && "$CONSOLE_UID" != "0" ]]; then
  TARGET_UIDS+=("$CONSOLE_UID:$CONSOLE_USER")
fi
if [[ -n "$TARGET_UID" && "$TARGET_UID" != "0" && "$TARGET_UID" != "$CONSOLE_UID" ]]; then
  TARGET_UIDS+=("$TARGET_UID:$TARGET_USER")
fi

for AGENT in "${SETUP_AGENTS[@]}"; do
  sudo launchctl disable "system/$AGENT" 2>/dev/null || true
  sudo launchctl bootout "system/$AGENT" 2>/dev/null || true
  for ENTRY in "${TARGET_UIDS[@]}"; do
    UID_VAL="${ENTRY%%:*}"
    USER_VAL="${ENTRY##*:}"
    launchctl disable "gui/$UID_VAL/$AGENT" 2>/dev/null || true
    launchctl bootout "gui/$UID_VAL/$AGENT" 2>/dev/null || true
  done
done

# Ensure mbuseragent is enabled so loginwindow can cleanly initialize GUI sessions
sudo launchctl enable "system/com.apple.mbuseragent" 2>/dev/null || true
for ENTRY in "${TARGET_UIDS[@]}"; do
  UID_VAL="${ENTRY%%:*}"
  launchctl enable "gui/$UID_VAL/com.apple.mbuseragent" 2>/dev/null || true
done

# Kill any active Setup Assistant or CloudConfigurationUI instances (do NOT kill mbuseragent)
sudo killall "Setup Assistant" 2>/dev/null || true
sudo killall CloudConfigurationUI 2>/dev/null || true

