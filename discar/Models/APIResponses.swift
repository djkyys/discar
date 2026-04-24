//
//  APIResponses.swift
//  discar
//
//  API response models - kept separate from APIClient to avoid Swift 6 actor isolation inference
//

import Foundation

struct ControllerStatusResponse: Codable, Sendable {
    let ready: Bool
    let recording: Bool
    let uuid: String?
    let duration: Int
    let cameras: [CameraStatus]

    struct CameraStatus: Codable, Sendable {
        let name: String
        let connected: Bool
        let state: String?
        let segment: Int?
        let cpu: Double?
        let ram: Double?
        let diskFreeGB: Double?
        let temp: Double?

        enum CodingKeys: String, CodingKey {
            case name, connected, state, segment, cpu, ram, temp
            case diskFreeGB = "disk_free_gb"
        }
    }
}

struct CANStatusResponse: Codable, Sendable {
    let connected: Bool
    let frameCount: Int
    let fileSizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case connected
        case frameCount = "frame_count"
        case fileSizeBytes = "file_size_bytes"
    }
}

struct StorageStatusResponse: Codable, Sendable {
    let healthy: Bool
    let logging: MountStatus?
    let sync: MountStatus?

    struct MountStatus: Codable, Sendable {
        let accessible: Bool
        let freeGB: Double?

        enum CodingKeys: String, CodingKey {
            case accessible
            case freeGB = "free_gb"
        }
    }
}

struct SyncResponse: Codable, Sendable {
    let success: Bool
    let filesSaved: Int

    enum CodingKeys: String, CodingKey {
        case success
        case filesSaved = "files_saved"
    }
}
