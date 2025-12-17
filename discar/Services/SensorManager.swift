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
    private var headphoneMotionBuffer: [DeviceMotionReading] = [] // Added (reuses DeviceMotionReading)
    private var headingBuffer: [HeadingReading] = []
    
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
                self.accelerometerBuffer.append(AccelerometerReading(
                    t: self.timestamp(),
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
                self.gyroscopeBuffer.append(GyroscopeReading(
                    t: self.timestamp(),
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
                self.magnetometerBuffer.append(MagnetometerReading(
                    t: self.timestamp(),
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
                self.deviceMotionBuffer.append(self.convertDeviceMotion(data))
            }
        }
        
        // Headphone Motion (AirPods)
        if headphoneManager.isDeviceMotionAvailable {
            headphoneManager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let data = data, let self = self else { return }
                self.headphoneMotionBuffer.append(self.convertDeviceMotion(data))
            }
        }
        
        // Barometer
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let data = data, let self = self else { return }
                self.barometerBuffer.append(BarometerReading(
                    t: self.timestamp(),
                    pressure: data.pressure.doubleValue
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
    
    private func convertDeviceMotion(_ data: CMDeviceMotion) -> DeviceMotionReading {
        DeviceMotionReading(
            t: self.timestamp(),
            attitude: Attitude(
                roll: data.attitude.roll,
                pitch: data.attitude.pitch,
                yaw: data.attitude.yaw
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
            )
        )
    }
    
    private func timestamp() -> Double {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
    
    private func clearBuffers() {
        accelerometerBuffer.removeAll()
        gyroscopeBuffer.removeAll()
        magnetometerBuffer.removeAll()
        barometerBuffer.removeAll()
        gpsBuffer.removeAll()
        deviceMotionBuffer.removeAll()
        headphoneMotionBuffer.removeAll() // Added
        headingBuffer.removeAll()
    }
    
    private func flushBuffers() async {
        guard let session = currentSession else { return }
        let storage = StorageService.shared
        
        await storage.appendSensorData(session: session, filename: "accelerometer.json", data: accelerometerBuffer)
        await storage.appendSensorData(session: session, filename: "gyroscope.json", data: gyroscopeBuffer)
        await storage.appendSensorData(session: session, filename: "magnetometer.json", data: magnetometerBuffer)
        await storage.appendSensorData(session: session, filename: "barometer.json", data: barometerBuffer)
        await storage.appendSensorData(session: session, filename: "gps.json", data: gpsBuffer)
        await storage.appendSensorData(session: session, filename: "devicemotion.json", data: deviceMotionBuffer)
        await storage.appendSensorData(session: session, filename: "headphonemotion.json", data: headphoneMotionBuffer) // Added
        await storage.appendSensorData(session: session, filename: "heading.json", data: headingBuffer)
        
        clearBuffers()
    }
    
    private func saveMetadata(session: Session) async {
        let metadata = SessionMetadata(
            id: session.id.uuidString,
            date: ISO8601DateFormatter().string(from: session.date),
            duration: currentDuration,
            sensorFiles: [
                "accelerometer.json",
                "gyroscope.json",
                "magnetometer.json",
                "barometer.json",
                "gps.json",
                "devicemotion.json",
                "headphonemotion.json", // Added
                "heading.json"
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
        gpsBuffer.append(GPSReading(
            t: timestamp(),
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            altitude: location.altitude,
            speed: location.speed,
            course: location.course,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy
        ))
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard isRecording else { return }
        headingBuffer.append(HeadingReading(
            t: timestamp(),
            magneticHeading: newHeading.magneticHeading,
            trueHeading: newHeading.trueHeading >= 0 ? newHeading.trueHeading : nil,
            accuracy: newHeading.headingAccuracy
        ))
    }
    
}
