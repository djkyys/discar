//
//  SensorManager.swift
//  discar
//

import Foundation
import Combine
import CoreMotion
import CoreLocation
import OSLog
import AVFoundation

@MainActor
class SensorManager: NSObject, ObservableObject {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "discar", category: "SensorManager")

    // MARK: - Published Properties

    @Published var isRecording = false
    @Published var currentDuration: TimeInterval = 0
    @Published var sensorHealth: SensorHealth?  // nil when not recording

    // MARK: - Private Properties

    private lazy var motionManager = CMMotionManager()
    private lazy var headphoneManager = CMHeadphoneMotionManager()
    private lazy var altimeter = CMAltimeter()

    private lazy var locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        return manager
    }()

    // Background audio to keep app alive when backgrounded
    private var backgroundAudioPlayer: AVAudioPlayer?

    private var startTime: Date?
    private var updateTimer: Timer?

    // Track last data received time for health monitoring
    private var lastDataTime: [HealthSensor: Date] = [:]
    private let dataTimeoutInterval: TimeInterval = 5.0  // Consider failed if no data for 5s

    // Buffers
    private var accelerometerBuffer: [AccelerometerReading] = []
    private var gyroscopeBuffer: [GyroscopeReading] = []
    private var magnetometerBuffer: [MagnetometerReading] = []
    private var barometerBuffer: [BarometerReading] = []
    private var gpsBuffer: [GPSReading] = []
    private var deviceMotionBuffer: [DeviceMotionReading] = []
    private var headphoneMotionBuffer: [DeviceMotionReading] = []
    private var headingBuffer: [HeadingReading] = []
    private var gravityBuffer: [GravityReading] = []
    private var orientationBuffer: [OrientationReading] = []

    // Melbourne timezone formatter for datetime column
    private let melbourneDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.timeZone = TimeZone(identifier: "Australia/Melbourne")
        return formatter
    }()

    private var currentSession: Session?

    // MARK: - Init

    override init() {
        let start = CFAbsoluteTimeGetCurrent()
        super.init()

        let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
        logger.info("SensorManager.init took \(duration, format: .fixed(precision: 2))ms")
    }

    deinit {
        updateTimer?.invalidate()
    }

    /// Pre-initialize managers to avoid lag on first record
    func warmUp() {
        _ = motionManager
        _ = headphoneManager
        _ = altimeter
        _ = locationManager
    }

    // MARK: - Recording

    func startRecording(session: Session) {
        guard !isRecording else { return }

        // Request permissions if not determined
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        }

        isRecording = true
        currentSession = session
        startTime = Date()
        currentDuration = 0
        clearBuffers()
        lastDataTime.removeAll()

        // Initialize sensor health
        initializeSensorHealth()

        // Start background audio to keep app alive when backgrounded
        startBackgroundAudio()

        startSensors()

        // Update timer
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.startTime else { return }
                self.currentDuration = Date().timeIntervalSince(start)

                // Check for sensor timeouts
                self.checkSensorTimeouts()

                // Flush every 10 seconds
                if Int(self.currentDuration) % 10 == 0 {
                    await self.flushBuffers()
                }
            }
        }
    }

    func stopRecording() async {
        guard isRecording else { return }

        isRecording = false
        updateTimer?.invalidate()
        updateTimer = nil

        stopSensors()
        stopBackgroundAudio()

        if let session = currentSession {
            await flushBuffers()
            await saveMetadata(session: session)
        }

        currentSession = nil
        startTime = nil
        sensorHealth = nil  // Clear health when not recording
    }

    // MARK: - Sensor Health

    private func initializeSensorHealth() {
        var health = SensorHealth()

        // Check GPS authorization
        let gpsAuthorized = locationManager.authorizationStatus == .authorizedWhenInUse ||
                           locationManager.authorizationStatus == .authorizedAlways

        health.initializeAvailability(
            hasAccelerometer: motionManager.isAccelerometerAvailable,
            hasGyroscope: motionManager.isGyroAvailable,
            hasMagnetometer: motionManager.isMagnetometerAvailable,
            hasBarometer: CMAltimeter.isRelativeAltitudeAvailable(),
            hasGPS: gpsAuthorized,
            hasDeviceMotion: motionManager.isDeviceMotionAvailable,
            hasHeadphoneMotion: headphoneManager.isDeviceMotionAvailable,
            hasCompass: CLLocationManager.headingAvailable()
        )

        sensorHealth = health
    }

    private func markSensorActive(_ sensor: HealthSensor) {
        lastDataTime[sensor] = Date()
        sensorHealth?.update(sensor, status: .active)
    }

    private func markSensorFailed(_ sensor: HealthSensor, reason: String) {
        logger.warning("Sensor failed: \(sensor.rawValue) - \(reason)")
        sensorHealth?.update(sensor, status: .failed(reason))
    }

    private func checkSensorTimeouts() {
        let now = Date()

        for sensor in HealthSensor.allCases {
            // Skip compass - it only updates when heading changes, not continuously
            if sensor == .compass { continue }

            // Skip sensors that are not available or already failed
            guard let health = sensorHealth else { continue }

            let status: SensorHealth.Status
            switch sensor {
            case .accelerometer: status = health.accelerometer
            case .gyroscope: status = health.gyroscope
            case .magnetometer: status = health.magnetometer
            case .barometer: status = health.barometer
            case .gps: status = health.gps
            case .deviceMotion: status = health.deviceMotion
            case .headphoneMotion: status = health.headphoneMotion
            case .compass: status = health.compass
            }

            // Only check active sensors for timeout
            guard case .active = status else { continue }

            if let lastTime = lastDataTime[sensor] {
                if now.timeIntervalSince(lastTime) > dataTimeoutInterval {
                    markSensorFailed(sensor, reason: "Timeout")
                }
            }
        }
    }

    // MARK: - Background Audio (keeps app alive when backgrounded)

    private func startBackgroundAudio() {
        do {
            // Configure audio session to mix with other audio (podcasts, music, etc.)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: .mixWithOthers)
            try session.setActive(true)

            // Generate 1 second of silence
            let sampleRate: Double = 44100
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
            let frameCount = AVAudioFrameCount(sampleRate)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
            buffer.frameLength = frameCount
            // Buffer is already zero-filled (silence)

            // Write to temporary file
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("silence.wav")
            let audioFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
            try audioFile.write(from: buffer)

            // Play on loop
            backgroundAudioPlayer = try AVAudioPlayer(contentsOf: tempURL)
            backgroundAudioPlayer?.numberOfLoops = -1  // Infinite loop
            backgroundAudioPlayer?.volume = 0.0
            backgroundAudioPlayer?.play()

            logger.info("Background audio started")
        } catch {
            logger.error("Failed to start background audio: \(error.localizedDescription)")
        }
    }

    private func stopBackgroundAudio() {
        backgroundAudioPlayer?.stop()
        backgroundAudioPlayer = nil
        logger.info("Background audio stopped")
    }

    // MARK: - Sensors

    private func startSensors() {
        let hz = 1.0

        // Accelerometer
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = hz
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
                guard let self = self else { return }

                if let error = error {
                    self.markSensorFailed(.accelerometer, reason: error.localizedDescription)
                    return
                }

                guard let data = data else { return }

                self.markSensorActive(.accelerometer)
                let ts = self.timestamp()
                self.accelerometerBuffer.append(AccelerometerReading(
                    time: ts.time,
                    datetime: ts.datetime,
                    x: data.acceleration.x,
                    y: data.acceleration.y,
                    z: data.acceleration.z
                ))
            }
        }

        // Gyroscope
        if motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = hz
            motionManager.startGyroUpdates(to: .main) { [weak self] data, error in
                guard let self = self else { return }

                if let error = error {
                    self.markSensorFailed(.gyroscope, reason: error.localizedDescription)
                    return
                }

                guard let data = data else { return }

                self.markSensorActive(.gyroscope)
                let ts = self.timestamp()
                self.gyroscopeBuffer.append(GyroscopeReading(
                    time: ts.time,
                    datetime: ts.datetime,
                    x: data.rotationRate.x,
                    y: data.rotationRate.y,
                    z: data.rotationRate.z
                ))
            }
        }

        // Magnetometer
        if motionManager.isMagnetometerAvailable {
            motionManager.magnetometerUpdateInterval = hz
            motionManager.startMagnetometerUpdates(to: .main) { [weak self] data, error in
                guard let self = self else { return }

                if let error = error {
                    self.markSensorFailed(.magnetometer, reason: error.localizedDescription)
                    return
                }

                guard let data = data else { return }

                self.markSensorActive(.magnetometer)
                let ts = self.timestamp()
                self.magnetometerBuffer.append(MagnetometerReading(
                    time: ts.time,
                    datetime: ts.datetime,
                    x: data.magneticField.x,
                    y: data.magneticField.y,
                    z: data.magneticField.z
                ))
            }
        }

        // Device Motion (iPhone)
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = hz
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] data, error in
                guard let self = self else { return }

                if let error = error {
                    self.markSensorFailed(.deviceMotion, reason: error.localizedDescription)
                    return
                }

                guard let data = data else { return }

                self.markSensorActive(.deviceMotion)
                let ts = self.timestamp()
                self.deviceMotionBuffer.append(self.convertDeviceMotion(data, ts: ts))

                // Also populate gravity and orientation buffers
                self.gravityBuffer.append(GravityReading(
                    time: ts.time,
                    datetime: ts.datetime,
                    x: data.gravity.x,
                    y: data.gravity.y,
                    z: data.gravity.z
                ))
                self.orientationBuffer.append(OrientationReading(
                    time: ts.time,
                    datetime: ts.datetime,
                    yaw: data.attitude.yaw,
                    roll: data.attitude.roll,
                    pitch: data.attitude.pitch,
                    qx: data.attitude.quaternion.x,
                    qy: data.attitude.quaternion.y,
                    qz: data.attitude.quaternion.z,
                    qw: data.attitude.quaternion.w
                ))
            }
        }

        // Headphone Motion (AirPods)
        if headphoneManager.isDeviceMotionAvailable {
            headphoneManager.startDeviceMotionUpdates(to: .main) { [weak self] data, error in
                guard let self = self else { return }

                if let error = error {
                    self.markSensorFailed(.headphoneMotion, reason: error.localizedDescription)
                    return
                }

                guard let data = data else { return }

                self.markSensorActive(.headphoneMotion)
                let ts = self.timestamp()
                self.headphoneMotionBuffer.append(self.convertDeviceMotion(data, ts: ts))
            }
        }

        // Barometer
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
                guard let self = self else { return }

                if let error = error {
                    self.markSensorFailed(.barometer, reason: error.localizedDescription)
                    return
                }

                guard let data = data else { return }

                self.markSensorActive(.barometer)
                let ts = self.timestamp()
                self.barometerBuffer.append(BarometerReading(
                    time: ts.time,
                    datetime: ts.datetime,
                    pressure: data.pressure.doubleValue,
                    relativeAltitude: data.relativeAltitude.doubleValue
                ))
            }
        }

        // GPS & Compass
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }

    private func stopSensors() {
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
        motionManager.stopMagnetometerUpdates()
        motionManager.stopDeviceMotionUpdates()
        headphoneManager.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }

    // MARK: - Helpers

    /// Checks if AirPods (or compatible Bluetooth headphones) are currently connected for Audio
    func isAirPodsConnected() -> Bool {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs

        logger.info("Audio Outputs: \(outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", "))")

        return outputs.contains { port in
            let isBluetooth = port.portType == .bluetoothA2DP ||
                              port.portType == .bluetoothHFP ||
                              port.portType == .bluetoothLE

            return isBluetooth && port.portName.contains("AirPods")
        }
    }

    private func convertDeviceMotion(_ data: CMDeviceMotion, ts: (time: Double, datetime: String)) -> DeviceMotionReading {
        let q = data.attitude.quaternion
        let rm = data.attitude.rotationMatrix
        let mf = data.magneticField

        let calibratedMagField: CalibratedMagneticField? = {
            let accuracy: Int
            switch mf.accuracy {
            case .uncalibrated: accuracy = -1
            case .low: accuracy = 0
            case .medium: accuracy = 1
            case .high: accuracy = 2
            @unknown default: accuracy = -1
            }
            return CalibratedMagneticField(
                x: mf.field.x,
                y: mf.field.y,
                z: mf.field.z,
                accuracy: accuracy
            )
        }()

        return DeviceMotionReading(
            time: ts.time,
            datetime: ts.datetime,
            attitude: Attitude(
                roll: data.attitude.roll,
                pitch: data.attitude.pitch,
                yaw: data.attitude.yaw
            ),
            quaternion: Quaternion(
                x: q.x,
                y: q.y,
                z: q.z,
                w: q.w
            ),
            rotationMatrix: RotationMatrix(
                m11: rm.m11, m12: rm.m12, m13: rm.m13,
                m21: rm.m21, m22: rm.m22, m23: rm.m23,
                m31: rm.m31, m32: rm.m32, m33: rm.m33
            ),
            userAcceleration: Vector3(
                x: data.userAcceleration.x,
                y: data.userAcceleration.y,
                z: data.userAcceleration.z
            ),
            gravity: Vector3(
                x: data.gravity.x,
                y: data.gravity.y,
                z: data.gravity.z
            ),
            rotationRate: Vector3(
                x: data.rotationRate.x,
                y: data.rotationRate.y,
                z: data.rotationRate.z
            ),
            magneticField: calibratedMagField,
            heading: data.heading >= 0 ? data.heading : nil
        )
    }

    private func timestamp() -> (time: Double, datetime: String) {
        let now = Date()
        guard let start = startTime else { return (0, melbourneDateFormatter.string(from: now)) }
        let elapsed = now.timeIntervalSince(start)
        return (elapsed, melbourneDateFormatter.string(from: now))
    }

    private func clearBuffers() {
        accelerometerBuffer.removeAll()
        gyroscopeBuffer.removeAll()
        magnetometerBuffer.removeAll()
        barometerBuffer.removeAll()
        gpsBuffer.removeAll()
        deviceMotionBuffer.removeAll()
        headphoneMotionBuffer.removeAll()
        headingBuffer.removeAll()
        gravityBuffer.removeAll()
        orientationBuffer.removeAll()
    }

    private func flushBuffers() async {
        guard let session = currentSession else { return }
        let storage = StorageService.shared

        await storage.appendCSVData(session: session, filename: "accelerometer.csv", data: accelerometerBuffer)
        await storage.appendCSVData(session: session, filename: "gyroscope.csv", data: gyroscopeBuffer)
        await storage.appendCSVData(session: session, filename: "magnetometer.csv", data: magnetometerBuffer)
        await storage.appendCSVData(session: session, filename: "barometer.csv", data: barometerBuffer)
        await storage.appendCSVData(session: session, filename: "gps.csv", data: gpsBuffer)
        await storage.appendCSVData(session: session, filename: "devicemotion.csv", data: deviceMotionBuffer)
        await storage.appendCSVData(session: session, filename: "headphonemotion.csv", data: headphoneMotionBuffer)
        await storage.appendCSVData(session: session, filename: "heading.csv", data: headingBuffer)
        await storage.appendCSVData(session: session, filename: "gravity.csv", data: gravityBuffer)
        await storage.appendCSVData(session: session, filename: "orientation.csv", data: orientationBuffer)

        clearBuffers()
    }

    private func saveMetadata(session: Session) async {
        let metadata = SessionMetadata(
            id: session.id.uuidString,
            date: ISO8601DateFormatter().string(from: session.date),
            duration: currentDuration,
            sensorFiles: [
                "accelerometer.csv",
                "gyroscope.csv",
                "magnetometer.csv",
                "barometer.csv",
                "gps.csv",
                "devicemotion.csv",
                "headphonemotion.csv",
                "heading.csv",
                "gravity.csv",
                "orientation.csv"
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(metadata) {
            await StorageService.shared.saveMetadata(session: session, data: data)
        }
    }
}

// MARK: - Location Delegate

extension SensorManager: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last, isRecording else { return }

            markSensorActive(.gps)
            let ts = timestamp()
            gpsBuffer.append(GPSReading(
                time: ts.time,
                datetime: ts.datetime,
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                altitude: location.altitude,
                ellipsoidalAltitude: location.ellipsoidalAltitude,
                speed: location.speed,
                speedAccuracy: location.speedAccuracy >= 0 ? location.speedAccuracy : nil,
                course: location.course,
                courseAccuracy: location.courseAccuracy >= 0 ? location.courseAccuracy : nil,
                horizontalAccuracy: location.horizontalAccuracy,
                verticalAccuracy: location.verticalAccuracy,
                floor: location.floor?.level
            ))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            guard isRecording else { return }

            markSensorActive(.compass)
            let ts = timestamp()
            headingBuffer.append(HeadingReading(
                time: ts.time,
                datetime: ts.datetime,
                magneticHeading: newHeading.magneticHeading,
                trueHeading: newHeading.trueHeading >= 0 ? newHeading.trueHeading : nil,
                accuracy: newHeading.headingAccuracy,
                x: newHeading.x,
                y: newHeading.y,
                z: newHeading.z
            ))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            markSensorFailed(.gps, reason: error.localizedDescription)
        }
    }
}
