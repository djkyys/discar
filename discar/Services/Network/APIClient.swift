//
//  APIClient.swift
//  discar
//
//  Centralized HTTP API client for controller communication
//

import Foundation

/// Centralized API client for all HTTP requests to the controller
actor APIClient {
    static let shared = APIClient()

    private let session = URLSession.shared
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - Recording Control

    func startRecording(uuid: String) async throws {
        guard var url = AppConfig.Controller.startRecordURL else {
            throw APIError.invalidURL
        }
        url.append(queryItems: [URLQueryItem(name: "uuid", value: uuid)])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = AppConfig.Timeouts.api

        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    func stopRecording() async throws {
        guard let url = AppConfig.Controller.stopRecordURL else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = AppConfig.Timeouts.api

        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    // MARK: - Status

    func getStatus() async throws -> ControllerStatusResponse {
        guard let url = AppConfig.Controller.statusURL else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = AppConfig.Timeouts.api

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        return try decoder.decode(ControllerStatusResponse.self, from: data)
    }

    func getCANStatus() async throws -> CANStatusResponse {
        guard let url = AppConfig.Controller.canStatusURL else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = AppConfig.Timeouts.api

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        return try decoder.decode(CANStatusResponse.self, from: data)
    }

    func getStorageStatus() async throws -> StorageStatusResponse {
        guard let url = AppConfig.Controller.storageStatusURL else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = AppConfig.Timeouts.api

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        return try decoder.decode(StorageStatusResponse.self, from: data)
    }

    // MARK: - Storage Management

    func remountStorage(mount: String = "all") async throws {
        guard var url = AppConfig.Controller.remountURL else {
            throw APIError.invalidURL
        }
        url.append(queryItems: [URLQueryItem(name: "mount", value: mount)])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = AppConfig.Timeouts.api

        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    func unmountStorage(mount: String) async throws {
        guard var url = AppConfig.Controller.unmountURL else {
            throw APIError.invalidURL
        }
        url.append(queryItems: [URLQueryItem(name: "mount", value: mount)])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = AppConfig.Timeouts.api

        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    // MARK: - Connection Test

    func testConnection() async throws -> Int {
        guard let url = AppConfig.Controller.statusURL else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = AppConfig.Timeouts.connectionTest

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let status = try decoder.decode(ControllerStatusResponse.self, from: data)
        return status.cameras.filter { $0.connected }.count
    }

    // MARK: - Validation

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 400:
            throw APIError.badRequest
        case 401, 403:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        case 500...599:
            throw APIError.serverError(httpResponse.statusCode)
        default:
            throw APIError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case badRequest
    case unauthorized
    case notFound
    case serverError(Int)
    case httpError(Int)
    case timeout
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response from server"
        case .badRequest: return "Bad request"
        case .unauthorized: return "Unauthorized"
        case .notFound: return "Not found"
        case .serverError(let code): return "Server error (\(code))"
        case .httpError(let code): return "HTTP error (\(code))"
        case .timeout: return "Request timed out"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        }
    }
}
