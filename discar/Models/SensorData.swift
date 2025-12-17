//
//  SensorData.swift
//  discar
//

import Foundation

// MARK: - Raw Sensors

struct AccelerometerReading: Codable {
    let t: Double  // timestamp
    let x: Double
    let y: Double
    let z: Double
}

struct GyroscopeReading: Codable {
    let t: Double
    let x: Double
    let y: Double
    let z: Double
}

struct MagnetometerReading: Codable {
    let t: Double
    let x: Double
    let y: Double
    let z: Double
}

struct BarometerReading: Codable {
    let t: Double
    let pressure: Double  // kPa
}

struct GPSReading: Codable {
    let t: Double
    let lat: Double
    let lon: Double
    let altitude: Double
    let speed: Double
    let course: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
}

// MARK: - Fused Sensors

struct DeviceMotionReading: Codable {
    let t: Double
    let attitude: Attitude
    let userAcceleration: Vector3
    let gravity: Vector3
    let rotationRate: Vector3
}

struct Attitude: Codable {
    let roll: Double
    let pitch: Double
    let yaw: Double
}

struct Vector3: Codable {
    let x: Double
    let y: Double
    let z: Double
}

struct HeadingReading: Codable {
    let t: Double
    let magneticHeading: Double
    let trueHeading: Double?
    let accuracy: Double
}

// MARK: - Session Metadata

struct SessionMetadata: Codable, Sendable {
    let id: String
    let date: String  // ISO 8601
    let duration: Double
    let sensorFiles: [String]
}

