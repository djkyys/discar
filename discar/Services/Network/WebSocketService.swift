//
//  WebSocketService.swift
//  discar
//
//  WebSocket client for real-time ctlr status updates

import Foundation
import Combine

@MainActor
class WebSocketService: ObservableObject {

    // MARK: - Connection State

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting(attempt: Int)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }

        var displayText: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting..."
            case .connected: return "Connected"
            case .reconnecting(let attempt): return "Reconnecting (\(attempt))..."
            }
        }
    }

    // MARK: - Published State

    @Published var connectionState: ConnectionState = .disconnected
    @Published var lastError: String?

    // Component states
    @Published var controller: ControllerStatus?
    @Published var cameras: [CameraStatus] = []
    @Published var system: SystemStatus?
    @Published var can: CANStatus?
    @Published var storage: StorageStatus?
    @Published var syncProgress: [String: SyncProgress] = [:]

    // MARK: - Data Types

    struct ControllerStatus: Equatable {
        let ready: Bool
        let recording: Bool
        let uuid: String?
        let duration: Int
    }

    struct CameraStatus: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let connected: Bool
        let state: String
        let segment: Int?
        let cpu: Double?
        let ram: Double?
        let diskFreeGB: Double?
        let temp: Double?
        let syncStatus: String?
        let syncSegmentsSynced: Int?
        let syncSegmentsQueued: Int?
    }

    struct SystemStatus: Equatable {
        let cpuPercent: Double
        let memPercent: Double
        let tempC: Double
    }

    struct CANStatus: Equatable {
        let connected: Bool
        let frameCount: Int
        let fileSizeBytes: Int
    }

    struct StorageStatus: Equatable {
        let healthy: Bool
        let loggingMounted: Bool
        let loggingFreeGB: Double
        let syncMounted: Bool
        let syncFreeGB: Double
    }

    struct SyncProgress: Equatable {
        let camera: String
        let synced: Int
        let queued: Int
        let status: String
    }

    // MARK: - Private Properties

    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var isManuallyDisconnected = false
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 10
    private let baseReconnectDelay: TimeInterval = 1.0

    private var webSocketURL: URL? {
        URL(string: AppConfig.Controller.wsURL)
    }

    // MARK: - Singleton

    static let shared = WebSocketService()

    private init() {}

    // MARK: - Connection Management

    func connect() {
        guard connectionState != .connected && connectionState != .connecting else { return }
        guard let url = webSocketURL else {
            lastError = "Invalid WebSocket URL"
            return
        }

        isManuallyDisconnected = false
        connectionState = .connecting
        lastError = nil

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        receiveMessage()
        startPingLoop()

        // Set connected after brief delay (connection is async)
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if webSocketTask?.state == .running {
                connectionState = .connected
                reconnectAttempt = 0
            }
        }
    }

    func disconnect() {
        isManuallyDisconnected = true
        cleanupConnection()
        connectionState = .disconnected
    }

    private func cleanupConnection() {
        pingTask?.cancel()
        pingTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    private func handleDisconnection() {
        cleanupConnection()

        guard !isManuallyDisconnected else {
            connectionState = .disconnected
            return
        }

        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard reconnectAttempt < maxReconnectAttempts else {
            connectionState = .disconnected
            lastError = "Max reconnection attempts reached"
            return
        }

        reconnectAttempt += 1
        connectionState = .reconnecting(attempt: reconnectAttempt)

        // Exponential backoff: 1s, 2s, 4s, 8s, max 30s
        let delay = min(baseReconnectDelay * pow(2.0, Double(reconnectAttempt - 1)), 30.0)

        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            connect()
        }
    }

    // MARK: - Message Handling

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                switch result {
                case .success(let message):
                    self?.handleMessage(message)
                    self?.receiveMessage() // Continue listening

                case .failure(let error):
                    self?.lastError = error.localizedDescription
                    self?.handleDisconnection()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseMessage(text)
            }
        @unknown default:
            break
        }
    }

    private func parseMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "initial":
            if let initialData = json["data"] as? [String: Any] {
                parseInitialState(initialData)
            }

        case "controller":
            if let ctrlData = json["data"] as? [String: Any] {
                controller = parseController(ctrlData)
            }

        case "cameras":
            if let camerasData = json["data"] as? [[String: Any]] {
                cameras = camerasData.compactMap { parseCamera($0) }
            }

        case "camera":
            if let cameraData = json["data"] as? [String: Any],
               let updated = parseCamera(cameraData) {
                if let index = cameras.firstIndex(where: { $0.name == updated.name }) {
                    cameras[index] = updated
                } else {
                    cameras.append(updated)
                }
            }

        case "system":
            if let sysData = json["data"] as? [String: Any] {
                system = parseSystem(sysData)
            }

        case "can":
            if let canData = json["data"] as? [String: Any] {
                can = parseCAN(canData)
            }

        case "storage":
            if let storageData = json["data"] as? [String: Any] {
                storage = parseStorage(storageData)
            }

        case "sync":
            if let syncData = json["data"] as? [String: Any],
               let progress = parseSyncProgress(syncData) {
                syncProgress[progress.camera] = progress
            }

        case "ping":
            // Server ping, ignore or respond
            break

        default:
            break
        }
    }

    private func parseInitialState(_ data: [String: Any]) {
        if let ctrlData = data["controller"] as? [String: Any] {
            controller = parseController(ctrlData)
        }

        if let camerasData = data["cameras"] as? [[String: Any]] {
            cameras = camerasData.compactMap { parseCamera($0) }
        }

        if let sysData = data["system"] as? [String: Any] {
            system = parseSystem(sysData)
        }

        if let canData = data["can"] as? [String: Any] {
            can = parseCAN(canData)
        }

        if let storageData = data["storage"] as? [String: Any] {
            storage = parseStorage(storageData)
        }

        connectionState = .connected
    }

    // MARK: - Parsers

    private func parseController(_ data: [String: Any]) -> ControllerStatus? {
        guard let ready = data["ready"] as? Bool,
              let recording = data["recording"] as? Bool,
              let duration = data["duration"] as? Int else {
            return nil
        }

        return ControllerStatus(
            ready: ready,
            recording: recording,
            uuid: data["uuid"] as? String,
            duration: duration
        )
    }

    private func parseCamera(_ data: [String: Any]) -> CameraStatus? {
        guard let name = data["name"] as? String,
              let connected = data["connected"] as? Bool,
              let state = data["state"] as? String else {
            return nil
        }

        return CameraStatus(
            name: name,
            connected: connected,
            state: state,
            segment: data["segment"] as? Int,
            cpu: data["cpu"] as? Double,
            ram: data["ram"] as? Double,
            diskFreeGB: data["disk_free_gb"] as? Double,
            temp: data["temp"] as? Double,
            syncStatus: data["sync_status"] as? String,
            syncSegmentsSynced: data["sync_segments_synced"] as? Int,
            syncSegmentsQueued: data["sync_segments_queued"] as? Int
        )
    }

    private func parseSystem(_ data: [String: Any]) -> SystemStatus? {
        guard let cpu = data["cpu_percent"] as? Double,
              let mem = data["mem_percent"] as? Double else {
            return nil
        }

        return SystemStatus(
            cpuPercent: cpu,
            memPercent: mem,
            tempC: data["temp_c"] as? Double ?? 0
        )
    }

    private func parseCAN(_ data: [String: Any]) -> CANStatus? {
        guard let connected = data["connected"] as? Bool,
              let frameCount = data["frame_count"] as? Int else {
            return nil
        }

        return CANStatus(
            connected: connected,
            frameCount: frameCount,
            fileSizeBytes: data["file_size_bytes"] as? Int ?? 0
        )
    }

    private func parseStorage(_ data: [String: Any]) -> StorageStatus? {
        let logging = data["logging"] as? [String: Any]
        let sync = data["sync"] as? [String: Any]

        return StorageStatus(
            healthy: data["healthy"] as? Bool ?? false,
            loggingMounted: logging?["accessible"] as? Bool ?? false,
            loggingFreeGB: logging?["free_gb"] as? Double ?? 0,
            syncMounted: sync?["accessible"] as? Bool ?? false,
            syncFreeGB: sync?["free_gb"] as? Double ?? 0
        )
    }

    private func parseSyncProgress(_ data: [String: Any]) -> SyncProgress? {
        guard let camera = data["camera"] as? String,
              let synced = data["synced"] as? Int,
              let queued = data["queued"] as? Int,
              let status = data["status"] as? String else {
            return nil
        }

        return SyncProgress(camera: camera, synced: synced, queued: queued, status: status)
    }

    // MARK: - Ping Loop

    private func startPingLoop() {
        pingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25_000_000_000) // 25 seconds
                guard !Task.isCancelled else { return }

                webSocketTask?.sendPing { [weak self] error in
                    if error != nil {
                        Task { @MainActor [weak self] in
                            self?.handleDisconnection()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    var isRecording: Bool {
        controller?.recording ?? false
    }

    var isSystemReady: Bool {
        controller?.ready ?? false
    }

    var connectedCamerasCount: Int {
        cameras.filter { $0.connected }.count
    }

    var totalCamerasCount: Int {
        cameras.count
    }
}
