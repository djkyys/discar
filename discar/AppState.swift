//
//  AppState.swift
//  discar
//

import Foundation
import Combine
import CoreMotion
import CoreLocation
import AVFoundation // Added

@MainActor
class AppState: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var sensorStatus: [String: Bool] = [:]
    @Published var isCheckingSensors = true
    
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        
        // Set delegate to receive authorization updates
        locationManager.delegate = self
        
        // Observer for Audio Route Changes (AirPods connect/disconnect)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioRouteChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        
        // Start background sensor check immediately on app launch
        Task.detached(priority: .background) {
            await self.checkSensors()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func audioRouteChanged(notification: Notification) {
        print("🎧 Audio route changed, rechecking sensors...")
        refreshSensors()
    }
    
    private func checkSensors() async {
        #if DEBUG
        print("🔍 Background: Checking sensors...")
        #endif
        
        // All checks happen on background thread
        let motion = CMMotionManager()
        
        // Get authorization status on main actor
        let authStatus = await MainActor.run {
            locationManager.authorizationStatus
        }
        
        // Check GPS availability
        let gpsAvailable: Bool
        if authStatus == .notDetermined {
            gpsAvailable = false
        } else {
            gpsAvailable = (authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways)
        }
        
        // Check AirPods Connection (AVAudioSession)
        let audioSession = AVAudioSession.sharedInstance()
        
        // Run on MainActor to access currentRoute safely and log results
        let isAirPodsConnected = await MainActor.run {
            let outputs = audioSession.currentRoute.outputs
            
            #if DEBUG
            print("🔍 AppState Audio Outputs: \(outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", "))")
            #endif
            
            return outputs.contains { port in
                let isBluetooth = port.portType == .bluetoothA2DP ||
                                  port.portType == .bluetoothHFP ||
                                  port.portType == .bluetoothLE
                
                // Blacklist "T25M" (Speaker), but allow any other Bluetooth device (AirPods, Sony, etc.)
                let isNotBlacklisted = !port.portName.contains("T25M")
                
                return isBluetooth && isNotBlacklisted
            }
        }
        
        // AirPods Status:
        // We show TRUE if they are connected (Audio), even if Motion isn't available yet.
        // Ideally we want Motion, but "Connected" is better feedback for the user than "False".
        let airPodsAvailable = isAirPodsConnected
        
        let status: [String: Bool] = [
            "Accelerometer": motion.isAccelerometerAvailable,
            "Gyroscope": motion.isGyroAvailable,
            "Magnetometer": motion.isMagnetometerAvailable,
            "Device Motion": motion.isDeviceMotionAvailable,
            "AirPods Motion": airPodsAvailable, // Updated Logic
            "Barometer": CMAltimeter.isRelativeAltitudeAvailable(),
            "GPS": gpsAvailable,
            "Compass": CLLocationManager.headingAvailable()
        ]
        
        #if DEBUG
        print("✅ Background: Sensors checked")
        for (sensor, available) in status.sorted(by: { $0.key < $1.key }) {
            print("  \(available ? "✅" : "❌") \(sensor)")
        }
        #endif
        
        // Update on main thread
        await MainActor.run {
            self.sensorStatus = status
            self.isCheckingSensors = false
        }
    }
    
    // Manual refresh
    func refreshSensors() {
        isCheckingSensors = true
        Task.detached(priority: .background) {
            await self.checkSensors()
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let newAuthStatus = manager.authorizationStatus
            let newGpsAvailable = (newAuthStatus == .authorizedWhenInUse || newAuthStatus == .authorizedAlways)
            
            if !self.sensorStatus.isEmpty {
                self.sensorStatus["GPS"] = newGpsAvailable
                #if DEBUG
                print("📍 Location authorization changed: \(newAuthStatus.rawValue), GPS Available: \(newGpsAvailable)")
                #endif
            }
        }
    }
}
