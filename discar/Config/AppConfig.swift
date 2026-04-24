//
//  AppConfig.swift
//  discar
//
//  Centralized configuration - single source of truth for all settings
//

import Foundation

enum AppConfig: Sendable {

    // MARK: - Controller Connection

    enum Controller: Sendable {
        /// Controller IP address (user configurable)
        nonisolated(unsafe) static var ip: String {
            get { UserDefaults.standard.string(forKey: Keys.controllerIP) ?? Defaults.controllerIP }
            set { UserDefaults.standard.set(newValue, forKey: Keys.controllerIP) }
        }

        /// Base HTTP URL for REST API
        nonisolated static var baseURL: String { "http://\(ip):8000" }

        /// WebSocket URL for real-time updates
        nonisolated static var wsURL: String { "ws://\(ip):8000/ws/status" }

        /// API endpoint URLs
        nonisolated static var statusURL: URL? { URL(string: "\(baseURL)/api/status") }
        nonisolated static var startRecordURL: URL? { URL(string: "\(baseURL)/api/record/start") }
        nonisolated static var stopRecordURL: URL? { URL(string: "\(baseURL)/api/record/stop") }
        nonisolated static var syncPhoneURL: URL? { URL(string: "\(baseURL)/api/sync/phone") }
        nonisolated static var logURL: URL? { URL(string: "\(baseURL)/api/log") }
        nonisolated static var storageStatusURL: URL? { URL(string: "\(baseURL)/api/storage/status") }
        nonisolated static var remountURL: URL? { URL(string: "\(baseURL)/api/storage/remount") }
        nonisolated static var unmountURL: URL? { URL(string: "\(baseURL)/api/storage/unmount") }
        nonisolated static var canStatusURL: URL? { URL(string: "\(baseURL)/api/can/status") }
    }

    // MARK: - Recording Settings

    enum Recording: Sendable {
        /// Sensor sampling frequency in Hz
        nonisolated static let sensorFrequency: Double = 1.0

        /// Interval for flushing sensor buffers to disk (seconds)
        nonisolated static let bufferFlushInterval: TimeInterval = 10.0

        /// Interval for polling CAN status during recording (seconds)
        nonisolated static let canPollInterval: TimeInterval = 2.0

        /// Time before sensor is considered unhealthy (seconds)
        nonisolated static let sensorHealthTimeout: TimeInterval = 5.0
    }

    // MARK: - Network Timeouts

    enum Timeouts: Sendable {
        /// Default API request timeout
        nonisolated static let api: TimeInterval = 10.0

        /// Connection test timeout
        nonisolated static let connectionTest: TimeInterval = 5.0

        /// Watch data transfer timeout
        nonisolated static let watchTransfer: TimeInterval = 30.0

        /// WebSocket ping interval
        nonisolated static let wsPingInterval: TimeInterval = 25.0

        /// Max reconnection attempts for WebSocket
        nonisolated static let wsMaxReconnectAttempts = 10

        /// Remote logging timeout
        nonisolated static let logging: TimeInterval = 3.0

        /// Session upload timeout
        nonisolated static let sessionUpload: TimeInterval = 120.0
    }

    // MARK: - UI Settings

    enum UI: Sendable {
        /// Maximum points for chart display
        nonisolated static let chartMaxPoints = 100

        /// Number of rows in raw data preview
        nonisolated static let previewRowCount = 20
    }

    // MARK: - Export Settings

    enum Export: Sendable {
        /// Age after which temporary exports are deleted (seconds)
        nonisolated static let cleanupAge: TimeInterval = 3600  // 1 hour
    }

    // MARK: - App Info

    enum App: Sendable {
        nonisolated static let version = "1.0.0"
        nonisolated static let nodeName = "iphone"  // For remote logging
    }

    // MARK: - Private Keys & Defaults

    private enum Keys: Sendable {
        nonisolated static let controllerIP = "controllerIP"
        nonisolated static let darkModeEnabled = "darkModeEnabled"
        nonisolated static let isTestMode = "isTestMode"
    }

    private enum Defaults: Sendable {
        nonisolated static let controllerIP = "192.168.8.145"
    }
}

// MARK: - Validation

extension AppConfig {

    /// Validate IP address format
    nonisolated static func isValidIP(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let num = Int(part) else { return false }
            return (0...255).contains(num)
        }
    }

    /// Validate UUID format
    nonisolated static func isValidUUID(_ string: String) -> Bool {
        UUID(uuidString: string) != nil
    }
}
