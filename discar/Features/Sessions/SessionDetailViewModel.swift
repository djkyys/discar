//
//  SessionDetailViewModel.swift
//  discar
//

import Foundation
import Combine

@MainActor
class SessionDetailViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var accelerometerCount = 0
    @Published var gyroscopeCount = 0
    @Published var magnetometerCount = 0
    @Published var barometerCount = 0
    @Published var gpsCount = 0
    @Published var deviceMotionCount = 0
    @Published var headphoneMotionCount = 0 // Added
    @Published var headingCount = 0
    
    private let session: Session
    
    init(session: Session) {
        self.session = session
    }
    
    func loadSessionData() async {
        isLoading = true
        
        let storage = StorageService.shared
        
        // Capture session properties to avoid Sendable issues
        let sessionCopy = session
        
        // Load counts in parallel
        async let accel = storage.getSensorDataCount(session: sessionCopy, filename: "accelerometer.json")
        async let gyro = storage.getSensorDataCount(session: sessionCopy, filename: "gyroscope.json")
        async let mag = storage.getSensorDataCount(session: sessionCopy, filename: "magnetometer.json")
        async let baro = storage.getSensorDataCount(session: sessionCopy, filename: "barometer.json")
        async let gps = storage.getSensorDataCount(session: sessionCopy, filename: "gps.json")
        async let motion = storage.getSensorDataCount(session: sessionCopy, filename: "devicemotion.json")
        async let headphone = storage.getSensorDataCount(session: sessionCopy, filename: "headphonemotion.json") // Added
        async let heading = storage.getSensorDataCount(session: sessionCopy, filename: "heading.json")
        
        let results = await (accel, gyro, mag, baro, gps, motion, headphone, heading)
        
        accelerometerCount = results.0
        gyroscopeCount = results.1
        magnetometerCount = results.2
        barometerCount = results.3
        gpsCount = results.4
        deviceMotionCount = results.5
        headphoneMotionCount = results.6 // Added
        headingCount = results.7
        
        isLoading = false
    }
}
