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
        ScrollView {
            VStack(spacing: 12) {
                // Phone Status Panel
                phoneStatusPanel

                Divider()

                // Watch Recording Section
                if sensorManager.isRecording {
                    watchRecordingView
                } else {
                    watchIdleView
                }
            }
            .padding()
        }
    }

    // MARK: - Phone Status Panel

    private var phoneStatusPanel: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "iphone")
                    .font(.caption)
                Text("iPhone")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Circle()
                    .fill(connectionManager.isPhoneReachable ? .green : .orange)
                    .frame(width: 6, height: 6)
            }

            HStack {
                if connectionManager.phoneIsRecording {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.red)
                            .frame(width: 6, height: 6)
                        Text("Recording")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                } else {
                    Text("Idle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let sessionID = connectionManager.phoneSessionID {
                    Text(String(sessionID.prefix(8)))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Watch Recording View

    private var watchRecordingView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                Text("RECORDING")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
            }

            Text(timeString(from: sensorManager.currentDuration))
                .font(.system(.title2, design: .rounded))
                .fontWeight(.bold)
                .monospacedDigit()

            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text(String(format: "%.0f", sensorManager.currentHeartRate))
                    .fontWeight(.medium)
                Text("BPM")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)

            // Stop Button
            Button {
                Task {
                    await connectionManager.stopWatchRecording()
                }
            } label: {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("Stop")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }

    // MARK: - Watch Idle View

    private var watchIdleView: some View {
        VStack(spacing: 12) {
            Image(systemName: "applewatch")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("Watch Ready")
                .font(.headline)

            // Start Button - always enabled, uses phone's UUID if available
            Button {
                Task {
                    await connectionManager.startWatchRecording()
                }
            } label: {
                HStack {
                    Image(systemName: "record.circle")
                    Text("Start")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(connectionManager.phoneIsRecording ? .green : .orange)

            if connectionManager.phoneIsRecording {
                Text("Will use iPhone session")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Text("iPhone not recording")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
