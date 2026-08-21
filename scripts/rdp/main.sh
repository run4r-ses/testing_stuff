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
  nohup websockify --web "$NOVNC_DIR" --heartbeat 30 6080 127.0.0.1:5900 > /tmp/websockify.log 2>&1 &
  echo $! > /tmp/websockify.pid
elif python3 -m websockify --help >/dev/null 2>&1; then
  nohup python3 -m websockify --web "$NOVNC_DIR" --heartbeat 30 6080 127.0.0.1:5900 > /tmp/websockify.log 2>&1 &
  echo $! > /tmp/websockify.pid
else
  echo "! websockify is not installed, attempting pip install"
  pip3 install --break-system-packages websockify 2>/dev/null || pip3 install websockify 2>/dev/null || true
  nohup websockify --web "$NOVNC_DIR" --heartbeat 30 6080 127.0.0.1:5900 > /tmp/websockify.log 2>&1 &
  echo $! > /tmp/websockify.pid
fi

# Ensure bore binary is available
export PATH="/tmp:/usr/local/bin:/opt/homebrew/bin:$PATH"
if ! command -v bore >/dev/null 2>&1; then
  echo "- bore not found in PATH, downloading binary from GitHub releases..."
  ARCH="$(uname -m)"
  if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
    curl -fsSL "https://github.com/ekzhang/bore/releases/download/v0.5.2/bore-v0.5.2-aarch64-apple-darwin.tar.gz" -o /tmp/bore.tar.gz 2>/dev/null || true
  else
    curl -fsSL "https://github.com/ekzhang/bore/releases/download/v0.5.2/bore-v0.5.2-x86_64-apple-darwin.tar.gz" -o /tmp/bore.tar.gz 2>/dev/null || true
  fi
  if [[ -f /tmp/bore.tar.gz ]]; then
    tar -xzf /tmp/bore.tar.gz -C /tmp/ 2>/dev/null || true
    chmod +x /tmp/bore 2>/dev/null || true
    sudo cp /tmp/bore /usr/local/bin/bore 2>/dev/null || sudo cp /tmp/bore /opt/homebrew/bin/bore 2>/dev/null || true
  fi
fi

# Start Serveo HTTPS Tunnel (via native SSH) for noVNC web interface
echo "- Starting Serveo HTTPS tunnel for noVNC (port 6080)"
nohup ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -R 80:localhost:6080 serveo.net > /tmp/serveo.log 2>&1 &
echo $! > /tmp/serveo.pid

# Start background bore tunnels
if command -v bore >/dev/null 2>&1 || [[ -x /tmp/bore ]]; then
  BORE_BIN="$(command -v bore 2>/dev/null || echo "/tmp/bore")"
  # 1. noVNC Web HTTP/WebSocket tunnel (port 6080 fallback)
  echo "- Starting bore tunnel for noVNC Web Interface (port 6080)"
  nohup "$BORE_BIN" local 6080 --to bore.pub > /tmp/novnc_tunnel.log 2>&1 &
  echo $! > /tmp/novnc_tunnel.pid

  # 2. Raw VNC / Apple Remote Desktop tunnel (port 5900)
  echo "- Starting bore tunnel for raw VNC / Screen Sharing (port 5900)"
  nohup "$BORE_BIN" local 5900 --to bore.pub > /tmp/tunnel.log 2>&1 &
  echo $! > /tmp/tunnel.pid
else
  echo "! bore binary could not be installed"
fi

# Start local loopback keeper to keep target user's virtual display alive 24/7
echo "- Starting local VNC loopback keeper for persistent display session"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
nohup python3 "$SCRIPT_DIR/loopback_keeper.py" > /tmp/loopback_keeper.log 2>&1 &
echo $! > /tmp/loopback_keeper.pid

echo "* Apple Remote Desktop & noVNC configured successfully"
