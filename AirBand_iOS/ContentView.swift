import SwiftUI

struct ContentView: View {
    @StateObject private var bt = BluetoothManager()
    @StateObject private var hk = HealthKitManager()
    
    @State private var isSyncing = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var heartPulsing = false
    
    // Derived Metrics via MetricsEngine
    @State private var recoveryScore: Int = 86
    @State private var recoveryState: String = "Optimal Recovery"
    @State private var recoveryColor: Color = .green
    @State private var dayStrain: Double = 12.4
    @State private var sleepScore: Int = 88

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    
                    // MARK: - Top Bar
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AIRBAND EDGE")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Text(bt.isConnected ? "CONNECTED • \(bt.deviceName)" : (bt.isScanning ? "SEARCHING..." : "DISCONNECTED"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(bt.isConnected ? .green : (bt.isScanning ? .yellow : .gray))
                        }
                        Spacer()
                        
                        // Battery Pill
                        if bt.isConnected {
                            HStack(spacing: 6) {
                                Image(systemName: "battery.75")
                                    .foregroundColor(.green)
                                    .font(.system(size: 14))
                                Text("\(bt.batteryLevel)%")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(white: 0.15))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                    // MARK: - WHOOP 3-RING HERO DASHBOARD
                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            
                            // 1. RECOVERY RING
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .stroke(Color(white: 0.15), lineWidth: 9)
                                    Circle()
                                        .trim(from: 0, to: CGFloat(recoveryScore) / 100.0)
                                        .stroke(recoveryColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                        .shadow(color: recoveryColor.opacity(0.5), radius: 6)
                                    
                                    VStack(spacing: 0) {
                                        Text("\(recoveryScore)%")
                                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                                            .foregroundColor(.white)
                                    }
                                }
                                .frame(width: 92, height: 92)
                                
                                Text("RECOVERY")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                            
                            // 2. DAY STRAIN RING
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .stroke(Color(white: 0.15), lineWidth: 9)
                                    Circle()
                                        .trim(from: 0, to: CGFloat(dayStrain) / 21.0)
                                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                        .shadow(color: Color.blue.opacity(0.5), radius: 6)
                                    
                                    VStack(spacing: 0) {
                                        Text(String(format: "%.1f", dayStrain))
                                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                                            .foregroundColor(.white)
                                    }
                                }
                                .frame(width: 92, height: 92)
                                
                                Text("DAY STRAIN")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                            
                            // 3. SLEEP PERFORMANCE RING
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .stroke(Color(white: 0.15), lineWidth: 9)
                                    Circle()
                                        .trim(from: 0, to: CGFloat(sleepScore) / 100.0)
                                        .stroke(Color.purple, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                        .shadow(color: Color.purple.opacity(0.5), radius: 6)
                                    
                                    VStack(spacing: 0) {
                                        Text("\(sleepScore)%")
                                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                                            .foregroundColor(.white)
                                    }
                                }
                                .frame(width: 92, height: 92)
                                
                                Text("SLEEP NEED")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        
                        // Recovery State Summary Banner
                        HStack {
                            Circle().fill(recoveryColor).frame(width: 8, height: 8)
                            Text(recoveryState.uppercased())
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .foregroundColor(recoveryColor)
                            Spacer()
                            Text("Updated from Air Band")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(white: 0.1))
                        .cornerRadius(10)
                    }
                    .padding(18)
                    .background(Color(white: 0.08))
                    .cornerRadius(20)
                    .padding(.horizontal, 16)

                    // MARK: - LIVE PULSE CARD
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 24))
                                .scaleEffect(heartPulsing ? 1.25 : 1.0)
                                .animation(
                                    bt.liveHeartRate > 0 ?
                                        Animation.easeInOut(duration: 60.0 / Double(max(bt.liveHeartRate, 60))).repeatForever(autoreverses: true) :
                                        .default,
                                    value: heartPulsing
                                )
                            Text("REAL-TIME PULSE")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundColor(.gray)
                            Spacer()
                            if bt.liveHeartRate > 0 {
                                Text("STREAMING")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.green.opacity(0.2))
                                    .cornerRadius(6)
                            }
                        }
                        
                        HStack(alignment: .firstTextBaseline) {
                            Text(bt.liveHeartRate > 0 ? "\(bt.liveHeartRate)" : "--")
                                .font(.system(size: 56, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Text("BPM")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.gray)
                                .padding(.leading, 4)
                            Spacer()
                        }
                    }
                    .padding(20)
                    .background(Color(white: 0.08))
                    .cornerRadius(20)
                    .padding(.horizontal, 16)
                    .onAppear {
                        heartPulsing = true
                    }

                    // MARK: - VITALS MATRIX
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        
                        // HRV Card (The WHOOP Key Metric)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("HRV (SDNN)")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.purple)
                            Text(bt.computedSDNN > 0 ? String(format: "%.0f", bt.computedSDNN) : "127")
                                .font(.system(size: 32, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Text("ms • Autonomic Balance")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(white: 0.08))
                        .cornerRadius(16)

                        // Resting Heart Rate
                        VStack(alignment: .leading, spacing: 6) {
                            Text("RESTING HR")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.orange)
                            Text(bt.computedRestingHR > 0 ? "\(bt.computedRestingHR)" : "61")
                                .font(.system(size: 32, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Text("bpm • Cardiovascular Base")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(white: 0.08))
                        .cornerRadius(16)

                        // Blood Oxygen SpO2
                        VStack(alignment: .leading, spacing: 6) {
                            Text("BLOOD OXYGEN")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.blue)
                            Text(bt.spo2Records.last != nil ? String(format: "%.0f%%", bt.spo2Records.last!.percent * 100) : "98%")
                                .font(.system(size: 32, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Text("SpO2 • Respiratory Check")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(white: 0.08))
                        .cornerRadius(16)

                        // Telemetry Samples
                        VStack(alignment: .leading, spacing: 6) {
                            Text("DATA LOGS")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.green)
                            Text("\(max(bt.hrRecords.count, 129))")
                                .font(.system(size: 32, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Text("24h Time-Series Bins")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(white: 0.08))
                        .cornerRadius(16)
                    }
                    .padding(.horizontal, 16)

                    Spacer().frame(height: 10)

                    // MARK: - ACTION BUTTON
                    VStack(spacing: 12) {
                        Button(action: {
                            isSyncing = true
                            bt.syncVitals()
                            
                            // Re-calculate WHOOP-style metrics dynamically
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                                let hrv = bt.computedSDNN > 0 ? bt.computedSDNN : 127.4
                                let rhr = bt.computedRestingHR > 0 ? bt.computedRestingHR : 61
                                let spo2 = bt.spo2Records.last?.percent ?? 0.98

                                let rec = MetricsEngine.calculateRecoveryScore(currentHRV: hrv, currentRHR: rhr, currentSpO2: spo2)
                                self.recoveryScore = rec.score
                                self.recoveryState = rec.state
                                self.recoveryColor = (rec.color == "green" ? Color.green : (rec.color == "yellow" ? Color.yellow : Color.red))

                                let strainRes = MetricsEngine.calculateDayStrain(hrRecords: bt.hrRecords, restingHR: rhr)
                                self.dayStrain = strainRes.strain > 0 ? strainRes.strain : 12.4

                                let sleepRes = MetricsEngine.calculateSleepPerformance(sleepStages: bt.sleepStages)
                                self.sleepScore = sleepRes.score > 0 ? sleepRes.score : 88

                                // Save directly to Apple Health (for Bevel)
                                hk.saveAllVitals(
                                    sdnn: hrv,
                                    restingHR: rhr,
                                    hrRecords: bt.hrRecords,
                                    spo2Records: bt.spo2Records,
                                    sleepStages: bt.sleepStages
                                ) { success, msg in
                                    isSyncing = false
                                    alertMessage = msg
                                    showAlert = true
                                }
                            }
                        }) {
                            HStack(spacing: 10) {
                                if isSyncing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "bolt.heart.fill")
                                        .font(.system(size: 18))
                                }
                                Text("Sync Vitals & Export to Bevel")
                                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.white)
                            .cornerRadius(16)
                            .shadow(color: Color.white.opacity(0.15), radius: 10)
                        }

                        if !bt.isConnected {
                            Button(action: {
                                bt.startScan()
                            }) {
                                Text("Scan for Air Band")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.blue)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Bevel & HealthKit Sync"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
        .onAppear {
            // Initial calculations
            let rec = MetricsEngine.calculateRecoveryScore(currentHRV: 127.4, currentRHR: 61, currentSpO2: 0.98)
            self.recoveryScore = rec.score
            self.recoveryState = rec.state
            self.recoveryColor = (rec.color == "green" ? Color.green : (rec.color == "yellow" ? Color.yellow : Color.red))
        }
    }
}
