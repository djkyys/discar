//
//  ProgressRing.swift
//  discar
//
//  Apple Fitness-inspired circular progress ring
//

import SwiftUI

/// Circular progress ring (Activity ring style)
struct ProgressRing: View {
    let progress: Double  // 0.0 to 1.0
    let color: Color
    let lineWidth: CGFloat
    let showPercentage: Bool

    init(
        progress: Double,
        color: Color = .blue,
        lineWidth: CGFloat = 12,
        showPercentage: Bool = false
    ) {
        self.progress = min(max(progress, 0), 1)
        self.color = color
        self.lineWidth = lineWidth
        self.showPercentage = showPercentage
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)

            // Percentage text
            if showPercentage {
                Text("\(Int(progress * 100))%")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
    }
}

/// Storage progress bar (horizontal)
struct StorageBar: View {
    let used: Double  // GB
    let total: Double  // GB
    let color: Color
    let label: String

    var progress: Double {
        guard total > 0 else { return 0 }
        return (total - used) / total  // Show FREE space
    }

    var freeGB: Double {
        total - used
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text(String(format: "%.1f GB free", freeGB))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))

                    // Progress
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 8)
        }
    }
}

/// Triple ring display (like Activity rings)
struct ActivityRings: View {
    let ring1: (progress: Double, color: Color, label: String)
    let ring2: (progress: Double, color: Color, label: String)
    let ring3: (progress: Double, color: Color, label: String)

    var body: some View {
        HStack(spacing: 24) {
            ringView(ring1)
            ringView(ring2)
            ringView(ring3)
        }
    }

    private func ringView(_ ring: (progress: Double, color: Color, label: String)) -> some View {
        VStack(spacing: 8) {
            ProgressRing(progress: ring.progress, color: ring.color, lineWidth: 8, showPercentage: true)
                .frame(width: 60, height: 60)

            Text(ring.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    VStack(spacing: 32) {
        // Single ring
        ProgressRing(progress: 0.75, color: .green, lineWidth: 16, showPercentage: true)
            .frame(width: 100, height: 100)

        // Activity rings
        ActivityRings(
            ring1: (0.85, .red, "CPU"),
            ring2: (0.62, .green, "Memory"),
            ring3: (0.45, .blue, "Disk")
        )

        // Storage bars
        VStack(spacing: 16) {
            StorageBar(used: 50, total: 500, color: .blue, label: "Logging")
            StorageBar(used: 200, total: 1200, color: .green, label: "Sync")
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    .padding()
}
