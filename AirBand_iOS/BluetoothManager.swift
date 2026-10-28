import Foundation
import CoreBluetooth
import Combine

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var isBluetoothReady = false
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var deviceName: String = "Not Connected"
    @Published var batteryLevel: Int = 0
    @Published var liveHeartRate: Int = 0
    @Published var lastSyncStatus: String = "Idle"
    
    // Extracted Health Metrics
    @Published var hrRecords: [(date: Date, bpm: Int)] = []
    @Published var spo2Records: [(date: Date, percent: Double)] = []
    @Published var sleepStages: [(startDate: Date, durationMinutes: Int, stage: Int)] = []
    @Published var computedSDNN: Double = 0.0
    @Published var computedRestingHR: Int = 0

    private var centralManager: CBCentralManager!
    private var airBandPeripheral: CBPeripheral?
    
    // GATT Characteristics
    private var cmdWriteChar: CBCharacteristic?
    private var cmdNotifyChar: CBCharacteristic?
    private var dataWriteChar: CBCharacteristic?
    private var dataNotifyChar: CBCharacteristic?
    
    // UUIDs
    private let SVC_CMD = CBUUID(string: "000055ff-0000-1000-8000-00805f9b34fb")
    private let CH_CMD_WRITE = CBUUID(string: "000033f1-0000-1000-8000-00805f9b34fb")
    private let CH_CMD_NOTIFY = CBUUID(string: "000033f2-0000-1000-8000-00805f9b34fb")
    
    private let SVC_DATA = CBUUID(string: "000056ff-0000-1000-8000-00805f9b34fb")
    private let CH_DATA_WRITE = CBUUID(string: "000034f1-0000-1000-8000-00805f9b34fb")
    private let CH_DATA_NOTIFY = CBUUID(string: "000034f2-0000-1000-8000-00805f9b34fb")
    
    var onDataSyncComplete: (() -> Void)?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        guard centralManager.state == .poweredOn else { return }
        isScanning = true
        lastSyncStatus = "Scanning for Air Band..."
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        isScanning = false
        centralManager.stopScan()
    }

    func disconnect() {
        if let p = airBandPeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
    }

    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isBluetoothReady = (central.state == .poweredOn)
        if central.state == .poweredOn {
            startScan()
        } else {
            isConnected = false
            lastSyncStatus = "Bluetooth unavailable"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        if name.lowercased().contains("air band") {
            stopScan()
            lastSyncStatus = "Found \(name). Connecting..."
            airBandPeripheral = peripheral
            airBandPeripheral?.delegate = self
            centralManager.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        deviceName = peripheral.name ?? "Air Band"
        lastSyncStatus = "Connected! Discovering services..."
        peripheral.discoverServices([SVC_CMD, SVC_DATA])
        startAutoSyncTimer()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        deviceName = "Not Connected"
        liveHeartRate = 0
        lastSyncStatus = "Disconnected. Auto-reconnecting..."
        stopAutoSyncTimer()
        startScan()
    }

    // MARK: - CBPeripheralDelegate
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            if service.uuid == SVC_CMD {
                peripheral.discoverCharacteristics([CH_CMD_WRITE, CH_CMD_NOTIFY], for: service)
            } else if service.uuid == SVC_DATA {
                peripheral.discoverCharacteristics([CH_DATA_WRITE, CH_DATA_NOTIFY], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            if char.uuid == CH_CMD_WRITE {
                cmdWriteChar = char
            } else if char.uuid == CH_CMD_NOTIFY {
                cmdNotifyChar = char
                peripheral.setNotifyValue(true, for: char)
            } else if char.uuid == CH_DATA_WRITE {
                dataWriteChar = char
            } else if char.uuid == CH_DATA_NOTIFY {
                dataNotifyChar = char
                peripheral.setNotifyValue(true, for: char)
            }
        }

        // Ready to communicate
        if cmdWriteChar != nil && cmdNotifyChar != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.syncVitals()
            }
        }
    }

    // MARK: - Sending Commands
    func sendCommand(_ bytes: [UInt8], writeType: CBCharacteristicWriteType = .withResponse) {
        guard let p = airBandPeripheral, let c = cmdWriteChar else { return }
        let data = Data(bytes)
        p.writeValue(data, for: c, type: writeType)
    }

    private var autoSyncTimer: Timer?

    func startAutoSyncTimer() {
        stopAutoSyncTimer()
        // Recurring background sync every 15 minutes (900s)
        autoSyncTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            guard let self = self, self.isConnected else { return }
            self.syncVitals()
        }
    }

    func stopAutoSyncTimer() {
        autoSyncTimer?.invalidate()
        autoSyncTimer = nil
    }

    func syncVitals() {
        lastSyncStatus = "Syncing historical data..."
        
        // 1. Set Time (A3)
        let now = Date()
        let cal = Calendar.current
        let y = UInt16(cal.component(.year, from: now))
        let m = UInt8(cal.component(.month, from: now))
        let d = UInt8(cal.component(.day, from: now))
        let hh = UInt8(cal.component(.hour, from: now))
        let mm = UInt8(cal.component(.minute, from: now))
        let ss = UInt8(cal.component(.second, from: now))
        sendCommand([0xA3, UInt8(y >> 8), UInt8(y & 0xFF), m, d, hh, mm, ss])

        // 2. Query Battery (A2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.sendCommand([0xA2])
        }

        // 3. Query 24h Heart Rate (F7 FA 00 00 00 00 00 00)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.sendCommand([0xF7, 0xFA, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        }

        // 4. Query SpO2 (34 FA)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.sendCommand([0x34, 0xFA])
        }

        // 5. Query Sleep (31 01)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            self.sendCommand([0x31, 0x01])
        }

        // 6. Complete Sync & Auto-Export
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
            self.computeHRVMetrics()
            self.lastSyncStatus = "Auto-Synced • \(Date().formatted(date: .omitted, time: .shortened))"
            self.onDataSyncComplete?()
        }
    }

    // MARK: - Receiving Data (Packet Parsing)
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, !data.isEmpty else { return }
        let bytes = [UInt8](data)
        let op = bytes[0]

        DispatchQueue.main.async {
            switch op {
            case 0xA2: // Battery
                if bytes.count > 1 {
                    self.batteryLevel = Int(bytes[1])
                }

            case 0xE5: // Real-time Heart Rate Stream
                if bytes.count >= 4 && bytes[1] == 0x00 && bytes[2] == 0x00 {
                    let hr = Int(bytes[3])
                    if hr > 0 {
                        self.liveHeartRate = hr
                    }
                }

            case 0xF7: // 24h Heart Rate History (18 bytes)
                if bytes.count == 18 {
                    self.parseHRRecord(bytes: bytes)
                } else if bytes.count >= 3 && bytes[1] == 0xFD {
                    self.lastSyncStatus = "HR sync complete (\(self.hrRecords.count) samples)"
                    self.computeHRVMetrics()
                    self.onDataSyncComplete?()
                }

            case 0x34: // SpO2 History (20 bytes)
                if bytes.count == 20 && bytes[1] == 0xFA {
                    self.parseSpO2Record(bytes: bytes)
                }

            case 0x32: // Sleep Stages on data channel
                self.parseSleepStages(bytes: bytes)

            default:
                break
            }
        }
    }

    private func parseHRRecord(bytes: [UInt8]) {
        let year = Int(bytes[1]) << 8 | Int(bytes[2])
        let month = Int(bytes[3])
        let day = Int(bytes[4])
        let hour = Int(bytes[5]) % 24
        
        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        dateComponents.hour = hour
        
        let cal = Calendar.current
        guard let baseDate = cal.date(from: dateComponents) else { return }

        // 12 x 10-minute bins ending at hour:00
        for i in 0..<12 {
            let hr = Int(bytes[6 + i])
            if hr > 35 && hr < 220 {
                let offsetMinutes = -((11 - i) * 10)
                if let sampleDate = cal.date(byAdding: .minute, value: offsetMinutes, to: baseDate) {
                    hrRecords.append((sampleDate, hr))
                }
            }
        }
    }

    private func parseSpO2Record(bytes: [UInt8]) {
        let year = Int(bytes[2]) << 8 | Int(bytes[3])
        let month = Int(bytes[4])
        let day = Int(bytes[5])
        let hour = Int(bytes[6]) % 24
        let minute = Int(bytes[7]) % 60

        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        dateComponents.hour = hour
        dateComponents.minute = minute

        let cal = Calendar.current
        guard let baseDate = cal.date(from: dateComponents) else { return }

        for i in 0..<12 {
            let spo2 = Int(bytes[8 + i])
            if spo2 >= 70 && spo2 <= 100 {
                let offsetMinutes = -((11 - i) * 10)
                if let sampleDate = cal.date(byAdding: .minute, value: offsetMinutes, to: baseDate) {
                    spo2Records.append((sampleDate, Double(spo2) / 100.0))
                }
            }
        }
    }

    private func parseSleepStages(bytes: [UInt8]) {
        let cal = Calendar.current
        let today = Date()
        for o in stride(from: 1, to: bytes.count - 5, by: 6) {
            let hh = Int(bytes[o]) % 24
            let mm = Int(bytes[o + 1]) % 60
            let stage = Int(bytes[o + 2])
            let dur = (Int(bytes[o + 4]) << 8) | Int(bytes[o + 5])

            var comp = cal.dateComponents([.year, .month, .day], from: today)
            comp.hour = hh
            comp.minute = mm
            if let startDate = cal.date(from: comp) {
                sleepStages.append((startDate, dur, stage))
            }
        }
    }

    private func computeHRVMetrics() {
        guard hrRecords.count >= 3 else { return }
        let validHrs = hrRecords.map { $0.bpm }.filter { $0 >= 40 && $0 <= 180 }
        guard validHrs.count >= 3 else { return }

        // RR interval in ms = 60000 / HR
        let rrs = validHrs.map { 60000.0 / Double($0) }
        let mean = rrs.reduce(0, +) / Double(rrs.count)
        let variance = rrs.map { pow($0 - mean, 2) }.reduce(0, +) / Double(rrs.count - 1)
        
        // SDNN (Apple Health HRV Standard)
        computedSDNN = round(sqrt(variance) * 10) / 10.0
        
        // Resting HR (lower 5th percentile)
        let sortedHrs = validHrs.sorted()
        computedRestingHR = sortedHrs[max(0, Int(Double(sortedHrs.count) * 0.05))]
    }
}
