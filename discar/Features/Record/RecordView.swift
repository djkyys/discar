//
//  RecordView.swift
//  discar
//

import SwiftUI
import SwiftData
import OSLog

struct RecordView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        RecordViewInternal(modelContext: modelContext)
    }
}

private struct RecordViewInternal: View {
    @StateObject private var viewModel: RecordViewModel
    @EnvironmentObject var appState: AppState

    init(modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: RecordViewModel(modelContext: modelContext))
    }

    var body: some View {
        RecordContent(viewModel: viewModel, appState: appState)
    }
}

private struct RecordContent: View {
    @ObservedObject var viewModel: RecordViewModel
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Record")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Sensor Status Card (pre-recording overview)
                if !viewModel.isRecording {
                    SensorStatusCard(
                        sensorStatus: appState.sensorStatus,
                        isLoading: appState.isCheckingSensors
                    )
                }

                // Live Sensor Health (during recording)
                if viewModel.isRecording, let health = viewModel.sensorHealth {
                    SensorHealthBar(health: health)
                }

                // External connections status (during recording)
                if viewModel.isRecording {
                    VStack(spacing: 12) {
                        // Watch Status
                        ConnectionStatusRow(
                            icon: "applewatch",
                            label: "Watch",
                            isConnected: viewModel.isWatchConnected,
                            detail: viewModel.isWatchConnected ? "Recording" : nil
                        )

                        // CAN Bus Status
                        CANStatusRow(
                            connected: viewModel.canConnected,
                            fileSizeFormatted: viewModel.canFileSizeFormatted
                        )
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(12)
                }

                // Record Button
                if viewModel.isStarting {
                    ProgressView("Preparing System...")
                        .padding()
                } else {
                    RecordButton(
                        isRecording: viewModel.isRecording,
                        duration: viewModel.durationFormatted,
                        action: {
                            Task {
                                if viewModel.isRecording {
                                    await viewModel.stopRecording()
                                } else {
                                    await viewModel.startRecording()
                                }
                            }
                        }
                    )
                }

                Spacer()
            }
            .padding()
            .alert("Recording Failed", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown Error")
            }
        }
    }
}

// MARK: - Record Button

struct RecordButton: View {
    let isRecording: Bool
    let duration: String
    let action: () -> Void

    private var buttonColor: Color {
        isRecording ? AppTheme.Colors.recording : AppTheme.Colors.accent
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: isRecording ? "stop.fill" : "record.circle.fill")
                    .font(.system(size: 20, weight: .semibold))

                if isRecording {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(duration)
                            .font(AppTheme.Typography.title3)
                            .monospacedDigit()
                        Text("Recording...")
                            .font(AppTheme.Typography.caption)
                            .opacity(0.9)
                    }
                } else {
                    Text("Start Recording")
                        .font(AppTheme.Typography.headline)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.lg)
            .background(buttonColor)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Connection Status Row

struct ConnectionStatusRow: View {
    let icon: String
    let label: String
    let isConnected: Bool
    let detail: String?

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(isConnected ? .green : .gray)
                    .frame(width: 20)

                Text(label)
                    .font(.subheadline)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(isConnected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                Text(isConnected ? (detail ?? "Connected") : "Disconnected")
                    .font(.caption)
                    .foregroundStyle(isConnected ? .green : .gray)
            }
        }
    }
}

// MARK: - CAN Status Row

struct CANStatusRow: View {
    let connected: Bool
    let fileSizeFormatted: String

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "car.fill")
                    .foregroundStyle(connected ? .green : .gray)
                    .frame(width: 20)

                Text("CAN Bus")
                    .font(.subheadline)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(connected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                if connected && !fileSizeFormatted.isEmpty {
                    Text(fileSizeFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !connected {
                    Text("Disconnected")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }
        }
    }
}

#Preview {
    RecordView()
        .environmentObject(AppState())
}
