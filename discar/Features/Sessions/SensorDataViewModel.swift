//
//  SensorDataViewModel.swift
//  discar
//

import Foundation
import Combine

@MainActor
class SensorDataViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var statistics = SensorStatistics()
    @Published var chartData: [ChartDataPoint] = []
    @Published var rawDataPreview: [String] = []
    
    private let session: Session
    private let sensorType: SensorType
    
    init(session: Session, sensorType: SensorType) {
        self.session = session
        self.sensorType = sensorType
    }
    
    func loadData() async {
        isLoading = true
        errorMessage = nil
        
        let storage = StorageService.shared
        let filename = sensorType.filename
        
        do {
            // Load data based on sensor type
            switch sensorType {
            case .accelerometer:
                guard let data: [AccelerometerReading] = await storage.loadSensorData(session: session, filename: filename) else {
                    throw DataError.fileNotFound
                }
                processAccelerometerData(data)
                
            case .gyroscope:
                guard let data: [GyroscopeReading] = await storage.loadSensorData(session: session, filename: filename) else {
                    throw DataError.fileNotFound
                }
                processGyroscopeData(data)
                
            case .magnetometer:
                guard let data: [MagnetometerReading] = await storage.loadSensorData(session: session, filename: filename) else {
                    throw DataError.fileNotFound
                }
                processMagnetometerData(data)
                
            case .barometer:
                guard let data: [BarometerReading] = await storage.loadSensorData(session: session, filename: filename) else {
                    throw DataError.fileNotFound
                }
                processBarometerData(data)
                
            case .gps:
                guard let data: [GPSReading] = await storage.loadSensorData(session: session, filename: filename) else {
                    throw DataError.fileNotFound
                }
                processGPSData(data)
                
            case .deviceMotion:
                guard let data: [DeviceMotionReading] = await storage.loadSensorData(session: session, filename: filename) else {
                    throw DataError.fileNotFound
                }
                processDeviceMotionData(data)
                
            case .headphoneMotion: // Added
                guard let data: [DeviceMotionReading] = await storage.loadSensorData(session: session, filename: filename) else {
                    throw DataError.fileNotFound
                }
                processDeviceMotionData(data) // Reuse processing
                
            case .heading:
                guard let data: [HeadingReading] = await storage.loadSensorData(session: session, filename: filename) else {
                    throw DataError.fileNotFound
                }
                processHeadingData(data)
            }
            
            isLoading = false
            
        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    // MARK: - Data Processing
    
    private func processAccelerometerData(_ data: [AccelerometerReading]) {
        // Statistics
        statistics.count = data.count
        statistics.duration = data.last?.t ?? 0
        statistics.frequency = statistics.duration > 0 ? Double(data.count) / statistics.duration : 0
        
        // Chart data (downsample to 100 points)
        let step = max(1, data.count / 100)
        chartData = stride(from: 0, to: data.count, by: step).map { i in
            ChartDataPoint(
                time: data[i].t,
                x: data[i].x,
                y: data[i].y,
                z: data[i].z
            )
        }
        
        // Raw data preview (first 20)
        rawDataPreview = data.prefix(20).map { reading in
            String(format: "t: %.2f | x: %.3f | y: %.3f | z: %.3f", reading.t, reading.x, reading.y, reading.z)
        }
    }
    
    private func processGyroscopeData(_ data: [GyroscopeReading]) {
        statistics.count = data.count
        statistics.duration = data.last?.t ?? 0
        statistics.frequency = statistics.duration > 0 ? Double(data.count) / statistics.duration : 0
        
        let step = max(1, data.count / 100)
        chartData = stride(from: 0, to: data.count, by: step).map { i in
            ChartDataPoint(time: data[i].t, x: data[i].x, y: data[i].y, z: data[i].z)
        }
        
        rawDataPreview = data.prefix(20).map { reading in
            String(format: "t: %.2f | x: %.3f | y: %.3f | z: %.3f", reading.t, reading.x, reading.y, reading.z)
        }
    }
    
    private func processMagnetometerData(_ data: [MagnetometerReading]) {
        statistics.count = data.count
        statistics.duration = data.last?.t ?? 0
        statistics.frequency = statistics.duration > 0 ? Double(data.count) / statistics.duration : 0
        
        let step = max(1, data.count / 100)
        chartData = stride(from: 0, to: data.count, by: step).map { i in
            ChartDataPoint(time: data[i].t, x: data[i].x, y: data[i].y, z: data[i].z)
        }
        
        rawDataPreview = data.prefix(20).map { reading in
            String(format: "t: %.2f | x: %.3f | y: %.3f | z: %.3f", reading.t, reading.x, reading.y, reading.z)
        }
    }
    
    private func processBarometerData(_ data: [BarometerReading]) {
        statistics.count = data.count
        statistics.duration = data.last?.t ?? 0
        statistics.frequency = statistics.duration > 0 ? Double(data.count) / statistics.duration : 0
        
        let step = max(1, data.count / 100)
        chartData = stride(from: 0, to: data.count, by: step).map { i in
            ChartDataPoint(time: data[i].t, x: data[i].pressure, y: nil, z: nil)
        }
        
        rawDataPreview = data.prefix(20).map { reading in
            String(format: "t: %.2f | pressure: %.2f kPa", reading.t, reading.pressure)
        }
    }
    
    private func processGPSData(_ data: [GPSReading]) {
        statistics.count = data.count
        statistics.duration = data.last?.t ?? 0
        statistics.frequency = statistics.duration > 0 ? Double(data.count) / statistics.duration : 0
        
        let step = max(1, data.count / 100)
        // Show altitude, speed, and horizontal accuracy
        chartData = stride(from: 0, to: data.count, by: step).map { i in
            ChartDataPoint(time: data[i].t, x: data[i].altitude, y: data[i].speed, z: data[i].horizontalAccuracy)
        }
        
        rawDataPreview = data.prefix(20).map { reading in
            String(format: "t: %.2fs\n  Lat: %.6f°, Lon: %.6f°\n  Alt: %.1fm, Speed: %.1fm/s, Course: %.1f°\n  H.Acc: %.1fm, V.Acc: %.1fm",
                   reading.t, reading.lat, reading.lon, reading.altitude,
                   reading.speed, reading.course, reading.horizontalAccuracy, reading.verticalAccuracy)
        }
    }
    
    private func processDeviceMotionData(_ data: [DeviceMotionReading]) {
        statistics.count = data.count
        statistics.duration = data.last?.t ?? 0
        statistics.frequency = statistics.duration > 0 ? Double(data.count) / statistics.duration : 0
        
        let step = max(1, data.count / 100)
        chartData = stride(from: 0, to: data.count, by: step).map { i in
            ChartDataPoint(
                time: data[i].t,
                x: data[i].attitude.roll,
                y: data[i].attitude.pitch,
                z: data[i].attitude.yaw
            )
        }
        
        rawDataPreview = data.prefix(20).map { reading in
            String(format: "t: %.2fs\n  Attitude: Roll=%.3f, Pitch=%.3f, Yaw=%.3f\n  UserAccel: x=%.3f, y=%.3f, z=%.3f\n  Gravity: x=%.3f, y=%.3f, z=%.3f\n  RotRate: x=%.3f, y=%.3f, z=%.3f",
                   reading.t,
                   reading.attitude.roll, reading.attitude.pitch, reading.attitude.yaw,
                   reading.userAcceleration.x, reading.userAcceleration.y, reading.userAcceleration.z,
                   reading.gravity.x, reading.gravity.y, reading.gravity.z,
                   reading.rotationRate.x, reading.rotationRate.y, reading.rotationRate.z)
        }
    }
    
    private func processHeadingData(_ data: [HeadingReading]) {
        statistics.count = data.count
        statistics.duration = data.last?.t ?? 0
        statistics.frequency = statistics.duration > 0 ? Double(data.count) / statistics.duration : 0
        
        let step = max(1, data.count / 100)
        chartData = stride(from: 0, to: data.count, by: step).map { i in
            ChartDataPoint(time: data[i].t, x: data[i].magneticHeading, y: data[i].trueHeading, z: nil)
        }
        
        rawDataPreview = data.prefix(20).map { reading in
            let trueStr = reading.trueHeading.map { String(format: "%.1f°", $0) } ?? "N/A"
            return String(format: "t: %.2f | mag: %.1f° | true: %@", reading.t, reading.magneticHeading, trueStr)
        }
    }
}

// MARK: - Supporting Types

struct SensorStatistics {
    var count: Int = 0
    var duration: Double = 0
    var frequency: Double = 0
}

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let time: Double
    let x: Double
    let y: Double?
    let z: Double?
}
