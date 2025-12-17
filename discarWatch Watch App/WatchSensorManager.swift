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
    var accelerometerBuffer: [WatchAccelerometerReading] = []
    var gyroscopeBuffer: [WatchGyroscopeReading] = []
    
    // NEW BUFFERS
    var ecgBuffer: [WatchECGReading] = []
    var spo2Buffer: [WatchBloodOxygenReading] = []
    var temperatureBuffer: [WatchTemperatureReading] = []
    var compassBuffer: [WatchCompassReading] = []
    var barometerBuffer: [WatchBarometerReading] = []
    
    func appendHeartRate(_ reading: WatchHeartRateReading) {
        heartRateBuffer.append(reading)
    }
    
    func appendAccelerometer(_ reading: WatchAccelerometerReading) {
        accelerometerBuffer.append(reading)
    }
    
    func appendGyroscope(_ reading: WatchGyroscopeReading) {
        gyroscopeBuffer.append(reading)
    }
    
    func appendECG(_ reading: WatchECGReading) {
        ecgBuffer.append(reading)
    }
    
    func appendSPO2(_ reading: WatchBloodOxygenReading) {
        spo2Buffer.append(reading)
    }
    
    func appendTemperature(_ reading: WatchTemperatureReading) {
        temperatureBuffer.append(reading)
    }

    func appendCompass(_ reading: WatchCompassReading) {
        compassBuffer.append(reading)
    }

    func appendBarometer(_ reading: WatchBarometerReading) {
        barometerBuffer.append(reading)
    }
    
    func flush() -> (
        [WatchHeartRateReading], [WatchAccelerometerReading], [WatchGyroscopeReading],
        [WatchECGReading], [WatchBloodOxygenReading], [WatchTemperatureReading],
        [WatchCompassReading], [WatchBarometerReading]
    ) {
        let hr = heartRateBuffer
        let acc = accelerometerBuffer
        let gyro = gyroscopeBuffer
        let ecg = ecgBuffer
        let spo2 = spo2Buffer
        let temp = temperatureBuffer
        let comp = compassBuffer
        let baro = barometerBuffer
        
        heartRateBuffer.removeAll()
        accelerometerBuffer.removeAll()
        gyroscopeBuffer.removeAll()
        ecgBuffer.removeAll()
        spo2Buffer.removeAll()
        temperatureBuffer.removeAll()
        compassBuffer.removeAll()
        barometerBuffer.removeAll()
        
        return (hr, acc, gyro, ecg, spo2, temp, comp, baro)
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
    private var sessionID: String? // Changed to String to match incoming format
    
    // MARK: - Buffers
    private let dataBuffer = DataBuffer()
    
    override init() {
        super.init()
        queue.maxConcurrentOperationCount = 1
        queue.name = "com.discar.watch.motion"
        locationManager.delegate = self
    }
    
    // MARK: - Public API
    
    func requestPermissions() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.error("HealthKit not available")
            return
        }
        
        let typesToShare: Set = [
            HKQuantityType.workoutType()
        ]
        
        var typesToRead: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.activitySummaryType(),
            HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!, // SpO2
            HKQuantityType.quantityType(forIdentifier: .bodyTemperature)!, // General body temp
        ]
        
        // Note: HKElectrocardiogramType is available on watchOS 6.0+
        // In modern SDKs, this function no longer returns an Optional type.
        let ecgType = HKObjectType.electrocardiogramType()
        typesToRead.insert(ecgType)
        
        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            logger.info("HealthKit authorization requested")
        } catch {
            logger.error("HealthKit auth error: \(error.localizedDescription)")
        }
        
        // Location Permission for Compass
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }
    
    // Modified signature to accept sessionID from Phone
    func startRecording(sessionID: String? = nil) async {
        guard !isRecording else { return }
        
        // Ensure permissions
        await requestPermissions()
        
        // Setup Workout Session
        do {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .other
            configuration.locationType = .outdoor
            
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            builder = workoutSession?.associatedWorkoutBuilder()
            
            workoutSession?.delegate = self
            builder?.delegate = self
            
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            
            // Start Session
            let date = Date()
            startDate = date
            // Use provided sessionID or generate new one (fallback)
            self.sessionID = sessionID ?? UUID().uuidString
            
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
                        self.logger.info("Recording started with Session ID: \(self.sessionID ?? "unknown")")
                    }
                } else {
                    self.logger.error("Failed to begin collection: \(error?.localizedDescription ?? "unknown error")")
                    self.workoutSession?.end()
                }
            }
            
        } catch {
            // This catch block will now handle any errors from beginCollection or setup
            logger.error("Failed to start workout session or begin collection: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() async {
        guard isRecording else { return }
        
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
                        
                        // Step 3: Once the workout is completely saved, perform final cleanup
                        // Use a Task to execute the cleanup (including the async flushData())
                        Task {
                            await self.flushAndResetState()
                        }
                    } else {
                        self.logger.error("Failed to finish workout: \(finishError?.localizedDescription ?? "unknown error")")
                        // Still proceed with cleanup even if finishing failed
                        Task {
                            await self.flushAndResetState()
                        }
                    }
                }
            } else {
                // Handle failure to end collection
                self.logger.error("Failed to end collection: \(error?.localizedDescription ?? "unknown error")")
                // Proceed to finish/cleanup anyway
                self.builder?.finishWorkout { (workout, _) in
                    Task {
                        await self.flushAndResetState()
                    }
                }
            }
        }
    }
    
    // MARK: - State Management Helper
    
    @MainActor // Ensure state resets happen on the main thread
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
    }
    
    // MARK: - Sensor Handling
    
    private func startSensors() {
        // 1. Motion (Accelerometer & Gyroscope)
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 1.0 / 50.0 // 50Hz
            // FIX: Corrected to use the modern start...Updates(to:withHandler:) signature
            motionManager.startAccelerometerUpdates(to: queue) { [weak self] data, error in
                guard let self = self, let data = data, error == nil else { return }
                Task {
                    await self.recordAccelerometer(data)
                }
            }
        }
        
        if motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = 1.0 / 50.0
            // FIX: Corrected to use the modern start...Updates(to:withHandler:) signature
            motionManager.startGyroUpdates(to: queue) { [weak self] data, error in
                guard let self = self, let data = data, error == nil else { return }
                Task {
                    await self.recordGyroscope(data)
                }
            }
        }
        
        // 2. Barometer
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: queue) { [weak self] (data: CMAltitudeData?, error: Error?) in
                guard let self = self, let data = data, error == nil else { return }
                let t = self.timestamp()
                let pressure = data.pressure.doubleValue
                Task {
                    await self.dataBuffer.appendBarometer(WatchBarometerReading(t: t, pressure: pressure))
                }
            }
        }
        
        // 3. Compass
        locationManager.startUpdatingHeading()
    }
    
    private func stopSensors() {
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        locationManager.stopUpdatingHeading()
    }
    
    private func recordAccelerometer(_ data: CMAccelerometerData) async {
        let t = timestamp()
        await dataBuffer.appendAccelerometer(WatchAccelerometerReading(t: t, x: data.acceleration.x, y: data.acceleration.y, z: data.acceleration.z))
    }
    
    private func recordGyroscope(_ data: CMGyroData) async {
        let t = timestamp()
        await dataBuffer.appendGyroscope(WatchGyroscopeReading(t: t, x: data.rotationRate.x, y: data.rotationRate.y, z: data.rotationRate.z))
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
        
        let sessionDir = docURL.appendingPathComponent(id) // id is now String
        
        do {
            try fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)
            
            let (hrData, accData, gyroData, ecgData, spo2Data, tempData, compData, baroData) = await dataBuffer.flush()
            
            // Write JSONs
            try writeJSON(accData, to: sessionDir.appendingPathComponent("accelerometer.json"))
            try writeJSON(gyroData, to: sessionDir.appendingPathComponent("gyroscope.json"))
            try writeJSON(hrData, to: sessionDir.appendingPathComponent("heart_rate.json"))
            try writeJSON(ecgData, to: sessionDir.appendingPathComponent("ecg.json"))
            try writeJSON(spo2Data, to: sessionDir.appendingPathComponent("spo2.json"))
            try writeJSON(tempData, to: sessionDir.appendingPathComponent("temperature.json"))
            try writeJSON(compData, to: sessionDir.appendingPathComponent("compass.json"))
            try writeJSON(baroData, to: sessionDir.appendingPathComponent("barometer.json"))
            
            // Metadata
            let meta = WatchSessionMetadata(
                id: id,
                date: ISO8601DateFormatter().string(from: start),
                duration: currentDuration,
                sensorFiles: [
                    "accelerometer.json", "gyroscope.json", "heart_rate.json",
                    "ecg.json", "spo2.json", "temperature.json", "compass.json", "barometer.json"
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
        logger.info("Workout session state changed: \(toState.rawValue)")
        
        DispatchQueue.main.async {
            self.isRecording = (toState == .running)
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
            
            let t = self.timestamp()
            let statistics = workoutBuilder.statistics(for: quantityType)
            guard let quantity = statistics?.mostRecentQuantity() else { continue }

            switch quantityType.identifier {
            case HKQuantityTypeIdentifier.heartRate.rawValue:
                let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                
                DispatchQueue.main.async {
                    self.currentHeartRate = bpm
                }
                
                Task {
                    await self.dataBuffer.appendHeartRate(WatchHeartRateReading(t: t, bpm: bpm))
                }
                
            case HKQuantityTypeIdentifier.oxygenSaturation.rawValue:
                let spo2 = quantity.doubleValue(for: HKUnit.percent()) * 100
                Task {
                    await self.dataBuffer.appendSPO2(WatchBloodOxygenReading(t: t, percentage: spo2))
                }
                
            case HKQuantityTypeIdentifier.basalBodyTemperature.rawValue:
                let tempChange = quantity.doubleValue(for: HKUnit.degreeCelsius())
                Task {
                    await self.dataBuffer.appendTemperature(WatchTemperatureReading(t: t, delta: tempChange))
                }
                
            default:
                break
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
        
        // Use magnetic heading by default, or true heading if available and calibrated
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        
        Task {
            await dataBuffer.appendCompass(WatchCompassReading(t: t, heading: heading))
        }
    }
}
