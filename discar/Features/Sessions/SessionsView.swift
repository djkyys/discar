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
                viewModel?.loadSessions()
            }
        }
    }
}

private struct SessionsContent: View {
    @ObservedObject var viewModel: SessionsViewModel
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false
    @State private var exportURLs: [URL] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if viewModel.isLoading {
                    ProgressView("Loading sessions...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    // Stats card
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isEditMode {
                    Button("Done") {
                        viewModel.exitEditMode()
                    }
                    .fontWeight(.semibold)
                } else {
                    Button("Edit") {
                        viewModel.isEditMode = true
                    }
                    .disabled(viewModel.sessions.isEmpty)
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                if viewModel.isEditMode && viewModel.hasSelection {
                    HStack(spacing: 16) {
                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .foregroundStyle(.red)

                        Button {
                            Task {
                                exportURLs = await viewModel.exportSelected()
                                if !exportURLs.isEmpty {
                                    showShareSheet = true
                                }
                            }
                        } label: {
                            if viewModel.isExporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .disabled(viewModel.isExporting)
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(urls: exportURLs) {
                exportURLs = []
                viewModel.exitEditMode()
            }
        }
        .alert("Delete Sessions", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.selectedCount)", role: .destructive) {
                viewModel.deleteSelected()
            }
        } message: {
            Text("Are you sure you want to delete \(viewModel.selectedCount) session(s)? This cannot be undone.")
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
            // Select All button in edit mode
            if viewModel.isEditMode {
                HStack {
                    Button(action: {
                        if viewModel.selectedCount == viewModel.sessions.count {
                            viewModel.clearSelection()
                        } else {
                            viewModel.selectAll()
                        }
                    }) {
                        Text(viewModel.selectedCount == viewModel.sessions.count ? "Deselect All" : "Select All")
                            .font(.subheadline)
                    }
                    Spacer()
                    Text("\(viewModel.selectedCount) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }

            ForEach(viewModel.sessions) { session in
                if viewModel.isEditMode {
                    // Edit mode - tap to select
                    SessionRowView(
                        session: session,
                        viewModel: viewModel,
                        isSelected: viewModel.selectedSessions.contains(session.id),
                        isEditMode: true
                    )
                    .onTapGesture {
                        viewModel.toggleSelection(session)
                    }
                } else {
                    // Normal mode - tap to navigate
                    NavigationLink(destination: SessionDetailView(session: session)) {
                        SessionRowView(
                            session: session,
                            viewModel: viewModel,
                            isSelected: false,
                            isEditMode: false
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Session Row

struct SessionRowView: View {
    let session: Session
    let viewModel: SessionsViewModel
    let isSelected: Bool
    let isEditMode: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Selection indicator (edit mode only)
            if isEditMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)
            }

            // Session info
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.formatDate(session.date))
                    .font(.headline)

                HStack(spacing: 8) {
                    Text(String((session.externalUUID ?? session.id.uuidString).prefix(6)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontDesign(.monospaced)

                    // Sync status indicator
                    if session.isSynced {
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark.icloud.fill")
                                .font(.caption2)
                            Text("synced")
                                .font(.caption2)
                        }
                        .foregroundStyle(.green)
                    } else {
                        HStack(spacing: 2) {
                            Image(systemName: "icloud.slash")
                                .font(.caption2)
                            Text("local")
                                .font(.caption2)
                        }
                        .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            // Duration
            Text(viewModel.formatDuration(session.duration))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fontDesign(.monospaced)

            // Chevron (normal mode only)
            if !isEditMode {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.1) : Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
}

#Preview {
    SessionsView()
}
