import Foundation
import HealthKit

class HealthKitManager: ObservableObject {
    @Published var isAuthorized = false
    @Published var authorizationRequested = false
    @Published var lastSaveStatus = "Ready"
    
    let healthStore = HKHealthStore()

    // HealthKit Types to Write & Read
    private let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
    private let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
    private let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let spo2Type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!
    private let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!

    init() {
        checkCurrentStatus()
    }

    func checkCurrentStatus() {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async {
                self.lastSaveStatus = "HealthKit not supported on this device"
            }
            return
        }
        let status = healthStore.authorizationStatus(for: hrvType)
        DispatchQueue.main.async {
            self.isAuthorized = (status == .sharingAuthorized)
        }
    }

    // Must be triggered when UI is visible (from onAppear or button tap)
    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async {
                self.lastSaveStatus = "HealthKit not supported on this device"
                completion?(false)
            }
            return
        }

        let writeTypes: Set<HKSampleType> = [hrvType, restingHRType, hrType, spo2Type, sleepType]
        let readTypes: Set<HKObjectType> = [hrvType, restingHRType, hrType, spo2Type, sleepType]

        healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.authorizationRequested = true
                self.checkCurrentStatus()
                if let error = error {
                    self.lastSaveStatus = "Permission prompt error: \(error.localizedDescription)"
                    completion?(false)
                } else {
                    self.lastSaveStatus = "HealthKit access configured"
                    completion?(true)
                }
            }
        }
    }

    func saveAllVitals(
        sdnn: Double,
        restingHR: Int,
        hrRecords: [(date: Date, bpm: Int)],
        spo2Records: [(date: Date, percent: Double)],
        sleepStages: [(startDate: Date, durationMinutes: Int, stage: Int)],
        completion: @escaping (Bool, String) -> Void
    ) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, "HealthKit is not available on this device.")
            return
        }

        let writeTypes: Set<HKSampleType> = [hrvType, restingHRType, hrType, spo2Type, sleepType]
        let readTypes: Set<HKObjectType> = [hrvType, restingHRType, hrType, spo2Type, sleepType]

        // Ensure authorization prompt is active if not yet determined
        healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { [weak self] _, _ in
            guard let self = self else { return }

            var samplesToSave: [HKSample] = []
            let now = Date()

            // 1. HRV SDNN Sample (WHOOP Recovery Metric for Bevel)
            if sdnn > 10.0 && sdnn < 300.0 {
                let hrvQuantity = HKQuantity(unit: HKUnit.secondUnit(with: .milli), doubleValue: sdnn)
                let hrvSample = HKQuantitySample(type: self.hrvType, quantity: hrvQuantity, start: now.addingTimeInterval(-60), end: now)
                samplesToSave.append(hrvSample)
            }

            // 2. Resting Heart Rate Sample
            if restingHR >= 35 && restingHR <= 120 {
                let rhrUnit = HKUnit.count().unitDivided(by: .minute())
                let rhrQuantity = HKQuantity(unit: rhrUnit, doubleValue: Double(restingHR))
                let rhrSample = HKQuantitySample(type: self.restingHRType, quantity: rhrQuantity, start: now.addingTimeInterval(-60), end: now)
                samplesToSave.append(rhrSample)
            }

            // 3. 24-Hour Continuous Heart Rate Time-Series
            let hrUnit = HKUnit.count().unitDivided(by: .minute())
            for r in hrRecords.suffix(150) {
                if r.bpm >= 35 && r.bpm <= 220 {
                    let q = HKQuantity(unit: hrUnit, doubleValue: Double(r.bpm))
                    let s = HKQuantitySample(type: self.hrType, quantity: q, start: r.date, end: r.date)
                    samplesToSave.append(s)
                }
            }

            // 4. Blood Oxygen (SpO2) Time-Series
            let spo2Unit = HKUnit.percent()
            for r in spo2Records.suffix(50) {
                if r.percent >= 0.70 && r.percent <= 1.0 {
                    let q = HKQuantity(unit: spo2Unit, doubleValue: r.percent)
                    let s = HKQuantitySample(type: self.spo2Type, quantity: q, start: r.date, end: r.date)
                    samplesToSave.append(s)
                }
            }

            // 5. Sleep Analysis Stages
            for stage in sleepStages {
                guard stage.durationMinutes > 0 else { continue }
                let endDate = stage.startDate.addingTimeInterval(TimeInterval(stage.durationMinutes * 60))
                guard endDate > stage.startDate else { continue }
                
                let value: HKCategoryValueSleepAnalysis
                switch stage.stage {
                case 1: value = .asleepDeep
                case 2: value = .asleepCore
                case 3: value = .asleepREM
                case 4: value = .awake
                default: value = .asleepCore
                }
                let s = HKCategorySample(type: self.sleepType, value: value.rawValue, start: stage.startDate, end: endDate)
                samplesToSave.append(s)
            }

            guard !samplesToSave.isEmpty else {
                DispatchQueue.main.async {
                    completion(false, "No valid biometric records ready to export.")
                }
                return
            }

            // Write all samples directly to HealthKit
            self.healthStore.save(samplesToSave) { success, error in
                DispatchQueue.main.async {
                    if success {
                        self.isAuthorized = true
                        self.lastSaveStatus = "Successfully exported \(samplesToSave.count) vitals to Apple Health!"
                        completion(true, "Successfully exported \(samplesToSave.count) vitals to Apple Health!\n\nBevel and Health app will now update.")
                    } else {
                        let msg = error?.localizedDescription ?? "Please enable permissions in Settings -> Health -> Data Access & Devices -> Zenflow."
                        self.lastSaveStatus = "Export error: \(msg)"
                        completion(false, msg)
                    }
                }
            }
        }
    }
}
