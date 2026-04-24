//
//  SessionDetailView.swift
//  discar
//

import SwiftUI
import SwiftData
import WatchConnectivity

struct SessionDetailView: View {
    let session: Session
    @StateObject private var viewModel: SessionDetailViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteAlert = false

    init(session: Session) {
        self.session = session
        _viewModel = StateObject(wrappedValue: SessionDetailViewModel(session: session))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // Session Info Card
                SessionInfoCard(session: session)
                
                // Sensor Data Cards
                if viewModel.isLoading {
                    ProgressView("Loading session data...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    VStack(spacing: 12) {
                        if viewModel.accelerometerCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .accelerometer)) {
                                SensorDataCard(
                                    title: SensorType.accelerometer.displayName,
                                    icon: SensorType.accelerometer.icon,
                                    count: viewModel.accelerometerCount,
                                    color: SensorType.accelerometer.color
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if viewModel.gyroscopeCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .gyroscope)) {
                                SensorDataCard(
                                    title: SensorType.gyroscope.displayName,
                                    icon: SensorType.gyroscope.icon,
                                    count: viewModel.gyroscopeCount,
                                    color: SensorType.gyroscope.color
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if viewModel.magnetometerCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .magnetometer)) {
                                SensorDataCard(
                                    title: SensorType.magnetometer.displayName,
                                    icon: SensorType.magnetometer.icon,
                                    count: viewModel.magnetometerCount,
                                    color: SensorType.magnetometer.color
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if viewModel.barometerCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .barometer)) {
                                SensorDataCard(
                                    title: SensorType.barometer.displayName,
                                    icon: SensorType.barometer.icon,
                                    count: viewModel.barometerCount,
                                    color: SensorType.barometer.color
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if viewModel.gpsCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .gps)) {
                                SensorDataCard(
                                    title: SensorType.gps.displayName,
                                    icon: SensorType.gps.icon,
                                    count: viewModel.gpsCount,
                                    color: SensorType.gps.color
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if viewModel.deviceMotionCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .deviceMotion)) {
                                SensorDataCard(
                                    title: SensorType.deviceMotion.displayName,
                                    icon: SensorType.deviceMotion.icon,
                                    count: viewModel.deviceMotionCount,
                                    color: SensorType.deviceMotion.color
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if viewModel.headphoneMotionCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .headphoneMotion)) {
                                SensorDataCard(
                                    title: SensorType.headphoneMotion.displayName,
                                    icon: SensorType.headphoneMotion.icon,
                                    count: viewModel.headphoneMotionCount,
                                    color: SensorType.headphoneMotion.color
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if viewModel.headingCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .heading)) {
                                SensorDataCard(
                                    title: SensorType.heading.displayName,
                                    icon: SensorType.heading.icon,
                                    count: viewModel.headingCount,
                                    color: SensorType.heading.color
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            // Sync to Controller
            SyncCard(session: session)

            // Export Options
            ExportCard(session: session)

            // Delete Button
            Button(role: .destructive, action: { showDeleteAlert = true }) {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Session")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundStyle(.red)
                .cornerRadius(12)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .alert("Delete Session?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteSession()
            }
        } message: {
            Text("This action cannot be undone. All sensor data for this session will be permanently deleted.")
        }
        .task {
            await viewModel.loadSessionData()
        }
    }
    
    private func deleteSession() {
        // Delete from SwiftData
        modelContext.delete(session)
        try? modelContext.save()
        
        // Delete files
        Task {
            do {
                try await StorageService.shared.deleteSession(session: session)
            } catch {
                print("Failed to delete session files: \(error)")
            }
        }
        
        // Dismiss view
        dismiss()
    }
}

// MARK: - Export Card

struct ExportCard: View {
    let session: Session
    @State private var showExporter = false
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.blue)
                Text("Export Session")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            Button(action: { exportAsZip() }) {
                HStack {
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "doc.zipper")
                    }
                    Text(isExporting ? "Creating ZIP..." : "Export as ZIP")
                    Spacer()
                    Image(systemName: "square.and.arrow.up")
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            .disabled(isExporting)
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .sheet(isPresented: $showExporter) {
            if let url = exportURL {
                DocumentExporter(url: url) {
                    showExporter = false
                    // Clean up after export
                    Task {
                        try? await ExportService.shared.cleanupOldExports()
                    }
                }
            }
        }
    }
    
    private func exportAsZip() {
        isExporting = true
        errorMessage = nil
        
        Task {
            do {
                let zipURL = try await ExportService.shared.createZIP(session: session)
                
                await MainActor.run {
                    self.exportURL = zipURL
                    self.isExporting = false
                    self.showExporter = true
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Export failed: \(error.localizedDescription)"
                    self.isExporting = false
                }
            }
        }
    }
}

// MARK: - Session Info Card

struct SessionInfoCard: View {
    let session: Session
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.blue)
                Text("Session Information")
                    .font(.headline)
            }
            
            Divider()
            
            InfoRow(label: "Date", value: formatDate(session.date))
            InfoRow(label: "Duration", value: formatDuration(session.duration))
            InfoRow(label: "Session ID", value: String((session.externalUUID ?? session.id.uuidString).prefix(6)))
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, secs)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Sensor Data Card

struct SensorDataCard: View {
    let title: String
    let icon: String
    let count: Int
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(count) data points")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Sync Card

struct SyncCard: View {
    let session: Session
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var watchCoordinator = WatchCoordinator.shared
    @State private var isSyncing = false
    @State private var isCheckingPreflight = false
    @State private var syncResult: SyncResult?
    @State private var preflightStatus: PreflightStatus?
    @State private var watchStatus: WatchSyncStatus = .unknown

    enum SyncResult {
        case success(Int)
        case error(String)
    }

    enum WatchSyncStatus: Equatable {
        case unknown
        case noData          // No watch data found for this session
        case hasData         // Watch data already synced locally
        case transferring(received: Int, expected: Int)
    }

    struct PreflightStatus {
        let recording: Bool
        let allSynced: Bool
        let anySyncing: Bool
        let totalSegments: Int
        let cameras: [CameraSync]

        struct CameraSync {
            let name: String
            let connected: Bool
            let syncStatus: String
            let segmentsOnCtlr: Int
            let segmentsExpected: Int
            let segmentsPending: Int
        }
    }

    private var controllerIP: String {
        AppConfig.Controller.ip
    }

    private var canSync: Bool {
        guard let status = preflightStatus else { return false }
        // Must have cameras synced - watch data is optional
        let camerasReady = !status.recording && status.allSynced && !status.anySyncing
        return camerasReady
    }

    private var preflightMessage: String? {
        guard let status = preflightStatus else { return nil }
        if status.recording { return "Recording in progress" }
        if status.anySyncing { return "Cameras syncing..." }
        if !status.allSynced {
            let pending = status.cameras.filter { $0.segmentsPending > 0 }
            if !pending.isEmpty {
                return "Waiting: \(pending.map { $0.name }.joined(separator: ", "))"
            }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.blue)
                Text("Sync to Controller")
                    .font(.headline)
                Spacer()
                if session.isSynced {
                    Label("Synced", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Divider()

            // Watch status
            HStack {
                Image(systemName: "applewatch")
                    .foregroundStyle(watchStatusColor)
                    .font(.caption)
                Text("Watch")
                    .font(.caption)
                Spacer()
                switch watchStatus {
                case .unknown:
                    Text("Checking...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                case .noData:
                    Text("No data")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                case .hasData:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Data Ready")
                            .foregroundStyle(.green)
                    }
                    .font(.caption2)
                case .transferring(let received, let expected):
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        if expected > 0 {
                            Text("\(received)/\(expected)")
                                .foregroundStyle(.orange)
                        } else {
                            Text("Syncing...")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption2)
                }
            }

            // Camera sync status
            if let status = preflightStatus {
                VStack(spacing: 8) {
                    ForEach(status.cameras, id: \.name) { cam in
                        HStack {
                            Image(systemName: cam.connected ? "video.fill" : "video.slash.fill")
                                .foregroundStyle(cam.connected ? .green : .red)
                                .font(.caption)
                            Text(cam.name.replacingOccurrences(of: "melb-01-", with: ""))
                                .font(.caption)
                            Spacer()
                            if cam.syncStatus == "syncing" {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                    Text("\(cam.segmentsOnCtlr)/\(cam.segmentsExpected)")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            } else if cam.syncStatus == "waiting" && cam.segmentsExpected > 0 {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                    Text("0/\(cam.segmentsExpected)")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            } else if cam.syncStatus == "partial" || (cam.segmentsExpected > 0 && cam.segmentsPending > 0) {
                                Text("\(cam.segmentsOnCtlr)/\(cam.segmentsExpected)")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                            } else if cam.syncStatus == "complete" || (cam.segmentsExpected > 0 && cam.segmentsPending == 0) {
                                HStack(spacing: 4) {
                                    Text("\(cam.segmentsOnCtlr)/\(cam.segmentsExpected)")
                                        .font(.caption2)
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                }
                            } else if cam.connected && cam.segmentsExpected == 0 {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                    Text("Waiting...")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("No data")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Upload button
            Button(action: { syncSession() }) {
                HStack {
                    if isSyncing {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Uploading...")
                    } else if isCheckingPreflight {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Checking...")
                    } else {
                        Image(systemName: "icloud.and.arrow.up")
                        Text("Upload All Data")
                    }
                    Spacer()
                    if !isSyncing && !isCheckingPreflight && canSync {
                        Image(systemName: "arrow.up.circle")
                    }
                }
                .padding()
                .background(canSync ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            .disabled(isSyncing || isCheckingPreflight || !canSync)

            // Preflight warning
            if let msg = preflightMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Result message
            if let result = syncResult {
                switch result {
                case .success(let count):
                    Text("Uploaded \(count) files - processing started")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .error(let msg):
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            // Show UUID
            if let uuid = session.externalUUID {
                Text("UUID: \(uuid.prefix(6))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Refresh button
            Button(action: { Task { await checkPreflight() } }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh Status")
                }
                .font(.caption)
                .foregroundStyle(.blue)
            }
            .disabled(isCheckingPreflight)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .task {
            await checkPreflight()
            await checkWatchStatus()

            // Auto-poll sync status every 3s while not fully synced
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }

                // Stop polling once all synced
                if let status = preflightStatus, status.allSynced && watchStatus == .hasData {
                    break
                }

                await checkPreflight()
                await checkWatchStatus()
            }
        }
        .onChange(of: watchCoordinator.isTransferring) {
            Task { await checkWatchStatus() }
        }
        .onChange(of: watchCoordinator.receivedFileCount) {
            Task { await checkWatchStatus() }
        }
        .onChange(of: watchCoordinator.transferComplete) {
            Task { await checkWatchStatus() }
        }
    }

    private var watchStatusColor: Color {
        switch watchStatus {
        case .unknown: return .secondary
        case .noData: return .secondary
        case .hasData: return .green
        case .transferring: return .orange
        }
    }

    private func checkWatchStatus() async {
        let sessionID = session.externalUUID ?? session.id.uuidString

        // Check if transfer is in progress for this session
        if watchCoordinator.isTransferring && watchCoordinator.currentTransferSessionID == sessionID {
            await MainActor.run {
                watchStatus = .transferring(
                    received: watchCoordinator.receivedFileCount,
                    expected: watchCoordinator.expectedFileCount
                )
            }
            return
        }

        // Check if we already have watch data locally
        let fileManager = FileManager.default
        guard let docURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            await MainActor.run { watchStatus = .noData }
            return
        }
        let sessionFolder = docURL.appendingPathComponent("Sessions").appendingPathComponent(session.folderPath)

        if WatchCoordinator.shared.hasWatchData(sessionFolder: sessionFolder) {
            await MainActor.run { watchStatus = .hasData }
        } else {
            await MainActor.run { watchStatus = .noData }
        }
    }

    private func checkPreflight() async {
        isCheckingPreflight = true
        defer { isCheckingPreflight = false }

        // Pass session UUID to check sync status for this specific session
        let sessionUUID = session.externalUUID ?? session.id.uuidString
        guard let url = URL(string: "http://\(controllerIP):8000/api/sync/status?uuid=\(sessionUUID)") else { return }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5.0
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(SyncStatusResponse.self, from: data)

            await MainActor.run {
                preflightStatus = PreflightStatus(
                    recording: response.recording,
                    allSynced: response.all_synced,
                    anySyncing: response.any_syncing,
                    totalSegments: response.total_segments ?? 0,
                    cameras: response.cameras.map { cam in
                        PreflightStatus.CameraSync(
                            name: cam.name,
                            connected: cam.connected,
                            syncStatus: cam.sync_status ?? "idle",
                            segmentsOnCtlr: cam.segments_on_ctlr ?? 0,
                            segmentsExpected: cam.segments_expected ?? 0,
                            segmentsPending: cam.segments_pending ?? 0
                        )
                    }
                )
            }
        } catch {
            // Failed to fetch - allow sync anyway
            await MainActor.run {
                preflightStatus = PreflightStatus(
                    recording: false,
                    allSynced: true,
                    anySyncing: false,
                    totalSegments: 0,
                    cameras: []
                )
            }
        }

        // Also refresh watch status
        await checkWatchStatus()
    }

    private func syncSession() {
        isSyncing = true
        syncResult = nil

        Task {
            // Upload all data to controller (phone + watch if available)
            do {
                let count = try await StorageService.shared.uploadSession(session: session)
                await MainActor.run {
                    session.isSynced = true
                    try? modelContext.save()  // Persist isSynced to database
                    syncResult = .success(count)
                    isSyncing = false
                }
            } catch {
                await MainActor.run {
                    syncResult = .error(error.localizedDescription)
                    isSyncing = false
                }
            }
        }
    }
}

// MARK: - Sync Status API Response

private struct SyncStatusResponse: Codable {
    let recording: Bool
    let uuid: String?
    let all_synced: Bool
    let any_syncing: Bool
    let total_segments: Int?
    let cameras: [CameraSyncStatus]

    struct CameraSyncStatus: Codable {
        let name: String
        let connected: Bool
        let sync_status: String?
        let segments_on_ctlr: Int?
        let segments_expected: Int?
        let segments_pending: Int?
        let last_sync: String?
    }
}

#Preview {
    NavigationStack {
        SessionDetailView(session: Session(date: Date()))
    }
}

