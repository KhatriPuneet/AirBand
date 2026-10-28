import Foundation
import HealthKit

class HealthKitManager: ObservableObject {
    @Published var isAuthorized = false
    @Published var lastSaveStatus = "Not yet saved"
    
    private let healthStore = HKHealthStore()

    // HealthKit Types to Write
    private let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
    private let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
    private let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let spo2Type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!
    private let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!

    init() {
        requestAuthorization()
    }

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            lastSaveStatus = "HealthKit not available on this device"
            return
        }

        let writeTypes: Set<HKSampleType> = [hrvType, restingHRType, hrType, spo2Type, sleepType]
        let readTypes: Set<HKObjectType> = [hrvType, restingHRType, hrType, spo2Type, sleepType]

        healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { success, error in
            DispatchQueue.main.async {
                self.isAuthorized = success
                if !success, let error = error {
                    self.lastSaveStatus = "Authorization error: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Save Metrics to Apple Health (for Bevel)
    
    func saveAllVitals(
        sdnn: Double,
        restingHR: Int,
        hrRecords: [(date: Date, bpm: Int)],
        spo2Records: [(date: Date, percent: Double)],
        sleepStages: [(startDate: Date, durationMinutes: Int, stage: Int)],
        completion: @escaping (Bool, String) -> Void
    ) {
        guard isAuthorized else {
            completion(false, "HealthKit not authorized. Enable permissions in Settings -> Health.")
            return
        }

        var samplesToSave: [HKSample] = []
        let now = Date()

        // 1. Save HRV (SDNN in milliseconds)
        if sdnn > 5.0 {
            let hrvQuantity = HKQuantity(unit: HKUnit.secondUnit(with: .milli), doubleValue: sdnn)
            let hrvSample = HKQuantitySample(type: hrvType, quantity: hrvQuantity, start: now, end: now)
            samplesToSave.append(hrvSample)
        }

        // 2. Save Resting Heart Rate (bpm)
        if restingHR > 35 && restingHR < 130 {
            let rhrQuantity = HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: Double(restingHR))
            let rhrSample = HKQuantitySample(type: restingHRType, quantity: rhrQuantity, start: now, end: now)
            samplesToSave.append(rhrSample)
        }

        // 3. Save Recent Heart Rate Samples (up to latest 50)
        let hrUnit = HKUnit.count().unitDivided(by: .minute())
        for r in hrRecords.suffix(50) {
            let q = HKQuantity(unit: hrUnit, doubleValue: Double(r.bpm))
            let s = HKQuantitySample(type: hrType, quantity: q, start: r.date, end: r.date)
            samplesToSave.append(s)
        }

        // 4. Save SpO2 Samples (as decimal percentage, e.g. 0.98 = 98%)
        let spo2Unit = HKUnit.percent()
        for r in spo2Records.suffix(20) {
            let q = HKQuantity(unit: spo2Unit, doubleValue: r.percent)
            let s = HKQuantitySample(type: spo2Type, quantity: q, start: r.date, end: r.date)
            samplesToSave.append(s)
        }

        // 5. Save Sleep Stages
        for stage in sleepStages {
            let endDate = stage.startDate.addingTimeInterval(TimeInterval(stage.durationMinutes * 60))
            let value: HKCategoryValueSleepAnalysis
            switch stage.stage {
            case 1: value = .asleepDeep
            case 2: value = .asleepCore
            case 3: value = .asleepREM
            case 4: value = .awake
            default: value = .asleepCore
            }
            let s = HKCategorySample(type: sleepType, value: value.rawValue, start: stage.startDate, end: endDate)
            samplesToSave.append(s)
        }

        // Execute batch write to Apple Health database
        healthStore.save(samplesToSave) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.lastSaveStatus = "Saved \(samplesToSave.count) samples to Apple Health!"
                    completion(true, "Successfully exported to Apple Health. Bevel will now update.")
                } else {
                    let msg = error?.localizedDescription ?? "Unknown save error"
                    self.lastSaveStatus = "Save failed: \(msg)"
                    completion(false, msg)
                }
            }
        }
    }
}
