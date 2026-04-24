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
                                    title: "Accelerometer",
                                    icon: "figure.walk",
                                    count: viewModel.accelerometerCount,
                                    color: .blue
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if viewModel.gyroscopeCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .gyroscope)) {
                                SensorDataCard(
                                    title: "Gyroscope",
                                    icon: "rotate.3d",
                                    count: viewModel.gyroscopeCount,
                                    color: .green
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if viewModel.magnetometerCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .magnetometer)) {
                                SensorDataCard(
                                    title: "Magnetometer",
                                    icon: "scope",
                                    count: viewModel.magnetometerCount,
                                    color: .purple
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if viewModel.barometerCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .barometer)) {
                                SensorDataCard(
                                    title: "Barometer",
                                    icon: "barometer",
                                    count: viewModel.barometerCount,
                                    color: .orange
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if viewModel.gpsCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .gps)) {
                                SensorDataCard(
                                    title: "GPS",
                                    icon: "location.fill",
                                    count: viewModel.gpsCount,
                                    color: .red
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if viewModel.deviceMotionCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .deviceMotion)) {
                                SensorDataCard(
                                    title: "Device Motion",
                                    icon: "arrow.trianglehead.2.clockwise.rotate.90",
                                    count: viewModel.deviceMotionCount,
                                    color: .cyan
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if viewModel.headphoneMotionCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .headphoneMotion)) {
                                SensorDataCard(
                                    title: "AirPods Motion",
                                    icon: "airpods.gen3",
                                    count: viewModel.headphoneMotionCount,
                                    color: .mint
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if viewModel.headingCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .heading)) {
                                SensorDataCard(
                                    title: "Heading (Compass)",
                                    icon: "location.north.fill",
                                    count: viewModel.headingCount,
                                    color: .indigo
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
    @State private var isSyncing = false
    @State private var isCheckingPreflight = false
    @State private var isRequestingWatchData = false
    @State private var syncResult: SyncResult?
    @State private var preflightStatus: PreflightStatus?
    @State private var watchStatus: WatchSyncStatus = .unknown

    enum SyncResult {
        case success(Int)
        case error(String)
    }

    enum WatchSyncStatus {
        case unknown
        case notReachable
        case reachable
        case hasData
        case transferring
    }

    struct PreflightStatus {
        let recording: Bool
        let allSynced: Bool
        let anySyncing: Bool
        let cameras: [CameraSync]

        struct CameraSync {
            let name: String
            let connected: Bool
            let syncStatus: String
            let segmentsPending: Int
        }
    }

    private var controllerIP: String {
        AppConfig.Controller.ip
    }

    private var canSync: Bool {
        guard let status = preflightStatus else { return false }
        // Must have cameras synced AND watch must be reachable (unless already has data)
        let camerasReady = !status.recording && status.allSynced && !status.anySyncing
        let watchReady = watchStatus == .reachable || watchStatus == .hasData
        return camerasReady && watchReady
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
        if watchStatus == .notReachable {
            return "Connect Apple Watch to sync"
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
                case .notReachable:
                    Text("Not Connected")
                        .font(.caption2)
                        .foregroundStyle(.red)
                case .reachable:
                    Text("Ready")
                        .font(.caption2)
                        .foregroundStyle(.green)
                case .hasData:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Data Ready")
                            .foregroundStyle(.green)
                    }
                    .font(.caption2)
                case .transferring:
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Transferring...")
                            .foregroundStyle(.orange)
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
                                    Text("Syncing")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            } else if cam.segmentsPending > 0 {
                                Text("\(cam.segmentsPending) pending")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                            } else if cam.connected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Upload button
            Button(action: { syncSession() }) {
                HStack {
                    if isSyncing || isRequestingWatchData {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(isRequestingWatchData ? "Getting Watch Data..." : "Uploading...")
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
            .disabled(isSyncing || isCheckingPreflight || !canSync || isRequestingWatchData)

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
        }
    }

    private var watchStatusColor: Color {
        switch watchStatus {
        case .unknown: return .secondary
        case .notReachable: return .red
        case .reachable, .hasData: return .green
        case .transferring: return .orange
        }
    }

    private func checkWatchStatus() async {
        // Check if we already have watch data
        let fileManager = FileManager.default
        guard let docURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let sessionFolder = docURL.appendingPathComponent("Sessions").appendingPathComponent(session.folderPath)

        if WatchCoordinator.shared.hasWatchData(sessionFolder: sessionFolder) {
            await MainActor.run { watchStatus = .hasData }
            return
        }

        // Check if watch is reachable
        await MainActor.run {
            if WCSession.default.isReachable {
                watchStatus = .reachable
            } else {
                watchStatus = .notReachable
            }
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
                    cameras: response.cameras.map { cam in
                        PreflightStatus.CameraSync(
                            name: cam.name,
                            connected: cam.connected,
                            syncStatus: cam.sync_status ?? "idle",
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
            // Step 1: Request watch data if watch is reachable and we don't have data yet
            if watchStatus == .reachable, let sessionID = session.externalUUID ?? Optional(session.id.uuidString) {
                await MainActor.run {
                    isRequestingWatchData = true
                    watchStatus = .transferring
                }

                let watchSuccess = await WatchCoordinator.shared.requestSessionData(
                    sessionID: sessionID,
                    timeout: 30
                )

                await MainActor.run {
                    isRequestingWatchData = false
                    watchStatus = watchSuccess ? .hasData : .reachable
                }

                if !watchSuccess {
                    await MainActor.run {
                        syncResult = .error("Failed to get watch data")
                        isSyncing = false
                    }
                    return
                }
            }

            // Step 2: Upload all data to controller
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
    let cameras: [CameraSyncStatus]

    struct CameraSyncStatus: Codable {
        let name: String
        let connected: Bool
        let sync_status: String?
        let segments_local: Int?
        let segments_on_ctlr: Int?
        let segments_pending: Int?
        let error: String?
    }
}

#Preview {
    NavigationStack {
        SessionDetailView(session: Session(date: Date()))
    }
}

