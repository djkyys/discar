//
//  StatusViewModel.swift
//  discar
//

import Foundation
import Combine
import SwiftData

@MainActor
class StatusViewModel: ObservableObject {
    // MARK: - Published Properties (UI State)
    @Published var totalSessions: Int = 0
    @Published var totalTimeInSeconds: Int = 0
    @Published var averageSessionInSeconds: Int = 0
    @Published var lastSessionDate: String? = nil

    // Controller Status
    @Published var ctlrStatus: CtlrStatus = .disconnected
    @Published var ctlrMessage: String = "Not Connected"

    // Live Data
    @Published var connectedCameras: String = "-/-"
    @Published var isRecording: Bool = false
    @Published var recordingDuration: Int = 0
    @Published var recordingUUID: String?

    // Camera List
    @Published var cameraNodes: [CameraNode] = []

    // System Stats
    @Published var storageUsedGB: Double = 0
    @Published var storageTotalGB: Double = 0
    @Published var storagePercent: Double = 0
    @Published var cpuPercent: Double = 0
    @Published var memPercent: Double = 0
    @Published var tempC: Double = 0

    // CAN Bus Status
    @Published var canConnected: Bool = false
    @Published var canFrameCount: Int = 0

    // Storage Health
    @Published var storageHealthy: Bool = true
    @Published var loggingMounted: Bool = true
    @Published var loggingFreeGB: Double = 0
    @Published var syncMounted: Bool = true
    @Published var syncFreeGB: Double = 0
    @Published var isRemounting: Bool = false
    @Published var isUnmounting: Bool = false
    @Published var unmountMessage: String?
    @Published var storageError: String?

    struct CameraNode: Identifiable {
        let id = UUID()
        let name: String
        let connected: Bool
        let state: String
        let segment: Int?
        let cpu: Double?
        let ram: Double?
        let diskFreeGB: Double?
        let temp: Double?
        // Sync status
        let syncStatus: String?
        let syncSegmentsSynced: Int?
        let syncSegmentsQueued: Int?
        let segmentsOnCtlr: Int?
        let syncError: String?
    }

    // MARK: - Private Properties
    private var modelContext: ModelContext?
    private var pollTimer: AnyCancellable?

    private var controllerIP: String {
        UserDefaults.standard.string(forKey: "controllerIP") ?? "192.168.8.145"
    }

    private var baseURL: String {
        "http://\(controllerIP):8000"
    }

    // MARK: - Enums
    enum CtlrStatus {
        case disconnected
        case connecting
        case ready
        case recording
        case error
    }

    // MARK: - Initialization & Context
    func updateModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Polling Logic

    func startPolling() {
        // Poll every 5 seconds
        pollTimer = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.fetchStatus() }
            }

        // Initial fetch
        Task {
            await fetchStatus()
            await fetchStorageStatus()
        }
    }

    func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    func fetchStatus() async {
        guard let url = URL(string: "\(baseURL)/api/status") else {
            ctlrStatus = .error
            ctlrMessage = "Invalid URL"
            return
        }

        if ctlrStatus == .disconnected {
            ctlrStatus = .connecting
            ctlrMessage = "Connecting..."
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                ctlrStatus = .error
                ctlrMessage = "Server Error"
                return
            }

            let status = try JSONDecoder().decode(StatusAPIResponse.self, from: data)

            // Update camera info
            let totalCams = status.cameras.count
            let onlineCams = status.cameras.filter { $0.connected }.count
            connectedCameras = "\(onlineCams)/\(totalCams)"

            cameraNodes = status.cameras.map { cam in
                CameraNode(
                    name: cam.name,
                    connected: cam.connected,
                    state: cam.state.capitalized,
                    segment: cam.segment,
                    cpu: cam.cpu,
                    ram: cam.ram,
                    diskFreeGB: cam.disk_free_gb,
                    temp: cam.temp,
                    syncStatus: cam.sync_status,
                    syncSegmentsSynced: cam.sync_segments_synced,
                    syncSegmentsQueued: cam.sync_segments_queued,
                    segmentsOnCtlr: cam.segments_on_ctlr,
                    syncError: cam.sync_error
                )
            }

            // Update recording status
            isRecording = status.recording
            recordingDuration = status.duration
            recordingUUID = status.uuid

            // Update system stats
            if let storage = status.storage {
                storageUsedGB = storage.used_gb
                storageTotalGB = storage.total_gb
                storagePercent = storage.percent
            }
            if let system = status.system {
                cpuPercent = system.cpu_percent
                memPercent = system.mem_percent
                tempC = system.temp_c ?? 0
            }
            if let can = status.can {
                canConnected = can.connected
                canFrameCount = can.frame_count
            }

            if status.recording {
                ctlrStatus = .recording
                ctlrMessage = "Recording (\(status.duration)s)"
            } else if status.ready {
                ctlrStatus = .ready
                ctlrMessage = "System Ready"
            } else {
                ctlrStatus = .error
                ctlrMessage = "Cameras Not Ready"
            }

        } catch {
            ctlrStatus = .disconnected
            ctlrMessage = "Connection Failed"
            connectedCameras = "-/-"
            cameraNodes = []
        }
    }

    // MARK: - Session Data Logic

    var totalTimeFormatted: String {
        formatTime(totalTimeInSeconds)
    }

    var averageSessionFormatted: String {
        formatTime(averageSessionInSeconds)
    }

    func loadData() {
        // Start polling when view appears
        startPolling()

        guard let modelContext = modelContext else { return }

        let descriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        do {
            let sessions = try modelContext.fetch(descriptor)
            totalSessions = sessions.count

            if !sessions.isEmpty {
                totalTimeInSeconds = Int(sessions.reduce(0) { $0 + $1.duration })
                averageSessionInSeconds = totalTimeInSeconds / totalSessions

                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                lastSessionDate = formatter.string(from: sessions.first!.date)
            } else {
                totalTimeInSeconds = 0
                averageSessionInSeconds = 0
                lastSessionDate = nil
            }
        } catch {
            print("Error loading data: \(error)")
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    // MARK: - Storage Health

    func fetchStorageStatus() async {
        guard let url = URL(string: "\(baseURL)/api/storage/status") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let status = try JSONDecoder().decode(StorageStatusResponse.self, from: data)

            storageHealthy = status.healthy
            loggingMounted = status.logging.accessible
            loggingFreeGB = status.logging.free_gb
            syncMounted = status.sync.accessible
            syncFreeGB = status.sync.free_gb
        } catch {
            storageHealthy = false
        }
    }

    func remountStorage() async {
        guard !isRemounting else { return }
        guard let url = URL(string: "\(baseURL)/api/storage/remount") else {
            storageError = "Invalid URL"
            return
        }

        isRemounting = true
        storageError = nil

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                isRemounting = false
                storageError = "Invalid response"
                return
            }

            if httpResponse.statusCode != 200 {
                isRemounting = false
                storageError = "Server error (\(httpResponse.statusCode))"
                return
            }

            let result = try JSONDecoder().decode(RemountResponse.self, from: data)

            if result.success {
                // Wait a moment for mounts to stabilize before refreshing
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                await fetchStorageStatus()
            } else {
                storageError = "Remount failed"
            }

            isRemounting = false
        } catch {
            isRemounting = false
            storageError = "Network error"
        }
    }

    func unmountSync() async {
        guard !isUnmounting else { return }
        guard let url = URL(string: "\(baseURL)/api/storage/unmount?mount=sync") else {
            storageError = "Invalid URL"
            return
        }

        isUnmounting = true
        unmountMessage = nil
        storageError = nil

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                isUnmounting = false
                storageError = "Invalid response"
                return
            }

            if httpResponse.statusCode != 200 {
                isUnmounting = false
                storageError = "Server error (\(httpResponse.statusCode))"
                return
            }

            let result = try JSONDecoder().decode(UnmountResponse.self, from: data)

            if result.success {
                unmountMessage = result.message ?? "Drive ejected safely"
                // Wait a moment then refresh status
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
                await fetchStorageStatus()
            } else {
                storageError = result.message ?? "Unmount failed"
            }

            isUnmounting = false
        } catch {
            isUnmounting = false
            storageError = "Network error"
        }
    }
}

// MARK: - API Response Model

private struct StatusAPIResponse: Codable {
    let ready: Bool
    let recording: Bool
    let uuid: String?
    let duration: Int
    let cameras: [CameraStatus]
    let storage: StorageInfo?
    let system: SystemInfo?
    let can: CANInfo?

    struct CANInfo: Codable {
        let connected: Bool
        let frame_count: Int
    }

    struct CameraStatus: Codable {
        let name: String
        let connected: Bool
        let state: String
        let segment: Int?
        let cpu: Double?
        let ram: Double?
        let disk_free_gb: Double?
        let temp: Double?
        // Sync status
        let sync_status: String?
        let sync_segments_synced: Int?
        let sync_segments_queued: Int?
        let segments_on_ctlr: Int?
        let sync_error: String?
    }

    struct StorageInfo: Codable {
        let used_gb: Double
        let total_gb: Double
        let percent: Double
    }

    struct SystemInfo: Codable {
        let cpu_percent: Double
        let mem_percent: Double
        let temp_c: Double?
    }
}

private struct StorageStatusResponse: Codable {
    let logging: MountStatus
    let sync: MountStatus
    let healthy: Bool

    struct MountStatus: Codable {
        let path: String
        let mounted: Bool
        let accessible: Bool
        let free_gb: Double
        let total_gb: Double
    }
}

private struct RemountResponse: Codable {
    let success: Bool
}

private struct UnmountResponse: Codable {
    let success: Bool
    let mount: String?
    let message: String?
}
