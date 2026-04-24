//
//  AppTheme.swift
//  discar
//
//  Clean Apple-style design system inspired by Tailscale

import SwiftUI

// MARK: - Design Tokens

struct AppTheme {

    // MARK: - Colors (System-based, adapts to light/dark mode)

    struct Colors {
        // Backgrounds - using system materials for native feel
        static let background = Color(uiColor: .systemBackground)
        static let secondaryBackground = Color(uiColor: .secondarySystemBackground)
        static let tertiaryBackground = Color(uiColor: .tertiarySystemBackground)
        static let groupedBackground = Color(uiColor: .systemGroupedBackground)

        // Text
        static let label = Color(uiColor: .label)
        static let secondaryLabel = Color(uiColor: .secondaryLabel)
        static let tertiaryLabel = Color(uiColor: .tertiaryLabel)

        // Semantic
        static let accent = Color.blue
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red

        // Recording
        static let recording = Color.red

        // Separators
        static let separator = Color(uiColor: .separator)
    }

    // MARK: - Typography

    struct Typography {
        // Large titles
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title = Font.title2.weight(.semibold)
        static let title3 = Font.title3.weight(.semibold)

        // Body
        static let headline = Font.headline
        static let body = Font.body
        static let callout = Font.callout
        static let subheadline = Font.subheadline
        static let footnote = Font.footnote
        static let caption = Font.caption
        static let caption2 = Font.caption2

        // Monospace for data
        static let mono = Font.system(.body, design: .monospaced)
        static let monoLarge = Font.system(.title, design: .monospaced).weight(.medium)
        static let monoSmall = Font.system(.caption, design: .monospaced)
    }

    // MARK: - Spacing

    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    // MARK: - Corner Radius

    struct Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 10
        static let lg: CGFloat = 12
    }
}

// MARK: - Reusable Components

/// Clean card container like Tailscale
struct Card<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(AppTheme.Spacing.lg)
            .background(AppTheme.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
    }
}

/// Section header like Tailscale
struct SectionHeader: View {
    let title: String
    let icon: String?

    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
            }
            Text(title.uppercased())
                .font(AppTheme.Typography.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
            Spacer()
        }
    }
}

/// Clean row item like Tailscale list rows
struct ListRow<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    let leading: Leading
    let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            leading

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.label)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                }
            }

            Spacer()

            trailing
        }
    }
}

/// Value display with label (like Tailscale stats)
struct StatValue: View {
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
                .font(AppTheme.Typography.title3)
                .foregroundStyle(color)

            Text(label)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
        }
    }
}

/// Icon with background circle
struct IconBadge: View {
    let icon: String
    let color: Color
    let size: CGFloat

    init(_ icon: String, color: Color = .blue, size: CGFloat = 32) {
        self.icon = icon
        self.color = color
        self.size = size
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xl) {
                // Status card
                Card {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        HStack {
                            IconBadge("server.rack", color: .green)
                            VStack(alignment: .leading) {
                                Text("Controller")
                                    .font(AppTheme.Typography.headline)
                                Text("Connected")
                                    .font(AppTheme.Typography.subheadline)
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            StatusPill("Ready", color: .green)
                        }
                    }
                }

                // Stats row
                Card {
                    VStack(spacing: AppTheme.Spacing.md) {
                        SectionHeader("System", icon: "cpu")

                        HStack {
                            StatValue("45%", label: "CPU")
                            Spacer()
                            StatValue("62%", label: "Memory")
                            Spacer()
                            StatValue("52°", label: "Temp")
                        }
                    }
                }

                // List items
                Card {
                    VStack(spacing: 0) {
                        SectionHeader("Cameras", icon: "video")
                            .padding(.bottom, AppTheme.Spacing.sm)

                        ListRow(title: "Camera 01", subtitle: "Idle") {
                            StatusDot(.green)
                        } trailing: {
                            Text("52°")
                                .font(AppTheme.Typography.monoSmall)
                                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        }

                        Divider().padding(.vertical, AppTheme.Spacing.sm)

                        ListRow(title: "Camera 02", subtitle: "Recording") {
                            StatusDot(.red)
                        } trailing: {
                            Text("58°")
                                .font(AppTheme.Typography.monoSmall)
                                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        }
                    }
                }
            }
            .padding()
        }
        .background(AppTheme.Colors.groupedBackground)
        .navigationTitle("Status")
    }
}
