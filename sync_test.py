import asyncio
import csv
import sys
from datetime import datetime, timezone
from bleak import BleakScanner, BleakClient

TARGET = "air band"

# GATT UUIDs
CH_CMD_WRITE = "000033f1-0000-1000-8000-00805f9b34fb"
CH_CMD_NOTIFY = "000033f2-0000-1000-8000-00805f9b34fb"
CH_DATA_WRITE = "000034f1-0000-1000-8000-00805f9b34fb"
CH_DATA_NOTIFY = "000034f2-0000-1000-8000-00805f9b34fb"


async def main():
    print(f"Scanning for '{TARGET}' (timeout: 10s)...")
    discovered = await BleakScanner.discover(timeout=10.0, return_adv=True)

    matches = []
    for d, adv in discovered.values():
        name = d.name or adv.local_name or ""
        if TARGET in name.lower():
            matches.append((d, adv))

    if not matches:
        print("Air Band not found. Make sure Bluetooth on iPhone is OFF and band is nearby.")
        return

    device, adv = matches[0]
    dev_name = device.name or adv.local_name or "Air Band"
    print(f"Connecting to {dev_name} ({device.address})...")

    csv_file = "valdus_sync_records.csv"
    with open(csv_file, "a", newline="") as f:
        writer = csv.writer(f)
        if f.tell() == 0:
            writer.writerow(["timestamp_utc", "channel", "hex", "decoded_info"])
            f.flush()

        async with BleakClient(device) as client:
            print(f"Connected: {client.is_connected}")

            # Collect received packets
            received_packets = []

            def on_packet(channel_name, data):
                ts = datetime.now(timezone.utc).isoformat()
                hex_str = bytes(data).hex(" ").upper()
                received_packets.append((channel_name, bytes(data)))
                print(f"  <-- [{channel_name}] {hex_str}")
                writer.writerow([ts, channel_name, hex_str, ""])
                f.flush()

            # Subscribe to command and data notification channels
            await client.start_notify(CH_CMD_NOTIFY, lambda c, d: on_packet("cmd_33f2", d))
            await client.start_notify(CH_DATA_NOTIFY, lambda c, d: on_packet("data_34f2", d))
            print("Subscribed to 33F2 and 34F2.\n")

            # 1. Query Device Version
            print("1. Sending Version Query (0xA1)...")
            await client.write_gatt_char(CH_CMD_WRITE, bytes([0xA1]), response=False)
            await asyncio.sleep(1.0)

            # 2. Query Battery Level
            print("2. Sending Battery Query (0xA2)...")
            await client.write_gatt_char(CH_CMD_WRITE, bytes([0xA2]), response=False)
            await asyncio.sleep(1.0)

            # 3. Request Sleep History (0x31 0x01)
            print("3. Requesting Sleep History (0x31 0x01)...")
            await client.write_gatt_char(CH_CMD_WRITE, bytes([0x31, 0x01]), response=False)
            await asyncio.sleep(3.0)

            # 4. Request 24h Heart Rate History (0xF7 0xFA + 6 zero bytes for all)
            print("4. Requesting 24h Heart Rate History (0xF7 0xFA)...")
            await client.write_gatt_char(CH_CMD_WRITE, bytes([0xF7, 0xFA, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]), response=False)
            await asyncio.sleep(4.0)

            # 5. Request SpO2 History (0x34 0xFA)
            print("5. Requesting SpO2 History (0x34 0xFA)...")
            await client.write_gatt_char(CH_CMD_WRITE, bytes([0x34, 0xFA]), response=False)
            await asyncio.sleep(3.0)

            # 6. Request Mood / Stress / Fatigue History (0x44 0xFA)
            print("6. Requesting Mood / Stress History (0x44 0xFA)...")
            await client.write_gatt_char(CH_CMD_WRITE, bytes([0x44, 0xFA]), response=False)
            await asyncio.sleep(3.0)

            # 7. Request Step History (0xB2 0xFA)
            print("7. Requesting Step History (0xB2 0xFA)...")
            await client.write_gatt_char(CH_CMD_WRITE, bytes([0xB2, 0xFA]), response=False)
            await asyncio.sleep(3.0)

            print("\nListening for remaining packets for 5 seconds...")
            await asyncio.sleep(5.0)

    print(f"\nSync test completed! Received {len(received_packets)} packets. Saved to {csv_file}")


if __name__ == "__main__":
    asyncio.run(main())
