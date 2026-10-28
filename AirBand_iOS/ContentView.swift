import SwiftUI

struct ContentView: View {
    @StateObject private var bt = BluetoothManager()
    @StateObject private var hk = HealthKitManager()
    
    @State private var isSyncing = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var heartPulsing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    
                    // Header & Device Status
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AirBand Sync")
                                .font(.title2.bold())
                                .foregroundColor(.white)
                            Text(bt.deviceName)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        
                        // Connection Indicator & Battery
                        HStack(spacing: 8) {
                            if bt.isConnected {
                                Image(systemName: "battery.75")
                                    .foregroundColor(.green)
                                Text("\(bt.batteryLevel)%")
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                            }
                            Circle()
                                .fill(bt.isConnected ? Color.green : (bt.isScanning ? Color.yellow : Color.red))
                                .frame(width: 10, height: 10)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(white: 0.15))
                        .cornerRadius(20)
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)

                    // Live Heart Rate Hero Card
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 28))
                                .scaleEffect(heartPulsing ? 1.2 : 1.0)
                                .animation(
                                    bt.liveHeartRate > 0 ?
                                        Animation.easeInOut(duration: 60.0 / Double(max(bt.liveHeartRate, 60))).repeatForever(autoreverses: true) :
                                        .default,
                                    value: heartPulsing
                                )
                            Text("LIVE HEART RATE")
                                .font(.caption.bold())
                                .foregroundColor(.gray)
                            Spacer()
                        }
                        
                        HStack(alignment: .firstTextBaseline) {
                            Text(bt.liveHeartRate > 0 ? "\(bt.liveHeartRate)" : "--")
                                .font(.system(size: 64, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("BPM")
                                .font(.headline)
                                .foregroundColor(.gray)
                            Spacer()
                        }
                    }
                    .padding(20)
                    .background(Color(white: 0.12))
                    .cornerRadius(16)
                    .padding(.horizontal)
                    .onAppear {
                        heartPulsing = true
                    }

                    // Vitals Grid (HRV, Resting HR, SpO2, Status)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        
                        // HRV Card (The main goal for Bevel!)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("HRV (SDNN)")
                                .font(.caption.bold())
                                .foregroundColor(.purple)
                            Text(bt.computedSDNN > 0 ? String(format: "%.1f", bt.computedSDNN) : "--")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("Milliseconds")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(white: 0.12))
                        .cornerRadius(16)

                        // Resting Heart Rate
                        VStack(alignment: .leading, spacing: 8) {
                            Text("RESTING HR")
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                            Text(bt.computedRestingHR > 0 ? "\(bt.computedRestingHR)" : "--")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("BPM Baseline")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(white: 0.12))
                        .cornerRadius(16)

                        // Blood Oxygen
                        VStack(alignment: .leading, spacing: 8) {
                            Text("BLOOD OXYGEN")
                                .font(.caption.bold())
                                .foregroundColor(.blue)
                            Text(bt.spo2Records.last != nil ? String(format: "%.0f%%", bt.spo2Records.last!.percent * 100) : "--")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("SpO2 Latest")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(white: 0.12))
                        .cornerRadius(16)

                        // Samples Synced
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SAMPLES SYNCED")
                                .font(.caption.bold())
                                .foregroundColor(.green)
                            Text("\(bt.hrRecords.count)")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("Records in Memory")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(white: 0.12))
                        .cornerRadius(16)
                    }
                    .padding(.horizontal)

                    // Status Bar
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.gray)
                        Text(bt.lastSyncStatus)
                            .font(.footnote)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding(.horizontal)

                    Spacer().frame(height: 20)

                    // Big Action Buttons
                    VStack(spacing: 14) {
                        Button(action: {
                            isSyncing = true
                            bt.syncVitals()
                            
                            // Auto save to HealthKit after 5s data gather
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                                hk.saveAllVitals(
                                    sdnn: bt.computedSDNN,
                                    restingHR: bt.computedRestingHR,
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
                            HStack {
                                if isSyncing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .padding(.trailing, 8)
                                } else {
                                    Image(systemName: "heart.text.square.fill")
                                        .font(.headline)
                                }
                                Text("Sync to Apple Health & Bevel")
                                    .font(.headline)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(bt.isConnected ? Color.blue : Color.gray)
                            .cornerRadius(14)
                        }
                        .disabled(!bt.isConnected || isSyncing)

                        if !bt.isConnected {
                            Button(action: {
                                bt.startScan()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Scan for Air Band")
                                }
                                .foregroundColor(.blue)
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Bevel Badge
                    Text("Compatible with Bevel Health & Apple HealthKit")
                        .font(.caption2)
                        .foregroundColor(Color(white: 0.4))
                        .padding(.top, 8)
                }
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("HealthKit Sync"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
}
