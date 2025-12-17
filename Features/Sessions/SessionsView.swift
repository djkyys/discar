//
//  SessionsView.swift
//  discar
//

import SwiftUI

struct SessionsView: View {
    @StateObject private var viewModel = SessionsViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if viewModel.isLoading {
                        ProgressView("Loading sessions...")
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        // Summary Cards
                        StatCard(
                            title: "Total Sessions",
                            value: "\(viewModel.sessions.count)",
                            icon: "list.bullet"
                        )
                        
                        if !viewModel.sessions.isEmpty {
                            let totalDuration = viewModel.sessions.reduce(0) { $0 + $1.duration }
                            StatCard(
                                title: "Total Time",
                                value: viewModel.formatDuration(totalDuration),
                                icon: "clock"
                            )
                            
                            if let latestSession = viewModel.sessions.first {
                                StatCard(
                                    title: "Latest Session",
                                    value: viewModel.formatDate(latestSession.date),
                                    icon: "calendar"
                                )
                            }
                        }
                        
                        // Sessions List
                        if viewModel.sessions.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "list.bullet.clipboard")
                                    .font(.system(size: 60))
                                    .foregroundStyle(.secondary)
                                Text("No sessions yet")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                Text("Start recording to create your first session")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding()
                        } else {
                            VStack(spacing: 12) {
                                ForEach(viewModel.sessions) { session in
                                    SessionRowView(
                                        session: session,
                                        viewModel: viewModel
                                    )
                                }
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Sessions")
            .onAppear {
                viewModel.loadSessions()
            }
        }
    }
}

// Session Row Component
struct SessionRowView: View {
    let session: Session
    let viewModel: SessionsViewModel
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.name)
                    .font(.headline)
                Text(viewModel.formatDate(session.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(viewModel.formatDuration(session.duration))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
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
    SessionsView()
}

