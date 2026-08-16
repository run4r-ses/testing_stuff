#!/usr/bin/env bash
set -euo pipefail

RUSTDESK_BIN="/Applications/RustDesk.app/Contents/MacOS/RustDesk"
if [[ ! -x "$RUSTDESK_BIN" && -x "/Applications/RustDesk.app/Contents/MacOS/rustdesk" ]]; then
  RUSTDESK_BIN="/Applications/RustDesk.app/Contents/MacOS/rustdesk"
fi

# 1. Resolve RustDesk ID
RUSTDESK_ID="Unavailable"
if [[ -f /tmp/rustdesk_id.txt ]]; then
  RUSTDESK_ID="$(cat /tmp/rustdesk_id.txt | tr -d '[:space:]')"
fi
if [[ -z "$RUSTDESK_ID" || "$RUSTDESK_ID" == "Unavailable" ]] && [[ -x "$RUSTDESK_BIN" ]]; then
  RUSTDESK_ID="$("$RUSTDESK_BIN" --get-id 2>/dev/null || echo 'Unavailable')"
  RUSTDESK_ID="$(echo "$RUSTDESK_ID" | tr -d '[:space:]')"
fi

# 2. Resolve Console User & OS Version
CONSOLE_USER="$(cat /tmp/rustdesk_user.txt 2>/dev/null || stat -f '%Su' /dev/console 2>/dev/null || echo "runner")"
OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo "macOS")"

# 3. Resolve Serveo direct tunnel host/port
SERVEO_ENDPOINT=""
for _ in {1..10}; do
  if [[ -f /tmp/serveo.log ]]; then
    # Serveo output lines typically contain: "Forwarding TCP connections from serveo.net:XXXXX" or "serveo.net:XXXXX"
    SERVEO_ENDPOINT="$(grep -E -o 'serveo\.net:[0-9]+' /tmp/serveo.log | tail -n 1 || true)"
    if [[ -n "$SERVEO_ENDPOINT" ]]; then
      break
    fi
  fi
  sleep 1
done

# 4. Display connection details in project logging style
echo
echo "* macOS web desktop is ready"
echo "* RustDesk ID:   $RUSTDESK_ID"
echo "* Console user:  $CONSOLE_USER"
echo "* OS version:    $OS_VERSION"
if [[ -n "$SERVEO_ENDPOINT" ]]; then
  echo "* Direct host:   $SERVEO_ENDPOINT"
fi
echo "*"
echo "* For web, you can connect via https://rustdesk.com/web/"
if [[ -n "$SERVEO_ENDPOINT" ]]; then
  echo "* For direct connection, enter '$SERVEO_ENDPOINT' into the RustDesk Client ID box"
fi
echo

# 5. Populate GitHub Step Summary if running inside GitHub Actions
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat << EOF >> "$GITHUB_STEP_SUMMARY"
### Connection information

| | |
| :--- | :--- |
| **RustDesk ID** | \`$RUSTDESK_ID\` |
| **Direct host** | \`${SERVEO_ENDPOINT:-Pending / Check Logs}\` |
| **Console user** | \`$CONSOLE_USER\` |
| **OS version** | \`$OS_VERSION\` |

Connect via [rustdesk.com/web](https://rustdesk.com/web/) using the ID above.

Connect via direct connection by entering \`${SERVEO_ENDPOINT:-serveo.net:PORT}\` into the RustDesk desktop client.
EOF
fi
