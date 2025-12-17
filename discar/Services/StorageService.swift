//
//  StorageService.swift
//  discar
//

import Foundation
import OSLog

actor StorageService {
    static let shared = StorageService()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "discar", category: "StorageService")
    
    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private var sessionsURL: URL {
        let url = documentsURL.appendingPathComponent("Sessions")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    
    // Get session folder URL
    private func getSessionFolder(session: Session) -> URL {
        sessionsURL.appendingPathComponent(session.folderPath)
    }
    
    // Create session folder
    func createSessionFolder(session: Session) throws {
        let folder = getSessionFolder(session: session)
        
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            logger.info("Created session folder: \(session.folderPath)")
        } catch {
            logger.error("Failed to create session folder: \(error.localizedDescription)")
            throw StorageError.folderCreationFailed(error)
        }
    }
    
    // MARK: - Optimized Writing (NDJSON)
    
    // Append sensor data to file using Append-Only Log (NDJSON)
    func appendSensorData<T: Codable>(session: Session, filename: String, data: [T]) {
        guard !data.isEmpty else { return }
        
        let folder = getSessionFolder(session: session)
        let fileURL = folder.appendingPathComponent(filename)
        
        // 1. Ensure file exists
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        
        do {
            // 2. Open FileHandle for writing
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            defer { try? fileHandle.close() }
            
            // 3. Seek to end (O(1) append)
            fileHandle.seekToEndOfFile()
            
            let encoder = JSONEncoder()
            // Note: No .prettyPrinted for NDJSON, we want single line per object
            encoder.outputFormatting = .sortedKeys
            
            // 4. Encode each item as a separate line
            for item in data {
                let jsonData = try encoder.encode(item)
                // Append newline delimiter
                if let jsonString = String(data: jsonData, encoding: .utf8),
                   let lineData = "\(jsonString)\n".data(using: .utf8) {
                    fileHandle.write(lineData)
                }
            }
            
            logger.debug("Appended \(data.count) items to \(filename)")
        } catch {
            logger.error("Failed to append to \(filename): \(error.localizedDescription)")
        }
    }
    
    // Save metadata (accepts pre-encoded Data)
    func saveMetadata(session: Session, data: Data) {
        let folder = getSessionFolder(session: session)
        let fileURL = folder.appendingPathComponent("metadata.json")
        
        do {
            try data.write(to: fileURL)
            logger.info("Saved metadata for session: \(session.folderPath)")
        } catch {
            logger.error("Failed to save metadata: \(error.localizedDescription)")
        }
    }
    
    // Delete session
    func deleteSession(session: Session) throws {
        let folder = getSessionFolder(session: session)
        
        do {
            try FileManager.default.removeItem(at: folder)
            logger.info("Deleted session folder: \(session.folderPath)")
        } catch {
            logger.error("Failed to delete session: \(error.localizedDescription)")
            throw StorageError.deletionFailed(error)
        }
    }

    // MARK: - Data Loading Methods (Backward Compatible)
    
    /// Get count of data points
    func getSensorDataCount(session: Session, filename: String) async -> Int {
        let url = getSessionFolder(session: session).appendingPathComponent(filename)
        
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return 0
        }
        
        // Check format based on first character
        if data.first == UInt8(ascii: "[") {
            // Legacy: JSON Array
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                return json?.count ?? 0
            } catch {
                return 0
            }
        } else {
            // Modern: NDJSON (Count newlines)
            // Reading entire file to string is okay for counting up to ~100MB, 
            // ideally we'd stream count, but this is sufficient for now.
            let string = String(data: data, encoding: .utf8) ?? ""
            return string.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
        }
    }
    
    /// Load all sensor data
    func loadSensorData<T: Codable>(session: Session, filename: String) async -> [T]? {
        let url = getSessionFolder(session: session).appendingPathComponent(filename)
        
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        
        // Check format
        if data.first == UInt8(ascii: "[") {
            // Legacy: JSON Array
            do {
                let decoder = JSONDecoder()
                return try decoder.decode([T].self, from: data)
            } catch {
                print("⚠️ Error loading legacy JSON \(filename): \(error)")
                return nil
            }
        } else {
            // Modern: NDJSON
            let decoder = JSONDecoder()
            let string = String(data: data, encoding: .utf8) ?? ""
            let lines = string.components(separatedBy: .newlines)
            
            var results: [T] = []
            results.reserveCapacity(lines.count)
            
            for line in lines where !line.isEmpty {
                if let lineData = line.data(using: .utf8) {
                    if let item = try? decoder.decode(T.self, from: lineData) {
                        results.append(item)
                    }
                }
            }
            return results
        }
    }
    
    /// Get downsampled data for charts (max N points)
    func getChartData<T: Codable>(session: Session, filename: String, maxPoints: Int = 100) async -> [T]? {
        guard let allData: [T] = await loadSensorData(session: session, filename: filename) else {
            return nil
        }
        
        // If data is small enough, return all
        if allData.count <= maxPoints {
            return allData
        }
        
        // Downsample by taking every Nth point
        let step = allData.count / maxPoints
        var downsampled: [T] = []
        
        for i in stride(from: 0, to: allData.count, by: step) {
            downsampled.append(allData[i])
        }
        
        return downsampled
    }
    
    /// Get paginated data for raw data table
    func getSensorDataPage<T: Codable>(session: Session, filename: String, offset: Int, limit: Int) async -> [T]? {
        guard let allData: [T] = await loadSensorData(session: session, filename: filename) else {
            return nil
        }
        
        let start = min(offset, allData.count)
        let end = min(offset + limit, allData.count)
        
        guard start < end else { return [] }
        
        return Array(allData[start..<end])
    }
}

// MARK: - Storage Errors

enum StorageError: LocalizedError {
    case folderCreationFailed(Error)
    case deletionFailed(Error)
    case dataLoadFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .folderCreationFailed(let error):
            return "Failed to create session folder: \(error.localizedDescription)"
        case .deletionFailed(let error):
            return "Failed to delete session: \(error.localizedDescription)"
        case .dataLoadFailed(let error):
            return "Failed to load data: \(error.localizedDescription)"
        }
    }
}
