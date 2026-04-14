//
//  SensorType.swift
//  discar
//

import Foundation

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
}

enum DataError: Error {
    case fileNotFound
    case invalidData
}
