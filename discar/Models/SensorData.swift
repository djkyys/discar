//
//  SensorData.swift
//  discar
//

import Foundation

// MARK: - CSV Protocol

protocol CSVConvertible {
    static var csvHeader: String { get }
    var csvRow: String { get }
}

// MARK: - Basic Types

struct Vector3: Codable {
    let x: Double
    let y: Double
    let z: Double
}

struct Quaternion: Codable {
    let x: Double
    let y: Double
    let z: Double
    let w: Double
}

struct RotationMatrix: Codable {
    let m11: Double, m12: Double, m13: Double
    let m21: Double, m22: Double, m23: Double
    let m31: Double, m32: Double, m33: Double
}

// MARK: - Raw Sensors

struct AccelerometerReading: Codable, CSVConvertible {
    let time: Double  // seconds elapsed
    let datetime: String  // Melbourne time
    let x: Double
    let y: Double
    let z: Double

    static var csvHeader: String { "time,datetime,x,y,z" }
    var csvRow: String { "\(time),\(datetime),\(x),\(y),\(z)" }
}

struct GyroscopeReading: Codable, CSVConvertible {
    let time: Double
    let datetime: String
    let x: Double
    let y: Double
    let z: Double

    static var csvHeader: String { "time,datetime,x,y,z" }
    var csvRow: String { "\(time),\(datetime),\(x),\(y),\(z)" }
}

struct MagnetometerReading: Codable, CSVConvertible {
    let time: Double
    let datetime: String
    let x: Double
    let y: Double
    let z: Double

    static var csvHeader: String { "time,datetime,x,y,z" }
    var csvRow: String { "\(time),\(datetime),\(x),\(y),\(z)" }
}

struct BarometerReading: Codable, CSVConvertible {
    let time: Double
    let datetime: String
    let pressure: Double  // kPa
    let relativeAltitude: Double?  // meters, change since start

    static var csvHeader: String { "time,datetime,pressure,relativeAltitude" }
    var csvRow: String { "\(time),\(datetime),\(pressure),\(relativeAltitude ?? 0)" }
}

struct GPSReading: Codable, CSVConvertible {
    let time: Double
    let datetime: String
    let lat: Double
    let lon: Double
    let altitude: Double
    let ellipsoidalAltitude: Double?  // WGS84 altitude (iOS 15+)
    let speed: Double
    let speedAccuracy: Double?  // iOS 10+
    let course: Double
    let courseAccuracy: Double?  // iOS 13.4+
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let floor: Int?  // indoor floor level if available

    static var csvHeader: String { "time,datetime,lat,lon,altitude,ellipsoidalAltitude,speed,speedAccuracy,course,courseAccuracy,horizontalAccuracy,verticalAccuracy,floor" }
    var csvRow: String {
        "\(time),\(datetime),\(lat),\(lon),\(altitude),\(ellipsoidalAltitude ?? 0),\(speed),\(speedAccuracy ?? -1),\(course),\(courseAccuracy ?? -1),\(horizontalAccuracy),\(verticalAccuracy),\(floor ?? -1)"
    }
}

// MARK: - Fused Sensors

struct DeviceMotionReading: Codable, CSVConvertible {
    let time: Double
    let datetime: String
    let attitude: Attitude
    let quaternion: Quaternion
    let rotationMatrix: RotationMatrix
    let userAcceleration: Vector3
    let gravity: Vector3
    let rotationRate: Vector3
    let magneticField: CalibratedMagneticField?
    let heading: Double?  // heading relative to reference frame

    static var csvHeader: String {
        "time,datetime,roll,pitch,yaw,qx,qy,qz,qw,m11,m12,m13,m21,m22,m23,m31,m32,m33,uax,uay,uaz,gx,gy,gz,rx,ry,rz,mfx,mfy,mfz,mfAccuracy,heading"
    }
    var csvRow: String {
        let mf = magneticField
        return "\(time),\(datetime),\(attitude.roll),\(attitude.pitch),\(attitude.yaw),\(quaternion.x),\(quaternion.y),\(quaternion.z),\(quaternion.w),\(rotationMatrix.m11),\(rotationMatrix.m12),\(rotationMatrix.m13),\(rotationMatrix.m21),\(rotationMatrix.m22),\(rotationMatrix.m23),\(rotationMatrix.m31),\(rotationMatrix.m32),\(rotationMatrix.m33),\(userAcceleration.x),\(userAcceleration.y),\(userAcceleration.z),\(gravity.x),\(gravity.y),\(gravity.z),\(rotationRate.x),\(rotationRate.y),\(rotationRate.z),\(mf?.x ?? 0),\(mf?.y ?? 0),\(mf?.z ?? 0),\(mf?.accuracy ?? -1),\(heading ?? -1)"
    }
}

// MARK: - Separated Sensor Files

struct GravityReading: Codable, CSVConvertible {
    let time: Double
    let datetime: String
    let x: Double
    let y: Double
    let z: Double

    static var csvHeader: String { "time,datetime,x,y,z" }
    var csvRow: String { "\(time),\(datetime),\(x),\(y),\(z)" }
}

struct OrientationReading: Codable, CSVConvertible {
    let time: Double
    let datetime: String
    let yaw: Double
    let roll: Double
    let pitch: Double
    let qx: Double
    let qy: Double
    let qz: Double
    let qw: Double

    static var csvHeader: String { "time,datetime,yaw,roll,pitch,qx,qy,qz,qw" }
    var csvRow: String { "\(time),\(datetime),\(yaw),\(roll),\(pitch),\(qx),\(qy),\(qz),\(qw)" }
}

struct Attitude: Codable {
    let roll: Double
    let pitch: Double
    let yaw: Double
}

struct CalibratedMagneticField: Codable {
    let x: Double
    let y: Double
    let z: Double
    let accuracy: Int  // -1=uncalibrated, 0=low, 1=medium, 2=high
}

struct HeadingReading: Codable, CSVConvertible {
    let time: Double
    let datetime: String
    let magneticHeading: Double
    let trueHeading: Double?
    let accuracy: Double
    // Raw geomagnetic values
    let x: Double?
    let y: Double?
    let z: Double?

    static var csvHeader: String { "time,datetime,magneticHeading,trueHeading,accuracy,x,y,z" }
    var csvRow: String {
        "\(time),\(datetime),\(magneticHeading),\(trueHeading ?? -1),\(accuracy),\(x ?? 0),\(y ?? 0),\(z ?? 0)"
    }
}

// MARK: - Session Metadata

struct SessionMetadata: Codable, Sendable {
    let id: String
    let date: String  // ISO 8601
    let duration: Double
    let sensorFiles: [String]
}

