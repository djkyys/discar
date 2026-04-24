//
//  SensorHealth.swift
//  discar
//

import Foundation

/// Represents the health status of all sensors during recording
struct SensorHealth {

    /// Status of an individual sensor
    enum Status: Equatable {
        case notAvailable       // Hardware not present
        case inactive           // Available but not started
        case active             // Receiving data
        case failed(String)     // Started but stopped working

        var isWorking: Bool {
            if case .active = self { return true }
            return false
        }

        var displayName: String {
            switch self {
            case .notAvailable: return "N/A"
            case .inactive: return "Off"
            case .active: return "Active"
            case .failed(let reason): return reason
            }
        }
    }

    /// All tracked sensors - using existing SensorType enum where applicable
    var accelerometer: Status = .inactive
    var gyroscope: Status = .inactive
    var magnetometer: Status = .inactive
    var barometer: Status = .inactive
    var gps: Status = .inactive
    var deviceMotion: Status = .inactive
    var headphoneMotion: Status = .inactive
    var compass: Status = .inactive

    // MARK: - Computed Properties

    /// Number of sensors currently receiving data
    var activeCount: Int {
        allStatuses.filter { $0.status.isWorking }.count
    }

    /// Total number of sensors that should be available (excluding notAvailable)
    var availableCount: Int {
        allStatuses.filter { entry in
            if case .notAvailable = entry.status { return false }
            return true
        }.count
    }

    /// Total sensors being tracked
    var totalCount: Int {
        allStatuses.count
    }

    /// Summary string like "7/8 active"
    var summary: String {
        "\(activeCount)/\(availableCount) active"
    }

    /// Whether any sensor has failed
    var hasFailures: Bool {
        allStatuses.contains { entry in
            if case .failed = entry.status { return true }
            return false
        }
    }

    /// Whether all available sensors are working
    var isHealthy: Bool {
        activeCount == availableCount && availableCount > 0
    }

    /// List of failed sensors with reasons
    var failures: [(name: String, reason: String)] {
        allStatuses.compactMap { entry in
            if case .failed(let reason) = entry.status {
                return (name: entry.name, reason: reason)
            }
            return nil
        }
    }

    /// All statuses for iteration
    var allStatuses: [(name: String, shortName: String, icon: String, status: Status)] {
        [
            ("Accelerometer", "Accel", "arrow.up.arrow.down", accelerometer),
            ("Gyroscope", "Gyro", "gyroscope", gyroscope),
            ("Magnetometer", "Mag", "magnet", magnetometer),
            ("Barometer", "Baro", "barometer", barometer),
            ("GPS", "GPS", "location.fill", gps),
            ("Device Motion", "Motion", "iphone.gen3", deviceMotion),
            ("AirPods Motion", "AirPods", "airpodspro", headphoneMotion),
            ("Compass", "Compass", "location.north.fill", compass)
        ]
    }

    // MARK: - Mutating Methods

    /// Update a specific sensor status
    mutating func update(_ sensor: HealthSensor, status: Status) {
        switch sensor {
        case .accelerometer:
            accelerometer = status
        case .gyroscope:
            gyroscope = status
        case .magnetometer:
            magnetometer = status
        case .barometer:
            barometer = status
        case .gps:
            gps = status
        case .deviceMotion:
            deviceMotion = status
        case .headphoneMotion:
            headphoneMotion = status
        case .compass:
            compass = status
        }
    }

    /// Reset all sensors to inactive
    mutating func reset() {
        accelerometer = .inactive
        gyroscope = .inactive
        magnetometer = .inactive
        barometer = .inactive
        gps = .inactive
        deviceMotion = .inactive
        headphoneMotion = .inactive
        compass = .inactive
    }

    /// Initialize sensors based on availability
    mutating func initializeAvailability(
        hasAccelerometer: Bool,
        hasGyroscope: Bool,
        hasMagnetometer: Bool,
        hasBarometer: Bool,
        hasGPS: Bool,
        hasDeviceMotion: Bool,
        hasHeadphoneMotion: Bool,
        hasCompass: Bool
    ) {
        accelerometer = hasAccelerometer ? .inactive : .notAvailable
        gyroscope = hasGyroscope ? .inactive : .notAvailable
        magnetometer = hasMagnetometer ? .inactive : .notAvailable
        barometer = hasBarometer ? .inactive : .notAvailable
        gps = hasGPS ? .inactive : .notAvailable
        deviceMotion = hasDeviceMotion ? .inactive : .notAvailable
        headphoneMotion = hasHeadphoneMotion ? .inactive : .notAvailable
        compass = hasCompass ? .inactive : .notAvailable
    }
}

/// Sensor types for health tracking (separate from data SensorType to avoid coupling)
enum HealthSensor: String, CaseIterable {
    case accelerometer
    case gyroscope
    case magnetometer
    case barometer
    case gps
    case deviceMotion
    case headphoneMotion
    case compass
}
