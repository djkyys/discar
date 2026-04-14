//
//  SettingsViewModel.swift
//  discar
//

import Foundation
import Combine
import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    // Dark mode setting (persisted in UserDefaults)
    @AppStorage("darkModeEnabled") var darkModeEnabled: Bool = false

    // Controller IP (persisted)
    @AppStorage("controllerIP") var controllerIP: String = "192.168.8.145"

    // Connection test state
    @Published var isTestingConnection = false
    @Published var connectionStatus: ConnectionStatus?

    enum ConnectionStatus {
        case success(cameras: Int)
        case failed(String)
    }

    // App info
    let appVersion: String = "1.0.0"

    // Computed property for color scheme
    var colorScheme: ColorScheme? {
        darkModeEnabled ? .dark : .light
    }

    // Test connection to controller
    func testConnection() async {
        isTestingConnection = true
        connectionStatus = nil

        guard let url = URL(string: "http://\(controllerIP):8000/api/status") else {
            connectionStatus = .failed("Invalid IP address")
            isTestingConnection = false
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                connectionStatus = .failed("Server error")
                isTestingConnection = false
                return
            }

            let status = try JSONDecoder().decode(CtlrStatusCheck.self, from: data)
            let connectedCams = status.cameras.filter { $0.connected }.count
            connectionStatus = .success(cameras: connectedCams)
        } catch let error as URLError {
            if error.code == .timedOut {
                connectionStatus = .failed("Connection timed out")
            } else if error.code == .cannotConnectToHost {
                connectionStatus = .failed("Cannot connect to host")
            } else {
                connectionStatus = .failed("Network error")
            }
        } catch {
            connectionStatus = .failed("Error: \(error.localizedDescription)")
        }

        isTestingConnection = false
    }
}

// Lightweight status check model
private struct CtlrStatusCheck: Codable {
    let ready: Bool
    let recording: Bool
    let cameras: [CameraStatus]

    struct CameraStatus: Codable {
        let name: String
        let connected: Bool
    }
}

