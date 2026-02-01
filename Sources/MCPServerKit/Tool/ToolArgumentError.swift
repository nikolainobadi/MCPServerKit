//
//  ToolArgumentError.swift
//  MCPServerKit
//
//  Created by Nikolai Nobadi on 1/25/26.
//

public enum ToolArgumentError: Error {
    case decodingError(Error)
    case missingOrInvalid(String)
}


// MARK: - ToolErrorConvertible
extension ToolArgumentError: ToolErrorConvertible {
    var message: String {
        switch self {
        case .missingOrInvalid(let key):
            return "Missing or invalid argument: \(key)."
        case .decodingError:
            return "Invalid tool arguments."
        }
    }

    public func toErrorPayload(toolName: String) -> ToolManagerErrorPayload {
        switch self {
        case .missingOrInvalid(let key):
            return .init(
                code: "tool.argument_invalid",
                message: message,
                details: [
                    "tool": toolName,
                    "path": key
                ]
            )

        case .decodingError(let error):
            return .init(
                code: "tool.argument_invalid",
                message: message,
                details: decodingDetails(error, toolName: toolName)
            )
        }
    }
}


// MARK: - Private Helpers
private func decodingDetails(_ error: Error, toolName: String) -> [String: String] {
    guard let decodingError = error as? DecodingError else {
        return [
            "tool": toolName,
            "reason": error.localizedDescription
        ]
    }

    switch decodingError {
    case .keyNotFound(let key, let context):
        return [
            "tool": toolName,
            "path": key.stringValue,
            "reason": context.debugDescription
        ]

    case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
        return [
            "tool": toolName,
            "path": context.codingPath.map(\.stringValue).joined(separator: "."),
            "reason": context.debugDescription
        ]
    @unknown default:
        return [
            "tool": toolName,
            "reason": "Unknown decoding error"
        ]
    }
}
