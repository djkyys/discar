//
//  OBDService.swift
//  discar
//
//  Created by Drogba on 2025/11/24.
//

import Foundation
import Combine

enum OBDConnectionState: String {
    case disconnected = "Disconnected"
    case checking = "Checking..."
    case connected = "Connected"
    case recording = "Recording"
    case error = "Error"
}

struct OBDStatusResponse: Codable {
    let service: String
    let connected: Bool
    let session_active: Bool
    let samples_collected: Int
}

struct OBDStartResponse: Codable {
    let status: String
    let session_id: String
    let log_file: String
}

class OBDService: ObservableObject {
    static let shared = OBDService()
    
    @Published var connectionState: OBDConnectionState = .disconnected
    @Published var isCarConnected: Bool = false
    @Published var samplesCollected: Int = 0
    
    private let baseURL = "http://raspberrypi.local:8001"
    private var statusTimer: Timer?
    
    private init() {
        startStatusCheck()
    }
    
    deinit {
        stopStatusCheck()
    }
    
    // MARK: - Status Polling
    
    func startStatusCheck() {
        // Poll every 10 seconds to check connectivity (Reduced frequency)
        statusTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkStatus()
        }
        checkStatus() // Initial check
    }
    
    func stopStatusCheck() {
        statusTimer?.invalidate()
        statusTimer = nil
    }
    
    func checkStatus() {
        guard let url = URL(string: "\(baseURL)/") else { return }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    // Reduce log noise for expected offline state
                    // print("OBD Check Error: \(error.localizedDescription)") 
                    self.connectionState = .disconnected
                    self.isCarConnected = false
                    return
                }
                
                guard let data = data else { return }
                
                do {
                    let status = try JSONDecoder().decode(OBDStatusResponse.self, from: data)
                    self.isCarConnected = status.connected
                    self.samplesCollected = status.samples_collected
                    
                    if status.session_active {
                        self.connectionState = .recording
                    } else if status.connected {
                        self.connectionState = .connected
                    } else {
                        // Service is up (HTTP 200) but car might be initializing
                        self.connectionState = .checking
                    }
                } catch {
                    print("OBD Decode Error: \(error)")
                    self.connectionState = .error
                }
            }
        }
        task.resume()
    }
    
    // MARK: - Session Management
    
    func startSession(sessionID: String) {
        guard let url = URL(string: "\(baseURL)/session/start") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["session_id": sessionID]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        print("OBD Service: Starting session \(sessionID)")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("OBD Start Session Error: \(error)")
                    // We don't block the app, just log it
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    print("OBD Session Started Successfully")
                    self?.connectionState = .recording
                } else {
                    print("OBD Start Failed with status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                }
            }
        }
        task.resume()
    }
    
    func stopSession() {
        guard let url = URL(string: "\(baseURL)/session/stop") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        print("OBD Service: Stopping session")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("OBD Stop Session Error: \(error)")
                    return
                }
                
                self?.checkStatus() // Refresh status immediately
            }
        }
        task.resume()
    }
}

