//
//  ContentView.swift
//  discarWatch Watch App
//
//  Created by Drogba on 2025/11/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var connectionManager = WatchConnectionManager.shared
    @StateObject private var sensorManager = WatchSensorManager.shared
    @State private var selection = 0
    
    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                // Tab 1: Recording Controls
                recordView
                    .tag(0)
                
                // Tab 2: Sensor Status
                VStack {
                    Text("Sensor Status")
                        .font(.headline)
                        .padding(.bottom, 5)
                    WatchSensorStatusCard()
                }
                .tag(1)
                
                // Tab 3: Sessions List
                WatchSessionsView()
                    .tag(2)
            }
            .tabViewStyle(.verticalPage) // Vertical swiping
        }
        .onAppear {
            Task {
                await sensorManager.requestPermissions()
            }
        }
    }
    
    private var recordView: some View {
        VStack(spacing: 20) {
            if sensorManager.isRecording {
                // Recording State
                VStack(spacing: 10) {
                    Text("RECORDING")
                        .font(.headline)
                        .foregroundStyle(.red)
                    
                    // Stats
                    VStack(spacing: 5) {
                        Text(String(format: "%.0f BPM", sensorManager.currentHeartRate))
                            .font(.system(.title, design: .rounded))
                            .fontWeight(.bold)
                        
                        Text(timeString(from: sensorManager.currentDuration))
                            .font(.monospacedDigit(.body)())
                            .foregroundStyle(.secondary)
                    }
                    
                    // Stop Button
                    Button(action: {
                         // Send Stop Command to Phone
                        connectionManager.sendStopCommand()
                        
                        // Optionally stop locally immediately to ensure data is saved even if phone is unreachable
                        Task {
                            await sensorManager.stopRecording()
                        }
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.title)
                            .padding()
                    }
                    .background(Color.red)
                    .clipShape(Circle())
                }
            } else {
                // Idle State
                VStack(spacing: 10) {
                    Text("Ready to Record")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Start Button
                    Button(action: {
                        // Only send the command. Do NOT start local recording yet.
                        // We wait for the Phone to confirm "isRecording: true" and provide a Session ID.
                        connectionManager.sendStartCommand()
                    }) {
                        Text("Start")
                            .font(.headline)
                            .padding()
                    }
                    .background(connectionManager.isPhoneReachable ? Color.blue : Color.gray)
                    .clipShape(Capsule())
                    .disabled(!connectionManager.isPhoneReachable)
                    
                    if !connectionManager.isPhoneReachable {
                        Text("Connecting to iPhone...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Error Overlay
            if let error = connectionManager.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .onTapGesture {
                        connectionManager.errorMessage = nil // Dismiss
                    }
            }
        }
        .padding()
        .onAppear {
            connectionManager.checkPhoneStatus()
        }
    }
    
    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    ContentView()
}
