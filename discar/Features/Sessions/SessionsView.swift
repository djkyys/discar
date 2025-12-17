//
//  SessionsView.swift
//  discar
//

import SwiftUI
import SwiftData

struct SessionsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: SessionsViewModel?
    
    var body: some View {
        NavigationStack {
            Group {
                if let viewModel = viewModel {
                    SessionsContent(viewModel: viewModel)
                } else {
                    ProgressView("Loading...")
                }
            }
            .navigationTitle("Sessions")
            .onAppear {
                if viewModel == nil {
                    viewModel = SessionsViewModel(modelContext: modelContext)
                }
                // Always reload sessions when view appears to reflect changes/deletions
                viewModel?.loadSessions()
            }
        }
    }
}

private struct SessionsContent: View {
    @ObservedObject var viewModel: SessionsViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if viewModel.isLoading {
                    ProgressView("Loading sessions...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    StatCard(
                        title: "Total Sessions",
                        value: "\(viewModel.sessions.count)",
                        icon: "list.bullet"
                    )
                    
                    if viewModel.sessions.isEmpty {
                        emptyStateView
                    } else {
                        sessionsList
                    }
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    private var emptyStateView: some View {
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
    }
    
    private var sessionsList: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.sessions) { session in
                NavigationLink(destination: SessionDetailView(session: session)) {
                    SessionRowView(session: session, viewModel: viewModel)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SessionRowView: View {
    let session: Session
    let viewModel: SessionsViewModel
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.formatDate(session.date))
                    .font(.headline)
                Text(String(session.id.uuidString.prefix(8)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontDesign(.monospaced)
            }
            
            Spacer()
            
            Text(viewModel.formatDuration(session.duration))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fontDesign(.monospaced)
            
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

