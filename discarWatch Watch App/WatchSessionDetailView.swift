//
//  WatchSessionDetailView.swift
//  discarWatch Watch App
//
//  Created by Drogba on 2025/11/24.
//

import SwiftUI

struct WatchSessionDetailView: View {
    let session: WatchSessionMetadata
    @State private var sensorCounts: [String: Int] = [:]
    @State private var isLoading = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                Text(formatDate(session.date))
                    .font(.headline)
                    .foregroundStyle(.blue)
                Text(formatDuration(session.duration))
                    .font(.title2)
                    .fontWeight(.bold)
                
                Divider()
                    .padding(.vertical)
                
                // Sensor Stats
                if isLoading {
                    ProgressView()
                } else {
                    VStack(spacing: 8) {
                        statRow(title: "Heart Rate", count: sensorCounts["heart_rate.json"] ?? 0, icon: "heart.fill", color: .red)
                        statRow(title: "Accelerometer", count: sensorCounts["accelerometer.json"] ?? 0, icon: "figure.walk", color: .blue)
                        statRow(title: "Gyroscope", count: sensorCounts["gyroscope.json"] ?? 0, icon: "rotate.3d", color: .green)
                        statRow(title: "GPS/Compass", count: sensorCounts["compass.json"] ?? 0, icon: "location.fill", color: .indigo)
                        statRow(title: "SpO2", count: sensorCounts["spo2.json"] ?? 0, icon: "lungs.fill", color: .cyan)
                        statRow(title: "Temperature", count: sensorCounts["temperature.json"] ?? 0, icon: "thermometer", color: .orange)
                    }
                }
            }
        }
        .padding()
        .navigationTitle("Details")
        .onAppear(perform: loadDetails)
    }
    
    private func statRow(title: String, count: Int, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            
            Text(title)
                .font(.caption)
            
            Spacer()
            
            Text("\(count)")
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
        }
        .opacity(count > 0 ? 1.0 : 0.4)
    }
    
    private func loadDetails() {
        let fileManager = FileManager.default
        guard let docURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let sessionDir = docURL.appendingPathComponent(session.id)
        
        Task {
            var counts: [String: Int] = [:]
            
            // Helper to count JSON array length
            func countFile(_ filename: String) -> Int {
                let url = sessionDir.appendingPathComponent(filename)
                guard let data = try? Data(contentsOf: url),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return 0 }
                return json.count
            }
            
            counts["heart_rate.json"] = countFile("heart_rate.json")
            counts["accelerometer.json"] = countFile("accelerometer.json")
            counts["gyroscope.json"] = countFile("gyroscope.json")
            counts["compass.json"] = countFile("compass.json")
            counts["spo2.json"] = countFile("spo2.json")
            counts["temperature.json"] = countFile("temperature.json")
            
            await MainActor.run {
                self.sensorCounts = counts
                self.isLoading = false
            }
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        guard let date = isoFormatter.date(from: dateString) else { return dateString }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}


