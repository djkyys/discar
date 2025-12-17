//
//  RecordView.swift
//  discar
//

import SwiftUI

struct RecordView: View {
    @StateObject private var viewModel = RecordViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Recording Status Card
                    StatCard(
                        title: "Status",
                        value: viewModel.isRecording ? "Recording" : "Ready",
                        icon: viewModel.isRecording ? "record.circle.fill" : "record.circle"
                    )
                    
                    // Duration Card
                    if viewModel.isRecording {
                        StatCard(
                            title: "Duration",
                            value: viewModel.durationFormatted,
                            icon: "clock"
                        )
                    }
                    
                    // Control Button
                    Button(action: {
                        if viewModel.isRecording {
                            viewModel.stopRecording()
                        } else {
                            viewModel.startRecording()
                        }
                    }) {
                        HStack {
                            Image(systemName: viewModel.isRecording ? "stop.fill" : "record.circle.fill")
                            Text(viewModel.isRecording ? "Stop Recording" : "Start Recording")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(viewModel.isRecording ? Color.red : Color.blue)
                        .cornerRadius(12)
                    }
                    .padding(.top, 10)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Record")
        }
    }
}

#Preview {
    RecordView()
}

