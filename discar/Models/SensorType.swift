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
    case headphoneMotion // Added

    var displayName: String {
        switch self {
        case .accelerometer: return "Accelerometer"
        case .gyroscope: return "Gyroscope"
        case .magnetometer: return "Magnetometer"
        case .barometer: return "Barometer"
        case .gps: return "GPS"
        case .deviceMotion: return "Device Motion"
        case .heading: return "Heading (Compass)"
        case .headphoneMotion: return "AirPods Motion" // Added
        }
    }

    var filename: String {
        switch self {
        case .accelerometer: return "accelerometer.json"
        case .gyroscope: return "gyroscope.json"
        case .magnetometer: return "magnetometer.json"
        case .barometer: return "barometer.json"
        case .gps: return "gps.json"
        case .deviceMotion: return "devicemotion.json"
        case .heading: return "heading.json"
        case .headphoneMotion: return "headphonemotion.json" // Added
        }
    }
}

enum DataError: Error {
    case fileNotFound
    case invalidData
}
