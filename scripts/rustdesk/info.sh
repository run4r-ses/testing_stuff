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
for _ in {1..30}; do
  if [[ -f /tmp/serveo.log ]]; then
    # Strip ANSI color/control codes
    CLEAN_LOG="$(sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g' /tmp/serveo.log 2>/dev/null || true)"

    # 1. Check for TCP forwarding (e.g. "Forwarding TCP connections from serveo.net:XXXXX")
    SERVEO_ENDPOINT="$(
      echo "$CLEAN_LOG" |
      grep -Ei 'Forwarding TCP connections from' |
      grep -Eo '([A-Za-z0-9.-]+\.)?serveo(usercontent)?\.net:[0-9]+' |
      head -n 1 || true
    )"

    # 2. Check for HTTP forwarding (e.g. "https://xxxx.serveousercontent.net")
    if [[ -z "$SERVEO_ENDPOINT" ]]; then
      SERVEO_ENDPOINT="$(
        echo "$CLEAN_LOG" |
        grep -Ei 'Forwarding HTTP traffic from' |
        grep -Eo 'https?://[A-Za-z0-9.-]+\.serveousercontent\.net' |
        head -n 1 || true
      )"
    fi

    # 3. Generic fallback match for host:port
    if [[ -z "$SERVEO_ENDPOINT" ]]; then
      SERVEO_ENDPOINT="$(
        echo "$CLEAN_LOG" |
        grep -Eo 'serveo\.net:[0-9]+' |
        head -n 1 || true
      )"
    fi

    if [[ -n "$SERVEO_ENDPOINT" ]]; then
      break
    fi
  fi

  # Check if tunnel process died early
  if [[ -f /tmp/serveo.pid ]]; then
    PID="$(cat /tmp/serveo.pid 2>/dev/null || true)"
    if [[ -n "$PID" ]] && ! kill -0 "$PID" 2>/dev/null; then
      echo "! Serveo SSH tunnel process died during startup (PID $PID)"
      if [[ -f /tmp/serveo.log ]]; then
        echo "--- serveo.log ---"
        cat /tmp/serveo.log || true
        echo "------------------"
      fi
      break
    fi
  fi

  sleep 1
done

if [[ -z "$SERVEO_ENDPOINT" && -f /tmp/serveo.log ]]; then
  echo "! Could not detect Serveo tunnel endpoint"
  echo "--- serveo.log ---"
  cat /tmp/serveo.log || true
  echo "------------------"
fi

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
