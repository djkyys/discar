//
//  Session.swift
//  discar
//

import SwiftData
import Foundation

@Model
class Session {
    var id: UUID
    var date: Date
    var duration: TimeInterval
    var folderPath: String  // e.g., "2025-11-18_10-30-45_abc123"
    var externalUUID: String?  // UUID from ctlr for correlation
    var isSynced: Bool = false

    init(date: Date, externalUUID: String? = nil) {
        // Create UUID first and store in local variable
        let sessionID = UUID()
        self.id = sessionID
        self.date = date
        self.duration = 0
        self.externalUUID = externalUUID

        // Create folder name using ctlr UUID if available, else local UUID
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = formatter.string(from: date)
        let shortID = (externalUUID ?? sessionID.uuidString).prefix(6)
        self.folderPath = "\(dateString)_\(shortID)"
    }
}

