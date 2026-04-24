//
//  MetricCard.swift
//  discar
//
//  Apple Fitness-inspired metric display card
//

import SwiftUI

/// Bold metric card with icon, value, and label (Fitness-style)
struct MetricCard: View {
    let value: String
    let label: String
    let icon: String?
    let color: Color

    init(_ value: String, label: String, icon: String? = nil, color: Color = .primary) {
        self.value = value
        self.label = label
        self.icon = icon
        self.color = color
    }

    var body: some View {
        VStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
            }

            Text(value)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(color)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Horizontal metric row with icon, label, and value
struct MetricRow: View {
    let label: String
    let value: String
    let icon: String?
    let color: Color

    init(_ label: String, value: String, icon: String? = nil, color: Color = .primary) {
        self.label = label
        self.value = value
        self.icon = icon
        self.color = color
    }

    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 24)
            }

            Text(label)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
    }
}

/// Large display metric (like Fitness workout duration)
struct DisplayMetric: View {
    let value: String
    let label: String
    let color: Color

    init(_ value: String, label: String, color: Color = .primary) {
        self.value = value
        self.label = label
        self.color = color
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack {
            MetricCard("45%", label: "CPU", icon: "cpu", color: .blue)
            MetricCard("62%", label: "Memory", icon: "memorychip", color: .orange)
            MetricCard("52\u{00B0}", label: "Temp", icon: "thermometer", color: .red)
        }

        DisplayMetric("12:34", label: "Duration", color: .green)

        VStack(spacing: 12) {
            MetricRow("Frames", value: "1,234", icon: "car", color: .blue)
            MetricRow("File Size", value: "2.4 MB", icon: "doc", color: .secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    .padding()
}
