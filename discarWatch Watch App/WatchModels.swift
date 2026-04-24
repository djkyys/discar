//
//  WatchModels.swift
//  discarWatch Watch App
//
//  Created by Drogba on 2025/11/24.
//

import Foundation

// MARK: - CSV Protocol (matches iOS)

protocol WatchCSVConvertible {
    static var csvHeader: String { get }
    var csvRow: String { get }
}

// MARK: - Timezone Helper

enum WatchTimeFormatter {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "Australia/Melbourne")
        return f
    }()

    static func format(_ date: Date) -> String {
        formatter.string(from: date)
    }
}

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

// MARK: - Heart Rate

struct WatchHeartRateReading: Codable, WatchCSVConvertible {
    let time: Double
    let datetime: String
    let bpm: Double

    static var csvHeader: String { "time,datetime,bpm" }
    var csvRow: String { "\(time),\(datetime),\(bpm)" }
}

// MARK: - Wrist Motion (Device Motion)

struct WatchDeviceMotionReading: Codable, WatchCSVConvertible {
    let time: Double
    let datetime: String
    let attitude: WatchAttitude
    let quaternion: WatchQuaternion
    let rotationMatrix: WatchRotationMatrix
    let userAcceleration: WatchVector3
    let gravity: WatchVector3
    let rotationRate: WatchVector3
    let magneticField: WatchCalibratedMagneticField?
    let heading: Double?

    static var csvHeader: String {
        "time,datetime,roll,pitch,yaw,qx,qy,qz,qw,m11,m12,m13,m21,m22,m23,m31,m32,m33,uax,uay,uaz,gx,gy,gz,rx,ry,rz,mfx,mfy,mfz,mfAccuracy,heading"
    }

    var csvRow: String {
        let mf = magneticField
        return "\(time),\(datetime),\(attitude.roll),\(attitude.pitch),\(attitude.yaw),\(quaternion.x),\(quaternion.y),\(quaternion.z),\(quaternion.w),\(rotationMatrix.m11),\(rotationMatrix.m12),\(rotationMatrix.m13),\(rotationMatrix.m21),\(rotationMatrix.m22),\(rotationMatrix.m23),\(rotationMatrix.m31),\(rotationMatrix.m32),\(rotationMatrix.m33),\(userAcceleration.x),\(userAcceleration.y),\(userAcceleration.z),\(gravity.x),\(gravity.y),\(gravity.z),\(rotationRate.x),\(rotationRate.y),\(rotationRate.z),\(mf?.x ?? 0),\(mf?.y ?? 0),\(mf?.z ?? 0),\(mf?.accuracy ?? -1),\(heading ?? -1)"
    }
}

// MARK: - Compass

struct WatchCompassReading: Codable, WatchCSVConvertible {
    let time: Double
    let datetime: String
    let heading: Double
    let accuracy: Double?

    static var csvHeader: String { "time,datetime,heading,accuracy" }
    var csvRow: String { "\(time),\(datetime),\(heading),\(accuracy ?? -1)" }
}

// MARK: - Barometer

struct WatchBarometerReading: Codable, WatchCSVConvertible {
    let time: Double
    let datetime: String
    let pressure: Double
    let relativeAltitude: Double?

    static var csvHeader: String { "time,datetime,pressure,relativeAltitude" }
    var csvRow: String { "\(time),\(datetime),\(pressure),\(relativeAltitude ?? 0)" }
}

// MARK: - Session Metadata

struct WatchSessionMetadata: Codable {
    let id: String
    let date: String
    let duration: Double
    let sensorFiles: [String]
}
