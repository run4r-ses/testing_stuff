#!/usr/bin/env bash
set -euo pipefail

echo "* Running keepalive monitor"

START_TIME=$(date +%s)

cleanup() {
  echo "* Stopping keepalive monitor"
}
trap cleanup EXIT INT TERM

while true; do
  CURRENT_TIME=$(date +%s)
  ELAPSED=$(( CURRENT_TIME - START_TIME ))
  ELAPSED_MIN=$(( ELAPSED / 60 ))

  # Check if RustDesk is alive
  if ! pgrep -i "rustdesk" >/dev/null 2>&1; then
    echo "! RustDesk process not detected in process table"
  fi

  echo "- [$(date '+%Y-%m-%d %H:%M:%S')] Keepalive monitor active (running for ${ELAPSED_MIN}m)"
  sleep 60
done
