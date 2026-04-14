//
//  SensorDataView.swift
//  discar
//

import SwiftUI
import Charts

struct SensorDataView: View {
    let session: Session
    let sensorType: SensorType
    @StateObject private var viewModel: SensorDataViewModel
    
    init(session: Session, sensorType: SensorType) {
        self.session = session
        self.sensorType = sensorType
        _viewModel = StateObject(wrappedValue: SensorDataViewModel(session: session, sensorType: sensorType))
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if viewModel.isLoading {
                    ProgressView("Loading \(sensorType.displayName) data...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if let error = viewModel.errorMessage {
                    ErrorCard(message: error)
                } else {
                    // Statistics Card
                    StatisticsCard(stats: viewModel.statistics)
                    
                    // Chart Card
                    ChartCard(chartData: viewModel.chartData, sensorType: sensorType)
                    
                    // Raw Data Table (first 20 points)
                    RawDataCard(data: viewModel.rawDataPreview, sensorType: sensorType)
                }
            }
            .padding()
        }
        .navigationTitle(sensorType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadData()
        }
    }
}

// MARK: - Statistics Card

struct StatisticsCard: View {
    let stats: SensorStatistics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar")
                    .foregroundStyle(.blue)
                Text("Statistics")
                    .font(.headline)
            }
            
            Divider()
            
            HStack(spacing: 20) {
                StatBox(label: "Total Points", value: "\(stats.count)")
                StatBox(label: "Duration", value: String(format: "%.1fs", stats.duration))
                StatBox(label: "Frequency", value: String(format: "%.1f Hz", stats.frequency))
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct StatBox: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Chart Card

struct ChartCard: View {
    let chartData: [ChartDataPoint]
    let sensorType: SensorType
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.xyaxis.line")
                    .foregroundStyle(.blue)
                Text("Data Visualization")
                    .font(.headline)
            }
            
            Divider()
            
            if chartData.isEmpty {
                Text("No data to display")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                Chart {
                    ForEach(chartData) { point in
                        LineMark(
                            x: .value("Time (s)", point.time),
                            y: .value(xAxisLabel, point.x),
                            series: .value("Axis", xAxisLabel)
                        )
                        .foregroundStyle(.red)
                        
                        if let y = point.y {
                            LineMark(
                                x: .value("Time (s)", point.time),
                                y: .value(yAxisLabel, y),
                                series: .value("Axis", yAxisLabel)
                            )
                            .foregroundStyle(.green)
                        }
                        
                        if let z = point.z {
                            LineMark(
                                x: .value("Time (s)", point.time),
                                y: .value(zAxisLabel, z),
                                series: .value("Axis", zAxisLabel)
                            )
                            .foregroundStyle(.blue)
                        }
                    }
                }
                .frame(height: 250)
                .chartXAxis {
                    AxisMarks(position: .bottom) { _ in
                        AxisValueLabel()
                        AxisGridLine()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel()
                        AxisGridLine()
                    }
                }
                
                // Legend
                HStack(spacing: 16) {
                    LegendItem(color: .red, label: xAxisLabel)
                    if chartData.first?.y != nil {
                        LegendItem(color: .green, label: yAxisLabel)
                    }
                    if chartData.first?.z != nil {
                        LegendItem(color: .blue, label: zAxisLabel)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // Sensor-specific axis labels
    private var xAxisLabel: String {
        switch sensorType {
        case .accelerometer: return "X (m/s²)"
        case .gyroscope: return "X (rad/s)"
        case .magnetometer: return "X (μT)"
        case .barometer: return "Pressure (kPa)"
        case .gps: return "Altitude (m)"
        case .deviceMotion: return "Roll (rad)"
        case .headphoneMotion: return "Roll (rad)"
        case .heading: return "Magnetic (°)"
        case .gravity: return "X (g)"
        case .orientation: return "Yaw (rad)"
        }
    }

    private var yAxisLabel: String {
        switch sensorType {
        case .accelerometer: return "Y (m/s²)"
        case .gyroscope: return "Y (rad/s)"
        case .magnetometer: return "Y (μT)"
        case .gps: return "Speed (m/s)"
        case .deviceMotion: return "Pitch (rad)"
        case .headphoneMotion: return "Pitch (rad)"
        case .heading: return "True (°)"
        case .gravity: return "Y (g)"
        case .orientation: return "Roll (rad)"
        default: return "Y"
        }
    }

    private var zAxisLabel: String {
        switch sensorType {
        case .accelerometer: return "Z (m/s²)"
        case .gyroscope: return "Z (rad/s)"
        case .magnetometer: return "Z (μT)"
        case .gps: return "H.Accuracy (m)"
        case .deviceMotion: return "Yaw (rad)"
        case .headphoneMotion: return "Yaw (rad)"
        case .gravity: return "Z (g)"
        case .orientation: return "Pitch (rad)"
        default: return "Z"
        }
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Raw Data Card

struct RawDataCard: View {
    let data: [String]
    let sensorType: SensorType
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .foregroundStyle(.blue)
                Text("Raw Data Preview")
                    .font(.headline)
                Spacer()
                Text("First 20 points")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            if data.isEmpty {
                Text("No data available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 25, alignment: .trailing)
                                
                                Text(item)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(nil)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(index % 2 == 0 ? Color.clear : Color.primary.opacity(0.03))
                        }
                    }
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(8)
                }
                .frame(maxHeight: 400)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Error Card

struct ErrorCard: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Error Loading Data")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    NavigationStack {
        SensorDataView(session: Session(date: Date()), sensorType: .accelerometer)
    }
}
