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
    
    init(date: Date) {
        // Create UUID first and store in local variable
        let sessionID = UUID()
        self.id = sessionID
        self.date = date
        self.duration = 0
        
        // Create folder name: 2025-11-18_10-30-45_abc123
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = formatter.string(from: date)
        let shortID = sessionID.uuidString.prefix(8)
        self.folderPath = "\(dateString)_\(shortID)"
    }
}

