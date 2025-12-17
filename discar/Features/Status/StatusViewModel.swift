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
    
    // Pi Status
    @Published var piStatus: PiStatus = .disconnected
    @Published var piMessage: String = "Tap to Connect"
    
    // Live Data
    @Published var lastHeartbeat: String = "Never"
    @Published var connectedCameras: String = "-/-"
    @Published var currentSpeed: Int = 0
    @Published var currentRPM: Int = 0
    
    // Dynamic Camera List
    @Published var cameraNodes: [CameraNode] = []
    
    struct CameraNode: Identifiable {
        let id = UUID()
        let name: String
        let connected: Bool
        let state: String
        let storageUsedPercent: Int
    }
    
    // MARK: - Private Properties
    private var modelContext: ModelContext?
    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTimer: AnyCancellable?
    
    // MARK: - Enums & Models
    enum PiStatus {
        case disconnected
        case connecting
        case connected // Connected but no specific status yet
        case idle      // System Ready
        case recording // System Recording
        case error     // Connection failed
    }
    
    // MARK: - Initialization & Context
    func updateModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - WebSocket Logic
    
    func connectToPi() {
        // Prevent double connection
        guard piStatus == .disconnected || piStatus == .error else { return }
        
        piStatus = .connecting
        piMessage = "Connecting..."
        
        // Create URL
        guard let url = URL(string: "ws://raspberrypi.local:8000/ws") else {
            piStatus = .error
            piMessage = "Invalid URL"
            return
        }
        
        // Start Connection
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // Start listening loop
        listenForMessages()
        
        // Start Ping Timer (Keep-alive)
        startPingTimer()
    }
    
    func disconnectPi() {
        pingTimer?.cancel()
        pingTimer = nil
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        piStatus = .disconnected
        piMessage = "Tap to Connect"
    }
    
    private func startPingTimer() {
        pingTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sendPing()
            }
    }
    
    private func sendPing() {
        let json = "{\"type\":\"ping\",\"timestamp\":\(Date().timeIntervalSince1970)}"
        let message = URLSessionWebSocketTask.Message.string(json)
        
        webSocketTask?.send(message) { error in
            if let error = error {
                print("Ping failed: \(error)")
            }
        }
    }
    
    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            // Jump to Main Thread to update UI
            Task { @MainActor in
                switch result {
                case .failure(let error):
                    print("WebSocket Error: \(error)")
                    self.piStatus = .error
                    self.piMessage = "Connection Failed"
                    // Stop pinging if failed
                    self.pingTimer?.cancel()
                    
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleJSON(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleJSON(text)
                        }
                    @unknown default:
                        break
                    }
                    
                    // Recursive call to keep listening
                    self.listenForMessages()
                }
            }
        }
    }
    
    private func handleJSON(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8) else { return }
        
        do {
            // 1. Decode just the 'type' first
            let root = try JSONDecoder().decode(WSMessageRoot.self, from: data)
            
            switch root.type {
            case "health_update":
                if let health = try? JSONDecoder().decode(WSHealthMessage.self, from: data) {
                    // Update Timestamp
                    let date = Date(timeIntervalSince1970: health.timestamp)
                    let formatter = DateFormatter()
                    formatter.timeStyle = .medium
                    lastHeartbeat = formatter.string(from: date)
                    
                    // Count Connected Cameras
                    // Hardcoded total expectation to 3
                    let totalCams = 3
                    let onlineCams = health.data.nodes.filter { $0.connected }.count
                    connectedCameras = "\(onlineCams)/\(totalCams)"
                    
                    // Map Nodes to UI Model
                    cameraNodes = health.data.nodes.map { node in
                        CameraNode(
                            name: node.name.capitalized,
                            connected: node.connected,
                            state: node.state?.capitalized ?? "Unknown",
                            storageUsedPercent: node.storage_percent_used ?? 0
                        )
                    }
                }
                
                if piStatus != .recording {
                    piStatus = .idle
                    piMessage = "System Ready"
                }
                
            case "obd_update":
                if let obd = try? JSONDecoder().decode(WSObdMessage.self, from: data) {
                    currentSpeed = obd.data.speed
                    currentRPM = obd.data.rpm
                }
                
            case "status_update":
                let status = try JSONDecoder().decode(WSStatusMessage.self, from: data)
                if status.data.recording {
                    piStatus = .recording
                    piMessage = "Recording (\(Int(status.data.duration))s)"
                } else {
                    piStatus = .idle
                    piMessage = "System Idle"
                }
                
            case "error":
                let errorMsg = try JSONDecoder().decode(WSErrorMessage.self, from: data)
                piStatus = .error
                piMessage = errorMsg.message
                
            case "ping":
                // Server ack, just ensure we show connected if we were just 'connecting'
                if piStatus == .connecting {
                    piStatus = .connected
                    piMessage = "Connected"
                }
                
            default:
                break
            }
        } catch {
            print("JSON Parse Error: \(error)")
            // Don't fail the connection on bad JSON, just ignore
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
        // Connect automatically when view appears
        connectToPi()
        
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
}

// MARK: - JSON Structs

struct WSMessageRoot: Codable {
    let type: String
}

struct WSStatusMessage: Codable {
    let type: String
    let data: StatusData
    
    struct StatusData: Codable {
        let recording: Bool
        let duration: TimeInterval
    }
}

struct WSErrorMessage: Codable {
    let type: String
    let message: String
    let severity: String
}

struct WSHealthMessage: Codable {
    let type: String
    let timestamp: TimeInterval
    let data: HealthData
    
    struct HealthData: Codable {
        let nodes: [NodeStatus]
    }
    
    struct NodeStatus: Codable {
        let name: String
        let connected: Bool
        let state: String? // Optional if missing in older logs
        let storage_percent_used: Int? // Optional
    }
}

struct WSObdMessage: Codable {
    let type: String
    let data: OBDData
    
    struct OBDData: Codable {
        let speed: Int
        let rpm: Int
    }
}
