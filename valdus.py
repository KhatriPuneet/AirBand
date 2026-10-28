import asyncio
import csv
import sys
from datetime import datetime, timezone
from bleak import BleakScanner, BleakClient

TARGET = 'air band'
NOTIFY_IDS = {'33f2', '34f2', '6002', '6102'}


def short_id(uuid: str) -> str:
    # Matches Bluetooth-base expanded UUIDs such as
    # 000033f2-0000-1000-8000-00805f9b34fb.
    return uuid.split('-')[0][-4:].lower()


async def main():
    duration = 180
    if len(sys.argv) > 1:
        try:
            duration = int(sys.argv[1])
        except ValueError:
            pass

    print(f"Scanning for '{TARGET}' (timeout: 15s)...")
    try:
        discovered = await BleakScanner.discover(timeout=15.0, return_adv=True)
    except Exception as e:
        print(f"Error scanning for BLE devices: {e}")
        print("Note: On macOS, ensure Terminal or Python has Bluetooth permissions in System Settings -> Privacy & Security -> Bluetooth.")
        return

    matches = []
    for d, adv in discovered.values():
        name = d.name or adv.local_name or ""
        if TARGET in name.lower():
            matches.append((d, adv))

    if not matches:
        print("No 'Air Band' found. Discovered nearby named devices:")
        for d, adv in discovered.values():
            name = d.name or adv.local_name
            if name:
                print(f"  - {name} ({d.address}) RSSI: {adv.rssi} dBm")
        print("\nTroubleshooting tips:")
        print("1. Ensure the band is disconnected from iPhone / GloryFit / nRF Connect.")
        print("   (Bluetooth on the iPhone may need to be toggled off temporarily).")
        print("2. Ensure Bluetooth is enabled on your Mac.")
        print("3. Bring the band close to your Mac.")
        return

    device, adv = matches[0]
    dev_name = device.name or adv.local_name or "Air Band"
    print(f"Found Air Band: {dev_name} ({device.address}) [RSSI: {adv.rssi} dBm]")
    print(f"Connecting to {dev_name}...")

    output_file = "valdus_packets.csv"
    with open(output_file, "a", newline="") as f:
        writer = csv.writer(f)
        # Write header if file is newly created or empty
        if f.tell() == 0:
            writer.writerow(["timestamp_utc", "uuid", "hex"])
            f.flush()

        async with BleakClient(device) as client:
            print(f"Connected: {client.is_connected}")

            def callback(char, data):
                ts = datetime.now(timezone.utc).isoformat()
                payload = bytes(data).hex(" ").upper()
                s_id = short_id(str(char.uuid))
                print(f"[{ts}] [{s_id}] {payload}")
                writer.writerow([ts, str(char.uuid), payload])
                f.flush()

            active = []
            print("\nDiscovering GATT services and characteristics:")
            for service in client.services:
                print(f"SERVICE {service.uuid}")
                for char in service.characteristics:
                    props = ", ".join(char.properties)
                    s_id = short_id(str(char.uuid))
                    print(f"  CHAR {char.uuid} ({s_id}) [{props}]")
                    if s_id in NOTIFY_IDS and "notify" in char.properties:
                        try:
                            await client.start_notify(char, callback)
                            active.append(char)
                            print(f"    --> Subscribed to notifications on {s_id}")
                        except Exception as exc:
                            print(f"    --> Could not subscribe to {s_id}: {exc}")

            print(f"\nRecording notifications for {duration} seconds (Ctrl+C to stop early)...")
            try:
                await asyncio.sleep(duration)
            except asyncio.CancelledError:
                print("\nRecording interrupted.")
            except KeyboardInterrupt:
                print("\nRecording stopped by user.")
            finally:
                print("Stopping notifications...")
                for char in active:
                    try:
                        await client.stop_notify(char)
                    except Exception:
                        pass

    print(f"Capture complete. Packets saved to {output_file}")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nExited.")
