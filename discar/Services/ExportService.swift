//
//  ExportService.swift
//  discar
//

import Foundation
import UIKit
import OSLog

actor ExportService {
    static let shared = ExportService()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "discar", category: "ExportService")
    
    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private var sessionsURL: URL {
        documentsURL.appendingPathComponent("Sessions")
    }
    
    private var tempExportsURL: URL {
        // Use system temporary directory - safest for sharing permissions
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Exports")
    }
    
    // Get session folder URL
    private func getSessionFolderURL(session: Session) -> URL {
        sessionsURL.appendingPathComponent(session.folderPath)
    }
    
    // Create ZIP of session folder
    func createZIP(session: Session) async throws -> URL {
        let sessionFolder = getSessionFolderURL(session: session)
        
        guard FileManager.default.fileExists(atPath: sessionFolder.path) else {
            throw ExportError.sessionFolderNotFound
        }
        
        // Create temp exports folder if needed
        if !FileManager.default.fileExists(atPath: tempExportsURL.path) {
            try FileManager.default.createDirectory(at: tempExportsURL, withIntermediateDirectories: true)
        }
        
        // Create destination ZIP path
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = dateFormatter.string(from: session.date)
        let zipName = "\(dateString)_\(session.id.uuidString.prefix(8)).zip"
        let destinationURL = tempExportsURL.appendingPathComponent(zipName)
        
        // Remove old file if exists
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        
        logger.info("Creating ZIP from: \(sessionFolder.path)")
        logger.info("Destination: \(destinationURL.path)")
        
        // Use NSFileCoordinator to create ZIP
        let zipURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?
            
            coordinator.coordinate(readingItemAt: sessionFolder, options: .forUploading, error: &coordinationError) { zippedURL in
                do {
                    // Copy the temporary ZIP to our cache location
                    try FileManager.default.copyItem(at: zippedURL, to: destinationURL)
                    
                    // Verify file exists and is readable
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        let attributes = try? FileManager.default.attributesOfItem(atPath: destinationURL.path)
                        let size = attributes?[.size] as? Int64 ?? 0
                        self.logger.info("ZIP created successfully: \(size) bytes")
                    }
                    
                    continuation.resume(returning: destinationURL)
                } catch {
                    self.logger.error("Failed to copy ZIP: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
            
            if let error = coordinationError {
                self.logger.error("Coordination error: \(error.localizedDescription)")
                continuation.resume(throwing: error)
            }
        }
        
        return zipURL
    }
    
    // Clean up old exports (call periodically)
    func cleanupOldExports() async throws {
        guard FileManager.default.fileExists(atPath: tempExportsURL.path) else {
            return
        }
        
        let files = try FileManager.default.contentsOfDirectory(at: tempExportsURL, includingPropertiesForKeys: [.creationDateKey])
        let now = Date()
        var cleanedCount = 0
        
        for file in files {
            if let creationDate = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate {
                // Delete files older than 1 hour
                if now.timeIntervalSince(creationDate) > 3600 {
                    do {
                        try FileManager.default.removeItem(at: file)
                        cleanedCount += 1
                    } catch {
                        logger.warning("Failed to delete old export: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        if cleanedCount > 0 {
            logger.info("Cleaned up \(cleanedCount) old export(s)")
        }
    }
}

enum ExportError: LocalizedError {
    case sessionFolderNotFound
    case zipCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .sessionFolderNotFound:
            return "Session folder not found"
        case .zipCreationFailed:
            return "Failed to create ZIP file"
        }
    }
}

