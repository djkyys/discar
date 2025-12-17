//
//  WatchModels.swift
//  discarWatch Watch App
//
//  Created by Drogba on 2025/11/24.
//

import Foundation

// MARK: - Sensor Data Models
// These mirror the phone models to ensure compatibility.
// Ideally, SensorData.swift should be shared between targets.

struct WatchAccelerometerReading: Codable {
    let t: Double
    let x: Double
    let y: Double
    let z: Double
}

struct WatchGyroscopeReading: Codable {
    let t: Double
    let x: Double
    let y: Double
    let z: Double
}

struct WatchHeartRateReading: Codable {
    let t: Double
    let bpm: Double
}

struct WatchECGReading: Codable {
    let t: Double
    let voltage: Double
}

struct WatchBloodOxygenReading: Codable {
    let t: Double
    let percentage: Double
}

struct WatchTemperatureReading: Codable {
    let t: Double
    let delta: Double
}

struct WatchCompassReading: Codable {
    let t: Double
    let heading: Double
}

struct WatchBarometerReading: Codable {
    let t: Double
    let pressure: Double
}

struct WatchSessionMetadata: Codable {
    let id: String
    let date: String
    let duration: Double
    let sensorFiles: [String]
}
