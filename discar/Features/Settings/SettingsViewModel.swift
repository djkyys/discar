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
    
    // App info
    let appVersion: String = "1.0.0"
    
    // Computed property for color scheme
    var colorScheme: ColorScheme? {
        darkModeEnabled ? .dark : .light
    }
}

