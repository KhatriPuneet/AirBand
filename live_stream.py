import asyncio
import sys
import os
from datetime import datetime

# Add RyzeWaveWatch to python path
sys.path.insert(0, os.path.abspath("./RyzeWaveWatch"))

from ryzewave import protocol as P
from ryzewave.client import RyzeWave

AIR_BAND_UUID = "6DB2DAAA-21FD-EF31-DDEF-75B6BBC7E2F0"


async def main():
    print(f"Connecting to Air Band ({AIR_BAND_UUID}) for live streaming...")
    w = RyzeWave(address=AIR_BAND_UUID, name_prefix="Air Band")

    try:
        await w.connect(timeout=20.0, authenticate=False)
    except Exception as e:
        print(f"Connection failed: {e}")
        return

    print("Connected! Activating live dynamic heart rate sensor on wrist...")
    
    # Send dynamic mode (D6 02)
    await w.write(P.enc_hr_mode(dynamic=True))
    await asyncio.sleep(1.5)

    def on_hr(hr):
        ts = datetime.now().strftime("%H:%M:%S")
        print(f"  [{ts}] LIVE HEART RATE: {hr} BPM  (Pulse Beat Detected)")

    try:
        print("\nStreaming live heart rate for 30 seconds... (Keep band on wrist)")
        await w.realtime_hr(30, on_hr)
    finally:
        await w.disconnect()
        print("\nLive session completed. Disconnected cleanly.")


if __name__ == "__main__":
    asyncio.run(main())
