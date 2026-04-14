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
    
    // MARK: - CSV Writing

    // Append sensor data to CSV file
    func appendCSVData<T: CSVConvertible>(session: Session, filename: String, data: [T]) {
        guard !data.isEmpty else { return }

        let folder = getSessionFolder(session: session)
        let fileURL = folder.appendingPathComponent(filename)

        // Check if file exists to determine if we need header
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)

        // Create file if needed
        if !fileExists {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        do {
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            defer { try? fileHandle.close() }

            fileHandle.seekToEndOfFile()

            // Write header if new file
            if !fileExists {
                if let headerData = "\(T.csvHeader)\n".data(using: .utf8) {
                    fileHandle.write(headerData)
                }
            }

            // Write rows
            for item in data {
                if let rowData = "\(item.csvRow)\n".data(using: .utf8) {
                    fileHandle.write(rowData)
                }
            }

            logger.debug("Appended \(data.count) CSV rows to \(filename)")
        } catch {
            logger.error("Failed to append CSV to \(filename): \(error.localizedDescription)")
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

    // MARK: - Sync Upload

    /// Upload session data to ctlr
    func uploadSession(session: Session) async throws -> Int {
        let folder = getSessionFolder(session: session)

        // Get UUID - prefer ctlr UUID, fallback to local
        let uuid = session.externalUUID ?? session.id.uuidString

        // Get controller IP
        let controllerIP = UserDefaults.standard.string(forKey: "controllerIP") ?? "192.168.8.145"
        guard let url = URL(string: "http://\(controllerIP):8000/api/sync/phone") else {
            throw StorageError.syncFailed("Invalid URL")
        }

        // Get all CSV files
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            throw StorageError.syncFailed("Cannot read session folder")
        }

        let csvFiles = files.filter { $0.pathExtension == "csv" || $0.lastPathComponent == "metadata.json" }
        if csvFiles.isEmpty {
            throw StorageError.syncFailed("No files to upload")
        }

        // Build multipart request
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        var body = Data()

        // Add UUID field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"uuid\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(uuid)\r\n".data(using: .utf8)!)

        // Add files
        for fileURL in csvFiles {
            guard let fileData = try? Data(contentsOf: fileURL) else { continue }
            let filename = fileURL.lastPathComponent

            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw StorageError.syncFailed("Server error")
        }

        // Parse response
        struct SyncResponse: Codable {
            let success: Bool
            let files_saved: Int
        }

        let syncResponse = try JSONDecoder().decode(SyncResponse.self, from: data)
        logger.info("Synced \(syncResponse.files_saved) files for session \(uuid)")

        return syncResponse.files_saved
    }

    // MARK: - Data Loading Methods (Backward Compatible)

    /// Get count of data points
    func getSensorDataCount(session: Session, filename: String) async -> Int {
        let url = getSessionFolder(session: session).appendingPathComponent(filename)

        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return 0
        }

        // CSV format: count lines minus header
        if filename.hasSuffix(".csv") {
            let string = String(data: data, encoding: .utf8) ?? ""
            let lines = string.components(separatedBy: .newlines).filter { !$0.isEmpty }
            return max(0, lines.count - 1)  // Subtract header
        }

        // Check format based on first character (legacy JSON/NDJSON)
        if data.first == UInt8(ascii: "[") {
            // Legacy: JSON Array
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                return json?.count ?? 0
            } catch {
                return 0
            }
        } else {
            // NDJSON (Count newlines)
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
    case syncFailed(String)

    var errorDescription: String? {
        switch self {
        case .folderCreationFailed(let error):
            return "Failed to create session folder: \(error.localizedDescription)"
        case .deletionFailed(let error):
            return "Failed to delete session: \(error.localizedDescription)"
        case .dataLoadFailed(let error):
            return "Failed to load data: \(error.localizedDescription)"
        case .syncFailed(let reason):
            return "Sync failed: \(reason)"
        }
    }
}
