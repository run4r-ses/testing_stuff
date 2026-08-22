#!/usr/bin/env python3
import asyncio
import os
import subprocess
import sys
import time

USERNAME = os.environ.get("RDP_USERNAME", os.environ.get("RUSTDESK_USERNAME", "goldenrecipe"))
PASSWORD = os.environ.get("RDP_PASSWORD", os.environ.get("RUSTDESK_PASSWORD", ""))

def log_msg(msg):
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}", flush=True)

def ensure_asyncvnc():
    try:
        import asyncvnc
        return asyncvnc
    except ImportError:
        log_msg("asyncvnc library not found, attempting auto-installation via pip...")
        install_commands = [
            [sys.executable, "-m", "pip", "install", "--break-system-packages", "asyncvnc"],
            [sys.executable, "-m", "pip", "install", "asyncvnc"],
            ["pip3", "install", "--break-system-packages", "asyncvnc"],
            ["pip3", "install", "asyncvnc"],
        ]
        for cmd in install_commands:
            try:
                res = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
                if res.returncode == 0:
                    break
            except Exception:
                continue
        try:
            import asyncvnc
            log_msg("asyncvnc successfully installed and loaded!")
            return asyncvnc
        except ImportError:
            log_msg("Could not auto-install asyncvnc library via pip.")
            return None

async def keep_session():
    log_msg(f"Starting local VNC loopback keeper for user '{USERNAME}'...")
    while True:
        asyncvnc = ensure_asyncvnc()
        if not asyncvnc:
            log_msg("asyncvnc library unavailable, retrying install in 10s...")
            await asyncio.sleep(10)
            continue

        try:
            connect_kwargs = {}
            if USERNAME:
                connect_kwargs["username"] = USERNAME
            if PASSWORD:
                connect_kwargs["password"] = PASSWORD

            async with asyncvnc.connect('127.0.0.1', 5900, **connect_kwargs) as client:
                log_msg(f"Local VNC loopback session established! '{USERNAME}' display active.")
                while True:
                    await asyncio.sleep(15)
        except (ConnectionRefusedError, OSError) as e:
            log_msg(f"Waiting for Screen Sharing server on port 5900 ({e}), retrying in 5s...")
            await asyncio.sleep(5)
        except Exception as e:
            log_msg(f"Loopback keeper status: {e}, reconnecting in 5s...")
            await asyncio.sleep(5)

if __name__ == "__main__":
    try:
        asyncio.run(keep_session())
    except KeyboardInterrupt:
        pass

