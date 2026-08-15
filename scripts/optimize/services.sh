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

# Optimize TCP network stack for low-latency VNC streaming (disable delayed ACK)
echo "- Optimizing TCP network stack for low-latency VNC"
sudo sysctl -w net.inet.tcp.delayed_ack=0 2>/dev/null || true
sudo sysctl -w net.inet.tcp.mptcp.enable=0 2>/dev/null || true
sudo sysctl -w net.inet.tcp.sendspace=1048576 2>/dev/null || true
sudo sysctl -w net.inet.tcp.recvspace=1048576 2>/dev/null || true
