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

    init() {
        // Initialize WCSession early so Watch can connect
        _ = ConnectivityManager.shared
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(darkModeEnabled ? .dark : .light)
                .environmentObject(appState)
        }
        .modelContainer(for: Session.self)
    }
}
