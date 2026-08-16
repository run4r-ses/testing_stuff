#!/usr/bin/env bash
set -euo pipefail

echo "* Disabling unnecessary services"

# Disable Spotlight indexing, metadata daemon, and UI agent permanently
echo "- Disabling Spotlight"
sudo touch /.metadata_never_index 2>/dev/null || true
sudo touch /System/Volumes/Data/.metadata_never_index 2>/dev/null || true
sudo touch /Users/.metadata_never_index 2>/dev/null || true
sudo mdutil -a -i off >/dev/null 2>&1 || true
sudo mdutil -a -d >/dev/null 2>&1 || true
sudo mdutil -a -E >/dev/null 2>&1 || true

# Prevent sleep, screensaver, and display throttling
echo "- Configuring power management"
sudo pmset -a \
  disablesleep 1 \
  sleep 0 \
  displaysleep 0 \
  disksleep 0 \
  ring 0 \
  womp 0 >/dev/null 2>&1 || true

# Disable CrashReporter UI dialogs
echo "- Disabling CrashReporter"
defaults write com.apple.CrashReporter DialogType none
sudo defaults write /Library/Preferences/com.apple.CrashReporter DialogType none 2>/dev/null || true

# Disable Siri and Feedback Assistant
echo "- Disabling Siri"
defaults write com.apple.assistant.support "Assistant Enabled" -bool false
defaults write com.apple.Siri StatusMenuVisible -bool false
defaults write com.apple.appleseed.FeedbackAssistant Autolaunch -bool false

# Disable Audio UI feedback effects
defaults write NSGlobalDomain "com.apple.sound.uiaudio.enabled" -int 0

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

CONSOLE_USER="$(stat -f '%Su' /dev/console 2>/dev/null || echo "runner")"
CONSOLE_UID="$(id -u "$CONSOLE_USER" 2>/dev/null || echo "501")"

DISABLE_SERVICES=(
  "com.apple.Spotlight"
  "com.apple.corespotlightd"
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

for SVC in "${DISABLE_SERVICES[@]}"; do
  sudo launchctl disable "system/$SVC" 2>/dev/null || true
  sudo launchctl bootout "system/$SVC" 2>/dev/null || true
  sudo launchctl unload -w "/System/Library/LaunchDaemons/$SVC.plist" 2>/dev/null || true
  if [[ -n "$CONSOLE_UID" && "$CONSOLE_UID" != "0" ]]; then
    launchctl disable "gui/$CONSOLE_UID/$SVC" 2>/dev/null || true
    launchctl bootout "gui/$CONSOLE_UID/$SVC" 2>/dev/null || true
    launchctl asuser "$CONSOLE_UID" sudo -u "$CONSOLE_USER" launchctl unload -w "/System/Library/LaunchAgents/$SVC.plist" 2>/dev/null || true
  fi
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
  "Spotlight"
)

for PROC in "${KILL_PROCS[@]}"; do
  sudo killall "$PROC" 2>/dev/null || true
done

# Disable software update checking
echo "- Disabling automatic software update checks"
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool false 2>/dev/null || true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool false 2>/dev/null || true
sudo defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool false 2>/dev/null || true
