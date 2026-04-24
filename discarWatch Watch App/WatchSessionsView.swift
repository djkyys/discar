//
//  WatchSessionsView.swift
//  discarWatch Watch App
//
//  Created by Drogba on 2025/11/24.
//

import SwiftUI

struct WatchSessionsView: View {
    @State private var sessions: [WatchSessionMetadata] = []

    var body: some View {
        List {
            if sessions.isEmpty {
                Text("No local sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions, id: \.id) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formatDate(session.date))
                            .font(.caption)
                        Text(formatDuration(session.duration))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: deleteSession)
            }
        }
        .navigationTitle("Local")
        .onAppear {
            loadSessions()
        }
    }
    
    private func loadSessions() {
        let fileManager = FileManager.default
        guard let docURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        do {
            let sessionDirs = try fileManager.contentsOfDirectory(at: docURL, includingPropertiesForKeys: nil)
            
            var loadedSessions: [WatchSessionMetadata] = []
            
            for dir in sessionDirs {
                let metaURL = dir.appendingPathComponent("metadata.json")
                if let data = try? Data(contentsOf: metaURL),
                   let meta = try? JSONDecoder().decode(WatchSessionMetadata.self, from: data) {
                    loadedSessions.append(meta)
                }
            }
            
            // Sort newest first
            sessions = loadedSessions.sorted(by: { $0.date > $1.date })
            
        } catch {
            print("Failed to list sessions: \(error)")
        }
    }
    
    private func deleteSession(at offsets: IndexSet) {
        let fileManager = FileManager.default
        guard let docURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        for index in offsets {
            let session = sessions[index]
            let sessionDir = docURL.appendingPathComponent(session.id)
            
            try? fileManager.removeItem(at: sessionDir)
        }
        
        sessions.remove(atOffsets: offsets)
    }
    
    private func formatDate(_ dateString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        guard let date = isoFormatter.date(from: dateString) else { return dateString }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

