//
//  discarApp.swift
//  discar
//
//  App entry point - initializes services and SwiftData
//

import SwiftUI
import SwiftData

@main
struct discarApp: App {
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Initialize WatchCoordinator early so Watch can connect
        _ = WatchCoordinator.shared
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(darkModeEnabled ? .dark : .light)
                .environmentObject(appState)
        }
        .modelContainer(for: Session.self)
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            // Cleanup old exports when entering background
            Task {
                try? await ExportService.shared.cleanupOldExports()
            }
        case .active:
            // Reconnect WebSocket when becoming active
            WebSocketService.shared.connect()
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}
