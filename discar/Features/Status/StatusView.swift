//
//  StatusView.swift
//  discar
//

import SwiftUI
import SwiftData

struct StatusView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = StatusViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // 1. Rider Controller
                    RiderControllerCard(
                        status: viewModel.piStatus,
                        message: viewModel.piMessage
                    )
                    
                    // 1b. OBD Status
                    OBDStatusCard()
                    
                    // 2. Action Buttons
                    ActionButtons(
                        isConnected: viewModel.piStatus != .disconnected && viewModel.piStatus != .error,
                        onConnect: viewModel.connectToPi,
                        onRefresh: {
                            viewModel.disconnectPi()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                viewModel.connectToPi()
                            }
                        }
                    )
                    
                    // 3. Live Data Section
                    if viewModel.piStatus == .idle || viewModel.piStatus == .recording || viewModel.piStatus == .connected {
                        VStack(spacing: 20) {
                            // Stats Grid
                            LiveStatsGrid(
                                connectedCameras: viewModel.connectedCameras,
                                lastHeartbeat: viewModel.lastHeartbeat
                            )
                            
                            // Camera System Grid
                            if !viewModel.cameraNodes.isEmpty {
                                CameraGrid(nodes: viewModel.cameraNodes)
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Status")
            .onAppear {
                viewModel.updateModelContext(modelContext)
                viewModel.loadData()
            }
        }
    }
}

// MARK: - Components

struct RiderControllerCard: View {
    let status: StatusViewModel.PiStatus
    let message: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rider Controller")
                    .font(.headline)
                    .foregroundStyle(.gray)
                
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .padding(2)
                        .background(Circle().stroke(statusColor.opacity(0.3), lineWidth: 2))
                    
                    Text(message)
                        .font(.title3)
                        .fontWeight(.bold)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Image(systemName: "server.rack")
                .font(.largeTitle)
                .foregroundStyle(Color.blue)
                .opacity(0.8)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }
    
    private var statusColor: Color {
        switch status {
        case .disconnected: return .gray
        case .connecting: return .yellow
        case .connected: return .green.opacity(0.6)
        case .idle: return .green
        case .recording: return .red
        case .error: return .orange
        }
    }
}

struct ActionButtons: View {
    let isConnected: Bool
    let onConnect: () -> Void
    let onRefresh: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Button(action: onConnect) {
                Text("Connect")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .disabled(isConnected)
            .opacity(isConnected ? 0.5 : 1.0)
            
            Button(action: onRefresh) {
                Text("Refresh")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(uiColor: .secondarySystemBackground))
                    .foregroundStyle(.primary)
                    .cornerRadius(12)
            }
        }
    }
}

struct LiveStatsGrid: View {
    let connectedCameras: String
    let lastHeartbeat: String
    
    var body: some View {
        HStack(spacing: 12) {
            StatsCard(title: "Cameras", value: connectedCameras, unit: "Active", icon: "video.fill")
            StatsCard(title: "Last Update", value: lastHeartbeat, unit: "", icon: "clock.arrow.circlepath")
        }
    }
}

struct StatsCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(Color.blue)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct CameraGrid: View {
    let nodes: [StatusViewModel.CameraNode]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Camera System")
                .font(.headline)
                .foregroundStyle(.gray)
                .padding(.leading, 4)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(nodes) { node in
                    CameraStatusCard(node: node)
                }
            }
        }
    }
}

struct CameraStatusCard: View {
    let node: StatusViewModel.CameraNode
    
    var body: some View {
        VStack(spacing: 8) {
            // Icon & Status Dot
            ZStack(alignment: .topTrailing) {
                Image(systemName: "video.fill")
                    .font(.system(size: 24))
                    // Fix: Explicitly cast to Color to avoid ShapeStyle ambiguity
                    .foregroundStyle(node.connected ? Color.primary : Color.gray.opacity(0.5))
                
                Circle()
                    .fill(node.connected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .offset(x: 2, y: -2)
            }
            
            Text(node.name)
                .font(.caption)
                .fontWeight(.bold)
            
            Text(node.state)
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            // Storage Bar
            VStack(spacing: 4) {
                ProgressView(value: Double(node.storageUsedPercent), total: 100)
                    .tint(storageColor(percent: node.storageUsedPercent))
                    .scaleEffect(x: 1, y: 0.5, anchor: .center)
                
                Text("\(node.storageUsedPercent)% Used")
                    .font(.caption2)
                    .foregroundStyle(Color.gray)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
    
    func storageColor(percent: Int) -> Color {
        if percent > 90 { return .red }
        if percent > 75 { return .orange }
        return .blue
    }
}

#Preview {
    StatusView()
}
