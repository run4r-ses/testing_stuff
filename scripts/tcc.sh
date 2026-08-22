#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RDP_USERNAME:-${RUSTDESK_USERNAME:-goldenrecipe}}"

echo "* Bypassing TCC"

TCC_SYSTEM="/Library/Application Support/com.apple.TCC/TCC.db"
TCC_USER="/Users/$USERNAME/Library/Application Support/com.apple.TCC/TCC.db"

patch_tcc() {
  local DB="$1"
  local USER_DIR
  USER_DIR="$(dirname "$DB")"

  # Ensure the directory exists
  sudo mkdir -p "$USER_DIR" 2>/dev/null || true

  # If database doesn't exist, create it with standard macOS TCC access table schema
  if ! sudo test -f "$DB"; then
    echo "- TCC database not found at $DB, creating database with schema..."
    sudo sqlite3 "$DB" "
      CREATE TABLE IF NOT EXISTS access (
        service TEXT NOT NULL,
        client TEXT NOT NULL,
        client_type INTEGER NOT NULL,
        auth_value INTEGER NOT NULL,
        auth_reason INTEGER NOT NULL,
        auth_version INTEGER NOT NULL,
        csreq BLOB,
        policy_id INTEGER,
        indirect_object_identifier_type INTEGER DEFAULT 0,
        indirect_object_identifier TEXT DEFAULT 'UNUSED',
        flags INTEGER DEFAULT 0,
        last_modified INTEGER NOT NULL,
        PRIMARY KEY (service, client, client_type, indirect_object_identifier)
      );
    " 2>/dev/null || true
    sudo chmod 600 "$DB" 2>/dev/null || true
  fi

  if ! sudo test -f "$DB"; then
    echo "! Could not initialize TCC database at $DB"
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
    "com.carriez.RustDesk_service"
    "com.carriez.RustDesk_server"
    "com.carriez.rustdesk_service"
    "com.carriez.rustdesk_server"
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
    "/Applications/RustDesk.app/Contents/MacOS/RustDesk_server"
    "/Applications/RustDesk.app/Contents/MacOS/RustDesk_service"
    "/Applications/RustDesk.app"
    "/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/MacOS/ARDAgent"
    "/System/Library/CoreServices/RemoteManagement/screensharingd.bundle/Contents/MacOS/screensharingd"
  )

  for SVC in "${SERVICES[@]}"; do
    for CLIENT in "${CLIENTS_BUNDLE[@]}"; do
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
          'UNUSED',
          0,
          $NOW
        );
      " 2>/dev/null || true
    done

    for CLIENT in "${CLIENTS_PATH[@]}"; do
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
          'UNUSED',
          0,
          $NOW
        );
      " 2>/dev/null || true
    done
  done

  # Fix permissions and ownership for user database
  if [[ "$DB" != "$TCC_SYSTEM" && -d "$USER_DIR" ]]; then
    local OWNER
    OWNER="$(echo "$DB" | sed -E 's|^/Users/([^/]+)/.*|\1|')"
    if id "$OWNER" >/dev/null 2>&1; then
      sudo chown -R "$OWNER:staff" "$USER_DIR" 2>/dev/null || true
      sudo chmod 700 "$USER_DIR" 2>/dev/null || true
      sudo chmod 600 "$DB" 2>/dev/null || true
    fi
  fi

  echo "* TCC modification completed for $DB"
}

# Patch system TCC database
patch_tcc "$TCC_SYSTEM"

# Patch all user TCC databases in /Users
for UDIR in /Users/*; do
  if [[ -d "$UDIR" ]]; then
    U="$(basename "$UDIR")"
    if [[ "$U" != "Shared" && "$U" != "Guest" ]]; then
      patch_tcc "$UDIR/Library/Application Support/com.apple.TCC/TCC.db"
    fi
  fi
done

# Ensure explicit target user path is also covered
patch_tcc "$TCC_USER"

echo
echo "* Restarting tccd daemon"
sudo killall -9 tccd 2>/dev/null || true
TARGET_UID="$(id -u "$USERNAME" 2>/dev/null || echo "")"
if [[ -n "$TARGET_UID" && "$TARGET_UID" != "0" ]]; then
  launchctl asuser "$TARGET_UID" sudo -u "$USERNAME" killall -9 tccd 2>/dev/null || true
fi
sleep 2

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
    "/Applications/RustDesk.app/Contents/MacOS/RustDesk_server" \
    "/Applications/RustDesk.app/Contents/MacOS/RustDesk_service" \
    "/Applications/RustDesk.app" \
    "com.carriez.rustdesk" \
    "com.carriez.RustDesk" \
    "com.carriez.RustDesk_service" \
    "com.carriez.RustDesk_server" \
    "com.carriez.rustdesk_service" \
    "com.carriez.rustdesk_server"; do
    sudo defaults write "$PLIST" "$APP_KEY" -date "3024-01-01 00:00:00 +0000" 2>/dev/null || true
  done

  if [[ "$U" != "root" ]]; then
    sudo chown -R "$U:staff" "$PLIST_DIR" 2>/dev/null || true
  fi
done

sudo killall -9 replayd 2>/dev/null || true
