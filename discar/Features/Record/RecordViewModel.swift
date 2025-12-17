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
    
    private let sensorManager = SensorManager()
    private var modelContext: ModelContext
    private var currentSession: Session?
    private var cancellables = Set<AnyCancellable>()
    
    private var isTestMode: Bool {
        UserDefaults.standard.bool(forKey: "isTestMode")
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
                        // If watch asks for status, we just confirm our current state
                        // This helps the watch know we are reachable
                        ConnectivityManager.shared.sendStatusToWatch(isRecording: self?.isRecording ?? false)
                    }
                    // Reset so it can fire again
                    ConnectivityManager.shared.receivedCommand = nil
                }
            }
            .store(in: &cancellables)
        
        // Pre-warm sensors asynchronously to avoid lag on first record
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
        if !isTestMode {
            do {
                try await checkPiReadiness()
            } catch {
                logger.error("Readiness check failed: \(error.localizedDescription)")
                showError(message: "System Not Ready: \(error.localizedDescription)")
                isStarting = false
                return
            }
            
            // 2. Start Pi Recording
            do {
                try await sendPiStartCommand()
            } catch {
                logger.error("Pi Start failed: \(error.localizedDescription)")
                showError(message: "Failed to start cameras: \(error.localizedDescription)")
                isStarting = false
                return
            }
        } else {
            logger.notice("⚠️ Test Mode: Skipping Pi Readiness and Start checks")
        }
        
            // 3. Start Local Recording (Only if steps 1 & 2 succeeded)
            let session = Session(date: Date())
            currentSession = session
            
            do {
                try await StorageService.shared.createSessionFolder(session: session)
                sensorManager.startRecording(session: session)
                
                logger.info("Local recording started: \(session.id.uuidString)")
                
                // Notify Watch with Session ID
                ConnectivityManager.shared.sendStatusToWatch(isRecording: true, sessionID: session.id.uuidString)
                
                // Start OBD Recording (Fire and Forget)
                if !isTestMode {
                    OBDService.shared.startSession(sessionID: session.id.uuidString)
                } else {
                    logger.notice("⚠️ Test Mode: Skipping OBD start command")
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
            logger.notice("⚠️ Test Mode: Skipping OBD stop command")
        }
        
        if let session = currentSession {
            session.duration = currentDuration
            modelContext.insert(session)
            
            do {
                try modelContext.save()
                logger.info("Session saved: \(session.id.uuidString)")
            } catch {
                logger.error("Failed to save session: \(error.localizedDescription)")
            }
        }
        currentSession = nil
        
        // 2. Stop Pi Recording
        if !isTestMode {
            do {
                try await sendPiStopCommand()
            } catch {
                logger.error("Pi Stop Warning: \(error.localizedDescription)")
                // Note: We don't show an alert here because local data is already safe.
                // Just log it.
            }
        } else {
            logger.notice("⚠️ Test Mode: Skipping Pi Stop command")
        }
    }
    
    private func showError(message: String) {
        self.errorMessage = message
        self.showError = true
    }
    
    // MARK: - API Calls
    
    private func checkPiReadiness() async throws {
        guard let url = URL(string: "http://raspberrypi.local:8000/recording/status") else {
            throw PiError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 3.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let jsonString = String(data: data, encoding: .utf8) {
            logger.info("🔍 Readiness Check Response: \(jsonString)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PiError.serverError
        }
        
        let status = try JSONDecoder().decode(PiStatusResponse.self, from: data)
        
        // Validation Logic
        if status.recording {
            throw PiError.alreadyRecording
        }
        
        // Check if any node is NOT connected or NOT idle
        // Safe unwrapping since fields are now optional
        let notReadyNodes = status.nodes.filter { 
            // If 'connected' is missing, assume TRUE if state exists
            let isConnected = $0.connected ?? true 
            let state = $0.state ?? "unknown"
            let isIdle = state == "idle"
            
            return !isConnected || !isIdle
        }
        
        if !notReadyNodes.isEmpty {
            let names = notReadyNodes.map { $0.name }.joined(separator: ", ")
            throw PiError.nodesNotReady(names)
        }
    }
    
    private func sendPiStartCommand() async throws {
        guard let url = URL(string: "http://raspberrypi.local:8000/recording/start") else {
            throw PiError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 200 {
                return // Success
            } else if httpResponse.statusCode == 409 {
                // Conflict - Parse error
                if let errorResponse = try? JSONDecoder().decode(PiErrorResponse.self, from: data) {
                    throw PiError.custom(errorResponse.error)
                }
            }
        }
        throw PiError.serverError
    }
    
    private func sendPiStopCommand() async throws {
        guard let url = URL(string: "http://raspberrypi.local:8000/recording/stop/synchronized") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10.0 // Allow time for sync
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PiError.serverError
        }
    }
}

// MARK: - Models & Errors

enum PiError: LocalizedError {
    case invalidURL
    case serverError
    case alreadyRecording
    case nodesNotReady(String)
    case custom(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Pi URL"
        case .serverError: return "Pi Server Error or Unreachable"
        case .alreadyRecording: return "System is already recording"
        case .nodesNotReady(let names): return "Cameras not ready: \(names)"
        case .custom(let msg): return msg
        }
    }
}

// Request 1: Check Readiness
struct PiStatusResponse: Codable {
    let recording: Bool
    let nodes: [PiNodeStatus]
}

struct PiNodeStatus: Codable {
    let name: String
    let state: String?
    let connected: Bool?
}

// Request 2: Start Error Response (409)
struct PiErrorResponse: Codable {
    let error: String
    let not_ready_nodes: [PiNodeError]?
}

struct PiNodeError: Codable {
    let name: String
    let reason: String
}
