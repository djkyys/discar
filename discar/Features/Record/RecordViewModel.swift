//
//  RecordViewModel.swift
//  discar
//

import SwiftUI
import SwiftData
import Combine
import OSLog

@MainActor
class RecordViewModel: ObservableObject {

    // UI State
    @Published var isRecording = false
    @Published var isStarting = false
    @Published var currentDuration: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var showError = false

    // Session UUID from ctlr
    @Published var currentUUID: String?

    private let sensorManager = SensorManager()
    private var modelContext: ModelContext
    private var currentSession: Session?
    private var cancellables = Set<AnyCancellable>()

    private var isTestMode: Bool {
        UserDefaults.standard.bool(forKey: "isTestMode")
    }

    private var controllerIP: String {
        UserDefaults.standard.string(forKey: "controllerIP") ?? "192.168.8.145"
    }

    private var baseURL: String {
        "http://\(controllerIP):8000"
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "discar", category: "RecordViewModel")

    init(modelContext: ModelContext) {
        let start = CFAbsoluteTimeGetCurrent()
        self.modelContext = modelContext

        // Auto-sync from SensorManager
        sensorManager.$isRecording.assign(to: &$isRecording)
        sensorManager.$currentDuration.assign(to: &$currentDuration)

        // Listen for Watch Commands
        ConnectivityManager.shared.$receivedCommand
            .compactMap { $0 }
            .sink { [weak self] command in
                Task { @MainActor [weak self] in
                    switch command {
                    case .startRecording:
                        await self?.startRecording()
                    case .stopRecording:
                        await self?.stopRecording()
                    case .getStatus:
                        ConnectivityManager.shared.sendStatusToWatch(
                            isRecording: self?.isRecording ?? false,
                            sessionID: self?.currentUUID
                        )
                    }
                    ConnectivityManager.shared.receivedCommand = nil
                }
            }
            .store(in: &cancellables)

        // Pre-warm sensors
        Task {
            sensorManager.warmUp()
        }

        let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
        logger.info("RecordViewModel.init took \(duration, format: .fixed(precision: 2))ms")
    }

    var durationFormatted: String {
        let h = Int(currentDuration) / 3600
        let m = (Int(currentDuration) % 3600) / 60
        let s = Int(currentDuration) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: - Recording Logic

    func startRecording() async {
        isStarting = true
        errorMessage = nil

        // 1. Check Readiness
        do {
            try await checkReadiness()
        } catch {
            if !isTestMode {
                logger.error("Readiness check failed: \(error.localizedDescription)")
                showError(message: "System Not Ready: \(error.localizedDescription)")
                isStarting = false
                return
            } else {
                logger.notice("Test Mode: Skipping Readiness Error: \(error.localizedDescription)")
            }
        }

        // 2. Check Watch Connectivity (skip in Test Mode)
        if !isTestMode && !ConnectivityManager.shared.isWatchConnected {
            logger.error("Watch not connected")
            showError(message: "Watch Not Connected. Please open the Watch App.")
            isStarting = false
            return
        } else if isTestMode {
            logger.notice("Test Mode: Skipping Watch connectivity check")
        }

        // 3. Start Recording via ctlr API - get UUID from response
        do {
            let startResponse = try await sendStartCommand()
            currentUUID = startResponse.uuid
            logger.info("Recording started with UUID: \(startResponse.uuid)")
        } catch {
            if !isTestMode {
                logger.error("Start failed: \(error.localizedDescription)")
                showError(message: "Failed to start cameras: \(error.localizedDescription)")
                isStarting = false
                return
            } else {
                logger.notice("Test Mode: Skipping Start Error: \(error.localizedDescription)")
                // Generate test session ID
                let timestamp = Int(Date().timeIntervalSince1970)
                currentUUID = "test-\(timestamp)"
            }
        }

        // 4. Start Local Recording with UUID from ctlr
        let session = Session(date: Date(), externalUUID: currentUUID)
        currentSession = session

        do {
            try await StorageService.shared.createSessionFolder(session: session)
            sensorManager.startRecording(session: session)

            logger.info("Local recording started: \(session.id.uuidString)")

            // Notify Watch with Session ID (use ctlr UUID)
            ConnectivityManager.shared.sendStatusToWatch(isRecording: true, sessionID: currentUUID)

            // Start OBD Recording
            if !isTestMode {
                OBDService.shared.startSession(sessionID: currentUUID ?? session.id.uuidString)
            } else {
                logger.notice("Test Mode: Skipping OBD start command")
            }

        } catch {
            logger.error("Failed to start local recording: \(error.localizedDescription)")
            showError(message: "Failed to start sensors: \(error.localizedDescription)")
            ConnectivityManager.shared.sendErrorToWatch("Sensor Error")
        }

        isStarting = false
    }

    func stopRecording() async {
        // 1. Stop Local Sensors First (Secure the data)
        await sensorManager.stopRecording()

        // Notify Watch
        ConnectivityManager.shared.sendStatusToWatch(isRecording: false)

        // Stop OBD Recording
        if !isTestMode {
            OBDService.shared.stopSession()
        } else {
            logger.notice("Test Mode: Skipping OBD stop command")
        }

        // Save session locally
        if let session = currentSession {
            session.duration = currentDuration
            modelContext.insert(session)

            do {
                try modelContext.save()
                logger.info("Session saved: \(session.id.uuidString), ctlr UUID: \(self.currentUUID ?? "none")")
            } catch {
                logger.error("Failed to save session: \(error.localizedDescription)")
            }
        }

        // 2. Stop via ctlr API
        do {
            let stopResponse = try await sendStopCommand()
            logger.info("Recording stopped: \(stopResponse.uuid), duration: \(stopResponse.duration)s")
        } catch {
            logger.error("Stop warning: \(error.localizedDescription)")
        }

        currentSession = nil
        currentUUID = nil
    }

    private func showError(message: String) {
        self.errorMessage = message
        self.showError = true
    }

    // MARK: - API Calls

    private func checkReadiness() async throws {
        guard let url = URL(string: "\(baseURL)/api/status") else {
            throw CtlrError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0

        let (data, response) = try await URLSession.shared.data(for: request)

        if let jsonString = String(data: data, encoding: .utf8) {
            logger.info("Status Response: \(jsonString)")
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CtlrError.serverError
        }

        let status = try JSONDecoder().decode(CtlrStatusResponse.self, from: data)

        if status.recording {
            throw CtlrError.alreadyRecording
        }

        if !status.ready {
            let notReady = status.cameras.filter { !$0.connected || $0.state != "idle" }
            let names = notReady.map { $0.name }.joined(separator: ", ")
            throw CtlrError.camerasNotReady(names)
        }
    }

    private func sendStartCommand() async throws -> CtlrStartResponse {
        guard let url = URL(string: "\(baseURL)/api/record/start") else {
            throw CtlrError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10.0

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CtlrError.serverError
        }

        if httpResponse.statusCode == 200 {
            return try JSONDecoder().decode(CtlrStartResponse.self, from: data)
        } else if httpResponse.statusCode == 409 {
            if let errorResponse = try? JSONDecoder().decode(CtlrErrorResponse.self, from: data) {
                throw CtlrError.custom(errorResponse.detail)
            }
            throw CtlrError.alreadyRecording
        } else if httpResponse.statusCode == 503 {
            if let errorResponse = try? JSONDecoder().decode(CtlrErrorResponse.self, from: data) {
                throw CtlrError.camerasNotReady(errorResponse.detail)
            }
        }

        throw CtlrError.serverError
    }

    private func sendStopCommand() async throws -> CtlrStopResponse {
        guard let url = URL(string: "\(baseURL)/api/record/stop") else {
            throw CtlrError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15.0

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CtlrError.serverError
        }

        return try JSONDecoder().decode(CtlrStopResponse.self, from: data)
    }
}

// MARK: - Models & Errors

enum CtlrError: LocalizedError {
    case invalidURL
    case serverError
    case alreadyRecording
    case camerasNotReady(String)
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Controller URL"
        case .serverError: return "Controller Error or Unreachable"
        case .alreadyRecording: return "System is already recording"
        case .camerasNotReady(let names): return "Cameras not ready: \(names)"
        case .custom(let msg): return msg
        }
    }
}

// GET /api/status
struct CtlrStatusResponse: Codable {
    let ready: Bool
    let recording: Bool
    let uuid: String?
    let duration: Int
    let cameras: [CtlrCameraStatus]
}

struct CtlrCameraStatus: Codable {
    let name: String
    let connected: Bool
    let state: String
}

// POST /api/record/start
struct CtlrStartResponse: Codable {
    let success: Bool
    let uuid: String
    let start_at: Int
}

// POST /api/record/stop
struct CtlrStopResponse: Codable {
    let success: Bool
    let uuid: String
    let duration: Int
}

// Error response
struct CtlrErrorResponse: Codable {
    let detail: String
}
