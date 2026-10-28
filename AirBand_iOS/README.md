# AirBand Sync for iOS

A standalone native iOS application that connects directly to the **VALDUS Air Band** via Bluetooth Low Energy (BLE) and writes **Heart Rate Variability (SDNN)**, **Resting Heart Rate**, **Heart Rate**, **Blood Oxygen (SpO₂)**, and **Sleep Stages** directly into **Apple Health** for **Bevel**.

**Zero Mac involved in daily use.** Runs 100% on your iPhone.

---

## Features

* **Direct BLE GATT Bridge:** Communicates directly with the band hardware on custom services `0x55FF` and `0x56FF`.
* **Live Heart Rate Gauge:** Displays real-time pulse on your iPhone screen with animated heartbeat feedback.
* **Clinical HRV Calculation:** Computes true SDNN (ms) and RMSSD (ms) mathematically from your pulse intervals.
* **Apple HealthKit Integration:** Seamlessly exports all metrics into Apple Health (`HKHealthStore`) with full HealthKit permissions.
* **Bevel Ready:** Bevel automatically reads the exported SDNN HRV and Resting HR to calculate your daily **Recovery Score**, **Sleep Bank**, and **Day Strain**.

---

## Project Structure

```
AirBand_iOS/
├── AirBandApp.swift        # App entry point
├── ContentView.swift       # Dark-mode dashboard (Live HR, HRV, SpO2, Sync button)
├── BluetoothManager.swift  # CoreBluetooth client for Air Band
├── HealthKitManager.swift  # Native Apple Health writer
├── Info.plist              # Bluetooth & HealthKit permissions
└── AirBand.entitlements    # HealthKit entitlements
```

---

## 2-Minute Installation via Xcode (Free Personal Signing)

1. Open **Xcode** on your Mac.
2. Select **File → Open** and choose the `AirBand_iOS` folder in this workspace.
3. In the project settings under **Signing & Capabilities**:
   * Select your personal Apple ID as the **Team**.
   * Xcode will automatically generate a free personal provisioning profile.
4. Plug your iPhone into your Mac using a lightning/USB-C cable.
5. In Xcode's top bar, select your iPhone as the destination device.
6. Click the **Run** button (Play icon).
7. On your iPhone:
   * Go to **Settings → General → VPN & Device Management** and tap **Trust [Your Apple ID]**.
   * Open the **AirBand** app from your home screen.
   * Grant **Bluetooth** and **Apple Health** permissions when prompted.
8. **Unplug your iPhone.** The Mac is never needed again!
