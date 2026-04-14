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
                statusRow(name: "Motion", icon: "gyroscope", isAvailable: sensorStatus["Motion"] ?? false)
                statusRow(name: "Compass", icon: "location.north.fill", isAvailable: sensorStatus["Compass"] ?? false)
                statusRow(name: "Heart", icon: "heart.fill", isAvailable: sensorStatus["Heart"] ?? false)
                statusRow(name: "Baro", icon: "barometer", isAvailable: sensorStatus["Baro"] ?? false)
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
        
        // Motion (Device Motion - fused accel + gyro + magnetometer)
        status["Motion"] = motion.isDeviceMotionAvailable
        
        // Compass (Heading from CLLocationManager)
        status["Compass"] = CLLocationManager.headingAvailable()
        
        // Heart (HealthKit available + workout write permission granted)
        // Note: We can only check WRITE permissions, not READ permissions (Apple privacy policy)
        let healthStore = HKHealthStore()
        let healthKitAvailable = HKHealthStore.isHealthDataAvailable()
        let workoutType = HKQuantityType.workoutType()
        let workoutGranted = healthStore.authorizationStatus(for: workoutType) == .sharingAuthorized

        status["Heart"] = healthKitAvailable && workoutGranted

        // Barometer
        status["Baro"] = CMAltimeter.isRelativeAltitudeAvailable()
        
        self.sensorStatus = status
    }
}
                 
