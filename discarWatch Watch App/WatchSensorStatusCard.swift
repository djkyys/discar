//
//  WatchSensorStatusCard.swift
//  discarWatch Watch App
//
//  Created by Drogba on 2025/11/24.
//

import SwiftUI
import CoreMotion
import HealthKit

struct WatchSensorStatusCard: View {
    @State private var sensorStatus: [String: Bool] = [:]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sensors")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 4) {
                statusRow(name: "Motion", icon: "figure.walk", isAvailable: sensorStatus["Motion"] ?? false)
                statusRow(name: "GPS", icon: "location.fill", isAvailable: sensorStatus["GPS"] ?? false)
                statusRow(name: "Heart", icon: "heart.fill", isAvailable: sensorStatus["Heart"] ?? false)
                statusRow(name: "Temp", icon: "thermometer", isAvailable: sensorStatus["Temp"] ?? false)
                statusRow(name: "Env", icon: "barometer", isAvailable: sensorStatus["Env"] ?? false)
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(10)
        .onAppear {
            checkSensors()
        }
    }
    
    private func statusRow(name: String, icon: String, isAvailable: Bool) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption2)
                .frame(width: 16)
                .foregroundStyle(isAvailable ? .green : .red)
            
            Text(name)
                .font(.caption2)
            
            Spacer()
            
            Circle()
                .fill(isAvailable ? Color.green : Color.red)
                .frame(width: 6, height: 6)
        }
    }
    
    private func checkSensors() {
        let motion = CMMotionManager()
        
        var status: [String: Bool] = [:]
        
        // Motion
        status["Motion"] = motion.isAccelerometerAvailable && motion.isGyroAvailable
        
        // GPS (Location Services)
        // Note: Actual authorization status is async, assuming available if hardware present for now
        status["GPS"] = true 
        
        // Heart (HealthKit)
        status["Heart"] = HKHealthStore.isHealthDataAvailable()

        // Temperature (HealthKit - body temperature)
        status["Temp"] = HKHealthStore.isHealthDataAvailable()

        // Environment (Barometer)
        status["Env"] = CMAltimeter.isRelativeAltitudeAvailable()
        
        self.sensorStatus = status
    }
}

