//
//  Formatters.swift
//  discar
//
//  Display formatting utilities
//

import Foundation

enum Formatters {

    // MARK: - Duration

    /// Format seconds as MM:SS or HH:MM:SS
    static func duration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    /// Format seconds as "X min" or "X hr Y min"
    static func durationWords(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        } else if minutes > 0 {
            return "\(minutes) min"
        } else {
            return "\(Int(seconds)) sec"
        }
    }

    // MARK: - Bytes

    /// Format bytes as human-readable (KB, MB, GB)
    static func bytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Format gigabytes with 1 decimal
    static func gigabytes(_ gb: Double) -> String {
        String(format: "%.1f GB", gb)
    }

    // MARK: - Percentage

    /// Format percentage (0-100)
    static func percentage(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    // MARK: - Temperature

    /// Format temperature in Celsius
    static func temperature(_ celsius: Double) -> String {
        String(format: "%.0f\u{00B0}", celsius)
    }

    // MARK: - Count

    /// Format large numbers with K/M suffix
    static func count(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        } else {
            return "\(value)"
        }
    }

    // MARK: - Date/Time

    /// Melbourne timezone date formatter
    static let melbourneDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.timeZone = TimeZone(identifier: "Australia/Melbourne")
        return formatter
    }()

    /// ISO 8601 formatter
    static let iso8601Formatter = ISO8601DateFormatter()

    /// Short date (Apr 24, 2025)
    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Short time (2:30 PM)
    static func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Relative time (2 hours ago, Yesterday, etc.)
    static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
