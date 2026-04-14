//
//  ConnectivityManager.swift
//  discar
//

import Foundation
import WatchConnectivity
import Combine

class ConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = ConnectivityManager()
    
    @Published var receivedCommand: WatchCommand?
    @Published var isWatchConnected: Bool = false
    
    enum WatchCommand: String {
        case startRecording
        case stopRecording
        case getStatus
    }
    
    override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }
    
    func sendStatusToWatch(isRecording: Bool, duration: TimeInterval = 0, sessionID: String? = nil) {
        guard WCSession.default.activationState == .activated else { return }
        
        var message: [String: Any] = [
            "isRecording": isRecording,
            "duration": duration
        ]
        
        if let sessionID = sessionID {
            message["sessionID"] = sessionID
        }
        
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("Error sending status to watch: \(error.localizedDescription)")
        }
    }
    
    func sendErrorToWatch(_ errorMessage: String) {
        guard WCSession.default.activationState == .activated else { return }
        
        let message: [String: Any] = ["error": errorMessage]
        WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Delegate file handling to the Transfer Manager
        WatchDataTransferManager.shared.handleReceivedFile(file)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            if let commandString = message["command"] as? String,
               let command = WatchCommand(rawValue: commandString) {
                self.receivedCommand = command
                
                if command == .getStatus {
                    // Handled by RecordViewModel to provide accurate state
                }
            }
        }
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isWatchConnected = session.isReachable
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) { }
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchConnected = session.isReachable
        }
    }
}


