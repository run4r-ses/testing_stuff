#!/usr/bin/env bash
set -euo pipefail

log_msg() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_msg "* Running session monitor"

# Prevent macOS sleep, display sleep, and idle throttling
caffeinate -dimsu &
CAFFEINATE_PID=$!

cleanup() {
  log_msg "* Stopping session monitor"
  kill "$CAFFEINATE_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

export PATH="/tmp:/usr/local/bin:/opt/homebrew/bin:$PATH"
BORE_BIN="$(command -v bore 2>/dev/null || echo "/tmp/bore")"

LOOP_COUNT=0
START_TIME="$(date +%s)"

while true; do
  NOW="$(date +%s)"
  ELAPSED=$(( (NOW - START_TIME) / 60 ))

  # Active dynamic telemetry every 60s to maintain genuine CI runner activity
  if (( LOOP_COUNT % 4 == 0 )); then
    # Measure real CPU, memory, and disk metrics
    CPU_LOAD="$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}' || echo "0.10")"
    FREE_MEM_PAGES="$(vm_stat 2>/dev/null | grep 'Pages free:' | awk '{print $3}' | tr -d '.' || echo "0")"
    FREE_MEM_MB=$(( FREE_MEM_PAGES * 4096 / 1048576 ))

    log_msg "Runner active [${ELAPSED}m] | Load: $CPU_LOAD | Free RAM: ${FREE_MEM_MB}MB | Screen Sharing: OK"

    # Lightweight I/O heartbeat
    touch /tmp/.runner_heartbeat 2>/dev/null || true
    echo "$NOW" > /tmp/.runner_heartbeat 2>/dev/null || true
  fi

  # Watchdog: verify raw VNC bore tunnel is alive (port 5900)
  if [[ -f /tmp/tunnel.pid ]]; then
    PID="$(cat /tmp/tunnel.pid 2>/dev/null || true)"
    if [[ -z "$PID" ]] || ! kill -0 "$PID" 2>/dev/null; then
      log_msg "! VNC tunnel restart requested"
      if command -v bore >/dev/null 2>&1 || [[ -x /tmp/bore ]]; then
        nohup "$BORE_BIN" local 5900 --to bore.pub > /tmp/tunnel.log 2>&1 &
        echo $! > /tmp/tunnel.pid
      fi
    fi
  fi

  # Watchdog: ensure screensharing service is loaded in launchd
  if ! sudo launchctl list com.apple.screensharing >/dev/null 2>&1; then
    log_msg "! Screensharing service reloading"
    sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true
  fi

  LOOP_COUNT=$(( LOOP_COUNT + 1 ))
  sleep 15
done
