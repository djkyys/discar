//
//  SensorManager.swift
//  discar
//

import Foundation
import Combine
import CoreMotion
import OSLog
import AVFoundation

@MainActor
class SensorManager: NSObject, ObservableObject {
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "discar", category: "SensorManager")
    
    // MARK: - Published Properties
    
    @Published var isRecording = false
    @Published var currentDuration: TimeInterval = 0
    
    // MARK: - Private Properties
    
    private lazy var motionManager = CMMotionManager()
    private lazy var headphoneManager = CMHeadphoneMotionManager() // Added
    private lazy var altimeter = CMAltimeter()
    
    private lazy var locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Enable background location updates
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        return manager
    }()
    
    private var startTime: Date?
    private var updateTimer: Timer?
    
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
        // Clean up timer to prevent leaks
        updateTimer?.invalidate()
    }
    
    /// Pre-initialize managers to avoid lag on first record
    func warmUp() {
        _ = motionManager
        _ = headphoneManager // Added
        _ = altimeter
        _ = locationManager
    }
    
    // MARK: - Recording
    
    func startRecording(session: Session) {
        guard !isRecording else { return }
        
        // Request permissions if not determined
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        
        isRecording = true
        currentSession = session
        startTime = Date()
        currentDuration = 0
        clearBuffers()
        
        startSensors()
        
        // Update timer - wrap in Task to access MainActor properties
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.startTime else { return }
                self.currentDuration = Date().timeIntervalSince(start)
                
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
        
        if let session = currentSession {
            await flushBuffers()
            await saveMetadata(session: session)
        }
        
        currentSession = nil
        startTime = nil
    }
    
    // MARK: - Sensors
    
    private func startSensors() {
        let hz = 1.0
        
        // Accelerometer
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = hz
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let data = data, let self = self else { return }
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
            motionManager.startGyroUpdates(to: .main) { [weak self] data, _ in
                guard let data = data, let self = self else { return }
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
            motionManager.startMagnetometerUpdates(to: .main) { [weak self] data, _ in
                guard let data = data, let self = self else { return }
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
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let data = data, let self = self else { return }
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
            headphoneManager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let data = data, let self = self else { return }
                let ts = self.timestamp()
                self.headphoneMotionBuffer.append(self.convertDeviceMotion(data, ts: ts))
            }
        }
        
        // Barometer
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let data = data, let self = self else { return }
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
        headphoneManager.stopDeviceMotionUpdates() // Added
        altimeter.stopRelativeAltitudeUpdates()
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }
    
    // MARK: - Helpers
    
    /// Checks if AirPods (or compatible Bluetooth headphones) are currently connected for Audio
    func isAirPodsConnected() -> Bool {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        
        // Log details for debugging
        logger.info("🔍 Audio Outputs: \(outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", "))")
        
        return outputs.contains { port in
            let isBluetooth = port.portType == .bluetoothA2DP ||
                              port.portType == .bluetoothHFP ||
                              port.portType == .bluetoothLE
            
            // Strictly check for "AirPods" in the name to exclude random speakers
            return isBluetooth && port.portName.contains("AirPods")
        }
    }
    
    private func convertDeviceMotion(_ data: CMDeviceMotion, ts: (time: Double, datetime: String)) -> DeviceMotionReading {
        let q = data.attitude.quaternion
        let rm = data.attitude.rotationMatrix
        let mf = data.magneticField

        // Convert calibration accuracy enum to int: -1=uncalibrated, 0=low, 1=medium, 2=high
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
        
        // Encode on MainActor to avoid isolation issues
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        if let data = try? encoder.encode(metadata) {
            await StorageService.shared.saveMetadata(session: session, data: data)
        }
    }
}

// MARK: - Location Delegate

extension SensorManager: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, isRecording else { return }
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

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard isRecording else { return }
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
