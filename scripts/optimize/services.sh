#!/usr/bin/env bash
set -euo pipefail

echo "* Disabling unnecessary services"

# Disable Spotlight indexing
echo "- Disabling Spotlight"
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
sudo sysctl -w net.inet.tcp.sendspace=1048576 2>/dev/null || true
sudo sysctl -w net.inet.tcp.recvspace=1048576 2>/dev/null || true
sudo sysctl -w kern.ipc.maxsockbuf=8388608 2>/dev/null || true

# Kill heavyweight background processes that waste CPU and produce screen updates
echo "- Killing unnecessary background processes"
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
)

for PROC in "${KILL_PROCS[@]}"; do
  sudo killall "$PROC" 2>/dev/null || true
done

# Disable software update checking
echo "- Disabling automatic software update checks"
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool false 2>/dev/null || true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool false 2>/dev/null || true
sudo defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool false 2>/dev/null || true
