//
//  StatusBadge.swift
//  discar
//
//  Status indicator badges and pills
//

import SwiftUI

/// Connection/state status badge
struct StatusBadge: View {
    let status: Status
    let size: Size

    enum Status {
        case connected
        case disconnected
        case recording
        case idle
        case syncing
        case error
        case warning

        var color: Color {
            switch self {
            case .connected, .idle: return .green
            case .disconnected, .error: return .red
            case .recording: return .red
            case .syncing: return .blue
            case .warning: return .orange
            }
        }

        var icon: String {
            switch self {
            case .connected: return "checkmark.circle.fill"
            case .disconnected: return "xmark.circle.fill"
            case .recording: return "record.circle.fill"
            case .idle: return "circle.fill"
            case .syncing: return "arrow.triangle.2.circlepath"
            case .error: return "exclamationmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }

        var text: String {
            switch self {
            case .connected: return "Connected"
            case .disconnected: return "Disconnected"
            case .recording: return "Recording"
            case .idle: return "Idle"
            case .syncing: return "Syncing"
            case .error: return "Error"
            case .warning: return "Warning"
            }
        }
    }

    enum Size {
        case small, medium, large

        var iconSize: Font {
            switch self {
            case .small: return .caption
            case .medium: return .body
            case .large: return .title3
            }
        }

        var textSize: Font {
            switch self {
            case .small: return .caption2
            case .medium: return .caption
            case .large: return .subheadline
            }
        }
    }

    init(_ status: Status, size: Size = .medium) {
        self.status = status
        self.size = size
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(size.iconSize)

            Text(status.text)
                .font(size.textSize)
                .fontWeight(.medium)
        }
        .foregroundStyle(status.color)
    }
}

/// Pill-shaped status indicator
struct StatusPill: View {
    let text: String
    let color: Color
    let isActive: Bool

    init(_ text: String, color: Color, isActive: Bool = true) {
        self.text = text
        self.color = color
        self.isActive = isActive
    }

    var body: some View {
        HStack(spacing: 6) {
            if isActive {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }

            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }
}

/// Simple dot indicator
struct StatusDot: View {
    let color: Color
    let size: CGFloat
    let isPulsing: Bool

    init(_ color: Color, size: CGFloat = 8, isPulsing: Bool = false) {
        self.color = color
        self.size = size
        self.isPulsing = isPulsing
    }

    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(isPulsing && isAnimating ? 1.2 : 1.0)
            .opacity(isPulsing && isAnimating ? 0.7 : 1.0)
            .animation(
                isPulsing ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                value: isAnimating
            )
            .onAppear {
                if isPulsing {
                    isAnimating = true
                }
            }
    }
}

#Preview {
    VStack(spacing: 24) {
        // Status badges
        VStack(alignment: .leading, spacing: 12) {
            StatusBadge(.connected, size: .large)
            StatusBadge(.recording, size: .medium)
            StatusBadge(.disconnected, size: .small)
            StatusBadge(.syncing)
        }

        Divider()

        // Status pills
        HStack {
            StatusPill("Ready", color: .green)
            StatusPill("Recording", color: .red, isActive: true)
            StatusPill("Offline", color: .gray, isActive: false)
        }

        Divider()

        // Status dots
        HStack(spacing: 16) {
            StatusDot(.green)
            StatusDot(.red, isPulsing: true)
            StatusDot(.orange, size: 12)
        }
    }
    .padding()
}
