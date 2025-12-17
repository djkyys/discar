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
                
                // Sensor Status Card
                SensorStatusCard(
                    sensorStatus: appState.sensorStatus,
                    isLoading: appState.isCheckingSensors
                )
                
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
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isRecording ? "stop.fill" : "record.circle.fill")
                    .font(.title2)
                
                if isRecording {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(duration)
                            .font(.title3)
                            .fontWeight(.bold)
                            .monospacedDigit()
                        Text("Recording...")
                            .font(.caption)
                    }
                } else {
                    Text("Start Recording")
                        .font(.headline)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isRecording ? Color.red : Color.blue)
            .cornerRadius(12)
            .shadow(color: (isRecording ? Color.red : Color.blue).opacity(0.3), radius: 8, y: 4)
        }
        .padding(.top, 10)
    }
}

#Preview {
    RecordView()
        .environmentObject(AppState())
}
