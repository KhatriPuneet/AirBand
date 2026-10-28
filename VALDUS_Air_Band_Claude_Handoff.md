# VALDUS Air Band → Apple Health / Bevel: Claude Project Handoff

**Status:** BLE services mapped with iPhone nRF Connect; two raw CSV logs collected; MacBook available; macOS Python extractor proposed but **not yet confirmed installed or executed**. No HRV or historical sleep protocol decoded.

## 1. User goal

The user has an inexpensive, unbranded **VALDUS Air Band** paired to **GloryFit** on an **iPhone**. They want WHOOP-like recovery insights in **Bevel**, ideally with free software. GloryFit displays metrics including heart rate, HRV, sleep, SpO₂ and stress, but only a subset is exported to Apple Health. The goal is to reverse-engineer the BLE protocol and build a reliable, ideally free pipeline to obtain missing metrics and, eventually, import **validated** measurements into Apple Health for Bevel.

### Critical limitations

- GloryFit's Apple Health permissions shown by the user include heart rate, sleep, steps, active energy, distance, height, weight and blood pressure, but **not HRV**, resting HR, SpO₂ or stress. Permissions and actual data written are separate issues.
- The GloryFit UI displayed **HRV ~34 ms**, but its exact metric/algorithm (SDNN, RMSSD, etc.) is **unknown**. Do not assume it is compatible with Apple Health's HRV SDNN field.
- The device's blood-pressure reading is not medically validated; do not treat it as clinically reliable.
- BLE data observed in nRF Connect does **not** automatically reveal GloryFit's commands or internal data storage.
- Do not claim an Apple Health or Bevel integration works until tested. macOS Python cannot directly write to iPhone HealthKit; an iOS app/Shortcuts-compatible import path would be required.

## 2. Devices and tools

- Band: **VALDUS Air Band**, advertised BLE name **`Air Band`**.
- Companion app: **GloryFit** on iPhone.
- BLE investigation app: **nRF Connect for Mobile** (iOS).
- Laptop: **MacBook (macOS)**, available for Python/Bleak development.
- No Android phone available at the time of discussion.
- Raw logs supplied in this conversation: **`Air Band.csv`** and **`Air Band 53.csv`**. Reattach these to Claude if it needs to inspect the full source logs; their original ChatGPT attachment paths may not exist in Claude's environment.

## 3. BLE service map (observed in nRF Connect)

| Service | Characteristic | Properties | Notes |
|---|---|---|---|
| `55FF` | `33F1` | Read / Write | Read returned 20-byte value |
| `55FF` | `33F2` | Notify | Main observed source of changing packets |
| `56FF` | `34F1` | Read / Write Without Response | Read returned 20-byte value |
| `56FF` | `34F2` | Notify | Notifications enabled; no confirmed received payloads in supplied logs |
| `60FF` | `6001` | Read / Write | Same observed value as `34F1` |
| `60FF` | `6002` | Notify | Notifications enabled in updated log; no confirmed payloads |
| `61FF` | `6101` | Read / Write Without Response | Not decoded |
| `61FF` | `6102` | Notify | Not decoded |
| Standard | `180F` | Battery service | Standard BLE service |
| Standard | `1800`, `1801` | Generic Access / Attribute | Standard BLE services |

Other advertised UUIDs included `5533` and `2222`.

**Note:** UUIDs are abbreviated 16-bit identifiers as shown in nRF Connect; Bleak may display expanded 128-bit Bluetooth UUID strings. Discover actual UUIDs at runtime; don't hardcode an assumed base UUID.

### Read results

- `33F1`: `0808 4839 2024 1943 756F FFFE 9821 005F 501B E09C`
- `34F1`: `00F4 0000 0000 0002 8800 2005 0000 0002 0040 0422`
- `6001`: `00F4 0000 0000 0002 8800 2005 0000 0002 0040 0422`

These bytes are **not decoded**. Do not write arbitrary data to these characteristics; unknown writes could alter configuration or invoke firmware/OTA features.

## 4. Notification observations

The updated log contains the following examples on **`33F2`**:

| Approx log time | Payload | Interpretation |
|---|---|---|
| 07:41:02 | `E511` | Repeating periodic packet; meaning unknown |
| 07:41:32 | `E500 0040` | Last byte `0x40` = 64; **possibly** HR bpm |
| 07:42:41 | `F703 07EA 0A1C 0728 3E` | Appears to include date/time and a value, but unverified |
| 07:42:42 | `E500 003E` | Last byte `0x3E` = 62; **possibly** HR bpm |
| 07:42:58 | `4400 0126 0000` | Unknown packet family |
| 07:45:03 | `5C11 0000 28` | Unknown packet family |
| 07:51:01 | `E511` | Repeating packet |
| 07:51:32 | `E500 003F` | Last byte `0x3F` = 63; **possibly** HR bpm |
| 07:52:41 | `F703 07EA 0A1C 0732 3D` | `07EA` may be year 2026; `0A1C` may be Oct 28; unverified |
| 07:52:42 | `E500 003D` | Last byte `0x3D` = 61; **possibly** HR bpm |

Earlier log also contained `E500 0043` (67) and `E500 0041` (65). The values look physiologically plausible but **do not establish the packet's meaning**. Validate against independently observed GloryFit heart rate at matching times and preferably during a controlled change in heart rate. If `F703` includes a date, investigate endianness and field boundaries systematically.

**No confirmed HRV, SpO₂ or historical sleep packets have been captured or decoded.** Existing captures mainly show unsolicited notifications, not a complete sync exchange.

## 5. MacBook implementation plan

### Step A: Prepare the Mac

Open Terminal:

```bash
python3 --version
mkdir -p ~/valdus-extractor
cd ~/valdus-extractor
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip bleak
```

Use Python 3.10+ if possible. Grant Terminal (or the Python-running application) Bluetooth access under macOS **System Settings → Privacy & Security → Bluetooth**. Disconnect the band from nRF Connect and stop GloryFit from competing for the BLE connection. Note that iOS can reconnect automatically.

### Step B: Create a read-only BLE scanner and notification logger

Create `valdus.py`:

```python
import asyncio
import csv
from datetime import datetime, timezone
from bleak import BleakScanner, BleakClient

TARGET = 'air band'
NOTIFY_IDS = {'33f2', '34f2', '6002', '6102'}


def short_id(uuid: str) -> str:
    # Matches Bluetooth-base expanded UUIDs such as
    # 000033f2-0000-1000-8000-00805f9b34fb.
    return uuid.split('-')[0][-4:].lower()


async def main():
    print('Scanning for Air Band...')
    devices = await BleakScanner.discover(timeout=15)
    matches = [d for d in devices if TARGET in (d.name or '').lower()]
    if not matches:
        print('No Air Band found. Nearby devices:')
        for d in devices:
            print(d.name, d.address)
        return

    device = matches[0]
    print('Connecting:', device.name, device.address)
    with open('valdus_packets.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['timestamp_utc', 'uuid', 'hex'])
        async with BleakClient(device) as client:
            print('Connected:', client.is_connected)

            def callback(char, data):
                ts = datetime.now(timezone.utc).isoformat()
                payload = bytes(data).hex(' ').upper()
                print(ts, short_id(char.uuid), payload)
                writer.writerow([ts, str(char.uuid), payload])
                f.flush()

            active = []
            for service in client.services:
                print('SERVICE', service.uuid)
                for char in service.characteristics:
                    print(' CHAR', char.uuid, char.properties)
                    if short_id(str(char.uuid)) in NOTIFY_IDS and 'notify' in char.properties:
                        try:
                            await client.start_notify(char, callback)
                            active.append(char)
                            print('  Listening:', char.uuid)
                        except Exception as exc:
                            print('  Could not subscribe:', exc)

            print('Recording for 180 seconds. Keep band nearby.')
            await asyncio.sleep(180)
            for char in active:
                try:
                    await client.stop_notify(char)
                except Exception:
                    pass
    print('Saved valdus_packets.csv')


if __name__ == '__main__':
    asyncio.run(main())
```

Run:

```bash
cd ~/valdus-extractor
source .venv/bin/activate
python valdus.py
```

**Caution:** This program is only a passive GATT notification subscriber. It cannot see the packets exchanged between the iPhone and GloryFit, and it cannot fetch historical data without discovering appropriate protocol commands. On some devices a CCCD subscription itself can affect device behavior, but this is lower risk than arbitrary writes.

### Step C: Analyze capture

Upload `valdus_packets.csv` to Claude along with the original nRF logs. Ask it to:

1. Parse all packets, deduplicate log lines, group by characteristic and packet prefix.
2. Examine packet frequency, payload lengths, byte offsets and likely timestamp fields.
3. Test the `E500` possible-heart-rate hypothesis using **independent measurements** rather than assuming it's true.
4. Check for any packets on `34F2`, `6002`, `6102`.
5. Document findings with confidence levels and retain raw bytes.

### Step D: Investigate history sync safely

- Research publicly documented GloryFit-compatible BLE protocols and verify device/firmware compatibility before using commands.
- Check whether GloryFit offers export, diagnostics or a user-accessible data backup.
- On macOS, examine supported Bluetooth diagnostic tools if needed, but **do not assume macOS can sniff an iPhone–band BLE connection**. Capturing another device's encrypted BLE traffic may require dedicated hardware or a different capture setup.
- If an Android device becomes available later, a Bluetooth HCI snoop log during GloryFit sync may be useful.
- Never guess firmware/OTA commands or perform bulk writes without a verified protocol and recovery plan.

## 6. Apple Health integration: separate phase

Once actual HRV semantics and sleep timestamps are verified:

1. Decide how to represent each metric in HealthKit; **do not relabel an unknown HRV algorithm as SDNN**.
2. Build or use an iPhone-side HealthKit writer with the appropriate user permissions. A Mac CSV by itself does not populate Apple Health.
3. Verify records actually appear in Apple Health with correct units, timestamps and source attribution.
4. Confirm Bevel reads those particular records and uses them in its recovery calculations. Bevel may require additional data sources or specific types of HRV records.
5. Deduplicate repeated syncs and handle time zones, incomplete sleep sessions, and sensor-quality caveats.

## 7. Open questions for Claude

- Which MacBook/macOS/Python version is installed? Has the script been run successfully?
- Does macOS discover `Air Band`, and are notifications received on the same characteristics?
- Can the `E500` candidate measurement be validated with simultaneous independent HR measurements?
- What exact BLE commands does this firmware use to request historical HRV/sleep/SpO₂ data?
- Does GloryFit store raw HRV values locally in a user-exportable format?
- What is the HRV definition shown by GloryFit (SDNN vs RMSSD vs proprietary)?
- What is the safest **free** HealthKit import route on iPhone, and does Bevel consume the imported samples?

## 8. Request to Claude: immediate next action

**Please continue as an engineering collaborator, one step at a time.** First help the user verify Python and Bleak on macOS and get a successful read-only notification capture. Troubleshoot actual errors rather than assuming success. After receiving the output CSV, analyze evidence before proposing any BLE writes or claiming HRV has been decoded. Keep instructions concise, runnable and explicit about what is confirmed versus hypothetical.

---

**Project outcome so far:** Custom services and periodic notification patterns identified. A possible heart-rate packet hypothesis exists. The Mac BLE extractor is prepared but not yet verified. **Historical HRV/sleep extraction and Apple Health integration are unsolved.**
