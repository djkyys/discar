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

    /// Upload session data to ctlr (phone + watch data)
    func uploadSession(session: Session) async throws -> Int {
        let folder = getSessionFolder(session: session)

        // Get UUID - prefer ctlr UUID, fallback to local
        let uuid = session.externalUUID ?? session.id.uuidString

        // Get controller URL
        guard let url = AppConfig.Controller.syncPhoneURL else {
            throw StorageError.syncFailed("Invalid URL")
        }

        // Get all CSV files from session folder
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            throw StorageError.syncFailed("Cannot read session folder")
        }

        var allFiles: [(url: URL, uploadPath: String)] = []

        // Add phone CSVs and metadata
        for file in files {
            if file.pathExtension == "csv" || file.lastPathComponent == "metadata.json" {
                allFiles.append((url: file, uploadPath: file.lastPathComponent))
            }
        }

        // Add watch CSVs from watch/ subfolder
        let watchFolder = folder.appendingPathComponent("watch")
        if fileManager.fileExists(atPath: watchFolder.path) {
            if let watchFiles = try? fileManager.contentsOfDirectory(at: watchFolder, includingPropertiesForKeys: nil) {
                for file in watchFiles {
                    if file.pathExtension == "csv" {
                        // Upload with watch/ prefix to maintain folder structure
                        allFiles.append((url: file, uploadPath: "watch/\(file.lastPathComponent)"))
                    }
                }
            }
        }

        if allFiles.isEmpty {
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
        for (fileURL, uploadPath) in allFiles {
            guard let fileData = try? Data(contentsOf: fileURL) else { continue }

            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(uploadPath)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            RemoteLogger.shared.error("sync", "Sync failed: Server error (\(uuid))")
            throw StorageError.syncFailed("Server error")
        }

        // Parse response
        struct SyncResponse: Codable {
            let success: Bool
            let files_saved: Int
        }

        let syncResponse = try JSONDecoder().decode(SyncResponse.self, from: data)
        logger.info("Synced \(syncResponse.files_saved) files for session \(uuid) (phone + watch)")
        RemoteLogger.shared.info("sync", "Synced \(syncResponse.files_saved) files: \(uuid)")

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
    
    /// Load all sensor data (supports CSV, JSON Array, and NDJSON)
    func loadSensorData<T: Codable>(session: Session, filename: String) async -> [T]? {
        let url = getSessionFolder(session: session).appendingPathComponent(filename)

        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        let string = String(data: data, encoding: .utf8) ?? ""

        // Check format based on file extension and content
        if filename.hasSuffix(".csv") {
            // CSV format - use type-specific parsing based on filename
            return parseCSVByFilename(string, filename: filename)
        } else if data.first == UInt8(ascii: "[") {
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

    /// Parse CSV based on filename to determine the correct type
    private func parseCSVByFilename<T>(_ content: String, filename: String) -> [T]? {
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else { return nil }

        let dataLines = Array(lines.dropFirst())

        // Match filename to sensor type (lowercase to match SensorType.filename)
        let baseName = filename.replacingOccurrences(of: ".csv", with: "").lowercased()

        switch baseName {
        case "accelerometer":
            let results = dataLines.compactMap { AccelerometerReading.fromCSV($0) }
            return results as? [T]
        case "gyroscope":
            let results = dataLines.compactMap { GyroscopeReading.fromCSV($0) }
            return results as? [T]
        case "magnetometer":
            let results = dataLines.compactMap { MagnetometerReading.fromCSV($0) }
            return results as? [T]
        case "barometer":
            let results = dataLines.compactMap { BarometerReading.fromCSV($0) }
            return results as? [T]
        case "gps":
            let results = dataLines.compactMap { GPSReading.fromCSV($0) }
            return results as? [T]
        case "devicemotion":
            let results = dataLines.compactMap { DeviceMotionReading.fromCSV($0) }
            return results as? [T]
        case "headphonemotion":
            let results = dataLines.compactMap { DeviceMotionReading.fromCSV($0) }
            return results as? [T]
        case "gravity":
            let results = dataLines.compactMap { GravityReading.fromCSV($0) }
            return results as? [T]
        case "orientation":
            let results = dataLines.compactMap { OrientationReading.fromCSV($0) }
            return results as? [T]
        case "heading":
            let results = dataLines.compactMap { HeadingReading.fromCSV($0) }
            return results as? [T]
        default:
            logger.warning("Unknown CSV file type: \(filename)")
            return nil
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
