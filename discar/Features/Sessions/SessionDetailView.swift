//
//  SessionDetailView.swift
//  discar
//

import SwiftUI
import SwiftData

struct SessionDetailView: View {
    let session: Session
    @StateObject private var viewModel: SessionDetailViewModel
    @StateObject private var transferManager = WatchDataTransferManager.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteAlert = false
    
    init(session: Session) {
        self.session = session
        _viewModel = StateObject(wrappedValue: SessionDetailViewModel(session: session))
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                // Watch Data Status Card
                WatchTransferCard(session: session)
                
                // Session Info Card
                SessionInfoCard(session: session)
                
                // Sensor Data Cards
                if viewModel.isLoading {
                    ProgressView("Loading session data...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    VStack(spacing: 12) {
                        if viewModel.accelerometerCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .accelerometer)) {
                                SensorDataCard(
                                    title: "Accelerometer",
                                    icon: "figure.walk",
                                    count: viewModel.accelerometerCount,
                                    color: .blue
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if viewModel.gyroscopeCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .gyroscope)) {
                                SensorDataCard(
                                    title: "Gyroscope",
                                    icon: "rotate.3d",
                                    count: viewModel.gyroscopeCount,
                                    color: .green
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if viewModel.magnetometerCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .magnetometer)) {
                                SensorDataCard(
                                    title: "Magnetometer",
                                    icon: "scope",
                                    count: viewModel.magnetometerCount,
                                    color: .purple
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if viewModel.barometerCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .barometer)) {
                                SensorDataCard(
                                    title: "Barometer",
                                    icon: "barometer",
                                    count: viewModel.barometerCount,
                                    color: .orange
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if viewModel.gpsCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .gps)) {
                                SensorDataCard(
                                    title: "GPS",
                                    icon: "location.fill",
                                    count: viewModel.gpsCount,
                                    color: .red
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if viewModel.deviceMotionCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .deviceMotion)) {
                                SensorDataCard(
                                    title: "Device Motion",
                                    icon: "arrow.trianglehead.2.clockwise.rotate.90",
                                    count: viewModel.deviceMotionCount,
                                    color: .cyan
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if viewModel.headphoneMotionCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .headphoneMotion)) {
                                SensorDataCard(
                                    title: "AirPods Motion",
                                    icon: "airpods.gen3",
                                    count: viewModel.headphoneMotionCount,
                                    color: .mint
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if viewModel.headingCount > 0 {
                            NavigationLink(destination: SensorDataView(session: session, sensorType: .heading)) {
                                SensorDataCard(
                                    title: "Heading (Compass)",
                                    icon: "location.north.fill",
                                    count: viewModel.headingCount,
                                    color: .indigo
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            // Export Options
            ExportCard(session: session)
            
            // Delete Button
            Button(role: .destructive, action: { showDeleteAlert = true }) {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Session")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundStyle(.red)
                .cornerRadius(12)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .alert("Delete Session?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteSession()
            }
        } message: {
            Text("This action cannot be undone. All sensor data for this session will be permanently deleted.")
        }
        .task {
            await viewModel.loadSessionData()
        }
    }
    
    private func deleteSession() {
        // Delete from SwiftData
        modelContext.delete(session)
        try? modelContext.save()
        
        // Delete files
        Task {
            do {
                try await StorageService.shared.deleteSession(session: session)
            } catch {
                print("Failed to delete session files: \(error)")
            }
        }
        
        // Dismiss view
        dismiss()
    }
}

// MARK: - Export Card

struct ExportCard: View {
    let session: Session
    @State private var showExporter = false
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.blue)
                Text("Export Session")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            Button(action: { exportAsZip() }) {
                HStack {
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "doc.zipper")
                    }
                    Text(isExporting ? "Creating ZIP..." : "Export as ZIP")
                    Spacer()
                    Image(systemName: "square.and.arrow.up")
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            .disabled(isExporting)
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .sheet(isPresented: $showExporter) {
            if let url = exportURL {
                DocumentExporter(url: url) {
                    showExporter = false
                    // Clean up after export
                    Task {
                        try? await ExportService.shared.cleanupOldExports()
                    }
                }
            }
        }
    }
    
    private func exportAsZip() {
        isExporting = true
        errorMessage = nil
        
        Task {
            do {
                let zipURL = try await ExportService.shared.createZIP(session: session)
                
                await MainActor.run {
                    self.exportURL = zipURL
                    self.isExporting = false
                    self.showExporter = true
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Export failed: \(error.localizedDescription)"
                    self.isExporting = false
                }
            }
        }
    }
}

// MARK: - Session Info Card

struct SessionInfoCard: View {
    let session: Session
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.blue)
                Text("Session Information")
                    .font(.headline)
            }
            
            Divider()
            
            InfoRow(label: "Date", value: formatDate(session.date))
            InfoRow(label: "Duration", value: formatDuration(session.duration))
            InfoRow(label: "Session ID", value: String(session.id.uuidString.prefix(8)) + "...")
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, secs)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Sensor Data Card

struct SensorDataCard: View {
    let title: String
    let icon: String
    let count: Int
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(count) data points")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    NavigationStack {
        SessionDetailView(session: Session(date: Date()))
    }
}

