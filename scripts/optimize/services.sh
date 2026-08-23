#!/usr/bin/env bash
set -euo pipefail

echo "* Disabling unnecessary services"

# Disable Spotlight content indexing
echo "- Configuring Spotlight"
sudo touch /tmp/.metadata_never_index
sudo mdutil -a -i off || true

# Prevent sleep, screensaver, and display throttling
echo "- Configuring power management"
sudo pmset -a \
  disablesleep 1 \
  sleep 0 \
  displaysleep 0 \
  disksleep 0 \
  ring 0 \
  womp 0 || true

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
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.CrashReporter DialogType none || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.assistant.support "Assistant Enabled" -bool false || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.Siri StatusMenuVisible -bool false || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write com.apple.appleseed.FeedbackAssistant Autolaunch -bool false || true
  HOME="$USER_HOME" sudo -H -u "$USER_NAME" defaults write NSGlobalDomain "com.apple.sound.uiaudio.enabled" -int 0 || true

  sudo chown -R "$USER_NAME":staff "$USER_HOME/Library" || true
}

# Apply for runner AND goldenrecipe
write_user_service_preferences "runner"
write_user_service_preferences "goldenrecipe"

# Apply to User Template
TEMPLATE_DIR="/Library/User Template/Non_localized"
if [[ -d "$TEMPLATE_DIR" ]]; then
  sudo mkdir -p "$TEMPLATE_DIR/Library/Preferences"
  sudo defaults write "$TEMPLATE_DIR/Library/Preferences/com.apple.CrashReporter.plist" DialogType none || true
  sudo defaults write "$TEMPLATE_DIR/Library/Preferences/com.apple.assistant.support.plist" "Assistant Enabled" -bool false || true
  sudo defaults write "$TEMPLATE_DIR/Library/Preferences/com.apple.Siri.plist" StatusMenuVisible -bool false || true
  sudo defaults write "$TEMPLATE_DIR/Library/Preferences/com.apple.appleseed.FeedbackAssistant.plist" Autolaunch -bool false || true
  sudo defaults write "$TEMPLATE_DIR/Library/Preferences/.GlobalPreferences.plist" "com.apple.sound.uiaudio.enabled" -int 0 || true
fi

# System-wide preferences
sudo defaults write /Library/Preferences/com.apple.CrashReporter DialogType none || true
sudo defaults write /Library/Preferences/com.apple.assistant.support "Assistant Enabled" -bool false || true
sudo defaults write /Library/Preferences/com.apple.Siri StatusMenuVisible -bool false || true

# Disable Time Machine
echo "- Disabling Time Machine"
sudo tmutil disable || true

# Optimize TCP/UDP network stack for low-latency streaming
echo "- Optimizing network stack for low-latency remote desktop"
sudo sysctl -w net.inet.tcp.delayed_ack=0 || true
sudo sysctl -w net.inet.tcp.mptcp.enable=0 || true
sudo sysctl -w net.inet.tcp.sendspace=2097152 || true
sudo sysctl -w net.inet.tcp.recvspace=2097152 || true
sudo sysctl -w kern.ipc.maxsockbuf=8388608 || true

# Prioritize WindowServer compositor to eliminate UI frame drops
echo "- Prioritizing WindowServer compositor"
sudo renice -n -20 -p $(pgrep WindowServer) || true

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

RUNNER_UID="$(id -u runner 2>/dev/null || echo "501")"
GOLDENRECIPE_UID="$(id -u goldenrecipe 2>/dev/null || echo "502")"
TARGET_UIDS=("$RUNNER_UID:runner" "$GOLDENRECIPE_UID:goldenrecipe")

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
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool false || true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool false || true
sudo defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool false || true
