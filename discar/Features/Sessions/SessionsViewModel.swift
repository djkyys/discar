//
//  SessionsViewModel.swift
//  discar
//

import Foundation
import Combine
import SwiftData
import OSLog

@MainActor
class SessionsViewModel: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var isLoading: Bool = false
    
    private var modelContext: ModelContext
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "discar", category: "SessionsViewModel")
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // Load sessions
    func loadSessions() {
        isLoading = true
        
        let descriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        
        do {
            sessions = try modelContext.fetch(descriptor)
            logger.info("Loaded \(self.sessions.count) sessions")
        } catch {
            logger.error("Failed to load sessions: \(error.localizedDescription)")
            sessions = []
        }
        
        isLoading = false
    }
    
    // Delete a session
    func deleteSession(_ session: Session) {
        // Delete from SwiftData
        modelContext.delete(session)
        
        do {
            try modelContext.save()
            logger.info("Deleted session from database: \(session.id.uuidString)")
        } catch {
            logger.error("Failed to delete session from database: \(error.localizedDescription)")
        }
        
        // Delete files
        Task {
            do {
                try await StorageService.shared.deleteSession(session: session)
            } catch {
                logger.error("Failed to delete session files: \(error.localizedDescription)")
            }
        }
        
        // Remove from local array
        sessions.removeAll { $0.id == session.id }
    }
    
    // Format date for display
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // Format duration for display (hh:mm:ss)
    func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

