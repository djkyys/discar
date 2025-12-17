//
//  SettingsView.swift
//  discar
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // App Info Card
                    StatCard(
                        title: "App Version",
                        value: viewModel.appVersion,
                        icon: "info.circle"
                    )
                    
                    // Preferences Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Preferences")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        // Notifications Toggle Card
                        ToggleCard(
                            title: "Enable Notifications",
                            icon: "bell",
                            isOn: $viewModel.notificationsEnabled,
                            onChange: {
                                viewModel.saveSettings()
                            }
                        )
                        
                        // Dark Mode Toggle Card
                        ToggleCard(
                            title: "Dark Mode",
                            icon: "moon",
                            isOn: $viewModel.darkModeEnabled,
                            onChange: {
                                viewModel.saveSettings()
                            }
                        )
                    }
                    
                    // Actions Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Actions")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        // Privacy Policy Button
                        Button(action: {
                            viewModel.openPrivacyPolicy()
                        }) {
                            HStack {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.blue)
                                    .frame(width: 40)
                                
                                Text("Privacy Policy")
                                    .font(.body)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                        
                        // Sign Out Button
                        Button(action: {
                            viewModel.signOut()
                        }) {
                            HStack {
                                Image(systemName: "arrow.right.square")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.red)
                                    .frame(width: 40)
                                
                                Text("Sign Out")
                                    .font(.body)
                                    .foregroundStyle(.red)
                                
                                Spacer()
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Settings")
            .onAppear {
                viewModel.loadSettings()
            }
        }
    }
}

// Toggle Card Component
struct ToggleCard: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    let onChange: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.blue)
                .frame(width: 40)
            
            Text(title)
                .font(.body)
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .onChange(of: isOn) { _, _ in
                    onChange()
                }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    SettingsView()
}

