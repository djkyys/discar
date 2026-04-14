//
//  HTTPServerService.swift
//  discar
//
//  Local HTTP server for exposing session data to external tools
//

import Foundation
import Network
import OSLog
import Combine

@MainActor
class HTTPServerService: ObservableObject {
    static let shared = HTTPServerService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "discar", category: "HTTPServer")

    @Published var isRunning = false
    @Published var port: UInt16 = 8080
    @Published var serverURL: String = ""

    private var listener: NWListener?
    private var connections: [NWConnection] = []

    // MARK: - Public API

    func start(port: UInt16 = 8080) {
        guard !isRunning else {
            logger.info("Server already running")
            return
        }

        self.port = port

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)

            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleListenerState(state)
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.handleNewConnection(connection)
                }
            }

            listener?.start(queue: .main)

        } catch {
            logger.error("Failed to start server: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil

        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()

        isRunning = false
        serverURL = ""
        logger.info("HTTP server stopped")
    }

    // MARK: - Connection Handling

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            let ipAddress = getLocalIPAddress() ?? "localhost"
            serverURL = "http://\(ipAddress):\(port)"
            logger.info("HTTP server running at \(self.serverURL)")

            if ipAddress == "localhost" {
                logger.warning("Could not detect WiFi IP - make sure device is connected to WiFi")
            }
        case .failed(let error):
            logger.error("Server failed: \(error.localizedDescription)")
            isRunning = false
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { @MainActor [weak self] in
                    self?.receiveRequest(on: connection)
                }
            case .failed, .cancelled:
                Task { @MainActor [weak self] in
                    self?.connections.removeAll { $0 === connection }
                }
            default:
                break
            }
        }

        connection.start(queue: .main)
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                connection.cancel()
                return
            }

            Task { @MainActor in
                await self.processRequest(data: data, connection: connection)
            }
        }
    }

    // MARK: - Request Processing

    private func processRequest(data: Data, connection: NWConnection) async {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }

        // Parse HTTP request line
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }

        let method = String(parts[0])
        let path = String(parts[1])

        logger.info("Request: \(method) \(path)")

        // Route handling
        if method == "GET" {
            await handleGET(path: path, connection: connection)
        } else {
            sendResponse(connection: connection, statusCode: 405, body: "Method Not Allowed")
        }
    }

    private func handleGET(path: String, connection: NWConnection) async {
        // GET /
        if path == "/" {
            let endpoints = """
            {
                "endpoints": {
                    "GET /sessions": "List all sessions",
                    "GET /sessions/{folderPath}": "Get session metadata",
                    "GET /sessions/{folderPath}/data": "Get all sensor data (JSON)",
                    "GET /sessions/{folderPath}/{sensor}.json": "Get sensor data as JSON",
                    "GET /sessions/{folderPath}/{sensor}.csv": "Get sensor data as CSV"
                }
            }
            """
            sendJSONResponse(connection: connection, json: endpoints)
            return
        }

        // GET /sessions
        if path == "/sessions" {
            await handleListSessions(connection: connection)
            return
        }

        // GET /sessions/{folderPath}/data
        if path.hasPrefix("/sessions/") && path.hasSuffix("/data") {
            let folderPath = String(path.dropFirst("/sessions/".count).dropLast("/data".count))
            await handleGetAllSessionData(folderPath: folderPath, connection: connection)
            return
        }

        // GET /sessions/{folderPath}/{sensor}.csv
        if path.hasPrefix("/sessions/") && path.hasSuffix(".csv") {
            let remaining = String(path.dropFirst("/sessions/".count))
            let components = remaining.split(separator: "/", maxSplits: 1)
            if components.count == 2 {
                let folderPath = String(components[0])
                let csvFilename = String(components[1])
                let jsonFilename = String(csvFilename.dropLast(".csv".count)) + ".json"
                await handleGetSensorDataCSV(folderPath: folderPath, filename: jsonFilename, connection: connection)
                return
            }
        }

        // GET /sessions/{folderPath}/{sensor}.json
        if path.hasPrefix("/sessions/") && path.hasSuffix(".json") {
            let remaining = String(path.dropFirst("/sessions/".count))
            let components = remaining.split(separator: "/", maxSplits: 1)
            if components.count == 2 {
                let folderPath = String(components[0])
                let filename = String(components[1])
                await handleGetSensorData(folderPath: folderPath, filename: filename, connection: connection)
                return
            }
        }

        // GET /sessions/{folderPath}
        if path.hasPrefix("/sessions/") {
            let folderPath = String(path.dropFirst("/sessions/".count))
            if !folderPath.contains("/") {
                await handleGetSession(folderPath: folderPath, connection: connection)
                return
            }
        }

        sendResponse(connection: connection, statusCode: 404, body: "Not Found")
    }

    // MARK: - API Handlers

    private func handleListSessions(connection: NWConnection) async {
        let fm = FileManager.default
        let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sessionsURL = docsURL.appendingPathComponent("Sessions")

        guard let contents = try? fm.contentsOfDirectory(at: sessionsURL, includingPropertiesForKeys: [.isDirectoryKey]) else {
            sendJSONResponse(connection: connection, json: "[]")
            return
        }

        var sessions: [[String: Any]] = []

        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                let folderName = url.lastPathComponent
                var sessionInfo: [String: Any] = ["folderPath": folderName]

                // Try to read metadata
                let metadataURL = url.appendingPathComponent("metadata.json")
                if let data = try? Data(contentsOf: metadataURL),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    sessionInfo.merge(json) { _, new in new }
                }

                sessions.append(sessionInfo)
            }
        }

        if let data = try? JSONSerialization.data(withJSONObject: sessions, options: .prettyPrinted),
           let json = String(data: data, encoding: .utf8) {
            sendJSONResponse(connection: connection, json: json)
        } else {
            sendJSONResponse(connection: connection, json: "[]")
        }
    }

    private func handleGetSession(folderPath: String, connection: NWConnection) async {
        let fm = FileManager.default
        let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sessionURL = docsURL.appendingPathComponent("Sessions").appendingPathComponent(folderPath)

        guard fm.fileExists(atPath: sessionURL.path) else {
            sendResponse(connection: connection, statusCode: 404, body: "Session not found")
            return
        }

        // Read metadata
        let metadataURL = sessionURL.appendingPathComponent("metadata.json")
        if let data = try? Data(contentsOf: metadataURL),
           let json = String(data: data, encoding: .utf8) {
            sendJSONResponse(connection: connection, json: json)
        } else {
            // List available files
            let files = (try? fm.contentsOfDirectory(atPath: sessionURL.path)) ?? []
            let response: [String: Any] = [
                "folderPath": folderPath,
                "files": files
            ]
            if let data = try? JSONSerialization.data(withJSONObject: response, options: .prettyPrinted),
               let json = String(data: data, encoding: .utf8) {
                sendJSONResponse(connection: connection, json: json)
            }
        }
    }

    private func handleGetSensorData(folderPath: String, filename: String, connection: NWConnection) async {
        guard let objects = loadSensorObjects(folderPath: folderPath, filename: filename) else {
            sendResponse(connection: connection, statusCode: 404, body: "File not found")
            return
        }

        if let arrayData = try? JSONSerialization.data(withJSONObject: objects, options: .prettyPrinted),
           let json = String(data: arrayData, encoding: .utf8) {
            sendJSONResponse(connection: connection, json: json)
        } else {
            sendResponse(connection: connection, statusCode: 500, body: "Failed to serialize data")
        }
    }

    private func handleGetSensorDataCSV(folderPath: String, filename: String, connection: NWConnection) async {
        guard let objects = loadSensorObjects(folderPath: folderPath, filename: filename) else {
            sendResponse(connection: connection, statusCode: 404, body: "File not found")
            return
        }

        let csv = convertToCSV(objects: objects)
        sendResponse(connection: connection, statusCode: 200, body: csv, contentType: "text/csv")
    }

    private func loadSensorObjects(folderPath: String, filename: String) -> [Any]? {
        let fm = FileManager.default
        let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = docsURL
            .appendingPathComponent("Sessions")
            .appendingPathComponent(folderPath)
            .appendingPathComponent(filename)

        guard fm.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        // Check if NDJSON (newline-delimited) and convert to array
        if data.first != UInt8(ascii: "[") {
            let string = String(data: data, encoding: .utf8) ?? ""
            let lines = string.components(separatedBy: .newlines).filter { !$0.isEmpty }

            var objects: [Any] = []
            for line in lines {
                if let lineData = line.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: lineData) {
                    objects.append(obj)
                }
            }
            return objects
        }

        // Already JSON array
        return try? JSONSerialization.jsonObject(with: data) as? [Any]
    }

    private func convertToCSV(objects: [Any]) -> String {
        guard let firstObj = objects.first as? [String: Any] else {
            return ""
        }

        // Flatten nested objects and collect all keys
        var allKeys = Set<String>()
        var flattenedRows: [[String: Any]] = []

        for obj in objects {
            if let dict = obj as? [String: Any] {
                let flattened = flattenDict(dict, prefix: "")
                for key in flattened.keys {
                    allKeys.insert(key)
                }
                flattenedRows.append(flattened)
            }
        }

        // Sort keys for consistent column order (t first, then alphabetical)
        var sortedKeys = allKeys.sorted()
        if let tIndex = sortedKeys.firstIndex(of: "t") {
            sortedKeys.remove(at: tIndex)
            sortedKeys.insert("t", at: 0)
        }

        // Build CSV
        var csv = sortedKeys.joined(separator: ",") + "\n"

        for row in flattenedRows {
            let values = sortedKeys.map { key -> String in
                if let value = row[key] {
                    return formatCSVValue(value)
                }
                return ""
            }
            csv += values.joined(separator: ",") + "\n"
        }

        return csv
    }

    private func flattenDict(_ dict: [String: Any], prefix: String) -> [String: Any] {
        var result: [String: Any] = [:]

        for (key, value) in dict {
            let newKey = prefix.isEmpty ? key : "\(prefix)_\(key)"

            if let nested = value as? [String: Any] {
                let flattened = flattenDict(nested, prefix: newKey)
                result.merge(flattened) { _, new in new }
            } else {
                result[newKey] = value
            }
        }

        return result
    }

    private func formatCSVValue(_ value: Any) -> String {
        switch value {
        case let num as Double:
            return String(format: "%.6f", num)
        case let num as Int:
            return String(num)
        case let str as String:
            // Escape quotes and wrap in quotes if contains comma
            if str.contains(",") || str.contains("\"") || str.contains("\n") {
                return "\"\(str.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            return str
        case let bool as Bool:
            return bool ? "true" : "false"
        default:
            return String(describing: value)
        }
    }

    private func handleGetAllSessionData(folderPath: String, connection: NWConnection) async {
        let fm = FileManager.default
        let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sessionURL = docsURL.appendingPathComponent("Sessions").appendingPathComponent(folderPath)

        guard fm.fileExists(atPath: sessionURL.path) else {
            sendResponse(connection: connection, statusCode: 404, body: "Session not found")
            return
        }

        let files = (try? fm.contentsOfDirectory(atPath: sessionURL.path)) ?? []
        var allData: [String: Any] = ["folderPath": folderPath]

        for file in files where file.hasSuffix(".json") && file != "metadata.json" {
            let fileURL = sessionURL.appendingPathComponent(file)
            if let data = try? Data(contentsOf: fileURL) {
                let sensorName = String(file.dropLast(".json".count))

                // Parse NDJSON or JSON array
                if data.first != UInt8(ascii: "[") {
                    let string = String(data: data, encoding: .utf8) ?? ""
                    let lines = string.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    var objects: [Any] = []
                    for line in lines {
                        if let lineData = line.data(using: .utf8),
                           let obj = try? JSONSerialization.jsonObject(with: lineData) {
                            objects.append(obj)
                        }
                    }
                    allData[sensorName] = objects
                } else if let arr = try? JSONSerialization.jsonObject(with: data) {
                    allData[sensorName] = arr
                }
            }
        }

        // Add metadata
        let metadataURL = sessionURL.appendingPathComponent("metadata.json")
        if let data = try? Data(contentsOf: metadataURL),
           let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            allData["metadata"] = metadata
        }

        if let data = try? JSONSerialization.data(withJSONObject: allData, options: .prettyPrinted),
           let json = String(data: data, encoding: .utf8) {
            sendJSONResponse(connection: connection, json: json)
        } else {
            sendResponse(connection: connection, statusCode: 500, body: "Failed to serialize data")
        }
    }

    // MARK: - Response Helpers

    private func sendResponse(connection: NWConnection, statusCode: Int, body: String, contentType: String = "text/plain") {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }

        let response = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r
        \(body)
        """

        let responseData = Data(response.utf8)
        connection.send(content: responseData, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to send response: \(error.localizedDescription)")
            }
            connection.cancel()
        })
    }

    private func sendJSONResponse(connection: NWConnection, json: String) {
        sendResponse(connection: connection, statusCode: 200, body: json, contentType: "application/json")
    }

    // MARK: - Utilities

    private func getLocalIPAddress() -> String? {
        var addresses: [String: String] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while ptr != nil {
            let interface = ptr!.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr,
                           socklen_t(interface.ifa_addr.pointee.sa_len),
                           &hostname,
                           socklen_t(hostname.count),
                           nil, 0, NI_NUMERICHOST)
                let address = String(cString: hostname)

                // Skip loopback
                if address != "127.0.0.1" {
                    addresses[name] = address
                    logger.debug("Found interface \(name): \(address)")
                }
            }
            ptr = interface.ifa_next
        }

        // Priority: en0 (WiFi), en1, pdp_ip0 (cellular), any other
        if let wifi = addresses["en0"] { return wifi }
        if let en1 = addresses["en1"] { return en1 }
        if let cellular = addresses["pdp_ip0"] { return cellular }

        // Return first available non-loopback address
        return addresses.values.first
    }
}
