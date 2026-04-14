//
//  WatchModels.swift
//  discarWatch Watch App
//
//  Created by Drogba on 2025/11/24.
//

import Foundation

// MARK: - Basic Types

struct WatchVector3: Codable {
    let x: Double
    let y: Double
    let z: Double
}

struct WatchQuaternion: Codable {
    let x: Double
    let y: Double
    let z: Double
    let w: Double
}

struct WatchRotationMatrix: Codable {
    let m11: Double, m12: Double, m13: Double
    let m21: Double, m22: Double, m23: Double
    let m31: Double, m32: Double, m33: Double
}

// MARK: - Fused Device Motion

struct WatchDeviceMotionReading: Codable {
    let t: Double
    let attitude: WatchAttitude
    let quaternion: WatchQuaternion
    let rotationMatrix: WatchRotationMatrix
    let userAcceleration: WatchVector3
    let gravity: WatchVector3
    let rotationRate: WatchVector3
    let magneticField: WatchCalibratedMagneticField?
    let heading: Double?
}

struct WatchAttitude: Codable {
    let roll: Double
    let pitch: Double
    let yaw: Double
}

struct WatchCalibratedMagneticField: Codable {
    let x: Double
    let y: Double
    let z: Double
    let accuracy: Int  // -1=uncalibrated, 0=low, 1=medium, 2=high
}

// MARK: - Other Watch Sensors

struct WatchHeartRateReading: Codable {
    let t: Double
    let bpm: Double
}

struct WatchCompassReading: Codable {
    let t: Double
    let heading: Double
    let accuracy: Double?
}

struct WatchBarometerReading: Codable {
    let t: Double
    let pressure: Double
    let relativeAltitude: Double?
}

struct WatchSessionMetadata: Codable {
    let id: String
    let date: String
    let duration: Double
    let sensorFiles: [String]
}
