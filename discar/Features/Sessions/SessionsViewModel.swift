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

    // Multi-select state
    @Published var selectedSessions: Set<UUID> = []
    @Published var isEditMode: Bool = false

    // Sync state
    @Published var isSyncing: Bool = false
    @Published var syncProgress: (completed: Int, total: Int) = (0, 0)
    @Published var syncError: String?

    private var modelContext: ModelContext
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "discar", category: "SessionsViewModel")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Computed Properties

    var unsyncedCount: Int {
        sessions.filter { !$0.isSynced }.count
    }

    var selectedCount: Int {
        selectedSessions.count
    }

    var hasSelection: Bool {
        !selectedSessions.isEmpty
    }

    // MARK: - Load Sessions

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

    // MARK: - Selection

    func toggleSelection(_ session: Session) {
        if selectedSessions.contains(session.id) {
            selectedSessions.remove(session.id)
        } else {
            selectedSessions.insert(session.id)
        }
    }

    func selectAll() {
        selectedSessions = Set(sessions.map { $0.id })
    }

    func clearSelection() {
        selectedSessions.removeAll()
    }

    func exitEditMode() {
        isEditMode = false
        clearSelection()
    }

    // MARK: - Delete

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

    func deleteSelected() {
        let toDelete = sessions.filter { selectedSessions.contains($0.id) }

        for session in toDelete {
            deleteSession(session)
        }

        clearSelection()
        isEditMode = false
    }

    // MARK: - Sync All

    func syncAll() async {
        let unsynced = sessions.filter { !$0.isSynced }
        guard !unsynced.isEmpty else { return }

        isSyncing = true
        syncError = nil
        syncProgress = (0, unsynced.count)

        var failedCount = 0

        for session in unsynced {
            do {
                _ = try await StorageService.shared.uploadSession(session: session)
                session.isSynced = true

                // Save to persist isSynced
                try? modelContext.save()

                syncProgress = (syncProgress.completed + 1, syncProgress.total)
                logger.info("Synced session: \(session.id.uuidString)")
            } catch {
                failedCount += 1
                logger.error("Failed to sync session \(session.id.uuidString): \(error.localizedDescription)")
            }
        }

        isSyncing = false

        if failedCount > 0 {
            syncError = "\(failedCount) session(s) failed to sync"
        }
    }

    // MARK: - Export

    @Published var isExporting: Bool = false
    @Published var exportError: String?

    func exportSelected() async -> [URL] {
        let toExport = sessions.filter { selectedSessions.contains($0.id) }
        guard !toExport.isEmpty else { return [] }

        isExporting = true
        exportError = nil

        var urls: [URL] = []

        for session in toExport {
            do {
                let zipURL = try await ExportService.shared.createZIP(session: session)
                urls.append(zipURL)
                logger.info("Exported session: \(session.id.uuidString)")
            } catch {
                logger.error("Failed to export session \(session.id.uuidString): \(error.localizedDescription)")
                exportError = "Failed to export some sessions"
            }
        }

        isExporting = false
        return urls
    }

    // MARK: - Formatting

    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
