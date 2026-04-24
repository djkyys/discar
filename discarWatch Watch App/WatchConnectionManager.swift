//
//  WatchConnectionManager.swift
//  discarWatch Watch App
//

import Foundation
import WatchConnectivity
import Combine
import os.log

class WatchConnectionManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectionManager()

    private let logger = Logger(subsystem: "com.discar.watch", category: "WatchConnectionManager")

    @Published var isRecording = false
    @Published var isPhoneReachable = false
    @Published var errorMessage: String?
    @Published var isTransferring = false

    // MARK: - Phone State (from applicationContext)

    /// Phone's recording state (read from applicationContext)
    @Published var phoneIsRecording = false
    /// Phone's session UUID (read from applicationContext)
    @Published var phoneSessionID: String?
    /// Timestamp of last phone state update
    @Published var phoneStateTimestamp: Date?

    override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    // MARK: - Application Context

    /// Process phone state from applicationContext
    private func processPhoneState(_ context: [String: Any]) {
        if let recording = context["phoneRecording"] as? Bool {
            phoneIsRecording = recording
            logger.info("📱 Phone recording state: \(recording)")
        }

        if let sessionID = context["sessionID"] as? String {
            phoneSessionID = sessionID
            logger.info("📱 Phone session ID: \(sessionID)")
        } else if !(context["phoneRecording"] as? Bool ?? true) {
            // Clear session ID when phone stops recording
            phoneSessionID = nil
        }

        if let timestamp = context["timestamp"] as? TimeInterval {
            phoneStateTimestamp = Date(timeIntervalSince1970: timestamp)
        }
    }

    func checkPhoneStatus() {
        isPhoneReachable = WCSession.default.activationState == .activated && WCSession.default.isReachable
    }

    // MARK: - Manual Watch Control (Decoupled Flow)

    /// Start watch recording manually (uses phone's sessionID if available)
    func startWatchRecording() async {
        logger.info("▶️ Manual watch start - phoneSessionID: \(self.phoneSessionID ?? "nil")")
        isRecording = true
        await WatchSensorManager.shared.startRecording(sessionID: phoneSessionID, resume: false)
    }

    /// Stop watch recording manually
    func stopWatchRecording() async {
        logger.info("⏹️ Manual watch stop")
        isRecording = false
        await WatchSensorManager.shared.stopRecording()
    }

    func sendMessage(_ message: [String: Any]) {
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

    // MARK: - File Transfer

    /// Transfer session CSV files to iPhone
    func transferSessionFiles(sessionID: String) {
        logger.info("📤 Transferring session files for: \(sessionID)")

        // Debug: List all sessions on watch
        if let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            if let contents = try? FileManager.default.contentsOfDirectory(at: docURL, includingPropertiesForKeys: nil) {
                logger.info("📁 Available sessions on watch: \(contents.map { $0.lastPathComponent })")
            }
        }

        let files = WatchSensorManager.shared.getSessionFiles(sessionID: sessionID)
        logger.info("📁 Found \(files.count) CSV files for session \(sessionID)")

        guard !files.isEmpty else {
            logger.warning("⚠️ No files found for session: \(sessionID)")
            // Notify iPhone that transfer is complete (no files)
            sendMessage(["command": "watchTransferComplete", "sessionID": sessionID, "fileCount": 0])
            return
        }

        DispatchQueue.main.async {
            self.isTransferring = true
        }

        var transferredCount = 0
        let totalCount = files.count

        for fileURL in files {
            let metadata: [String: Any] = [
                "sessionID": sessionID,
                "filename": fileURL.lastPathComponent
            ]

            logger.info("📤 Transferring: \(fileURL.lastPathComponent)")

            WCSession.default.transferFile(fileURL, metadata: metadata)
            transferredCount += 1
        }

        // Notify iPhone of transfer initiation
        sendMessage([
            "command": "watchTransferStarted",
            "sessionID": sessionID,
            "fileCount": totalCount
        ])

        DispatchQueue.main.async {
            self.isTransferring = false
        }

        logger.info("📤 Initiated transfer of \(transferredCount) files")
    }

    // MARK: - WCSessionDelegate

    /// Handle messages from iPhone (file transfer requests only)
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            self.isPhoneReachable = true
            self.errorMessage = nil

            // Handle sendSession command for file transfer
            if let command = message["command"] as? String, command == "sendSession" {
                if let sessionID = message["sessionID"] as? String {
                    self.logger.info("📥 Processing sendSession for sessionID: \(sessionID)")
                    self.transferSessionFiles(sessionID: sessionID)
                }
            }

            // Handle error messages
            if let error = message["error"] as? String {
                self.errorMessage = error
            }
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.checkPhoneStatus()
            // Read any existing applicationContext
            let context = session.receivedApplicationContext
            if !context.isEmpty {
                self.processPhoneState(context)
            }
        }
    }

    /// Handle applicationContext updates from phone (decoupled state sync)
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        logger.info("📥 Received applicationContext: \(applicationContext)")
        DispatchQueue.main.async {
            self.processPhoneState(applicationContext)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isPhoneReachable = session.isReachable
        }
    }

    // MARK: - File Transfer Delegate

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if let error = error {
            logger.error("❌ File transfer failed: \(error.localizedDescription)")
        } else {
            let filename = fileTransfer.file.metadata?["filename"] as? String ?? "unknown"
            logger.info("✅ File transfer complete: \(filename)")
        }
    }
}

