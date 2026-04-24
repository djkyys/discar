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

        if isPhoneReachable {
            sendMessage(["command": "getStatus"])
        }
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

    /// Handle messages WITH reply (used for start recording confirmation)
    func session(_ session: WCSession, didReceiveMessage message: [String : Any],
                 replyHandler: @escaping ([String : Any]) -> Void) {
        logger.info("📥 Received message with reply handler")

        // Handle startRecording command with confirmation
        if let command = message["command"] as? String, command == "startRecording" {
            let sessionID = message["sessionID"] as? String
            logger.info("📥 startRecording command, sessionID: \(sessionID ?? "nil")")

            Task { @MainActor in
                self.isPhoneReachable = true
                self.errorMessage = nil
                self.isRecording = true

                await WatchSensorManager.shared.startRecording(sessionID: sessionID, resume: false)

                // Confirm back to phone
                replyHandler(["started": true])
                self.logger.info("✅ Replied: started = true")
            }
            return
        }

        // For other messages, just acknowledge
        replyHandler(["received": true])
    }

    /// Handle messages WITHOUT reply (fire and forget)
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            // If we receive any message, the phone is reachable
            self.isPhoneReachable = true
            self.errorMessage = nil // Clear errors on success

            // Handle sendSession command from iPhone
            if let command = message["command"] as? String {
                self.logger.info("📥 Received command: \(command)")

                if command == "sendSession" {
                    if let sessionID = message["sessionID"] as? String {
                        self.logger.info("📥 Processing sendSession for sessionID: \(sessionID)")
                        self.transferSessionFiles(sessionID: sessionID)
                    } else {
                        self.logger.error("❌ sendSession command missing sessionID")
                    }
                    return
                }
            }

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

