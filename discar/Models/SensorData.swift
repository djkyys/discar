//
//  SensorData.swift
//  discar
//

import Foundation

// MARK: - CSV Protocol

protocol CSVConvertible: Sendable {
    nonisolated static var csvHeader: String { get }
    nonisolated var csvRow: String { get }
}

protocol CSVParsable {
    nonisolated static func fromCSV(_ row: String) -> Self?
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

struct AccelerometerReading: Codable, CSVConvertible, CSVParsable {
    let time: Double  // seconds elapsed
    let datetime: String  // Melbourne time
    let x: Double
    let y: Double
    let z: Double

    static var csvHeader: String { "time,datetime,x,y,z" }
    var csvRow: String { "\(time),\(datetime),\(x),\(y),\(z)" }

    nonisolated static func fromCSV(_ row: String) -> AccelerometerReading? {
        let cols = row.components(separatedBy: ",")
        guard cols.count >= 5,
              let time = Double(cols[0]),
              let x = Double(cols[2]),
              let y = Double(cols[3]),
              let z = Double(cols[4]) else { return nil }
        return AccelerometerReading(time: time, datetime: cols[1], x: x, y: y, z: z)
    }
}

struct GyroscopeReading: Codable, CSVConvertible, CSVParsable {
    let time: Double
    let datetime: String
    let x: Double
    let y: Double
    let z: Double

    static var csvHeader: String { "time,datetime,x,y,z" }
    var csvRow: String { "\(time),\(datetime),\(x),\(y),\(z)" }

    nonisolated static func fromCSV(_ row: String) -> GyroscopeReading? {
        let cols = row.components(separatedBy: ",")
        guard cols.count >= 5,
              let time = Double(cols[0]),
              let x = Double(cols[2]),
              let y = Double(cols[3]),
              let z = Double(cols[4]) else { return nil }
        return GyroscopeReading(time: time, datetime: cols[1], x: x, y: y, z: z)
    }
}

struct MagnetometerReading: Codable, CSVConvertible, CSVParsable {
    let time: Double
    let datetime: String
    let x: Double
    let y: Double
    let z: Double

    static var csvHeader: String { "time,datetime,x,y,z" }
    var csvRow: String { "\(time),\(datetime),\(x),\(y),\(z)" }

    nonisolated static func fromCSV(_ row: String) -> MagnetometerReading? {
        let cols = row.components(separatedBy: ",")
        guard cols.count >= 5,
              let time = Double(cols[0]),
              let x = Double(cols[2]),
              let y = Double(cols[3]),
              let z = Double(cols[4]) else { return nil }
        return MagnetometerReading(time: time, datetime: cols[1], x: x, y: y, z: z)
    }
}

struct BarometerReading: Codable, CSVConvertible, CSVParsable {
    let time: Double
    let datetime: String
    let pressure: Double  // kPa
    let relativeAltitude: Double?  // meters, change since start

    static var csvHeader: String { "time,datetime,pressure,relativeAltitude" }
    var csvRow: String { "\(time),\(datetime),\(pressure),\(relativeAltitude ?? 0)" }

    nonisolated static func fromCSV(_ row: String) -> BarometerReading? {
        let cols = row.components(separatedBy: ",")
        guard cols.count >= 4,
              let time = Double(cols[0]),
              let pressure = Double(cols[2]) else { return nil }
        let relativeAltitude = Double(cols[3])
        return BarometerReading(time: time, datetime: cols[1], pressure: pressure, relativeAltitude: relativeAltitude)
    }
}

struct GPSReading: Codable, CSVConvertible, CSVParsable {
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

    nonisolated static func fromCSV(_ row: String) -> GPSReading? {
        let cols = row.components(separatedBy: ",")
        guard cols.count >= 13,
              let time = Double(cols[0]),
              let lat = Double(cols[2]),
              let lon = Double(cols[3]),
              let altitude = Double(cols[4]),
              let speed = Double(cols[6]),
              let course = Double(cols[8]),
              let horizontalAccuracy = Double(cols[10]),
              let verticalAccuracy = Double(cols[11]) else { return nil }
        let ellipsoidalAltitude = Double(cols[5]).flatMap { $0 == 0 ? nil : $0 }
        let speedAccuracy = Double(cols[7]).flatMap { $0 == -1 ? nil : $0 }
        let courseAccuracy = Double(cols[9]).flatMap { $0 == -1 ? nil : $0 }
        let floor = Int(cols[12]).flatMap { $0 == -1 ? nil : $0 }
        return GPSReading(time: time, datetime: cols[1], lat: lat, lon: lon, altitude: altitude,
                          ellipsoidalAltitude: ellipsoidalAltitude, speed: speed, speedAccuracy: speedAccuracy,
                          course: course, courseAccuracy: courseAccuracy, horizontalAccuracy: horizontalAccuracy,
                          verticalAccuracy: verticalAccuracy, floor: floor)
    }
}

// MARK: - Fused Sensors

struct DeviceMotionReading: Codable, CSVConvertible, CSVParsable {
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

    nonisolated static func fromCSV(_ row: String) -> DeviceMotionReading? {
        let cols = row.components(separatedBy: ",")
        guard cols.count >= 32,
              let time = Double(cols[0]),
              let roll = Double(cols[2]), let pitch = Double(cols[3]), let yaw = Double(cols[4]),
              let qx = Double(cols[5]), let qy = Double(cols[6]), let qz = Double(cols[7]), let qw = Double(cols[8]),
              let m11 = Double(cols[9]), let m12 = Double(cols[10]), let m13 = Double(cols[11]),
              let m21 = Double(cols[12]), let m22 = Double(cols[13]), let m23 = Double(cols[14]),
              let m31 = Double(cols[15]), let m32 = Double(cols[16]), let m33 = Double(cols[17]),
              let uax = Double(cols[18]), let uay = Double(cols[19]), let uaz = Double(cols[20]),
              let gx = Double(cols[21]), let gy = Double(cols[22]), let gz = Double(cols[23]),
              let rx = Double(cols[24]), let ry = Double(cols[25]), let rz = Double(cols[26]) else { return nil }

        let mfx = Double(cols[27]) ?? 0
        let mfy = Double(cols[28]) ?? 0
        let mfz = Double(cols[29]) ?? 0
        let mfAccuracy = Int(cols[30]) ?? -1
        let magneticField = mfAccuracy >= 0 ? CalibratedMagneticField(x: mfx, y: mfy, z: mfz, accuracy: mfAccuracy) : nil
        let heading = Double(cols[31]).flatMap { $0 == -1 ? nil : $0 }

        return DeviceMotionReading(
            time: time, datetime: cols[1],
            attitude: Attitude(roll: roll, pitch: pitch, yaw: yaw),
            quaternion: Quaternion(x: qx, y: qy, z: qz, w: qw),
            rotationMatrix: RotationMatrix(m11: m11, m12: m12, m13: m13, m21: m21, m22: m22, m23: m23, m31: m31, m32: m32, m33: m33),
            userAcceleration: Vector3(x: uax, y: uay, z: uaz),
            gravity: Vector3(x: gx, y: gy, z: gz),
            rotationRate: Vector3(x: rx, y: ry, z: rz),
            magneticField: magneticField,
            heading: heading
        )
    }
}

// MARK: - Separated Sensor Files

struct GravityReading: Codable, CSVConvertible, CSVParsable {
    let time: Double
    let datetime: String
    let x: Double
    let y: Double
    let z: Double

    static var csvHeader: String { "time,datetime,x,y,z" }
    var csvRow: String { "\(time),\(datetime),\(x),\(y),\(z)" }

    nonisolated static func fromCSV(_ row: String) -> GravityReading? {
        let cols = row.components(separatedBy: ",")
        guard cols.count >= 5,
              let time = Double(cols[0]),
              let x = Double(cols[2]),
              let y = Double(cols[3]),
              let z = Double(cols[4]) else { return nil }
        return GravityReading(time: time, datetime: cols[1], x: x, y: y, z: z)
    }
}

struct OrientationReading: Codable, CSVConvertible, CSVParsable {
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

    nonisolated static func fromCSV(_ row: String) -> OrientationReading? {
        let cols = row.components(separatedBy: ",")
        guard cols.count >= 9,
              let time = Double(cols[0]),
              let yaw = Double(cols[2]),
              let roll = Double(cols[3]),
              let pitch = Double(cols[4]),
              let qx = Double(cols[5]),
              let qy = Double(cols[6]),
              let qz = Double(cols[7]),
              let qw = Double(cols[8]) else { return nil }
        return OrientationReading(time: time, datetime: cols[1], yaw: yaw, roll: roll, pitch: pitch, qx: qx, qy: qy, qz: qz, qw: qw)
    }
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

struct HeadingReading: Codable, CSVConvertible, CSVParsable {
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

    nonisolated static func fromCSV(_ row: String) -> HeadingReading? {
        let cols = row.components(separatedBy: ",")
        guard cols.count >= 8,
              let time = Double(cols[0]),
              let magneticHeading = Double(cols[2]),
              let accuracy = Double(cols[4]) else { return nil }
        let trueHeading = Double(cols[3]).flatMap { $0 == -1 ? nil : $0 }
        let x = Double(cols[5]).flatMap { $0 == 0 ? nil : $0 }
        let y = Double(cols[6]).flatMap { $0 == 0 ? nil : $0 }
        let z = Double(cols[7]).flatMap { $0 == 0 ? nil : $0 }
        return HeadingReading(time: time, datetime: cols[1], magneticHeading: magneticHeading, trueHeading: trueHeading, accuracy: accuracy, x: x, y: y, z: z)
    }
}

// MARK: - Session Metadata

struct SessionMetadata: Codable, Sendable {
    let id: String
    let date: String  // ISO 8601
    let duration: Double
    let sensorFiles: [String]
}

