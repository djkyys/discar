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
                // Tab 1: Status (display only, no controls)
                statusView
                    .tag(0)

                // Tab 2: Sessions (minimal, for cleanup)
                WatchSessionsView()
                    .tag(1)
            }
            .tabViewStyle(.verticalPage)
        }
        .onAppear {
            Task {
                await sensorManager.requestPermissions()
            }
            connectionManager.checkPhoneStatus()
        }
    }

    private var statusView: some View {
        VStack(spacing: 0) {
            // Top half: iPhone status + sensors
            VStack(spacing: 6) {
                phoneStatusRow
                sensorIndicators
            }
            .frame(maxHeight: .infinity)

            // Bottom half: Record button
            recordButton
                .frame(maxHeight: .infinity)
        }
        .padding()
    }

    // MARK: - Phone Status Row

    private var phoneStatusRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "iphone")
                .font(.caption2)

            Circle()
                .fill(connectionManager.isPhoneReachable ? .green : .orange)
                .frame(width: 5, height: 5)

            if connectionManager.phoneIsRecording {
                Circle()
                    .fill(.red)
                    .frame(width: 5, height: 5)
                Text("REC")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.red)
                if let sessionID = connectionManager.phoneSessionID {
                    Text(String(sessionID.prefix(6)))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Idle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Sensor Indicators

    private var sensorIndicators: some View {
        HStack(spacing: 8) {
            sensorDot("heart.fill", active: sensorManager.isRecording)
            sensorDot("move.3d", active: sensorManager.isRecording)
            sensorDot("barometer", active: sensorManager.isRecording)
            sensorDot("location.north.fill", active: sensorManager.isRecording)
        }
    }

    private func sensorDot(_ icon: String, active: Bool) -> some View {
        Image(systemName: icon)
            .font(.caption2)
            .foregroundStyle(active ? .green : .secondary)
    }

    // MARK: - Record Button

    private var recordButton: some View {
        VStack(spacing: 4) {
            if sensorManager.isRecording {
                // Recording state
                Text(timeString(from: sensorManager.currentDuration))
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .monospacedDigit()

                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                    Text("\(Int(sensorManager.currentHeartRate))")
                        .fontWeight(.medium)
                }
                .font(.caption)

                Button {
                    Task { await connectionManager.stopWatchRecording() }
                } label: {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("Stop")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                // Idle state
                Button {
                    Task { await connectionManager.startWatchRecording() }
                } label: {
                    HStack {
                        Image(systemName: "record.circle")
                        Text("Start")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(connectionManager.phoneIsRecording ? .green : .orange)
            }
        }
    }

    private func timeString(from interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    ContentView()
}
