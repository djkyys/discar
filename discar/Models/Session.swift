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
    var folderPath: String  // Full UUID from controller (e.g., "abc12345-6789-0def-...")
    var externalUUID: String?  // UUID from ctlr for correlation
    var isSynced: Bool = false

    init(date: Date, externalUUID: String? = nil) {
        // Create UUID first and store in local variable
        let sessionID = UUID()
        self.id = sessionID
        self.date = date
        self.duration = 0
        self.externalUUID = externalUUID

        // Create folder name using full UUID (ctlr UUID if available, else local UUID)
        let uuid = externalUUID ?? sessionID.uuidString
        self.folderPath = uuid
    }
}

