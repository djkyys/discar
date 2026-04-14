//
//  WatchConnectionManager.swift
//  discarWatch Watch App
//

import Foundation
import WatchConnectivity
import Combine

class WatchConnectionManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectionManager()
    
    @Published var isRecording = false
    @Published var isPhoneReachable = false
    @Published var errorMessage: String?
    
    override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }
    
    func checkPhoneStatus() {
        // Optimistically assume reachable if session is active, real check happens on send
        isPhoneReachable = WCSession.default.activationState == .activated && WCSession.default.isReachable
        
        if isPhoneReachable {
            sendMessage(["command": "getStatus"])
        } else {
            errorMessage = "Phone not reachable"
        }
    }
    
    func sendStartCommand() {
        sendMessage(["command": "startRecording"])
    }
    
    func sendStopCommand() {
        sendMessage(["command": "stopRecording"])
    }
    
    private func sendMessage(_ message: [String: Any]) {
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else {
            isPhoneReachable = false
            errorMessage = "Phone not reachable"
            return
        }
        
        isPhoneReachable = true
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            DispatchQueue.main.async {
                self.isPhoneReachable = false
                self.errorMessage = "Failed to send: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            // If we receive any message, the phone is reachable
            self.isPhoneReachable = true
            self.errorMessage = nil // Clear errors on success
            
            if let recordingState = message["isRecording"] as? Bool {
                let sessionID = message["sessionID"] as? String
                let currentlyRecording = WatchSensorManager.shared.isRecording
                
                print("📩 Received message - isRecording: \(recordingState), sessionID: \(sessionID ?? "nil")")
                print("📩 Current WatchSensorManager.isRecording: \(currentlyRecording)")
                
                self.isRecording = recordingState
                
                Task { @MainActor in
                    if recordingState {
                        // If already recording, this should resume (maintenance) not restart (new UUID)
                        let shouldResume = currentlyRecording
                        await WatchSensorManager.shared.startRecording(sessionID: sessionID, resume: shouldResume)
                    } else {
                        await WatchSensorManager.shared.stopRecording()
                    }
                }
            }
            
            if let error = message["error"] as? String {
                self.errorMessage = error
            }
        }
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.checkPhoneStatus()
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isPhoneReachable = session.isReachable
        }
    }
}

