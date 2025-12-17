//
//  discarApp.swift
//  discar
//

import SwiftUI
import SwiftData

@main
struct discarApp: App {
    @AppStorage("darkModeEnabled") private var darkModeEnabled: Bool = false
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(darkModeEnabled ? .dark : .light)
                .environmentObject(appState)
        }
        .modelContainer(for: Session.self)
    }
}
