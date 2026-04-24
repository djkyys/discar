//
//  SensorStatusCard.swift
//  discar
//
//  Sensor status display using Card style

import SwiftUI

struct SensorStatusCard: View {
    let sensorStatus: [String: Bool]
    let isLoading: Bool

    private var availableCount: Int {
        sensorStatus.values.filter { $0 }.count
    }

    private var totalCount: Int {
        sensorStatus.count
    }

    private var statusColor: Color {
        if totalCount == 0 { return AppTheme.Colors.secondaryLabel }
        let percentage = Double(availableCount) / Double(totalCount)
        if percentage == 1.0 { return AppTheme.Colors.success }
        if percentage >= 0.7 { return AppTheme.Colors.warning }
        return AppTheme.Colors.error
    }

    var body: some View {
        Card {
            VStack(spacing: AppTheme.Spacing.md) {
                // Header
                HStack {
                    SectionHeader("Phone Sensors", icon: "sensor.fill")
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if !sensorStatus.isEmpty {
                        StatusPill("\(availableCount)/\(totalCount)", color: statusColor)
                    }
                }

                // Sensor grid
                if !sensorStatus.isEmpty {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: AppTheme.Spacing.sm) {
                        ForEach(sensorStatus.sorted(by: { $0.key < $1.key }), id: \.key) { sensor in
                            SensorStatusRow(name: sensor.key, isAvailable: sensor.value)
                        }
                    }
                } else if !isLoading {
                    Text("No sensors detected")
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.md)
                }
            }
        }
    }
}

// MARK: - Sensor Status Row

private struct SensorStatusRow: View {
    let name: String
    let isAvailable: Bool

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            StatusDot(isAvailable ? .green : .red)

            Image(systemName: sensorIcon)
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                .frame(width: 16)

            Text(shortName)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(isAvailable ? AppTheme.Colors.label : AppTheme.Colors.secondaryLabel)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    private var shortName: String {
        SensorType.from(name: name)?.shortName ?? name
            .replacingOccurrences(of: "Device ", with: "")
            .replacingOccurrences(of: "Core ", with: "")
    }

    private var sensorIcon: String {
        SensorType.from(name: name)?.icon ?? "sensor"
    }
}

#Preview {
    ScrollView {
        VStack(spacing: AppTheme.Spacing.lg) {
            SensorStatusCard(
                sensorStatus: [
                    "Accelerometer": true,
                    "Gyroscope": true,
                    "Magnetometer": true,
                    "Device Motion": true,
                    "GPS": false,
                    "Heading": true,
                    "Barometer": true,
                    "Gravity": true
                ],
                isLoading: false
            )

            SensorStatusCard(
                sensorStatus: [:],
                isLoading: true
            )
        }
        .padding()
    }
    .background(AppTheme.Colors.groupedBackground)
}
