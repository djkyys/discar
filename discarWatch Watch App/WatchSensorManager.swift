//
//  WatchSensorManager.swift
//  discarWatch Watch App
//
//  Created by Drogba on 2025/11/24.
//

import Foundation
import Combine
import HealthKit
import CoreMotion
import os.log

// Define an Actor for thread-safe data buffering
actor DataBuffer {
    var heartRateBuffer: [WatchHeartRateReading] = []
    var deviceMotionBuffer: [WatchDeviceMotionReading] = []
    var compassBuffer: [WatchCompassReading] = []
    var barometerBuffer: [WatchBarometerReading] = []
    
    func appendHeartRate(_ reading: WatchHeartRateReading) {
        heartRateBuffer.append(reading)
    }
    
    func appendDeviceMotion(_ reading: WatchDeviceMotionReading) {
        deviceMotionBuffer.append(reading)
    }

    func appendCompass(_ reading: WatchCompassReading) {
        compassBuffer.append(reading)
    }

    func appendBarometer(_ reading: WatchBarometerReading) {
        barometerBuffer.append(reading)
    }
    
    func flush() -> (
        [WatchHeartRateReading], [WatchDeviceMotionReading],
        [WatchCompassReading], [WatchBarometerReading]
    ) {
        let hr = heartRateBuffer
        let motion = deviceMotionBuffer
        let comp = compassBuffer
        let baro = barometerBuffer
        
        heartRateBuffer.removeAll()
        deviceMotionBuffer.removeAll()
        compassBuffer.removeAll()
        barometerBuffer.removeAll()
        
        return (hr, motion, comp, baro)
    }
}

@MainActor
class WatchSensorManager: NSObject, ObservableObject {
    static let shared = WatchSensorManager()
    
    private let logger = Logger(subsystem: "com.discar.watch", category: "WatchSensorManager")
    
    // MARK: - Publishing
    @Published var isRecording = false
    @Published var currentHeartRate: Double = 0
    @Published var currentDuration: TimeInterval = 0
    
    // MARK: - HealthKit
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    
    // MARK: - Motion & Environment
    private let motionManager = CMMotionManager()
    private let altimeter = CMAltimeter()
    private let locationManager = CLLocationManager()
    private let queue = OperationQueue()
    
    // MARK: - State
    private var startDate: Date?
    private var timer: Timer?
    private var sessionID: String?
    
    // Persistence Keys
    private let kIsRecording = "isRecording"
    private let kSessionID = "sessionID"
    private let kStartDate = "startDate"
    
    // MARK: - Buffers
    private let dataBuffer = DataBuffer()
    
    override init() {
        super.init()
        logger.info("🔧 WatchSensorManager.init() called")
        queue.maxConcurrentOperationCount = 1
        queue.name = "com.discar.watch.motion"
        locationManager.delegate = self
        
        // Restore State if app was killed
        restoreState()
    }
    
    // MARK: - Persistence Logic
    
    private func restoreState() {
        let defaults = UserDefaults.standard
        let wasRecording = defaults.bool(forKey: kIsRecording)
        let savedID = defaults.string(forKey: kSessionID)
        let savedDate = defaults.object(forKey: kStartDate) as? Date
        
        logger.info("🔄 restoreState() - wasRecording: \(wasRecording), savedID: \(savedID ?? "nil"), savedDate: \(savedDate?.description ?? "nil")")
        
        if wasRecording,
           let id = savedID,
           let date = savedDate {
            
            logger.info("🔄 Restoring previous session: \(id)")
            
            // Restore properties
            self.sessionID = id
            self.startDate = date
            
            // Resume Sensors (HealthKit might need re-auth, but we try)
            Task {
                await startRecording(sessionID: id, resume: true)
            }
        } else {
            logger.info("🔄 No session to restore")
        }
    }
    
    private func saveState() {
        logger.info("💾 saveState() - sessionID: \(self.sessionID ?? "nil")")
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: kIsRecording)
        defaults.set(sessionID, forKey: kSessionID)
        defaults.set(startDate, forKey: kStartDate)
    }
    
    private func clearState() {
        logger.info("🗑️ clearState()")
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: kIsRecording)
        defaults.removeObject(forKey: kSessionID)
        defaults.removeObject(forKey: kStartDate)
    }
    
    // MARK: - Public API

    /// Request HealthKit permissions - follows Apple's standard pattern exactly
    func requestPermissions() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.error("HealthKit not available on this device")
            return
        }

        // Following Apple's documentation pattern exactly:
        // Same types in both toShare and read for workout + heart rate
        let allTypes: Set<HKSampleType> = [
            HKQuantityType.workoutType(),
            HKQuantityType(.heartRate)
        ]

        do {
            // Request authorization matching Apple's docs
            try await healthStore.requestAuthorization(toShare: allTypes, read: allTypes)
            logger.info("HealthKit authorization completed")

        } catch {
            logger.error("HealthKit authorization error: \(error.localizedDescription)")
        }

        // Location Permission for Compass (separate from HealthKit)
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            logger.info("Location permission requested")
        }
    }
    
    // Modified signature to accept sessionID from Phone and resume flag
    func startRecording(sessionID: String? = nil, resume: Bool = false) async {
        logger.info("▶️ startRecording() called - sessionID: \(sessionID ?? "nil"), resume: \(resume), isRecording: \(self.isRecording)")
        
        // Safety: If resume requested but session ID mismatch, stop previous one
        if resume && sessionID != nil && self.sessionID != nil && sessionID != self.sessionID {
            logger.warning("⚠️ Session ID mismatch during resume (\(sessionID!) != \(self.sessionID!)). Stopping old session.")
            await stopRecording()
        }
        
        guard !self.isRecording || resume else {
            logger.info("▶️ startRecording() - SKIPPED (already recording and not resuming)")
            return
        }

        // Check workout WRITE permission status
        let workoutType = HKQuantityType.workoutType()
        let workoutStatus = healthStore.authorizationStatus(for: workoutType)

        logger.info("▶️ Workout write permission status: \(workoutStatus.rawValue)")

        // If permission is undetermined, request it
        if workoutStatus == .notDetermined {
            logger.info("Requesting HealthKit permissions...")
            await requestPermissions()

            // Re-check after request
            let newWorkoutStatus = healthStore.authorizationStatus(for: workoutType)
            if newWorkoutStatus != .sharingAuthorized {
                logger.error("Workout permission not granted")
                return
            }
        }
        // If already denied, we cannot proceed with workout sessions
        else if workoutStatus == .sharingDenied {
            logger.error("Workout permission denied - please enable in Settings > Health > discarWatch")
            return
        }

        // Setup Workout Session
        do {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .other
            configuration.locationType = .outdoor

            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            builder = workoutSession?.associatedWorkoutBuilder()

            workoutSession?.delegate = self
            builder?.delegate = self

            // Create data source and EXPLICITLY enable heart rate collection
            let dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            dataSource.enableCollection(for: HKQuantityType(.heartRate), predicate: nil)
            builder?.dataSource = dataSource

            logger.info("Heart rate collection explicitly enabled")
            
            // Start Session
            // If resuming, use existing startDate, else create new
            let date = resume ? (self.startDate ?? Date()) : Date()
            
            if !resume {
                startDate = date
                // Use provided sessionID or generate new one (fallback)
                self.sessionID = sessionID ?? UUID().uuidString
                
                // Save State immediately
                saveState()
            }
            
            workoutSession?.startActivity(with: date)
            
            // Reverted to completion handler pattern for backward compatibility
            builder?.beginCollection(withStart: date) { [weak self] (success, error) in
                guard let self = self else { return }
                
                if success {
                    // Start non-HealthKit sensors
                    self.startSensors()
                    
                    Task { @MainActor in
                        self.isRecording = true
                        self.startTimer()
                        let action = resume ? "Resumed" : "Started"
                        self.logger.info("Recording \(action) with Session ID: \(self.sessionID ?? "unknown")")
                    }
                } else {
                    self.logger.error("Failed to begin collection: \(error?.localizedDescription ?? "unknown error")")
                    self.workoutSession?.end()
                }
            }
            
        } catch {
            logger.error("Failed to start workout session or begin collection: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() async {
        logger.info("⏹️ stopRecording() called - isRecording: \(self.isRecording)")
        
        guard self.isRecording else {
            logger.info("⏹️ stopRecording() - SKIPPED (not recording)")
            return
        }
        
        let date = Date()
        
        // Stop Motion sensors immediately
        stopSensors()
        
        // End the Workout Session activity
        workoutSession?.end()
        
        // Step 1: End collection using the completion handler
        builder?.endCollection(withEnd: date) { [weak self] (success, error) in
            guard let self = self else { return }
            
            if success {
                // Step 2: Finish the workout using the completion handler
                self.builder?.finishWorkout { (workout, finishError) in
                    if let workout = workout {
                        self.logger.info("Workout saved to HealthKit: \(workout)")
                        
                        Task {
                            await self.flushAndResetState()
                        }
                    } else {
                        self.logger.error("Failed to finish workout: \(finishError?.localizedDescription ?? "unknown error")")
                        Task {
                            await self.flushAndResetState()
                        }
                    }
                }
            } else {
                self.logger.error("Failed to end collection: \(error?.localizedDescription ?? "unknown error")")
                self.builder?.finishWorkout { (workout, _) in
                    Task {
                        await self.flushAndResetState()
                    }
                }
            }
        }
    }
    
    // MARK: - State Management Helper
    
    @MainActor
    private func flushAndResetState() async {
        // Flush data
        await flushData()
        
        // Reset State
        isRecording = false
        timer?.invalidate()
        timer = nil
        workoutSession = nil
        builder = nil
        startDate = nil
        currentHeartRate = 0
        currentDuration = 0
        
        logger.info("Recording stopped and state reset.")
        
        // Clear Persisted State
        clearState()
    }
    
    // MARK: - Sensor Handling
    
    private func startSensors() {
        // 1. Device Motion (Fused: Accelerometer + Gyroscope + Magnetometer)
        // Provides: Attitude (pitch/roll/yaw), UserAcceleration, Gravity, RotationRate
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0 / 2.0 // 2Hz (2 samples per second)
            motionManager.startDeviceMotionUpdates(to: queue) { [weak self] data, error in
                guard let self = self, let data = data, error == nil else { return }
                Task {
                    await self.recordDeviceMotion(data)
                }
            }
        } else {
            logger.warning("Device Motion not available on this device")
        }
        
        // 2. Barometer
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: queue) { [weak self] (data: CMAltitudeData?, error: Error?) in
                guard let self = self, let data = data, error == nil else { return }
                let t = self.timestamp()
                let pressure = data.pressure.doubleValue
                let relAltitude = data.relativeAltitude.doubleValue
                Task {
                    await self.dataBuffer.appendBarometer(WatchBarometerReading(
                        t: t,
                        pressure: pressure,
                        relativeAltitude: relAltitude
                    ))
                }
            }
        }
        
        // 3. Compass
        locationManager.startUpdatingHeading()
    }
    
    private func stopSensors() {
        motionManager.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        locationManager.stopUpdatingHeading()
    }
    
    private func recordDeviceMotion(_ data: CMDeviceMotion) async {
        let t = timestamp()
        let q = data.attitude.quaternion
        let rm = data.attitude.rotationMatrix
        let mf = data.magneticField

        // Convert calibration accuracy enum to int: -1=uncalibrated, 0=low, 1=medium, 2=high
        let calibratedMagField: WatchCalibratedMagneticField? = {
            let accuracy: Int
            switch mf.accuracy {
            case .uncalibrated: accuracy = -1
            case .low: accuracy = 0
            case .medium: accuracy = 1
            case .high: accuracy = 2
            @unknown default: accuracy = -1
            }
            return WatchCalibratedMagneticField(
                x: mf.field.x,
                y: mf.field.y,
                z: mf.field.z,
                accuracy: accuracy
            )
        }()

        let reading = WatchDeviceMotionReading(
            t: t,
            attitude: WatchAttitude(
                roll: data.attitude.roll,
                pitch: data.attitude.pitch,
                yaw: data.attitude.yaw
            ),
            quaternion: WatchQuaternion(
                x: q.x,
                y: q.y,
                z: q.z,
                w: q.w
            ),
            rotationMatrix: WatchRotationMatrix(
                m11: rm.m11, m12: rm.m12, m13: rm.m13,
                m21: rm.m21, m22: rm.m22, m23: rm.m23,
                m31: rm.m31, m32: rm.m32, m33: rm.m33
            ),
            userAcceleration: WatchVector3(
                x: data.userAcceleration.x,
                y: data.userAcceleration.y,
                z: data.userAcceleration.z
            ),
            gravity: WatchVector3(
                x: data.gravity.x,
                y: data.gravity.y,
                z: data.gravity.z
            ),
            rotationRate: WatchVector3(
                x: data.rotationRate.x,
                y: data.rotationRate.y,
                z: data.rotationRate.z
            ),
            magneticField: calibratedMagField,
            heading: data.heading >= 0 ? data.heading : nil
        )
        await dataBuffer.appendDeviceMotion(reading)
    }
    
    // MARK: - Helpers
    
    private func timestamp() -> Double {
        guard let start = startDate else { return 0 }
        return Date().timeIntervalSince(start)
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateDuration()
            }
        }
    }
    
    private func updateDuration() {
        guard let start = startDate else { return }
        currentDuration = Date().timeIntervalSince(start)
    }
    
    // MARK: - Storage
    
    private func flushData() async {
        guard let id = sessionID, let start = startDate else { return }
        
        let fileManager = FileManager.default
        guard let docURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let sessionDir = docURL.appendingPathComponent(id)
        
        do {
            try fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)
            
            let (hrData, motionData, compData, baroData) = await dataBuffer.flush()
            
            // Write JSONs
            try writeJSON(hrData, to: sessionDir.appendingPathComponent("heart_rate.json"))
            try writeJSON(motionData, to: sessionDir.appendingPathComponent("devicemotion.json"))
            try writeJSON(compData, to: sessionDir.appendingPathComponent("compass.json"))
            try writeJSON(baroData, to: sessionDir.appendingPathComponent("barometer.json"))
            
            // Metadata
            let meta = WatchSessionMetadata(
                id: id,
                date: ISO8601DateFormatter().string(from: start),
                duration: currentDuration,
                sensorFiles: [
                    "heart_rate.json", "devicemotion.json", "compass.json", "barometer.json"
                ]
            )
            try writeJSON(meta, to: sessionDir.appendingPathComponent("metadata.json"))
            
            logger.info("Data flushed to \(sessionDir.path)")
            
        } catch {
            logger.error("Failed to save data: \(error.localizedDescription)")
        }
    }
    
    private func writeJSON<T: Encodable>(_ data: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: url)
    }
}

// MARK: - Delegates

extension WatchSensorManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        logger.info("🏋️ Workout state: \(fromState.rawValue) → \(toState.rawValue)")
        
        // DON'T blindly set isRecording based on workout state!
        // The workout can pause/resume without us wanting to stop the logical recording.
        // We only reset state if the workout is explicitly ended.
        if toState == .ended {
            logger.warning("🏋️ Workout ended - cleaning up state if needed")
            // If it ended and we thought we were recording, we might need to stop.
            // But usually stopRecording() handles this.
        }
    }
    
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        logger.error("Workout session failed: \(error.localizedDescription)")
    }
}

extension WatchSensorManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }

            // Debug Log
            logger.info("Received HealthKit Data: \(quantityType.identifier)")

            let t = self.timestamp()
            let statistics = workoutBuilder.statistics(for: quantityType)
            guard let quantity = statistics?.mostRecentQuantity() else { continue }

            // Check if this is heart rate data using modern syntax
            if quantityType == HKQuantityType(.heartRate) {
                let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))

                logger.info("Heart rate received: \(bpm) BPM")

                DispatchQueue.main.async {
                    self.currentHeartRate = bpm
                }

                Task {
                    await self.dataBuffer.appendHeartRate(WatchHeartRateReading(t: t, bpm: bpm))
                }
            }
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
    }
}

// MARK: - Location Delegate

extension WatchSensorManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard isRecording else { return }
        let t = timestamp()

        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        let accuracy = newHeading.headingAccuracy >= 0 ? newHeading.headingAccuracy : nil

        Task {
            await dataBuffer.appendCompass(WatchCompassReading(t: t, heading: heading, accuracy: accuracy))
        }
    }
}


