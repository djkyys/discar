//
//  SensorHealthBar.swift
//  discar
//

import SwiftUI

/// Displays real-time sensor health during recording
struct SensorHealthBar: View {
    let health: SensorHealth

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with summary
            HStack {
                Label("Sensors", systemImage: "sensor.fill")
                    .font(.headline)

                Spacer()

                // Summary badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(health.isHealthy ? Color.green : (health.hasFailures ? Color.red : Color.orange))
                        .frame(width: 8, height: 8)

                    Text(health.summary)
                        .font(.caption)
                        .foregroundStyle(health.isHealthy ? .green : (health.hasFailures ? .red : .orange))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((health.isHealthy ? Color.green : (health.hasFailures ? Color.red : Color.orange)).opacity(0.1))
                .cornerRadius(8)
            }

            // Sensor dots grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                ForEach(health.allStatuses, id: \.name) { sensor in
                    SensorDot(
                        name: sensor.shortName,
                        icon: sensor.icon,
                        status: sensor.status
                    )
                }
            }

            // Show failures if any
            if health.hasFailures {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(health.failures, id: \.name) { failure in
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)

                            Text("\(failure.name): \(failure.reason)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
}

/// Individual sensor status dot
struct SensorDot: View {
    let name: String
    let icon: String
    let status: SensorHealth.Status

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(statusColor)
            }

            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var statusColor: Color {
        switch status {
        case .active:
            return .green
        case .inactive:
            return .gray
        case .notAvailable:
            return .gray.opacity(0.5)
        case .failed:
            return .red
        }
    }
}

/// Compact version for smaller spaces
struct SensorHealthCompact: View {
    let health: SensorHealth

    var body: some View {
        HStack(spacing: 4) {
            ForEach(health.allStatuses, id: \.name) { sensor in
                Circle()
                    .fill(colorFor(sensor.status))
                    .frame(width: 8, height: 8)
            }

            Text(health.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
    }

    private func colorFor(_ status: SensorHealth.Status) -> Color {
        switch status {
        case .active: return .green
        case .inactive: return .gray
        case .notAvailable: return .gray.opacity(0.3)
        case .failed: return .red
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        // Healthy state
        SensorHealthBar(health: {
            var h = SensorHealth()
            h.accelerometer = .active
            h.gyroscope = .active
            h.magnetometer = .active
            h.barometer = .active
            h.gps = .active
            h.deviceMotion = .active
            h.headphoneMotion = .active
            h.compass = .active
            return h
        }())

        // Partial failure
        SensorHealthBar(health: {
            var h = SensorHealth()
            h.accelerometer = .active
            h.gyroscope = .active
            h.magnetometer = .active
            h.barometer = .active
            h.gps = .active
            h.deviceMotion = .active
            h.headphoneMotion = .failed("Disconnected")
            h.compass = .active
            return h
        }())

        // Compact version
        SensorHealthCompact(health: {
            var h = SensorHealth()
            h.accelerometer = .active
            h.gyroscope = .active
            h.magnetometer = .failed("Error")
            h.barometer = .active
            h.gps = .notAvailable
            h.deviceMotion = .active
            h.headphoneMotion = .inactive
            h.compass = .active
            return h
        }())
    }
    .padding()
}
