//
//  Logger.swift
//  discar
//
//  Remote logging service - sends logs to ctlr via HTTP POST
//

import Foundation

/// Remote logger that sends logs to ctlr, which publishes to MQTT
/// Same format as Pi camera nodes for unified logging
/// Uses @unchecked Sendable for safe cross-actor access (all methods are thread-safe)
final class RemoteLogger: @unchecked Sendable {
    nonisolated static let shared = RemoteLogger()

    private let node = "iphone"
    private let session = URLSession.shared

    private nonisolated var logURL: String {
        "\(AppConfig.Controller.baseURL)/api/log"
    }

    private init() {}

    /// Send log to ctlr (fire-and-forget)
    /// - Parameters:
    ///   - component: Component name (e.g., "recording", "sync", "watch")
    ///   - message: Log message
    ///   - level: Log level (INFO, WARN, ERROR)
    nonisolated func log(_ component: String, _ message: String, level: String = "INFO") {
        guard let url = URL(string: logURL) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 3.0

        let payload: [String: Any] = [
            "node": node,
            "component": component,
            "level": level,
            "message": message,
            "ts": ISO8601DateFormatter().string(from: Date())
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        // Fire and forget - don't block on response
        session.dataTask(with: request).resume()

        // Also print locally for debugging
        print("[\(level)] \(component): \(message)")
    }

    // Convenience methods
    nonisolated func info(_ component: String, _ message: String) {
        log(component, message, level: "INFO")
    }

    nonisolated func warn(_ component: String, _ message: String) {
        log(component, message, level: "WARN")
    }

    nonisolated func error(_ component: String, _ message: String) {
        log(component, message, level: "ERROR")
    }
}
