#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RDP_USERNAME:-${RUSTDESK_USERNAME:-goldenrecipe}}"

echo "* Bypassing TCC"

TCC_SYSTEM="/Library/Application Support/com.apple.TCC/TCC.db"
TCC_USER="/Users/$USERNAME/Library/Application Support/com.apple.TCC/TCC.db"

patch_tcc() {
  local DB="$1"

  if [[ ! -f "$DB" ]]; then
    echo "! TCC database does not exist at $DB"
    return 0
  fi

  echo
  echo "- Inspecting TCC database: $DB"

  local HAS_AUTH_VALUE
  HAS_AUTH_VALUE="$(
    sudo sqlite3 "$DB" \
      "SELECT COUNT(*)
       FROM pragma_table_info('access')
       WHERE name='auth_value';" 2>/dev/null || echo "0"
  )"

  if [[ "$HAS_AUTH_VALUE" != "1" ]]; then
    echo "! This TCC database does not expose auth_value, skipping patch"
    return 0
  fi

  local NOW
  NOW="$(date +%s)"

  echo "- Applying Screen Recording, Accessibility, and Input permissions"

  local SERVICES=(
    "kTCCServiceScreenCapture"
    "kTCCServiceAccessibility"
    "kTCCServicePostEvent"
    "kTCCServiceListenEvent"
    "kTCCServiceAppleEvents"
    "kTCCServiceSystemPolicyAllFiles"
    "kTCCServiceSystemPolicySysAdminFiles"
    "kTCCServiceSystemPolicyDesktopFolder"
    "kTCCServiceSystemPolicyDocumentsFolder"
    "kTCCServiceSystemPolicyDownloadsFolder"
  )

  local CLIENTS_BUNDLE=(
    "com.apple.bash"
    "com.apple.sh"
    "com.apple.zsh"
    "com.apple.osascript"
    "com.apple.Terminal"
    "com.apple.systemevents"
    "com.apple.finder"
    "com.apple.dock"
    "com.apple.screensharing.agent"
    "com.apple.screensharingd"
    "com.apple.RemoteDesktopAgent"
    "com.carriez.rustdesk"
    "com.carriez.RustDesk"
  )

  local CLIENTS_PATH=(
    "/bin/bash"
    "/bin/sh"
    "/bin/zsh"
    "/usr/bin/osascript"
    "/usr/bin/python3"
    "/usr/bin/tclsh"
    "/usr/local/bin/desktoppr"
    "/opt/homebrew/bin/desktoppr"
    "/usr/local/bin/bore"
    "/opt/homebrew/bin/bore"
    "/tmp/bore"
    "/Applications/RustDesk.app/Contents/MacOS/RustDesk"
    "/Applications/RustDesk.app/Contents/MacOS/rustdesk"
    "/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/MacOS/ARDAgent"
    "/System/Library/CoreServices/RemoteManagement/screensharingd.bundle/Contents/MacOS/screensharingd"
  )

  local INDIRECT_OBJECTS=(
    "UNUSED"
    "com.apple.systemevents"
    "com.apple.finder"
    "com.apple.dock"
  )

  for SVC in "${SERVICES[@]}"; do
    for CLIENT in "${CLIENTS_BUNDLE[@]}"; do
      for IND in "${INDIRECT_OBJECTS[@]}"; do
        if [[ "$SVC" != "kTCCServiceAppleEvents" && "$IND" != "UNUSED" ]]; then
          continue
        fi
        sudo sqlite3 "$DB" "
          INSERT OR REPLACE INTO access
          (
            service,
            client,
            client_type,
            auth_value,
            auth_reason,
            auth_version,
            policy_id,
            indirect_object_identifier_type,
            indirect_object_identifier,
            flags,
            last_modified
          )
          VALUES
          (
            '$SVC',
            '$CLIENT',
            0,
            2,
            2,
            1,
            NULL,
            0,
            '$IND',
            0,
            $NOW
          );
        " 2>/dev/null || true
      done
    done

    for CLIENT in "${CLIENTS_PATH[@]}"; do
      for IND in "${INDIRECT_OBJECTS[@]}"; do
        if [[ "$SVC" != "kTCCServiceAppleEvents" && "$IND" != "UNUSED" ]]; then
          continue
        fi
        sudo sqlite3 "$DB" "
          INSERT OR REPLACE INTO access
          (
            service,
            client,
            client_type,
            auth_value,
            auth_reason,
            auth_version,
            policy_id,
            indirect_object_identifier_type,
            indirect_object_identifier,
            flags,
            last_modified
          )
          VALUES
          (
            '$SVC',
            '$CLIENT',
            1,
            2,
            2,
            1,
            NULL,
            0,
            '$IND',
            0,
            $NOW
          );
        " 2>/dev/null || true
      done
    done
  done

  echo "* TCC modification completed for $DB"
}

# Patch system TCC database
patch_tcc "$TCC_SYSTEM"

# Patch target user TCC database
if [[ -d "/Users/$USERNAME/Library/Application Support/com.apple.TCC" ]]; then
  sudo chown -R \
    "$USERNAME":staff \
    "/Users/$USERNAME/Library/Application Support/com.apple.TCC" \
    2>/dev/null || true
fi
patch_tcc "$TCC_USER"

# Patch runner user TCC database if distinct
if [[ "$USERNAME" != "runner" && -d "/Users/runner/Library/Application Support/com.apple.TCC" ]]; then
  patch_tcc "/Users/runner/Library/Application Support/com.apple.TCC/TCC.db"
fi

echo
echo "* Restarting tccd daemon"
sudo killall -9 tccd 2>/dev/null || true
sleep 3

echo
echo "- Suppressing Screen Capture alerts"
for U in "$USERNAME" "runner" "root"; do
  if [[ "$U" == "root" ]]; then
    PLIST_DIR="/var/root/Library/Group Containers/group.com.apple.replayd"
  else
    PLIST_DIR="/Users/$U/Library/Group Containers/group.com.apple.replayd"
  fi
  sudo mkdir -p "$PLIST_DIR"
  PLIST="$PLIST_DIR/ScreenCaptureApprovals.plist"

  for APP_KEY in \
    "/Applications/RustDesk.app/Contents/MacOS/RustDesk" \
    "/Applications/RustDesk.app/Contents/MacOS/rustdesk" \
    "/Applications/RustDesk.app" \
    "com.carriez.rustdesk" \
    "com.carriez.RustDesk"; do
    sudo defaults write "$PLIST" "$APP_KEY" -date "3024-01-01 00:00:00 +0000" 2>/dev/null || true
  done

  if [[ "$U" != "root" ]]; then
    sudo chown -R "$U:staff" "$PLIST_DIR" 2>/dev/null || true
  fi
done

sudo killall -9 replayd 2>/dev/null || true
