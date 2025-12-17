//
//  SettingsView.swift
//  discar
//

import SwiftUI
import CoreMotion
import CoreLocation

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject var appState: AppState
    @AppStorage("isTestMode") private var isTestMode = false // New Storage
    @State private var showPrivacyPolicy = false
    
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
                    
                    // Sensor Diagnostics (New Section)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Diagnostics")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        SensorStatusCard(
                            sensorStatus: appState.sensorStatus,
                            isLoading: appState.isCheckingSensors
                        )
                        
                        Button(action: {
                            appState.refreshSensors()
                        }) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Recheck Sensors")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                    
                    // Preferences Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Preferences")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        // Dark Mode Toggle Card
                        ToggleCard(
                            title: "Dark Mode",
                            icon: "moon",
                            isOn: $viewModel.darkModeEnabled
                        )
                    }
                    
                    // Developer Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Developer")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ToggleCard(
                            title: "Test Mode (Skip Pi Check)",
                            icon: "ant.circle",
                            isOn: $isTestMode
                        )
                    }
                    
                    // Actions Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Actions")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        // Privacy Policy Button
                        Button(action: {
                            showPrivacyPolicy = true
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
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPrivacyPolicy) {
                PrivacyPolicyView()
            }
        }
    }
}

// Toggle Card Component
struct ToggleCard: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    
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
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// Privacy Policy Modal View
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Privacy Policy")
                        .font(.title)
                        .fontWeight(.bold)
                        .padding(.bottom, 10)
                    
                    Text("Last Updated: November 18, 2025")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text("""
                    Your privacy is important to us. This Privacy Policy explains how we collect, use, and protect your information when you use our app.
                    
                    Information We Collect
                    We may collect information that you provide directly to us, including session data and usage statistics.
                    
                    How We Use Your Information
                    We use the information we collect to provide and improve our services, process your requests, and communicate with you.
                    
                    Data Security
                    We implement appropriate security measures to protect your personal information against unauthorized access, alteration, disclosure, or destruction.
                    
                    Your Rights
                    You have the right to access, update, or delete your personal information at any time through the app settings.
                    
                    Contact Us
                    If you have any questions about this Privacy Policy, please contact us through the app.
                    """)
                    .font(.body)
                    .lineSpacing(4)
                }
                .padding()
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
