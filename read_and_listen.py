import asyncio
import csv
import sys
from datetime import datetime, timezone
from bleak import BleakScanner, BleakClient

TARGET = "air band"


def short_id(uuid: str) -> str:
    return uuid.split("-")[0][-4:].lower()


async def main():
    duration = 180
    if len(sys.argv) > 1:
        try:
            duration = int(sys.argv[1])
        except ValueError:
            pass

    print(f"Scanning for '{TARGET}' (timeout: 10s)...")
    discovered = await BleakScanner.discover(timeout=10.0, return_adv=True)

    matches = []
    for d, adv in discovered.values():
        name = d.name or adv.local_name or ""
        if TARGET in name.lower():
            matches.append((d, adv))

    if not matches:
        print("Air Band not found. Is it awake and nearby?")
        return

    device, adv = matches[0]
    dev_name = device.name or adv.local_name or "Air Band"
    print(f"Connecting to {dev_name} ({device.address})...")

    output_file = "valdus_packets.csv"
    with open(output_file, "a", newline="") as f:
        writer = csv.writer(f)
        if f.tell() == 0:
            writer.writerow(["timestamp_utc", "uuid", "hex", "event_type"])
            f.flush()

        async with BleakClient(device) as client:
            print(f"Connected: {client.is_connected}\n")

            # 1. Read all readable characteristics
            print("--- READING READABLE CHARACTERISTICS ---")
            for service in client.services:
                for char in service.characteristics:
                    s_id = short_id(str(char.uuid))
                    if "read" in char.properties:
                        try:
                            val = await client.read_gatt_char(char)
                            hex_val = val.hex(" ").upper()
                            ascii_val = "".join([chr(b) if 32 <= b <= 126 else "." for b in val])
                            print(f"[READ] {s_id} ({char.uuid}): {hex_val} | '{ascii_val}'")
                            writer.writerow([datetime.now(timezone.utc).isoformat(), str(char.uuid), hex_val, "read"])
                            f.flush()
                        except Exception as e:
                            print(f"[READ FAILED] {s_id} ({char.uuid}): {e}")

            # 2. Subscribe to all notifiable characteristics
            print("\n--- SUBSCRIBING TO NOTIFICATIONS ---")

            def callback(char, data):
                ts = datetime.now(timezone.utc).isoformat()
                payload = bytes(data).hex(" ").upper()
                s_id = short_id(str(char.uuid))
                print(f"[NOTIFY] [{ts}] [{s_id}] {payload}")
                writer.writerow([ts, str(char.uuid), payload, "notify"])
                f.flush()

            active = []
            for service in client.services:
                for char in service.characteristics:
                    s_id = short_id(str(char.uuid))
                    if "notify" in char.properties or "indicate" in char.properties:
                        try:
                            await client.start_notify(char, callback)
                            active.append(char)
                            print(f"[SUBSCRIBED] {s_id} ({char.uuid})")
                        except Exception as e:
                            print(f"[SUBSCRIBE FAILED] {s_id}: {e}")

            print(f"\nListening for notifications for {duration} seconds... (Wear band on wrist to activate sensors)")
            try:
                await asyncio.sleep(duration)
            except (KeyboardInterrupt, asyncio.CancelledError):
                print("\nStopping...")
            finally:
                for char in active:
                    try:
                        await client.stop_notify(char)
                    except Exception:
                        pass

    print(f"\nFinished. All data appended to {output_file}")


if __name__ == "__main__":
    asyncio.run(main())
