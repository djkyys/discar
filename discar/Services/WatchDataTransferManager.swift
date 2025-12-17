//
//  WatchDataTransferManager.swift
//  discar
//
//  Created by Drogba on 2025/11/24.
//

import Foundation
import WatchConnectivity
import Combine

class WatchDataTransferManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchDataTransferManager()
    
    @Published var isTransferring = false
    @Published var transferProgress: Double = 0
    @Published var lastTransferredFile: String?
    
    override init() {
        super.init()
        // WCSession is likely already activated by ConnectivityManager, but we assign delegate here if needed.
        // Note: Only one delegate is allowed per session. We might need to merge this with ConnectivityManager
        // or have ConnectivityManager delegate calls to us.
        // For now, assuming ConnectivityManager handles the session, we will inject logic there.
    }
    
    // Called when a file is received from Watch
    func handleReceivedFile(_ file: WCSessionFile) {
        guard let sessionID = file.metadata?["sessionID"] as? String,
              let filename = file.metadata?["filename"] as? String else { return }
        
        print("Received file from watch: \(filename) for session \(sessionID)")
        
        Task {
            await saveWatchFile(sourceURL: file.fileURL, sessionID: sessionID, filename: filename)
        }
    }
    
    private func saveWatchFile(sourceURL: URL, sessionID: String, filename: String) async {
        let fileManager = FileManager.default
        guard let docURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        // Destination: Documents/SessionID/watch_filename.json
        let sessionDir = docURL.appendingPathComponent(sessionID)
        let destURL = sessionDir.appendingPathComponent("watch_\(filename)")
        
        do {
            try fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)
            
            // If file exists, remove it first
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            
            try fileManager.moveItem(at: sourceURL, to: destURL)
            print("Saved watch file to: \(destURL.path)")
            
            DispatchQueue.main.async {
                self.lastTransferredFile = filename
            }
            
        } catch {
            print("Failed to save watch file: \(error)")
        }
    }
    
    // MARK: - WCSessionDelegate Stubs (Not used directly if integrated into ConnectivityManager)
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {}
}

