//
//  RecordViewModel.swift
//  discar
//
//  Recording orchestration - coordinates phone, watch, and controller
//

import SwiftUI
import SwiftData
import Combine
import OSLog

@MainActor
class RecordViewModel: ObservableObject {

    // MARK: - Published State

    /// Recording state
    @Published var isRecording = false
    @Published var isStarting = false
    @Published var currentDuration: TimeInterval = 0

    /// Error handling
    @Published var errorMessage: String?
    @Published var showError = false

    /// Watch prompts (decoupled flow)
    @Published var showWatchStartPrompt = false
    @Published var showWatchStopPrompt = false

    /// Sensor health from SensorManager
    @Published var sensorHealth: SensorHealth?

    /// CAN bus status (polled during recording)
    @Published var canConnected = false
    @Published var canFrameCount = 0
    @Published var canFileSizeBytes = 0

    /// Watch connectivity
    @Published var isWatchConnected = false

    /// Current session UUID (from controller)
    @Published var currentUUID: String?

    // MARK: - Computed Properties

    var durationFormatted: String {
        Formatters.duration(currentDuration)
    }

    var canFileSizeFormatted: String {
        Formatters.bytes(Int64(canFileSizeBytes))
    }

    var isTestMode: Bool {
        UserDefaults.standard.bool(forKey: "isTestMode")
    }

    // MARK: - Private

    private let sensorManager = SensorManager()
    private var modelContext: ModelContext?
    private var currentSession: Session?
    private var canPollTimer: Timer?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "discar", category: "RecordViewModel")

    // MARK: - Initialization

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext

        // Bind to SensorManager state
        sensorManager.$isRecording.assign(to: &$isRecording)
        sensorManager.$currentDuration.assign(to: &$currentDuration)
        sensorManager.$sensorHealth.assign(to: &$sensorHealth)

        // Bind to WatchCoordinator state
        WatchCoordinator.shared.$isReachable.assign(to: &$isWatchConnected)

        // Pre-warm sensors for faster start
        Task {
            sensorManager.warmUp()
        }
    }

    /// Update model context (called when view appears)
    func updateModelContext(_ context: ModelContext) {
        self.modelContext = context
    }


    // MARK: - Recording Control

    /// Start synchronized recording across phone, watch, and controller
    func startRecording() async {
        isStarting = true
        errorMessage = nil

        // Step 1: Check controller readiness
        do {
            let status = try await APIClient.shared.getStatus()

            if status.recording {
                throw RecordingError.alreadyRecording
            }

            if !status.ready {
                let notReady = status.cameras.filter { !$0.connected }
                let names = notReady.map { $0.name }.joined(separator: ", ")
                throw RecordingError.camerasNotReady(names)
            }

        } catch {
            if !isTestMode {
                logger.error("Readiness check failed: \(error.localizedDescription)")
                showError("System Not Ready: \(error.localizedDescription)")
                isStarting = false
                return
            }
            logger.notice("Test Mode: Skipping readiness check")
        }

        // Step 2: Generate session UUID
        let uuid = UUID().uuidString
        logger.info("Generated session UUID: \(uuid)")
        RemoteLogger.shared.info("recording", "Generated UUID: \(uuid.prefix(8))")

        // Step 3: Publish state to watch (decoupled flow)
        // Watch will show phone status and user can manually start watch recording
        logger.info("Publishing recording state to watch...")
        WatchCoordinator.shared.publishRecordingState(isRecording: true, sessionID: uuid)
        showWatchStartPrompt = true
        logger.info("Watch state published - user can now start watch recording")

        // Step 4: Start Controller
        do {
            try await APIClient.shared.startRecording(uuid: uuid)
            currentUUID = uuid
            logger.info("Controller started with UUID: \(uuid)")
            RemoteLogger.shared.info("recording", "Controller started")
        } catch {
            if !isTestMode {
                logger.error("Controller start failed: \(error.localizedDescription)")
                // Publish failed state so watch knows phone isn't recording
                WatchCoordinator.shared.publishRecordingState(isRecording: false)
                showError("Failed to start cameras: \(error.localizedDescription)")
                isStarting = false
                return
            }
            currentUUID = uuid
        }

        // Step 5: Start Phone sensors
        let session = Session(date: Date(), externalUUID: currentUUID)
        currentSession = session

        do {
            try await StorageService.shared.createSessionFolder(session: session)
            sensorManager.startRecording(session: session)
            logger.info("Phone recording started")

            // Start CAN polling
            startCANPolling()

        } catch {
            logger.error("Failed to start sensors: \(error.localizedDescription)")
            showError("Failed to start sensors: \(error.localizedDescription)")
            WatchCoordinator.shared.sendError("Sensor Error")
        }

        isStarting = false
    }

    /// Stop synchronized recording
    func stopRecording() async {
        RemoteLogger.shared.info("recording", "Stopping session: \(currentUUID?.prefix(8) ?? "none")")

        // Step 1: Publish stop state to watch (decoupled flow)
        // Watch will show phone status and user can manually stop watch recording
        logger.info("Publishing stop state to watch...")
        WatchCoordinator.shared.publishRecordingState(isRecording: false)
        showWatchStopPrompt = true

        // Step 2: Stop Phone sensors
        await sensorManager.stopRecording()

        // Step 3: Stop CAN polling
        stopCANPolling()
        canConnected = false
        canFrameCount = 0
        canFileSizeBytes = 0

        // Step 4: Save session to SwiftData
        if let session = currentSession, let modelContext = modelContext {
            session.duration = currentDuration
            modelContext.insert(session)

            do {
                try modelContext.save()
                logger.info("Session saved: \(session.id.uuidString)")
            } catch {
                logger.error("Failed to save session: \(error.localizedDescription)")
            }
        }

        // Step 5: Stop Controller
        do {
            try await APIClient.shared.stopRecording()
            logger.info("Controller stopped")
            RemoteLogger.shared.info("recording", "Stopped successfully")
        } catch {
            logger.warning("Controller stop warning: \(error.localizedDescription)")
        }

        currentSession = nil
        currentUUID = nil
    }

    // MARK: - CAN Polling

    private func startCANPolling() {
        canPollTimer = Timer.scheduledTimer(
            withTimeInterval: AppConfig.Recording.canPollInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchCANStatus()
            }
        }
        // Initial fetch
        Task { await fetchCANStatus() }
    }

    private func stopCANPolling() {
        canPollTimer?.invalidate()
        canPollTimer = nil
    }

    private func fetchCANStatus() async {
        do {
            let status = try await APIClient.shared.getCANStatus()
            canConnected = status.connected
            canFrameCount = status.frameCount
            canFileSizeBytes = status.fileSizeBytes
        } catch {
            // Silently fail - CAN status is non-critical
        }
    }

    // MARK: - Error Handling

    private func showError(_ message: String) {
        errorMessage = message
        showError = true
    }
}

// MARK: - Recording Errors

enum RecordingError: LocalizedError {
    case alreadyRecording
    case camerasNotReady(String)
    case watchNotResponding
    case controllerUnreachable

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "System is already recording"
        case .camerasNotReady(let names):
            return "Cameras not ready: \(names)"
        case .watchNotResponding:
            return "Watch not responding"
        case .controllerUnreachable:
            return "Controller unreachable"
        }
    }
}
