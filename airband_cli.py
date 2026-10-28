import asyncio
import sys
import os

# Add RyzeWaveWatch to python path
sys.path.insert(0, os.path.abspath("./RyzeWaveWatch"))

from ryzewave import protocol as P
from ryzewave.client import RyzeWave

AIR_BAND_UUID = "6DB2DAAA-21FD-EF31-DDEF-75B6BBC7E2F0"


def hexdump(ch, d):
    op = P.OPNAME.get(d[0], f"0x{d[0]:02X}") if d else ""
    print(f"  <-- [{ch}] {d.hex(' ').upper()} ({op})")


async def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "info"
    print(f"Connecting to Air Band ({AIR_BAND_UUID})...")
    w = RyzeWave(address=AIR_BAND_UUID, name_prefix="Air Band")
    w.on_event = hexdump

    try:
        await w.connect(timeout=20.0, authenticate=False)
    except Exception as e:
        print(f"Connection failed: {e}")
        return

    try:
        print(f"Connected: True")
        print(f"Features: {w.features}")
        if w.max_len:
            print(f"Max Data Packet Length: {w.max_len}")

        if cmd == "info":
            try:
                ver = await w.version()
                print(f"Firmware Version: {ver}")
            except Exception as e:
                print(f"Version query failed: {e}")

            try:
                pct, chg = await w.battery()
                print(f"Battery: {pct}% {'(charging)' if chg else ''}")
            except Exception as e:
                print(f"Battery query failed: {e}")

        elif cmd == "sync":
            print("\n=== 1. SYNCING SLEEP DATA (0x31 0x01) ===")
            try:
                sleep_records = await w.fetch_sleep()
                print(f"Found {len(sleep_records)} sleep stage records:")
                for s in sleep_records:
                    stage_name = {1: "Deep", 2: "Light", 3: "REM", 4: "Awake"}.get(s.stage, f"Stage {s.stage}")
                    print(f"  {s.when:%Y-%m-%d %H:%M} -> {stage_name} ({s.minutes} min)")
            except Exception as e:
                print(f"Sleep sync error: {e}")

            print("\n=== 2. SYNCING 24H HEART RATE (0xF7 0xFA) ===")
            try:
                hr_records = await w.fetch_heart_rate()
                print(f"Found {len(hr_records)} heart rate records:")
                for t, hr in hr_records[-20:]:  # show latest 20
                    print(f"  {t:%Y-%m-%d %H:%M} -> {hr} bpm")
            except Exception as e:
                print(f"Heart rate sync error: {e}")

            print("\n=== 3. SYNCING SpO2 (0x34 0xFA) ===")
            try:
                spo2_records = await w.fetch_spo2()
                print(f"Found {len(spo2_records)} SpO2 records:")
                for t, v in spo2_records[-10:]:
                    print(f"  {t:%Y-%m-%d %H:%M} -> {v}%")
            except Exception as e:
                print(f"SpO2 sync error: {e}")

            print("\n=== 4. SYNCING STEPS (0xB2 0xFA) ===")
            try:
                step_records = await w.fetch_steps()
                print(f"Found {len(step_records)} hourly step records:")
                for r in step_records[-10:]:
                    print(f"  {r.when:%Y-%m-%d %H:00} -> Total: {r.total} (Walk: {r.walk_steps}, Run: {r.run_steps})")
            except Exception as e:
                print(f"Steps sync error: {e}")

        elif cmd == "time":
            ack = await w.set_time()
            print(f"Time set ack: {ack.hex(' ').upper()}")

    finally:
        await w.disconnect()
        print("\nDisconnected cleanly.")


if __name__ == "__main__":
    asyncio.run(main())
