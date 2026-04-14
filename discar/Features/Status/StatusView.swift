//
//  StatusView.swift
//  discar
//

import SwiftUI
import SwiftData

struct StatusView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = StatusViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // 1. Controller Status
                    ControllerCard(
                        status: viewModel.ctlrStatus,
                        message: viewModel.ctlrMessage
                    )

                    // 2. CAN Bus Status
                    CANStatusCard(
                        connected: viewModel.canConnected,
                        frameCount: viewModel.canFrameCount
                    )

                    // 3. Refresh Button
                    Button(action: {
                        Task { await viewModel.fetchStatus() }
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(uiColor: .secondarySystemBackground))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                    }

                    // 4. Live Data Section
                    if viewModel.ctlrStatus == .ready || viewModel.ctlrStatus == .recording {
                        VStack(spacing: 20) {
                            // Cameras Active
                            StatsCard(
                                title: "Cameras",
                                value: viewModel.connectedCameras,
                                unit: "Active",
                                icon: "video.fill"
                            )

                            // System Stats
                            SystemStatsCard(
                                storageUsed: viewModel.storageUsedGB,
                                storageTotal: viewModel.storageTotalGB,
                                storagePercent: viewModel.storagePercent,
                                cpu: viewModel.cpuPercent,
                                temp: viewModel.tempC
                            )

                            // Storage Health
                            StorageHealthCard(
                                healthy: viewModel.storageHealthy,
                                loggingMounted: viewModel.loggingMounted,
                                loggingFreeGB: viewModel.loggingFreeGB,
                                syncMounted: viewModel.syncMounted,
                                syncFreeGB: viewModel.syncFreeGB,
                                isRemounting: viewModel.isRemounting,
                                isUnmounting: viewModel.isUnmounting,
                                unmountMessage: viewModel.unmountMessage,
                                storageError: viewModel.storageError,
                                onRemount: {
                                    Task { await viewModel.remountStorage() }
                                },
                                onUnmount: {
                                    Task { await viewModel.unmountSync() }
                                }
                            )

                            // Camera System Grid
                            if !viewModel.cameraNodes.isEmpty {
                                CameraGrid(nodes: viewModel.cameraNodes)
                            }
                        }
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Status")
            .onAppear {
                viewModel.updateModelContext(modelContext)
                viewModel.loadData()
            }
            .onDisappear {
                viewModel.stopPolling()
            }
        }
    }
}

// MARK: - Components

struct ControllerCard: View {
    let status: StatusViewModel.CtlrStatus
    let message: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Controller")
                    .font(.headline)
                    .foregroundStyle(.gray)

                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .padding(2)
                        .background(Circle().stroke(statusColor.opacity(0.3), lineWidth: 2))

                    Text(message)
                        .font(.title3)
                        .fontWeight(.bold)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "server.rack")
                .font(.largeTitle)
                .foregroundStyle(Color.blue)
                .opacity(0.8)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }

    private var statusColor: Color {
        switch status {
        case .disconnected: return .gray
        case .connecting: return .yellow
        case .ready: return .green
        case .recording: return .red
        case .error: return .orange
        }
    }
}

struct StatsCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(Color.blue)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct SystemStatsCard: View {
    let storageUsed: Double
    let storageTotal: Double
    let storagePercent: Double
    let cpu: Double
    let temp: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Controller")
                .font(.headline)
                .foregroundStyle(.gray)
                .padding(.leading, 4)

            VStack(spacing: 12) {
                // Storage Bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "externaldrive.fill")
                            .foregroundStyle(.blue)
                        Text("Storage")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.1f / %.0f GB", storageUsed, storageTotal))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: storagePercent, total: 100)
                        .tint(storagePercent > 80 ? .red : storagePercent > 60 ? .orange : .blue)
                }

                Divider()

                // CPU & Temp Row
                HStack(spacing: 20) {
                    HStack {
                        Image(systemName: "cpu")
                            .foregroundStyle(.blue)
                        Text("CPU")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.0f%%", cpu))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)

                    HStack {
                        Image(systemName: "thermometer.medium")
                            .foregroundStyle(temp > 70 ? .red : temp > 60 ? .orange : .blue)
                        Text("Temp")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.0f°C", temp))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(12)
        }
    }
}

struct StorageHealthCard: View {
    let healthy: Bool
    let loggingMounted: Bool
    let loggingFreeGB: Double
    let syncMounted: Bool
    let syncFreeGB: Double
    let isRemounting: Bool
    let isUnmounting: Bool
    let unmountMessage: String?
    let storageError: String?
    let onRemount: () -> Void
    let onUnmount: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Storage")
                    .font(.headline)
                    .foregroundStyle(.gray)

                Spacer()

                if healthy {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Healthy")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("Issue")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.leading, 4)

            VStack(spacing: 10) {
                // Logging Mount
                HStack {
                    Image(systemName: loggingMounted ? "externaldrive.fill" : "externaldrive.badge.xmark")
                        .foregroundStyle(loggingMounted ? .blue : .red)
                    Text("Logging")
                        .font(.subheadline)
                    Spacer()
                    if loggingMounted {
                        Text(String(format: "%.0f GB free", loggingFreeGB))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not Mounted")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Divider()

                // Sync Mount
                HStack {
                    Image(systemName: syncMounted ? "externaldrive.fill" : "externaldrive.badge.xmark")
                        .foregroundStyle(syncMounted ? .blue : .red)
                    Text("Sync (exFAT)")
                        .font(.subheadline)
                    Spacer()
                    if syncMounted {
                        Text(String(format: "%.0f GB free", syncFreeGB))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not Mounted")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                // Remount button if unhealthy
                if !healthy {
                    Divider()
                    Button(action: onRemount) {
                        HStack {
                            if isRemounting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(isRemounting ? "Remounting..." : "Remount Storage")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .cornerRadius(8)
                    }
                    .disabled(isRemounting)
                }

                // Unmount button for safe removal (only when sync is mounted)
                if syncMounted {
                    Divider()
                    Button(action: onUnmount) {
                        HStack {
                            if isUnmounting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "eject.fill")
                            }
                            Text(isUnmounting ? "Ejecting..." : "Eject Sync Drive")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.2))
                        .foregroundStyle(.blue)
                        .cornerRadius(8)
                    }
                    .disabled(isUnmounting)
                }

                // Show unmount message or error
                if let message = unmountMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.top, 4)
                }

                if let error = storageError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                }
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(12)
        }
    }
}

struct CameraGrid: View {
    let nodes: [StatusViewModel.CameraNode]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cameras")
                .font(.headline)
                .foregroundStyle(.gray)
                .padding(.leading, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(nodes) { node in
                    CameraStatusCard(node: node)
                }
            }
        }
    }
}

struct CameraStatusCard: View {
    let node: StatusViewModel.CameraNode

    private var shortName: String {
        // "melb-01-cam-01" -> "Cam 01"
        let parts = node.name.split(separator: "-")
        if parts.count >= 2, let last = parts.last {
            return "Cam \(last)"
        }
        return node.name
    }

    private var stateColor: Color {
        switch node.state.lowercased() {
        case "recording": return .red
        case "idle": return .green
        default: return .orange
        }
    }

    private var syncIcon: String {
        if node.syncStatus == "syncing" {
            return "arrow.triangle.2.circlepath"
        }
        if let queued = node.syncSegmentsQueued, queued > 0 {
            return "clock.arrow.circlepath"
        }
        return "checkmark.circle.fill"
    }

    private var syncColor: Color {
        if node.syncStatus == "syncing" {
            return .orange
        }
        if let queued = node.syncSegmentsQueued, queued > 0 {
            return .yellow
        }
        if node.syncError != nil {
            return .red
        }
        return .green
    }

    private var syncText: String {
        let onCtlr = node.segmentsOnCtlr ?? 0
        let synced = node.syncSegmentsSynced ?? 0

        if node.syncStatus == "syncing" {
            return "Syncing... (\(onCtlr) on ctlr)"
        }
        if let queued = node.syncSegmentsQueued, queued > 0 {
            return "\(queued) pending"
        }
        if let segment = node.segment, node.state.lowercased() == "recording" {
            return "\(onCtlr)/\(segment + 1) synced"
        }
        return "\(onCtlr) synced"
    }

    var body: some View {
        VStack(spacing: 8) {
            // Header: Icon + Name + Status
            HStack {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: node.state.lowercased() == "recording" ? "video.fill.badge.checkmark" : "video.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(node.connected ? stateColor : Color.gray.opacity(0.5))

                    Circle()
                        .fill(node.connected ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                        .offset(x: 3, y: -3)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(shortName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(node.state)
                        .font(.caption2)
                        .foregroundStyle(stateColor)
                }

                Spacer()

                // Segment when recording
                if let segment = node.segment, node.state.lowercased() == "recording" {
                    Text("Seg \(segment)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(4)
                }
            }

            if node.connected {
                Divider()

                // Stats Grid
                HStack(spacing: 12) {
                    if let temp = node.temp {
                        StatBadge(icon: "thermometer", value: String(format: "%.0f°", temp), color: temp > 70 ? .red : temp > 60 ? .orange : .blue)
                    }
                    if let cpu = node.cpu {
                        StatBadge(icon: "cpu", value: String(format: "%.0f%%", cpu), color: cpu > 80 ? .red : .blue)
                    }
                    if let disk = node.diskFreeGB {
                        StatBadge(icon: "internaldrive", value: String(format: "%.0fG", disk), color: disk < 5 ? .red : .blue)
                    }
                }

                // Sync Status Row
                if let synced = node.syncSegmentsSynced, let onCtlr = node.segmentsOnCtlr {
                    Divider()
                    HStack(spacing: 4) {
                        Image(systemName: syncIcon)
                            .font(.caption2)
                            .foregroundStyle(syncColor)
                        Text(syncText)
                            .font(.caption2)
                            .foregroundStyle(syncColor)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct StatBadge: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(value)
                .font(.caption2)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    StatusView()
}
