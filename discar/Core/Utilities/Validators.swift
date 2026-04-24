//
//  Validators.swift
//  discar
//
//  Input validation utilities
//

import Foundation

enum Validators {

    /// Validate IPv4 address format
    static func isValidIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let num = Int(part) else { return false }
            return (0...255).contains(num)
        }
    }

    /// Validate UUID string format
    static func isValidUUID(_ string: String) -> Bool {
        UUID(uuidString: string) != nil
    }

    /// Validate URL string
    static func isValidURL(_ string: String) -> Bool {
        URL(string: string) != nil
    }

    /// Validate port number
    static func isValidPort(_ port: Int) -> Bool {
        (1...65535).contains(port)
    }
}
