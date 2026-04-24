//
//  SensorType.swift
//  discar
//

import Foundation
import SwiftUI

enum SensorType: String, CaseIterable {
    case accelerometer
    case gyroscope
    case magnetometer
    case barometer
    case gps
    case deviceMotion
    case heading
    case headphoneMotion
    case gravity
    case orientation

    var displayName: String {
        switch self {
        case .accelerometer: return "Accelerometer"
        case .gyroscope: return "Gyroscope"
        case .magnetometer: return "Magnetometer"
        case .barometer: return "Barometer"
        case .gps: return "GPS"
        case .deviceMotion: return "Device Motion"
        case .heading: return "Heading (Compass)"
        case .headphoneMotion: return "AirPods Motion"
        case .gravity: return "Gravity"
        case .orientation: return "Orientation"
        }
    }

    var filename: String {
        switch self {
        case .accelerometer: return "accelerometer.csv"
        case .gyroscope: return "gyroscope.csv"
        case .magnetometer: return "magnetometer.csv"
        case .barometer: return "barometer.csv"
        case .gps: return "gps.csv"
        case .deviceMotion: return "devicemotion.csv"
        case .heading: return "heading.csv"
        case .headphoneMotion: return "headphonemotion.csv"
        case .gravity: return "gravity.csv"
        case .orientation: return "orientation.csv"
        }
    }

    /// SF Symbol icon for this sensor type
    var icon: String {
        switch self {
        case .accelerometer: return "move.3d"
        case .gyroscope: return "gyroscope"
        case .magnetometer: return "dot.radiowaves.right"
        case .barometer: return "barometer"
        case .gps: return "location.fill"
        case .deviceMotion: return "sensor.fill"
        case .heading: return "location.north.fill"
        case .headphoneMotion: return "airpodspro"
        case .gravity: return "arrow.down.circle.fill"
        case .orientation: return "rotate.3d"
        }
    }

    /// Display color for this sensor type
    var color: Color {
        switch self {
        case .accelerometer: return .blue
        case .gyroscope: return .green
        case .magnetometer: return .purple
        case .barometer: return .orange
        case .gps: return .red
        case .deviceMotion: return .cyan
        case .heading: return .indigo
        case .headphoneMotion: return .mint
        case .gravity: return .teal
        case .orientation: return .pink
        }
    }

    /// Short name for compact display
    var shortName: String {
        switch self {
        case .accelerometer: return "Accel"
        case .gyroscope: return "Gyro"
        case .magnetometer: return "Mag"
        case .barometer: return "Baro"
        case .gps: return "GPS"
        case .deviceMotion: return "Motion"
        case .heading: return "Compass"
        case .headphoneMotion: return "AirPods"
        case .gravity: return "Gravity"
        case .orientation: return "Orient"
        }
    }

    /// Get SensorType from a display name string (case-insensitive matching)
    static func from(name: String) -> SensorType? {
        let lowercased = name.lowercased()
        if lowercased.contains("accelerometer") { return .accelerometer }
        if lowercased.contains("gyro") { return .gyroscope }
        if lowercased.contains("magnet") { return .magnetometer }
        if lowercased.contains("barometer") || lowercased.contains("altitude") { return .barometer }
        if lowercased.contains("gps") || lowercased.contains("location") { return .gps }
        if lowercased.contains("device") && lowercased.contains("motion") { return .deviceMotion }
        if lowercased.contains("heading") || lowercased.contains("compass") { return .heading }
        if lowercased.contains("airpods") || lowercased.contains("headphone") { return .headphoneMotion }
        if lowercased.contains("gravity") { return .gravity }
        if lowercased.contains("orientation") { return .orientation }
        return nil
    }
}

enum DataError: Error {
    case fileNotFound
    case invalidData
}
