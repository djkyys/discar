//
//  StatusView.swift
//  discar
//
//  Clean status dashboard inspired by Tailscale

import SwiftUI
import SwiftData

struct StatusView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = StatusViewModel()
    @StateObject private var recordViewModel: RecordViewModel
    @EnvironmentObject var appState: AppState

    init() {
        // RecordViewModel needs modelContext, but we can't access @Environment in init
        // So we create it without modelContext and update later
        _recordViewModel = StateObject(wrappedValue: RecordViewModel())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {
                    // Record Section
                    RecordSection(
                        recordViewModel: recordViewModel,
                        appState: appState
                    )

                    // Connection status
                    ConnectionCard(state: viewModel.connectionState)

                    // Controller
                    ControllerCard(
                        controller: viewModel.controller,
                        isConnected: viewModel.connectionState.isConnected
                    )

                    // Cameras
                    CamerasCard(
                        cameras: viewModel.cameras,
                        syncProgress: viewModel.syncProgress
                    )

                    // CAN & System
                    HStack(spacing: AppTheme.Spacing.lg) {
                        CANCard(can: viewModel.can)
                        SystemCard(system: viewModel.system)
                    }

                    // Storage
                    StorageCard(
                        storage: viewModel.storage,
                        isRecording: recordViewModel.isRecording,
                        isRemounting: viewModel.isRemounting,
                        isUnmounting: viewModel.isUnmounting,
                        unmountMessage: viewModel.unmountMessage,
                        storageError: viewModel.storageError,
                        onRemount: { Task { await viewModel.remountStorage() } },
                        onUnmount: { Task { await viewModel.unmountSync() } }
                    )

                    // Sessions
                    SessionsCard(
                        totalSessions: viewModel.totalSessions,
                        totalTime: viewModel.totalTimeFormatted,
                        averageSession: viewModel.averageSessionFormatted,
                        lastSessionDate: viewModel.lastSessionDate
                    )
                }
                .padding()
            }
            .background(AppTheme.Colors.groupedBackground)
            .navigationTitle("Status")
            .onAppear {
                viewModel.updateModelContext(modelContext)
                viewModel.connect()
                viewModel.loadSessionStats()
                recordViewModel.updateModelContext(modelContext)
            }
        }
    }
}

// MARK: - Connection Card

private struct ConnectionCard: View {
    let state: WebSocketService.ConnectionState

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            StatusDot(statusColor)

            Text(state.displayText)
                .font(AppTheme.Typography.subheadline)
                .foregroundStyle(AppTheme.Colors.secondaryLabel)

            Spacer()

            if case .reconnecting = state {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(AppTheme.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
    }

    private var statusColor: Color {
        switch state {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .disconnected: return .red
        }
    }
}

// MARK: - Controller Card

private struct ControllerCard: View {
    let controller: WebSocketService.ControllerStatus?
    let isConnected: Bool

    var body: some View {
        Card {
            HStack {
                IconBadge("server.rack", color: statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Controller")
                        .font(AppTheme.Typography.headline)

                    if let ctrl = controller {
                        Text(statusText(ctrl))
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(statusColor)
                    } else {
                        Text(isConnected ? "Loading..." : "Offline")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    }
                }

                Spacer()

                if let ctrl = controller {
                    if ctrl.recording {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatDuration(ctrl.duration))
                                .font(AppTheme.Typography.monoLarge)
                                .foregroundStyle(.red)
                            if let uuid = ctrl.uuid {
                                Text(String(uuid.prefix(8)))
                                    .font(AppTheme.Typography.caption)
                                    .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                            }
                        }
                    } else {
                        StatusPill(ctrl.ready ? "Ready" : "Not Ready", color: ctrl.ready ? .green : .orange)
                    }
                }
            }
        }
    }

    private var statusColor: Color {
        guard let ctrl = controller else { return .gray }
        if ctrl.recording { return .red }
        if ctrl.ready { return .green }
        return .orange
    }

    private func statusText(_ ctrl: WebSocketService.ControllerStatus) -> String {
        if ctrl.recording { return "Recording" }
        if ctrl.ready { return "System Ready" }
        return "Cameras Not Ready"
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Cameras Card

private struct CamerasCard: View {
    let cameras: [WebSocketService.CameraStatus]
    let syncProgress: [String: WebSocketService.SyncProgress]

    var body: some View {
        Card {
            VStack(spacing: AppTheme.Spacing.md) {
                HStack {
                    SectionHeader("Cameras", icon: "video")

                    Spacer()

                    let online = cameras.filter { $0.connected }.count
                    Text("\(online)/\(cameras.count)")
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(online == cameras.count ? .green : .orange)
                }

                if cameras.isEmpty {
                    Text("No cameras")
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.lg)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(cameras.enumerated()), id: \.element.name) { index, camera in
                            if index > 0 {
                                Divider().padding(.vertical, AppTheme.Spacing.sm)
                            }
                            CameraRow(camera: camera, syncProgress: syncProgress[camera.name])
                        }
                    }
                }
            }
        }
    }
}

private struct CameraRow: View {
    let camera: WebSocketService.CameraStatus
    let syncProgress: WebSocketService.SyncProgress?

    private var shortName: String {
        if let last = camera.name.split(separator: "-").last {
            return "Camera \(last)"
        }
        return camera.name
    }

    private var stateColor: Color {
        if !camera.connected { return .gray }
        switch camera.state.lowercased() {
        case "recording": return .red
        case "idle": return .green
        default: return .orange
        }
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            HStack {
                StatusDot(stateColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(shortName)
                        .font(AppTheme.Typography.body)

                    Text(camera.connected ? camera.state.capitalized : "Offline")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(stateColor)
                }

                Spacer()

                if camera.connected {
                    HStack(spacing: AppTheme.Spacing.md) {
                        if let temp = camera.temp {
                            MetricLabel(String(format: "%.0f°", temp), icon: "thermometer.medium")
                        }
                        if let cpu = camera.cpu {
                            MetricLabel(String(format: "%.0f%%", cpu), icon: "cpu")
                        }
                    }
                }
            }

            // Sync progress bar
            if let sync = syncProgress, sync.queued > 0 {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Text("Sync")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AppTheme.Colors.tertiaryBackground)
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(sync.status == "complete" ? Color.green : Color.blue)
                                .frame(width: geo.size.width * CGFloat(sync.synced) / CGFloat(max(sync.queued, 1)), height: 4)
                        }
                    }
                    .frame(height: 4)

                    Text("\(sync.synced)/\(sync.queued)")
                        .font(AppTheme.Typography.monoSmall)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                }
            }
        }
    }
}

private struct MetricLabel: View {
    let value: String
    let icon: String

    init(_ value: String, icon: String) {
        self.value = value
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(AppTheme.Colors.tertiaryLabel)
            Text(value)
                .font(AppTheme.Typography.monoSmall)
                .foregroundStyle(AppTheme.Colors.secondaryLabel)
        }
    }
}

// MARK: - CAN Card

private struct CANCard: View {
    let can: WebSocketService.CANStatus?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Image(systemName: "car.fill")
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    Text("CAN")
                        .font(AppTheme.Typography.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                }

                Spacer(minLength: 0)

                if let can = can {
                    HStack {
                        StatusDot(can.connected ? .green : .red)
                        Text(can.connected ? "Connected" : "Disconnected")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundStyle(can.connected ? .green : .red)
                    }

                    Text(can.connected && can.fileSizeBytes > 0 ? formatBytes(can.fileSizeBytes) : "--")
                        .font(AppTheme.Typography.monoSmall)
                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                } else {
                    Text("--")
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                    Text("--")
                        .font(AppTheme.Typography.monoSmall)
                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}

// MARK: - System Card

private struct SystemCard: View {
    let system: WebSocketService.SystemStatus?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    Text("System")
                        .font(AppTheme.Typography.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                }

                Spacer(minLength: 0)

                if let sys = system {
                    HStack(spacing: AppTheme.Spacing.lg) {
                        VStack(alignment: .leading) {
                            Text(String(format: "%.0f%%", sys.cpuPercent))
                                .font(AppTheme.Typography.subheadline)
                            Text("CPU")
                                .font(AppTheme.Typography.caption2)
                                .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                        }

                        VStack(alignment: .leading) {
                            Text(String(format: "%.0f°", sys.tempC))
                                .font(AppTheme.Typography.subheadline)
                            Text("Temp")
                                .font(AppTheme.Typography.caption2)
                                .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                        }
                    }
                } else {
                    Text("--")
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                    Text("--")
                        .font(AppTheme.Typography.monoSmall)
                        .foregroundStyle(AppTheme.Colors.tertiaryLabel)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        }
    }
}

// MARK: - Storage Card

private struct StorageCard: View {
    let storage: WebSocketService.StorageStatus?
    let isRecording: Bool
    let isRemounting: Bool
    let isUnmounting: Bool
    let unmountMessage: String?
    let storageError: String?
    let onRemount: () -> Void
    let onUnmount: () -> Void

    var body: some View {
        Card {
            VStack(spacing: AppTheme.Spacing.md) {
                HStack {
                    SectionHeader("Storage", icon: "externaldrive")
                    Spacer()
                    if let s = storage {
                        StatusPill(s.healthy ? "Healthy" : "Issue", color: s.healthy ? .green : .red)
                    }
                }

                if let s = storage {
                    VStack(spacing: AppTheme.Spacing.sm) {
                        StorageRow(name: "Logging", mounted: s.loggingMounted, freeGB: s.loggingFreeGB)
                        Divider()
                        StorageRow(name: "Sync", mounted: s.syncMounted, freeGB: s.syncFreeGB)
                    }

                    if !s.healthy || s.syncMounted {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            if !s.healthy {
                                Button(action: onRemount) {
                                    HStack {
                                        if isRemounting {
                                            ProgressView().scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "arrow.clockwise")
                                        }
                                        Text("Remount")
                                    }
                                    .font(AppTheme.Typography.subheadline.weight(.medium))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, AppTheme.Spacing.md)
                                    .padding(.vertical, AppTheme.Spacing.sm)
                                    .background(Color.orange.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                                }
                                .disabled(isRemounting)
                            }

                            if s.syncMounted {
                                Button(action: onUnmount) {
                                    HStack {
                                        if isUnmounting {
                                            ProgressView().scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "eject")
                                        }
                                        Text("Eject")
                                    }
                                    .font(AppTheme.Typography.subheadline.weight(.medium))
                                    .foregroundStyle(isRecording ? .gray : .blue)
                                    .padding(.horizontal, AppTheme.Spacing.md)
                                    .padding(.vertical, AppTheme.Spacing.sm)
                                    .background((isRecording ? Color.gray : Color.blue).opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                                }
                                .disabled(isUnmounting || isRecording)
                            }
                        }

                        if isRecording && s.syncMounted {
                            Text("Can't eject during recording")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    if let msg = unmountMessage {
                        Text(msg)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(.green)
                    }

                    if let err = storageError {
                        Text(err)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }
}

private struct StorageRow: View {
    let name: String
    let mounted: Bool
    let freeGB: Double

    var body: some View {
        HStack {
            StatusDot(mounted ? .green : .red)

            Text(name)
                .font(AppTheme.Typography.body)

            Spacer()

            if mounted {
                Text(String(format: "%.0f GB free", freeGB))
                    .font(AppTheme.Typography.monoSmall)
                    .foregroundStyle(AppTheme.Colors.secondaryLabel)
            } else {
                Text("Not mounted")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Sessions Card

private struct SessionsCard: View {
    let totalSessions: Int
    let totalTime: String
    let averageSession: String
    let lastSessionDate: String?

    var body: some View {
        Card {
            VStack(spacing: AppTheme.Spacing.md) {
                SectionHeader("Sessions", icon: "list.bullet")

                if totalSessions > 0 {
                    HStack {
                        StatValue("\(totalSessions)", label: "Total")
                        Spacer()
                        StatValue(totalTime, label: "Recorded")
                        Spacer()
                        StatValue(averageSession, label: "Average")
                    }

                    if let lastDate = lastSessionDate {
                        Divider()
                        HStack {
                            Text("Last session")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                            Spacer()
                            Text(lastDate)
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        }
                    }
                } else {
                    Text("No sessions recorded")
                        .font(AppTheme.Typography.subheadline)
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                        .padding(.vertical, AppTheme.Spacing.md)
                }
            }
        }
    }
}

// MARK: - Record Section

private struct RecordSection: View {
    @ObservedObject var recordViewModel: RecordViewModel
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            // Recording card with button
            Card {
                VStack(spacing: AppTheme.Spacing.md) {
                    // Live sensor health (during recording)
                    if recordViewModel.isRecording, let health = recordViewModel.sensorHealth {
                        SensorHealthBar(health: health)
                    }

                    // External connections (during recording)
                    if recordViewModel.isRecording {
                        VStack(spacing: AppTheme.Spacing.sm) {
                            ConnectionStatusRow(
                                icon: "applewatch",
                                label: "Watch",
                                isConnected: recordViewModel.isWatchConnected,
                                detail: recordViewModel.isWatchConnected ? "Recording" : nil
                            )
                            CANStatusRow(
                                connected: recordViewModel.canConnected,
                                fileSizeFormatted: recordViewModel.canFileSizeFormatted
                            )
                        }
                    }

                    // Record Button
                    if recordViewModel.isStarting {
                        ProgressView("Preparing System...")
                            .padding(.vertical, AppTheme.Spacing.md)
                    } else {
                        RecordButton(
                            isRecording: recordViewModel.isRecording,
                            duration: recordViewModel.durationFormatted,
                            action: {
                                Task {
                                    if recordViewModel.isRecording {
                                        await recordViewModel.stopRecording()
                                    } else {
                                        await recordViewModel.startRecording()
                                    }
                                }
                            }
                        )
                    }
                }
            }

            // Sensor status (below record button, when not recording)
            if !recordViewModel.isRecording {
                SensorStatusCardCompact(
                    sensorStatus: appState.sensorStatus,
                    isLoading: appState.isCheckingSensors
                )
            }
        }
        .alert("Recording Failed", isPresented: $recordViewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(recordViewModel.errorMessage ?? "Unknown Error")
        }
        .alert("Start Watch Recording", isPresented: $recordViewModel.showWatchStartPrompt) {
            Button("OK") { }
        } message: {
            Text("Recording started. Open Watch app and tap Start to begin watch recording.")
        }
        .alert("Stop Watch Recording", isPresented: $recordViewModel.showWatchStopPrompt) {
            Button("OK") { }
        } message: {
            Text("Recording stopped. Open Watch app and tap Stop to end watch recording.")
        }
    }
}

// MARK: - Compact Sensor Status Card

private struct SensorStatusCardCompact: View {
    let sensorStatus: [String: Bool]
    let isLoading: Bool

    private var sortedSensors: [(name: String, active: Bool)] {
        sensorStatus.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    private func iconFor(_ name: String) -> String {
        switch name.lowercased() {
        case let n where n.contains("accelerometer"): return "move.3d"
        case let n where n.contains("gyro"): return "rotate.3d"
        case let n where n.contains("magnet"): return "safari"  // compass-like
        case let n where n.contains("motion"): return "figure.walk"
        case let n where n.contains("gps"), let n where n.contains("location"): return "location.fill"
        case let n where n.contains("heading"), let n where n.contains("compass"): return "location.north.fill"
        case let n where n.contains("barometer"), let n where n.contains("altitude"): return "barometer"
        case let n where n.contains("gravity"): return "arrow.down.circle"
        case let n where n.contains("orientation"): return "gyroscope"
        default: return "sensor"
        }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                // Header
                HStack {
                    Image(systemName: "iphone")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    Text("PHONE SENSORS")
                        .font(AppTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.secondaryLabel)
                    Spacer()
                    if isLoading {
                        ProgressView().scaleEffect(0.7)
                    }
                }

                if !isLoading && !sensorStatus.isEmpty {
                    // Sensor icons in a row
                    HStack(spacing: AppTheme.Spacing.md) {
                        ForEach(sortedSensors, id: \.name) { sensor in
                            VStack(spacing: 2) {
                                Image(systemName: iconFor(sensor.name))
                                    .font(.system(size: 16))
                                    .foregroundStyle(sensor.active ? AppTheme.Colors.success : AppTheme.Colors.error)
                                Circle()
                                    .fill(sensor.active ? AppTheme.Colors.success : AppTheme.Colors.error)
                                    .frame(width: 4, height: 4)
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    StatusView()
        .environmentObject(AppState())
}
