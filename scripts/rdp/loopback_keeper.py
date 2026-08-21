#!/usr/bin/env python3
import asyncio
import os
import sys
import time

USERNAME = os.environ.get("RDP_USERNAME", os.environ.get("RUSTDESK_USERNAME", "goldenrecipe"))
PASSWORD = os.environ.get("RDP_PASSWORD", os.environ.get("RUSTDESK_PASSWORD", ""))

async def keep_session():
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Starting local VNC loopback keeper for user '{USERNAME}'...", flush=True)
    while True:
        try:
            import asyncvnc
            async with asyncvnc.connect('127.0.0.1', 5900, username=USERNAME, password=PASSWORD) as client:
                print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Local VNC loopback session established! '{USERNAME}' display active.", flush=True)
                while True:
                    await asyncio.sleep(15)
        except ImportError:
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] asyncvnc library not found, attempting auto-install...", flush=True)
            os.system("pip3 install --break-system-packages asyncvnc >/dev/null 2>&1 || pip3 install asyncvnc >/dev/null 2>&1")
            await asyncio.sleep(3)
        except Exception as e:
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Loopback keeper status: {e}, reconnecting in 5s...", flush=True)
            await asyncio.sleep(5)

if __name__ == "__main__":
    try:
        asyncio.run(keep_session())
    except KeyboardInterrupt:
        pass
