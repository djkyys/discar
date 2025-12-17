//
//  SensorStatusCard.swift
//  discar
//

import SwiftUI

struct SensorStatusCard: View {
    let sensorStatus: [String: Bool]
    let isLoading: Bool
    @State private var isExpanded = false
    @StateObject private var obdService = OBDService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 16 : 0) {
            // Header
            HStack {
                Image(systemName: "sensor.fill")
                    .foregroundStyle(.blue)
                Text("Sensors")
                    .font(.headline)
                
                Spacer()
                
                if isLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Checking...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !sensorStatus.isEmpty {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        
                        Text("\(availableCount)/\(sensorStatus.count + 1)") // +1 for OBD
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isLoading && !sensorStatus.isEmpty else { return }
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            }
            
            // Expanded content
            if isExpanded {
                Divider()
                
                VStack(spacing: 12) {
                    if !sensorStatus.isEmpty {
                        ForEach(sensorStatus.sorted(by: { $0.key < $1.key }), id: \.key) { sensor in
                            SensorRow(name: sensor.key, isAvailable: sensor.value)
                        }
                    }
                    
                    // Add OBD Row
                    OBDRow(state: obdService.connectionState)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .onAppear {
            // Ensure status checking is active
            obdService.startStatusCheck()
        }
    }
    
    // Status color based on sensor availability
    private var statusColor: Color {
        let totalSensors = Double(max(sensorStatus.count + 1, 1)) // +1 for OBD
        var activeCount = Double(availableCount)
        if obdService.isCarConnected { activeCount += 1.0 }
        
        let percentage = activeCount / totalSensors
        if percentage == 1.0 {
            return .green
        } else if percentage >= 0.7 {
            return .orange
        } else {
            return .red
        }
    }
    
    private var availableCount: Int {
        sensorStatus.values.filter { $0 }.count + (obdService.isCarConnected ? 1 : 0)
    }
}

// MARK: - OBD Row
struct OBDRow: View {
    let state: OBDConnectionState
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(stateColor)
                .frame(width: 10, height: 10)
            
            // Sensor icon
            Image(systemName: "car.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            // Sensor name
            Text("OBD-II (Pi)")
                .font(.subheadline)
            
            Spacer()
            
            // Status text
            Text(state.rawValue)
                .font(.caption2)
                .foregroundStyle(stateColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(stateColor.opacity(0.1))
                .cornerRadius(4)
        }
    }
    
    private var stateColor: Color {
        switch state {
        case .connected, .recording:
            return .green
        case .checking:
            return .orange
        case .disconnected, .error:
            return .red
        }
    }
}

// MARK: - Sensor Row
struct SensorRow: View {
    let name: String
    let isAvailable: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(isAvailable ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            
            // Sensor icon
            Image(systemName: sensorIcon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            // Sensor name
            Text(name)
                .font(.subheadline)
            
            Spacer()
            
            // Status text
            Text(isAvailable ? "Available" : "Unavailable")
                .font(.caption2)
                .foregroundStyle(isAvailable ? .green : .red)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(isAvailable ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                .cornerRadius(4)
        }
    }
    
    private var sensorIcon: String {
        switch name.lowercased() {
        case let n where n.contains("accelerometer"):
            return "figure.walk"
        case let n where n.contains("gyro"):
            return "rotate.3d"
        case let n where n.contains("magnet"):
            return "scope"
        case let n where n.contains("motion"):
            return "arrow.trianglehead.2.clockwise.rotate.90"
        case let n where n.contains("gps"):
            return "location.fill"
        case let n where n.contains("compass"):
            return "location.north.fill"
        case let n where n.contains("pedometer"), let n where n.contains("step"):
            return "figure.walk"
        case let n where n.contains("distance"):
            return "ruler"
        case let n where n.contains("floor"):
            return "stairs"
        case let n where n.contains("pace"):
            return "speedometer"
        case let n where n.contains("cadence"):
            return "metronome"
        case let n where n.contains("barometer"), let n where n.contains("altitude"):
            return "barometer"
        case let n where n.contains("obd"):
            return "car.fill"
        default:
            return "sensor"
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SensorStatusCard(
            sensorStatus: [
                "Accelerometer": true,
                "Gyroscope": true,
                "Magnetometer": true,
                "Device Motion": true,
                "GPS": true,
                "Compass": true,
                "Barometer": true
            ],
            isLoading: false
        )
    }
    .padding()
}
