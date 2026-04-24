//
//  ActionButton.swift
//  discar
//
//  Styled action buttons
//

import SwiftUI

/// Primary action button with consistent styling
struct ActionButton: View {
    let title: String
    let icon: String?
    let style: Style
    let isLoading: Bool
    let action: () -> Void

    enum Style {
        case primary
        case secondary
        case destructive
        case recording

        var backgroundColor: Color {
            switch self {
            case .primary: return .blue
            case .secondary: return Color(.secondarySystemBackground)
            case .destructive: return .red
            case .recording: return .red
            }
        }

        var foregroundColor: Color {
            switch self {
            case .primary, .destructive, .recording: return .white
            case .secondary: return .primary
            }
        }
    }

    init(
        _ title: String,
        icon: String? = nil,
        style: Style = .primary,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(style.foregroundColor)
                } else if let icon = icon {
                    Image(systemName: icon)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(style.backgroundColor)
            .foregroundStyle(style.foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isLoading)
    }
}

/// Icon-only button (for toolbar actions)
struct IconButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    init(_ icon: String, color: Color = .blue, action: @escaping () -> Void) {
        self.icon = icon
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.1))
                .clipShape(Circle())
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        ActionButton("Start Recording", icon: "record.circle", style: .recording) { }

        ActionButton("Test Connection", icon: "wifi", style: .primary, isLoading: false) { }

        ActionButton("Export", icon: "square.and.arrow.up", style: .secondary) { }

        ActionButton("Delete", icon: "trash", style: .destructive) { }

        HStack(spacing: 16) {
            IconButton("gear") { }
            IconButton("arrow.clockwise", color: .green) { }
            IconButton("trash", color: .red) { }
        }
    }
    .padding()
}
