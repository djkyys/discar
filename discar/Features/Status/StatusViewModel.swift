//
//  StatusViewModel.swift
//  discar
//
//  ViewModel for Status panel - uses WebSocket with HTTP fallback

import Foundation
import Combine
import SwiftData

@MainActor
class StatusViewModel: ObservableObject {

    // MARK: - Connection State

    @Published var connectionState: WebSocketService.ConnectionState = .disconnected

    // MARK: - Component States

    @Published var controller: WebSocketService.ControllerStatus?
    @Published var cameras: [WebSocketService.CameraStatus] = []
    @Published var system: WebSocketService.SystemStatus?
    @Published var can: WebSocketService.CANStatus?
    @Published var storage: WebSocketService.StorageStatus?
    @Published var syncProgress: [String: WebSocketService.SyncProgress] = [:]

    // MARK: - Session Stats (local data)

    @Published var totalSessions: Int = 0
    @Published var totalTimeInSeconds: Int = 0
    @Published var averageSessionInSeconds: Int = 0
    @Published var lastSessionDate: String? = nil

    // MARK: - Storage Actions State

    @Published var isRemounting: Bool = false
    @Published var isUnmounting: Bool = false
    @Published var unmountMessage: String?
    @Published var storageError: String?

    // MARK: - Convenience Accessors

    var isRecording: Bool {
        controller?.recording ?? false
    }

    var isReady: Bool {
        controller?.ready ?? false
    }

    var connectedCameras: String {
        let online = cameras.filter { $0.connected }.count
        return "\(online)/\(cameras.count)"
    }

    var totalTimeFormatted: String {
        formatTime(totalTimeInSeconds)
    }

    var averageSessionFormatted: String {
        formatTime(averageSessionInSeconds)
    }

    var recordingDuration: Int {
        controller?.duration ?? 0
    }

    // MARK: - Private Properties

    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    private let webSocket = WebSocketService.shared

    private var baseURL: String {
        AppConfig.Controller.baseURL
    }

    // MARK: - Initialization

    init() {
        setupBindings()
    }

    private func setupBindings() {
        // Bind WebSocket state to local published properties
        webSocket.$connectionState
            .receive(on: DispatchQueue.main)
            .assign(to: &$connectionState)

        webSocket.$controller
            .receive(on: DispatchQueue.main)
            .assign(to: &$controller)

        webSocket.$cameras
            .receive(on: DispatchQueue.main)
            .assign(to: &$cameras)

        webSocket.$system
            .receive(on: DispatchQueue.main)
            .assign(to: &$system)

        webSocket.$can
            .receive(on: DispatchQueue.main)
            .assign(to: &$can)

        webSocket.$storage
            .receive(on: DispatchQueue.main)
            .assign(to: &$storage)

        webSocket.$syncProgress
            .receive(on: DispatchQueue.main)
            .assign(to: &$syncProgress)
    }

    // MARK: - Context

    func updateModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Connection Control

    func connect() {
        webSocket.connect()
    }

    func disconnect() {
        webSocket.disconnect()
    }

    // MARK: - Session Data

    func loadSessionStats() {
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
            print("Error loading session stats: \(error)")
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

    // MARK: - Storage Actions

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
                // Storage status will be updated via WebSocket
                try? await Task.sleep(nanoseconds: 500_000_000)
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

// MARK: - Response Models

private struct RemountResponse: Codable {
    let success: Bool
}

private struct UnmountResponse: Codable {
    let success: Bool
    let mount: String?
    let message: String?
}
