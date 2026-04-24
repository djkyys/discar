//
//  WatchCoordinator.swift
//  discar
//
//  Unified Watch communication manager
//  Merges ConnectivityManager + WatchDataTransferManager into single coordinator
//

import Foundation
import WatchConnectivity
import Combine
import OSLog

/// Unified coordinator for all Apple Watch communication
@MainActor
class WatchCoordinator: NSObject, ObservableObject {
    static let shared = WatchCoordinator()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "discar", category: "WatchCoordinator")

    // MARK: - Published State

    /// Watch connection state
    @Published var isReachable = false
    @Published var activationState: WCSessionActivationState = .notActivated

    /// Commands received from watch
    @Published var receivedCommand: WatchCommand?

    /// Transfer state
    @Published var isTransferring = false
    @Published var transferProgress: Double = 0
    @Published var receivedFileCount = 0
    @Published var expectedFileCount = 0
    @Published var transferComplete = false
    @Published var currentTransferSessionID: String?

    // MARK: - Types

    enum WatchCommand: String {
        case startRecording
        case stopRecording
        case getStatus
    }

    // MARK: - Private State

    private var transferContinuation: CheckedContinuation<Bool, Never>?

    // MARK: - Initialization

    override init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
        guard WCSession.isSupported() else {
            logger.warning("WatchConnectivity not supported on this device")
            return
        }

        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - Application Context (Decoupled State)

    /// Publish phone recording state to watch via applicationContext
    /// Watch can read this anytime - doesn't require live connection
    func publishRecordingState(isRecording: Bool, sessionID: String? = nil) {
        guard WCSession.default.activationState == .activated else { return }

        var context: [String: Any] = [
            "phoneRecording": isRecording,
            "timestamp": Date().timeIntervalSince1970
        ]

        if let sessionID = sessionID {
            context["sessionID"] = sessionID
        }

        do {
            try WCSession.default.updateApplicationContext(context)
            logger.info("Published state: recording=\(isRecording), sessionID=\(sessionID ?? "nil")")
        } catch {
            logger.error("Failed to update application context: \(error.localizedDescription)")
        }
    }

    // MARK: - Legacy Methods (kept for compatibility)

    /// Send error message to watch
    func sendError(_ message: String) {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.sendMessage(["error": message], replyHandler: nil, errorHandler: nil)
    }

    // MARK: - Data Transfer

    /// Request watch to send session files and wait for completion
    func requestSessionData(sessionID: String, timeout: TimeInterval = 30) async -> Bool {
        logger.info("Requesting watch data for session: \(sessionID)")

        guard WCSession.default.isReachable else {
            logger.error("Watch not reachable")
            return false
        }

        // Reset state
        receivedFileCount = 0
        expectedFileCount = 0
        transferComplete = false
        currentTransferSessionID = sessionID
        isTransferring = true

        // Send request
        let message: [String: Any] = [
            "command": "sendSession",
            "sessionID": sessionID
        ]

        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            self.logger.error("Failed to send request: \(error.localizedDescription)")
        }

        // Wait for completion with timeout
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            self.transferContinuation = continuation

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if self.transferContinuation != nil {
                    self.logger.warning("Watch transfer timed out")
                    self.transferContinuation?.resume(returning: false)
                    self.transferContinuation = nil
                }
            }
        }

        isTransferring = false
        return result
    }

    /// Check if watch data exists for a session
    nonisolated func hasWatchData(sessionFolder: URL) -> Bool {
        let watchDir = sessionFolder.appendingPathComponent("watch")
        guard FileManager.default.fileExists(atPath: watchDir.path) else { return false }

        if let files = try? FileManager.default.contentsOfDirectory(at: watchDir, includingPropertiesForKeys: nil) {
            return files.contains { $0.pathExtension == "csv" }
        }
        return false
    }

    /// Get watch CSV files for a session
    nonisolated func getWatchFiles(sessionFolder: URL) -> [URL] {
        let watchDir = sessionFolder.appendingPathComponent("watch")
        guard let files = try? FileManager.default.contentsOfDirectory(at: watchDir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { $0.pathExtension == "csv" }
    }

    // MARK: - Internal Handlers

    fileprivate func handleTransferStarted(sessionID: String, fileCount: Int) {
        logger.info("Watch transfer started: \(fileCount) files for \(sessionID)")

        expectedFileCount = fileCount
        currentTransferSessionID = sessionID

        // If no files expected, complete immediately
        if fileCount == 0 {
            transferComplete = true
            transferContinuation?.resume(returning: true)
            transferContinuation = nil
        }
    }

    fileprivate func handleTransferComplete(sessionID: String, fileCount: Int) {
        logger.info("Watch transfer complete: \(fileCount) files")

        if fileCount == 0 {
            transferComplete = true
            transferContinuation?.resume(returning: true)
            transferContinuation = nil
        }
    }

    fileprivate func handleReceivedFile(sessionID: String, filename: String) {
        logger.info("Processing received file: \(filename)")

        receivedFileCount += 1

        if expectedFileCount > 0 && receivedFileCount >= expectedFileCount {
            transferComplete = true
            transferContinuation?.resume(returning: true)
            transferContinuation = nil
        }
    }

    /// Copy received file synchronously (must be called from nonisolated context before temp file is deleted)
    nonisolated private func copyReceivedFile(_ file: WCSessionFile) -> (sessionID: String, filename: String)? {
        guard let sessionID = file.metadata?["sessionID"] as? String,
              let filename = file.metadata?["filename"] as? String else { return nil }

        let fileManager = FileManager.default
        guard let docURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        let sessionsDir = docURL.appendingPathComponent("Sessions")
        let sessionDir = sessionsDir.appendingPathComponent(sessionID)
        let watchDir = sessionDir.appendingPathComponent("watch")
        let destURL = watchDir.appendingPathComponent(filename)

        do {
            try fileManager.createDirectory(at: watchDir, withIntermediateDirectories: true)

            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }

            try fileManager.copyItem(at: file.fileURL, to: destURL)
            return (sessionID, filename)
        } catch {
            return nil
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchCoordinator: WCSessionDelegate {

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.activationState = activationState
            self.isReachable = session.isReachable

            if session.isReachable {
                RemoteLogger.shared.info("watch", "Watch connected")
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) { }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            let wasReachable = self.isReachable
            self.isReachable = session.isReachable

            if session.isReachable && !wasReachable {
                RemoteLogger.shared.info("watch", "Watch connected")
            } else if !session.isReachable && wasReachable {
                RemoteLogger.shared.warn("watch", "Watch disconnected")
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if let commandString = message["command"] as? String {
                switch commandString {
                case "watchTransferStarted":
                    if let sessionID = message["sessionID"] as? String,
                       let fileCount = message["fileCount"] as? Int {
                        self.handleTransferStarted(sessionID: sessionID, fileCount: fileCount)
                    }

                case "watchTransferComplete":
                    if let sessionID = message["sessionID"] as? String,
                       let fileCount = message["fileCount"] as? Int {
                        self.handleTransferComplete(sessionID: sessionID, fileCount: fileCount)
                    }

                default:
                    if let command = WatchCommand(rawValue: commandString) {
                        self.receivedCommand = command
                    }
                }
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Copy file synchronously before temp file is deleted
        guard let result = copyReceivedFile(file) else { return }

        // Update state on MainActor
        Task { @MainActor in
            self.handleReceivedFile(sessionID: result.sessionID, filename: result.filename)
        }
    }
}
