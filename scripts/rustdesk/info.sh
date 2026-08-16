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

# 3. Resolve direct tunnel host/port (localhost.run)
TUNNEL_ENDPOINT=""
for _ in {1..30}; do
  if [[ -f /tmp/tunnel.log ]]; then
    # Strip ANSI color/control codes
    CLEAN_LOG="$(sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g' /tmp/tunnel.log 2>/dev/null || true)"

    # 1. Match TCP domain:port for localhost.run (e.g. *.lhrtunnel.pro:XXXXX or *.lhr.life:XXXXX)
    TUNNEL_ENDPOINT="$(
      echo "$CLEAN_LOG" |
      grep -Eo '([A-Za-z0-9.-]+\.)?(lhrtunnel\.pro|lhr\.life|localhost\.run):[0-9]+' |
      head -n 1 || true
    )"

    # 2. Generic fallback matching hostname:port from tunnel log
    if [[ -z "$TUNNEL_ENDPOINT" ]]; then
      TUNNEL_ENDPOINT="$(
        echo "$CLEAN_LOG" |
        grep -Ei 'tunneled' |
        grep -Eo '[A-Za-z0-9.-]+\.[a-zA-Z]{2,}:[0-9]+' |
        head -n 1 || true
      )"
    fi

    if [[ -n "$TUNNEL_ENDPOINT" ]]; then
      break
    fi
  fi

  # Check if tunnel process died early
  if [[ -f /tmp/tunnel.pid ]]; then
    PID="$(cat /tmp/tunnel.pid 2>/dev/null || true)"
    if [[ -n "$PID" ]] && ! kill -0 "$PID" 2>/dev/null; then
      echo "! localhost.run tunnel process died during startup (PID $PID)"
      if [[ -f /tmp/tunnel.log ]]; then
        echo "--- tunnel.log ---"
        cat /tmp/tunnel.log || true
        echo "------------------"
      fi
      break
    fi
  fi

  sleep 1
done

if [[ -z "$TUNNEL_ENDPOINT" && -f /tmp/tunnel.log ]]; then
  echo "! Could not detect direct tunnel endpoint"
  echo "--- tunnel.log ---"
  cat /tmp/tunnel.log || true
  echo "------------------"
fi

# 4. Display connection details in project logging style
echo
echo "* macOS web desktop is ready"
echo "* RustDesk ID:   $RUSTDESK_ID"
echo "* Console user:  $CONSOLE_USER"
echo "* OS version:    $OS_VERSION"
if [[ -n "$TUNNEL_ENDPOINT" ]]; then
  echo "* Direct host:   $TUNNEL_ENDPOINT"
fi
echo "*"
echo "* For web, you can connect via https://rustdesk.com/web/"
if [[ -n "$TUNNEL_ENDPOINT" ]]; then
  echo "* For direct connection, enter '$TUNNEL_ENDPOINT' into the RustDesk Client ID box"
fi
echo
