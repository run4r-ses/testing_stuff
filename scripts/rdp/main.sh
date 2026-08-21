#!/usr/bin/env bash
set -euo pipefail

USERNAME="${RDP_USERNAME:-${RUSTDESK_USERNAME:-goldenrecipe}}"
PASSWORD="${RDP_PASSWORD:-${RUSTDESK_PASSWORD:-}}"

if [[ -z "$PASSWORD" ]]; then
  echo "! RDP_PASSWORD or RUSTDESK_PASSWORD environment variable is required"
  exit 1
fi

echo "* Configuring Apple Remote Desktop / Screen Sharing"

# Enable Screen Sharing launchd service
echo "- Enabling Screen Sharing service"
sudo defaults write /var/db/launchd.db/com.apple.launchd/overrides.plist com.apple.screensharing -dict Disabled -bool false
sudo launchctl enable system/com.apple.screensharing 2>/dev/null || true
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true

# Configure kickstart for ARD / Screen Sharing access for target user with legacy VNC password
echo "- Configuring kickstart permissions for $USERNAME"
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -activate \
  -configure \
  -allowAccessFor -specifiedUsers \
  -access -on \
  -privs -all \
  -users "$USERNAME" \
  -clientopts -setvncpw -vncpw "$PASSWORD" \
  -clientopts -setvnclegacy -vnclegacy yes \
  -restart -agent -menu 2>/dev/null || true

# Ensure screensharing daemon is active
sudo launchctl kickstart -k system/com.apple.screensharing 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# Setup noVNC with Explicit Legacy VncAuth (Password Only)
# ────────────────────────────────────────────────────────────────────
echo "* Setting up noVNC with legacy VncAuth protocol"

NOVNC_DIR="/Users/Shared/noVNC"
if [[ ! -d "$NOVNC_DIR" ]]; then
  echo "- Downloading noVNC client"
  git clone --depth 1 https://github.com/novnc/noVNC.git "$NOVNC_DIR" 2>/dev/null || true
fi

if [[ -f "$NOVNC_DIR/core/rfb.js" ]]; then
  echo "- Enforcing legacy VncAuth security in noVNC rfb.js"
  python3 -c "
import re

rfb_path = '$NOVNC_DIR/core/rfb.js'
with open(rfb_path, 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Remove securityTypeARD from clientTypes to completely prevent ARD Diffie-Hellman / username+password negotiation
code = re.sub(
    r'_isSupportedSecurityType\(type\)\s*\{[\s\S]*?return clientTypes\.includes\(type\);[\s\S]*?\}',
    '''_isSupportedSecurityType(type) {
        const clientTypes = [
            securityTypeVNCAuth,
            securityTypeNone,
            securityTypeTight,
        ];
        return clientTypes.includes(type);
    }''',
    code
)

# 2. In _negotiateSecurity, explicitly prioritize and force securityTypeVNCAuth (Type 2)
code = re.sub(
    r'for\s*\(\s*let\s+type\s+of\s+types\s*\)\s*\{\s*if\s*\(\s*this\._isSupportedSecurityType\(type\)\s*\)\s*\{\s*this\._rfbAuthScheme\s*=\s*type;\s*break;\s*\}\s*\}',
    '''if (types.includes(securityTypeVNCAuth)) {
                this._rfbAuthScheme = securityTypeVNCAuth;
            } else {
                for (let type of types) {
                    if (this._isSupportedSecurityType(type)) {
                        this._rfbAuthScheme = type;
                        break;
                    }
                }
            }''',
    code
)

with open(rfb_path, 'w', encoding='utf-8') as f:
    f.write(code)
print('- Successfully patched noVNC rfb.js for legacy VncAuth')
" 2>/dev/null || true
fi

# Ensure websockify is available and start websockify proxy (port 6080 -> 5900)
echo "- Starting websockify proxy for noVNC (port 6080 -> 5900)"
if command -v websockify >/dev/null 2>&1; then
  nohup websockify --web "$NOVNC_DIR" 6080 127.0.0.1:5900 > /tmp/websockify.log 2>&1 &
  echo $! > /tmp/websockify.pid
elif python3 -m websockify --help >/dev/null 2>&1; then
  nohup python3 -m websockify --web "$NOVNC_DIR" 6080 127.0.0.1:5900 > /tmp/websockify.log 2>&1 &
  echo $! > /tmp/websockify.pid
else
  echo "! websockify is not installed, attempting pip install"
  pip3 install --break-system-packages websockify 2>/dev/null || pip3 install websockify 2>/dev/null || true
  nohup websockify --web "$NOVNC_DIR" 6080 127.0.0.1:5900 > /tmp/websockify.log 2>&1 &
  echo $! > /tmp/websockify.pid
fi

# Start background bore tunnels
if command -v bore >/dev/null 2>&1; then
  # 1. noVNC Web HTTP/WebSocket tunnel (port 6080)
  echo "- Starting bore tunnel for noVNC Web Interface (port 6080)"
  nohup bore local 6080 --to bore.pub > /tmp/novnc_tunnel.log 2>&1 &
  echo $! > /tmp/novnc_tunnel.pid

  # 2. Raw VNC / Apple Remote Desktop tunnel (port 5900)
  echo "- Starting bore tunnel for raw VNC / Screen Sharing (port 5900)"
  nohup bore local 5900 --to bore.pub > /tmp/tunnel.log 2>&1 &
  echo $! > /tmp/tunnel.pid
else
  echo "! bore-cli is not installed"
fi

echo "* Apple Remote Desktop & noVNC configured successfully"
