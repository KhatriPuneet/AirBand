import Foundation

// MARK: - WHOOP & OpenStrap Scientific Metrics Engine

class MetricsEngine {
    
    // Default baseline parameters (calibrated over 7-day rolling window)
    static var defaultMaxHR: Int = 190
    
    // MARK: - 1. RECOVERY SCORE (0 - 100%)
    /// Computes WHOOP-style Recovery Score from overnight/morning HRV, Resting HR, and SpO2.
    /// - Parameters:
    ///   - currentHRV: Today's SDNN in ms
    ///   - baselineHRV: 7-day rolling average SDNN in ms (default ~100)
    ///   - currentRHR: Today's resting heart rate in bpm
    ///   - baselineRHR: 7-day rolling average resting heart rate in bpm (default ~62)
    ///   - currentSpO2: Latest SpO2 percentage (e.g. 0.98 for 98%)
    /// - Returns: Score 0-100, color classification ("green", "yellow", "red"), and summary
    static func calculateRecoveryScore(
        currentHRV: Double,
        baselineHRV: Double = 100.0,
        currentRHR: Int,
        baselineRHR: Int = 62,
        currentSpO2: Double = 0.98
    ) -> (score: Int, state: String, color: String) {
        guard currentHRV > 0, currentRHR > 0 else {
            return (0, "Insufficient Data", "gray")
        }

        // 1. HRV Z-Score Component (60% weight in WHOOP algorithm)
        // Positive when current HRV is higher than baseline
        let hrvDeviation = (currentHRV - baselineHRV) / max(baselineHRV * 0.15, 8.0)
        let hrvScore = 50.0 + (hrvDeviation * 25.0)

        // 2. Resting HR Component (30% weight in WHOOP algorithm)
        // Inverted: Lower RHR than baseline indicates better parasympathetic recovery
        let rhrDeviation = Double(baselineRHR - currentRHR) / max(Double(baselineRHR) * 0.08, 4.0)
        let rhrScore = 50.0 + (rhrDeviation * 20.0)

        // 3. SpO2 Modifier (10% weight)
        let spo2Score: Double
        if currentSpO2 >= 0.97 {
            spo2Score = 100.0
        } else if currentSpO2 >= 0.94 {
            spo2Score = 75.0
        } else {
            spo2Score = 40.0
        }

        // Weighted blend
        let rawScore = (hrvScore * 0.60) + (rhrScore * 0.30) + (spo2Score * 0.10)
        let clampedScore = max(1, min(99, Int(round(rawScore))))

        // WHOOP Recovery Zones
        let state: String
        let color: String
        if clampedScore >= 67 {
            state = "Optimal Recovery (Green)"
            color = "green"
        } else if clampedScore >= 34 {
            state = "Adequate Recovery (Yellow)"
            color = "yellow"
        } else {
            state = "Under-Recovered (Red)"
            color = "red"
        }

        return (clampedScore, state, color)
    }

    // MARK: - 2. DAY STRAIN SCORE (0.0 - 21.0)
    /// Computes WHOOP-style Day Strain on the Borg 0-21 logarithmic scale.
    /// Uses Heart Rate Reserve (HRR) and Banister's TRIMP training impulse integration.
    /// - Parameters:
    ///   - hrRecords: Array of (timestamp, bpm) throughout the day
    ///   - restingHR: Resting heart rate in bpm
    ///   - maxHR: Max heart rate in bpm (defaults to 220 - age)
    /// - Returns: Strain float 0.0 to 21.0, and time spent in Zones 1-5 (minutes)
    static func calculateDayStrain(
        hrRecords: [(date: Date, bpm: Int)],
        restingHR: Int = 60,
        maxHR: Int = 190
    ) -> (strain: Double, zoneMinutes: [String: Int]) {
        guard !hrRecords.isEmpty, maxHR > restingHR else {
            return (0.0, ["Zone 1": 0, "Zone 2": 0, "Zone 3": 0, "Zone 4": 0, "Zone 5": 0])
        }

        var trimpTotal: Double = 0.0
        var zones = [
            "Zone 1 (50-60%)": 0,
            "Zone 2 (60-70%)": 0,
            "Zone 3 (70-80%)": 0,
            "Zone 4 (80-90%)": 0,
            "Zone 5 (90-100%)": 0
        ]

        let hrReserve = Double(maxHR - restingHR)

        for record in hrRecords {
            let hr = record.bpm
            guard hr >= restingHR else { continue }
            
            // Heart Rate Reserve fraction: 0.0 to 1.0
            let hrr = min(1.0, max(0.0, Double(hr - restingHR) / hrReserve))
            
            // Assume 10-minute bin representation (or 1-minute weight)
            let durationMinutes = 10.0

            // Categorize into WHOOP HR Zones
            if hrr >= 0.90 {
                zones["Zone 5 (90-100%)", default: 0] += Int(durationMinutes)
            } else if hrr >= 0.80 {
                zones["Zone 4 (80-90%)", default: 0] += Int(durationMinutes)
            } else if hrr >= 0.70 {
                zones["Zone 3 (70-80%)", default: 0] += Int(durationMinutes)
            } else if hrr >= 0.60 {
                zones["Zone 2 (60-70%)", default: 0] += Int(durationMinutes)
            } else if hrr >= 0.50 {
                zones["Zone 1 (50-60%)", default: 0] += Int(durationMinutes)
            }

            // Banister TRIMP exponential weight: y = hrr * 0.64 * e^(1.92 * hrr)
            let weight = hrr * 0.64 * exp(1.92 * hrr)
            trimpTotal += durationMinutes * weight
        }

        // Map TRIMP to WHOOP's logarithmic 0.0 to 21.0 scale:
        // Strain = 21 * (1 - e^(-k * TRIMP))
        let k = 0.0032
        let rawStrain = 21.0 * (1.0 - exp(-k * trimpTotal))
        let finalStrain = round(min(21.0, max(0.0, rawStrain)) * 10) / 10.0

        return (finalStrain, zones)
    }

    // MARK: - 3. SLEEP PERFORMANCE SCORE (0 - 100%)
    /// Computes Sleep Performance based on actual sleep vs baseline sleep need, plus sleep stage quality.
    /// - Parameters:
    ///   - sleepStages: List of (startDate, durationMinutes, stageCode: 1=Deep, 2=Light, 3=REM, 4=Awake)
    ///   - baselineSleepNeedMinutes: Target sleep (default 8 hours = 480 min)
    static func calculateSleepPerformance(
        sleepStages: [(startDate: Date, durationMinutes: Int, stage: Int)],
        baselineSleepNeedMinutes: Int = 480
    ) -> (score: Int, totalAsleepMinutes: Int, deepMinutes: Int, remMinutes: Int, lightMinutes: Int, awakeMinutes: Int) {
        guard !sleepStages.isEmpty else {
            return (0, 0, 0, 0, 0, 0)
        }

        var deep = 0
        var rem = 0
        var light = 0
        var awake = 0

        for stage in sleepStages {
            switch stage.stage {
            case 1: deep += stage.durationMinutes
            case 2: light += stage.durationMinutes
            case 3: rem += stage.durationMinutes
            case 4: awake += stage.durationMinutes
            default: light += stage.durationMinutes
            }
        }

        let totalAsleep = deep + rem + light
        let performanceRatio = Double(totalAsleep) / Double(max(baselineSleepNeedMinutes, 300))
        let rawScore = min(100.0, performanceRatio * 100.0)
        
        // Quality bonus for restorative sleep (Deep + REM ideally > 40% of total)
        let restorativeRatio = totalAsleep > 0 ? Double(deep + rem) / Double(totalAsleep) : 0
        let qualityAdjustment = (restorativeRatio - 0.40) * 15.0
        
        let finalScore = max(1, min(100, Int(round(rawScore + qualityAdjustment))))
        return (finalScore, totalAsleep, deep, rem, light, awake)
    }
}
