//
//  ToolHandlerHelpers.swift
//  MCPServerKit
//
//  Created by Nikolai Nobadi on 1/28/26.
//

import MCP
import Foundation

/// Provides common helper methods for tool execution.
///
/// Conforming types gain access to argument decoding, payload encoding,
/// and value extraction utilities used during tool handling.
public protocol ToolHandlerHelpers: Sendable { }

// MARK: - Default Implementations
public extension ToolHandlerHelpers {
    func encodePayload<T: Encodable>(_ payload: T, formatting: PayloadFormatting = .compact) -> String {
        let encoder = JSONEncoder()
        switch formatting {
        case .compact:
            encoder.outputFormatting = [.sortedKeys]
        case .prettyPrinted:
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }

        return (try? String(decoding: encoder.encode(payload), as: UTF8.self)) ?? "{\"message\":\"Failed to encode payload\"}"
    }

    func requireString(_ arguments: [String: Value]?, key: String) throws -> String {
        guard let value = arguments?[key]?.stringValue else {
            throw ToolArgumentError.missingOrInvalid(key)
        }

        return value
    }

    func optionalString(_ arguments: [String: Value]?, key: String) -> String? {
        return arguments?[key]?.stringValue
    }

    func requireBool(_ arguments: [String: Value]?, key: String) throws -> Bool {
        guard let value = arguments?[key]?.boolValue else {
            throw ToolArgumentError.missingOrInvalid(key)
        }

        return value
    }

    func intValue(from value: Value?) -> Int? {
        guard let value else {
            return nil
        }

        if let intValue = value.intValue {
            return intValue
        }

        if let doubleValue = value.doubleValue, doubleValue.rounded() == doubleValue {
            return Int(doubleValue)
        }

        return nil
    }

    func decodeArguments<T: Decodable>(_ type: T.Type, from arguments: [String: Value]?) throws -> T {
        do {
            let value = Value.object(arguments ?? [:])
            let data = try JSONEncoder().encode(value)

            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ToolArgumentError.decodingError(error)
        }
    }
}
