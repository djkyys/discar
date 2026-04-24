//
//  SettingsViewModel.swift
//  discar
//
//  App configuration and connection testing
//

import Foundation
import SwiftUI
import Combine

@MainActor
class SettingsViewModel: ObservableObject {

    // MARK: - Settings (Persisted)

    @AppStorage("darkModeEnabled") var darkModeEnabled = false
    @AppStorage("controllerIP") var controllerIP = "192.168.8.145"

    // MARK: - Connection Test State

    @Published var isTestingConnection = false
    @Published var connectionStatus: ConnectionStatus?

    enum ConnectionStatus {
        case success(cameras: Int)
        case failed(String)
    }

    // MARK: - App Info

    let appVersion = AppConfig.App.version

    // MARK: - Computed Properties

    var colorScheme: ColorScheme? {
        darkModeEnabled ? .dark : .light
    }

    var isValidIP: Bool {
        AppConfig.isValidIP(controllerIP)
    }

    // MARK: - Connection Test

    func testConnection() async {
        isTestingConnection = true
        connectionStatus = nil

        guard isValidIP else {
            connectionStatus = .failed("Invalid IP address format")
            isTestingConnection = false
            return
        }

        do {
            let cameras = try await APIClient.shared.testConnection()
            connectionStatus = .success(cameras: cameras)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                connectionStatus = .failed("Connection timed out")
            case .cannotConnectToHost:
                connectionStatus = .failed("Cannot connect to host")
            default:
                connectionStatus = .failed("Network error")
            }
        } catch {
            connectionStatus = .failed(error.localizedDescription)
        }

        isTestingConnection = false
    }
}
