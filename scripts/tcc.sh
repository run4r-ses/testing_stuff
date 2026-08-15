#!/usr/bin/env bash
set -euo pipefail

USERNAME="${VNC_USERNAME:-runneradmin}"

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

  echo "- Applying Screen Recording & PostEvent permissions"

  local SQL="
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
    SELECT
      'kTCCServiceScreenCapture',
      'com.apple.screensharing.agent',
      0,
      2,
      2,
      1,
      NULL,
      0,
      'UNUSED',
      0,
      $NOW
    WHERE
      EXISTS (SELECT 1 FROM pragma_table_info('access') WHERE name='service')
      AND EXISTS (SELECT 1 FROM pragma_table_info('access') WHERE name='client')
      AND EXISTS (SELECT 1 FROM pragma_table_info('access') WHERE name='auth_value');

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
    SELECT
      'kTCCServicePostEvent',
      'com.apple.screensharing.agent',
      0,
      2,
      2,
      1,
      NULL,
      0,
      'UNUSED',
      0,
      $NOW
    WHERE
      EXISTS (SELECT 1 FROM pragma_table_info('access') WHERE name='service')
      AND EXISTS (SELECT 1 FROM pragma_table_info('access') WHERE name='client')
      AND EXISTS (SELECT 1 FROM pragma_table_info('access') WHERE name='auth_value');
  "

  if sudo sqlite3 "$DB" "$SQL" 2>&1; then
    echo "* TCC modification accepted successfully for $DB"
  else
    echo "! TCC modification failed for $DB"
  fi

  echo "- Current kTCCServiceScreenCapture entries:"
  sudo sqlite3 -header -column "$DB" "
    SELECT service, client, auth_value, auth_reason, flags, last_modified
    FROM access
    WHERE service='kTCCServiceScreenCapture';
  " 2>/dev/null || true
}

# Patch system TCC database
patch_tcc "$TCC_SYSTEM"

# Ensure user TCC directory exists and has correct ownership
if [[ -d "/Users/$USERNAME/Library/Application Support/com.apple.TCC" ]]; then
  sudo chown -R \
    "$USERNAME":staff \
    "/Users/$USERNAME/Library/Application Support/com.apple.TCC" \
    2>/dev/null || true
fi

# Patch user TCC database
patch_tcc "$TCC_USER"

echo
echo "* Restarting tccd daemon"
sudo killall -9 tccd 2>/dev/null || true
sleep 3
