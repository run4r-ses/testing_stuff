#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="${RDP_USERNAME:-${RUSTDESK_USERNAME:-goldenrecipe}}"
TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null || echo "")"
CONSOLE_USER="$(stat -f '%Su' /dev/console 2>/dev/null || echo "runner")"
CONSOLE_UID="$(id -u "$CONSOLE_USER" 2>/dev/null || echo "501")"

echo "* Disabling unnecessary services"

# Disable Spotlight content indexing
echo "- Configuring Spotlight"
sudo touch /tmp/.metadata_never_index 2>/dev/null || true
sudo mdutil -a -i off >/dev/null 2>&1 || true

# Prevent sleep, screensaver, and display throttling
echo "- Configuring power management"
sudo pmset -a \
  disablesleep 1 \
  sleep 0 \
  displaysleep 0 \
  disksleep 0 \
  ring 0 \
  womp 0 >/dev/null 2>&1 || true

# Helper function to apply user-level service/audio/crash preferences
write_user_service_preferences() {
  local USER_NAME="$1"
  local USER_HOME="/Users/$USER_NAME"

  if [[ ! -d "$USER_HOME" ]]; then
    return 0
  fi

  echo "- Applying service preferences for user $USER_NAME"
  sudo mkdir -p "$USER_HOME/Library/Preferences"

  # Direct plist writes
  sudo defaults write "$USER_HOME/Library/Preferences/com.apple.CrashReporter.plist" DialogType none
  sudo defaults write "$USER_HOME/Library/Preferences/com.apple.assistant.support.plist" "Assistant Enabled" -bool false
  sudo defaults write "$USER_HOME/Library/Preferences/com.apple.Siri.plist" StatusMenuVisible -bool false
  sudo defaults write "$USER_HOME/Library/Preferences/com.apple.appleseed.FeedbackAssistant.plist" Autolaunch -bool false
  sudo defaults write "$USER_HOME/Library/Preferences/.GlobalPreferences.plist" "com.apple.sound.uiaudio.enabled" -int 0

  # Via user domain with proper HOME
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.CrashReporter DialogType none 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.assistant.support "Assistant Enabled" -bool false 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.Siri StatusMenuVisible -bool false 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.appleseed.FeedbackAssistant Autolaunch -bool false 2>/dev/null || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write NSGlobalDomain "com.apple.sound.uiaudio.enabled" -int 0 2>/dev/null || true

  sudo chown -R "$USER_NAME":staff "$USER_HOME/Library" 2>/dev/null || true
}

# Apply for target user
write_user_service_preferences "$TARGET_USER"

# Apply for runner if distinct
if [[ "$TARGET_USER" != "runner" && -d "/Users/runner" ]]; then
  write_user_service_preferences "runner"
fi

# Apply to User Template
TEMPLATE_DIR="/Library/User Template/Non_localized"
if [[ -d "$TEMPLATE_DIR" ]]; then
  sudo mkdir -p "$TEMPLATE_DIR/Library/Preferences"
  sudo defaults write "$TEMPLATE_DIR/Library/Preferences/com.apple.CrashReporter.plist" DialogType none 2>/dev/null || true
  sudo defaults write "$TEMPLATE_DIR/Library/Preferences/com.apple.assistant.support.plist" "Assistant Enabled" -bool false 2>/dev/null || true
  sudo defaults write "$TEMPLATE_DIR/Library/Preferences/com.apple.Siri.plist" StatusMenuVisible -bool false 2>/dev/null || true
  sudo defaults write "$TEMPLATE_DIR/Library/Preferences/com.apple.appleseed.FeedbackAssistant.plist" Autolaunch -bool false 2>/dev/null || true
  sudo defaults write "$TEMPLATE_DIR/Library/Preferences/.GlobalPreferences.plist" "com.apple.sound.uiaudio.enabled" -int 0 2>/dev/null || true
fi

# System-wide preferences
sudo defaults write /Library/Preferences/com.apple.CrashReporter DialogType none 2>/dev/null || true
sudo defaults write /Library/Preferences/com.apple.assistant.support "Assistant Enabled" -bool false 2>/dev/null || true
sudo defaults write /Library/Preferences/com.apple.Siri StatusMenuVisible -bool false 2>/dev/null || true

# Disable Time Machine
echo "- Disabling Time Machine"
sudo tmutil disable 2>/dev/null || true

# Optimize TCP/UDP network stack for low-latency streaming
echo "- Optimizing network stack for low-latency remote desktop"
sudo sysctl -w net.inet.tcp.delayed_ack=0 2>/dev/null || true
sudo sysctl -w net.inet.tcp.mptcp.enable=0 2>/dev/null || true
sudo sysctl -w net.inet.tcp.sendspace=2097152 2>/dev/null || true
sudo sysctl -w net.inet.tcp.recvspace=2097152 2>/dev/null || true
sudo sysctl -w kern.ipc.maxsockbuf=8388608 2>/dev/null || true

# Prioritize WindowServer compositor to eliminate UI frame drops
echo "- Prioritizing WindowServer compositor"
sudo renice -n -20 -p $(pgrep WindowServer) 2>/dev/null || true

# Disable and unload background daemons that waste CPU and trigger screen refreshes
echo "- Suppressing background services"

DISABLE_SERVICES=(
  "com.apple.metadata.mds"
  "com.apple.metadata.mds.index"
  "com.apple.metadata.mds.spindump"
  "com.apple.photoanalysisd"
  "com.apple.photolibraryd"
  "com.apple.mediaanalysisd"
  "com.apple.triald"
  "com.apple.parsecd"
  "com.apple.intelligenceplatformd"
  "com.apple.remindd"
  "com.apple.CalendarAgent"
  "com.apple.suggestd"
  "com.apple.rapportd"
  "com.apple.biometrickitd"
  "com.apple.gamecontrollerd"
  "com.apple.AMPDeviceDiscoveryAgent"
  "com.apple.diagnostics_agent"
  "com.apple.spindump"
  "com.apple.ReportCrash"
  "com.apple.SubmitDiagInfo"
  "com.apple.UsageTrackingAgent"
  "com.apple.knowledge-agent"
)

# Collect all relevant UIDs to disable LaunchAgents for
TARGET_UIDS=()
if [[ -n "$CONSOLE_UID" && "$CONSOLE_UID" != "0" ]]; then
  TARGET_UIDS+=("$CONSOLE_UID:$CONSOLE_USER")
fi
if [[ -n "$TARGET_UID" && "$TARGET_UID" != "0" && "$TARGET_UID" != "$CONSOLE_UID" ]]; then
  TARGET_UIDS+=("$TARGET_UID:$TARGET_USER")
fi

for SVC in "${DISABLE_SERVICES[@]}"; do
  sudo launchctl disable "system/$SVC" 2>/dev/null || true
  sudo launchctl bootout "system/$SVC" 2>/dev/null || true
  sudo launchctl unload -w "/System/Library/LaunchDaemons/$SVC.plist" 2>/dev/null || true

  for ENTRY in "${TARGET_UIDS[@]}"; do
    UID_VAL="${ENTRY%%:*}"
    USER_VAL="${ENTRY##*:}"
    launchctl disable "gui/$UID_VAL/$SVC" 2>/dev/null || true
    launchctl bootout "gui/$UID_VAL/$SVC" 2>/dev/null || true
    launchctl asuser "$UID_VAL" sudo -u "$USER_VAL" launchctl unload -w "/System/Library/LaunchAgents/$SVC.plist" 2>/dev/null || true
  done
done

# Terminate any currently active instances
KILL_PROCS=(
  "softwareupdated"
  "com.apple.DiagnosticReportCleanUpAgent"
  "diagnostics_agent"
  "spindump"
  "ReportCrash"
  "SubmitDiagInfo"
  "AMPDeviceDiscoveryAgent"
  "photoanalysisd"
  "photolibraryd"
  "mediaanalysisd"
  "gamecontrollerd"
  "ManagedClient"
  "suggestd"
  "rapportd"
  "parsecd"
  "intelligenceplatformd"
  "triald"
  "UsageTrackingAgent"
  "remindd"
  "CalendarAgent"
  "contactsd"
  "coreduetd"
  "knowledge-agent"
  "mds"
  "mds_stores"
  "mdworker"
  "mdworker_shared"
)

for PROC in "${KILL_PROCS[@]}"; do
  sudo killall "$PROC" 2>/dev/null || true
done

# Disable software update checking
echo "- Disabling automatic software update checks"
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool false 2>/dev/null || true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool false 2>/dev/null || true
sudo defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool false 2>/dev/null || true
