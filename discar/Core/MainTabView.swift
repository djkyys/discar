//
//  MainTabView.swift
//  discar
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            StatusView()
                .tabItem {
                    Label("Status", systemImage: "chart.bar.fill")
                }
            
            RecordView()
                .tabItem {
                    Label("Record", systemImage: "record.circle")
                }
            
            SessionsView()
                .tabItem {
                    Label("Sessions", systemImage: "list.bullet")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .tint(.blue)
    }
}

#Preview {
    MainTabView()
}
