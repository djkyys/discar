//
//  WatchTransferCard.swift
//  discar
//
//  Created by Drogba on 2025/11/24.
//

import SwiftUI
import WatchConnectivity

struct WatchTransferCard: View {
    let session: Session
    @StateObject private var transferManager = WatchDataTransferManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "applewatch")
                    .foregroundStyle(.orange)
                Text("Watch Data")
                    .font(.headline)
                
                Spacer()
                
                if WCSession.default.isReachable {
                    Text("Connected")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("Not Connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            if hasWatchData() {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Watch data synced")
                        .font(.subheadline)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No watch data found for this session.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    if WCSession.default.isReachable {
                        Button(action: requestWatchSync) {
                            Text("Request Sync from Watch")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(8)
                                .background(Color.orange.opacity(0.1))
                                .foregroundStyle(.orange)
                                .cornerRadius(8)
                        }
                    } else {
                        Text("Connect Watch to sync data")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            if let lastFile = transferManager.lastTransferredFile {
                Text("Last received: \(lastFile)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func hasWatchData() -> Bool {
        let fileManager = FileManager.default
        guard let docURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return false }
        let sessionDir = docURL.appendingPathComponent(session.id.uuidString)
        let watchFile = sessionDir.appendingPathComponent("watch_heart_rate.json") // Check for key file
        return fileManager.fileExists(atPath: watchFile.path)
    }
    
    private func requestWatchSync() {
        guard WCSession.default.isReachable else { return }
        // In a real implementation, you'd send a specific command to the watch to push the file
        // e.g., sendMessage(["command": "syncSession", "sessionID": session.id.uuidString])
        print("Requesting sync for session: \(session.id)")
    }
}


