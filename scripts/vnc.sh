#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RDP_USERNAME:-${VNC_USERNAME:-goldenrecipe}}"
PASSWORD="${RDP_PASSWORD:-${VNC_PASSWORD:-}}"
if [[ -z "$PASSWORD" ]]; then
  echo "! VNC_PASSWORD or RDP_PASSWORD environment variable is required"
  exit 1
fi
ARD="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"

echo "* Configuring ARD"

# Configure ARD with remote control access specifically for target user
sudo "$ARD" \
  -activate \
  -configure \
  -access -on \
  -allowAccessFor -specifiedUsers \
  -users "$USERNAME" \
  -privs -all \
  -clientopts -setvncpw -vncpw "$PASSWORD" \
  -clientopts -setvnclegacy -vnclegacy yes \
  -setreqperm -reqperm no \
  -setmenuextra -menuextra no \
  -restart -agent -menu

sleep 5

echo "- Configuring VNC authentication"

#
# macOS legacy VNC authentication uses the DES-style password transformation.
#
VNC_HASH="$(
  printf '%s\n' "$PASSWORD" |
  perl -we '
    BEGIN {
      @k = unpack "C*", pack "H*",
        "1734516E8BA8C5E2FF1C39567390ADCA";
    }

    $_ = <>;
    chomp;

    s/^(.{8}).*/$1/;

    @p = unpack "C*", $_;

    foreach (@k) {
      printf "%02X", $_ ^ (shift @p || 0);
    }

    print "\n";
  '
)"

printf '%s\n' "$VNC_HASH" |
  sudo tee /Library/Preferences/com.apple.VNCSettings.txt >/dev/null

sudo chmod 600 /Library/Preferences/com.apple.VNCSettings.txt

sudo "$ARD" \
  -configure \
  -clientopts \
  -setvnclegacy \
  -vnclegacy yes

sudo "$ARD" \
  -restart \
  -agent \
  -menu

sleep 5

echo "* Verifying status"

echo "- Console user:"
stat -f '%Su' /dev/console 2>/dev/null || whoami

echo
echo "- Active TCP listeners on port 5900:"
sudo lsof -nP -iTCP:5900 -sTCP:LISTEN || true

echo
echo "- Checking VNC port reachability:"
if nc -z 127.0.0.1 5900; then
  echo "* VNC TCP port 5900 is reachable"
else
  echo "! VNC TCP port 5900 is not reachable"
  exit 1
fi

echo
echo "- Remote Management processes:"
ps aux | grep -Ei '[A]RDAgent|[Ss]creensharingd|[Ss]creensharingAgent|[Vv]NCPrivilegeProxy' || true
