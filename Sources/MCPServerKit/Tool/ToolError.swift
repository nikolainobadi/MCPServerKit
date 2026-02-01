//
//  ToolError.swift
//  MCPServerKit
//
//  Created by Nikolai Nobadi on 1/28/26.
//

/// A protocol that defines the error namespace for a feature.
///
/// Each feature declares a single domain string that prefixes all error codes
/// originating from that feature (e.g., "profile", "summary").
public protocol ToolErrorDomain {
    static var domain: String { get }
}

/// A protocol for declarative, identity-based tool errors.
///
/// Conforming types are string-backed enums where each case represents
/// a distinct error identity. MCPServerKit handles all payload construction,
/// allowing features to throw simple errors without transport concerns.
///
/// Error codes are automatically converted to snake_case, so you can use
/// idiomatic Swift camelCase naming for enum cases.
///
/// Example:
/// ```swift
/// enum ProfileToolError: String, DomainError {
///     static let domain = "profile"
///     case readFailed    // produces error code "profile.read_failed"
///     case updateFailed
/// }
/// ```
public protocol ToolError: Error, ToolErrorConvertible, ToolErrorDomain, RawRepresentable where RawValue == String {
    /// Optional custom message for this error case.
    ///
    /// Override this property to provide user-facing messages that differ
    /// from the default derived message. Returns `nil` by default.
    var messageOverride: String? { get }
}

// MARK: - Default Implementations
public extension ToolError {
    var messageOverride: String? { nil }

    func toErrorPayload(toolName: String) -> ToolManagerErrorPayload {
        toErrorPayload(toolName: toolName, message: nil, details: nil)
    }

    func toErrorPayload(toolName: String, message: String?, details: [String: String]?) -> ToolManagerErrorPayload {
        let code = "\(Self.domain).\(rawValue.toSnakeCase())"
        let resolvedMessage = message ?? messageOverride ?? defaultMessage
        var resolvedDetails = details ?? [:]
        resolvedDetails["tool"] = toolName
        return ToolManagerErrorPayload(code: code, message: resolvedMessage, details: resolvedDetails)
    }

    /// Wraps this error with additional context for the error payload.
    ///
    /// Use this when throwing errors that need runtime-specific details
    /// while preserving the stable error code.
    ///
    /// - Parameters:
    ///   - details: Additional key-value pairs to include in the error payload.
    ///   - message: Optional runtime-specific message override.
    /// - Returns: A contextual wrapper that conforms to `ToolErrorConvertible`.
    func withDetails(_ details: [String: String], message: String? = nil) -> ContextualDomainError<Self> {
        ContextualDomainError(error: self, details: details, messageOverride: message)
    }
}

// MARK: - Private Helpers
private extension ToolError {
    var defaultMessage: String {
        rawValue.toSnakeCase().replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private extension String {
    /// Converts camelCase to snake_case. Idempotent for already snake_cased strings.
    func toSnakeCase() -> String {
        guard !isEmpty else { return self }

        var result = ""
        for (index, character) in enumerated() {
            if character.isUppercase {
                if index > 0 {
                    result.append("_")
                }
                result.append(character.lowercased())
            } else {
                result.append(character)
            }
        }
        return result
    }
}

// MARK: - ContextualDomainError
/// A wrapper that adds runtime context to a domain error.
///
/// This type preserves the concrete error identity while allowing
/// additional details and message overrides at the throw site.
public struct ContextualDomainError<E: ToolError>: ToolErrorConvertible {
    public let error: E
    public let details: [String: String]
    public let messageOverride: String?

    public init(error: E, details: [String: String], messageOverride: String?) {
        self.error = error
        self.details = details
        self.messageOverride = messageOverride
    }

    public func toErrorPayload(toolName: String) -> ToolManagerErrorPayload {
        error.toErrorPayload(toolName: toolName, message: messageOverride, details: details)
    }
}
